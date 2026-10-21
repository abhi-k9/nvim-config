-- lua/scoper/lsp.lua
--
-- LSP integration. Goal: speed up clangd indexing on big C/C++ projects
-- by feeding it a filtered compile_commands.json that only contains
-- translation units inside the active scope.
--
-- Three operating modes, picked per call:
--
--   1. **Filter applies.** Scoping ON, non-empty include list, a
--      compile_commands.json is found, and it parses as valid JSON.
--      Steps:
--        a. Locate compile_commands.json (cwd, ./build, ./out,
--           ./cmake-build-*)
--        b. Parse and filter entries where `file` is in the active
--           scope (scoper.cdb; reloads run it in a background Neovim
--           process so big databases don't freeze the editor)
--        c. Write the filtered JSON to:
--             stdpath("cache")/scoper/<cwd-hash>/<scope>/<scope-hash>/compile_commands.json
--        d. Configure clangd via vim.lsp.config with --compile-commands-dir
--           pointing at that cache dir, alongside the default flags
--        e. Restart this project's running clangd clients so they pick
--           up the new cmd
--
--   2. **No filter, but the unfiltered file is located.** Scoping OFF,
--      or empty include list, or the JSON failed to parse. Steps b-c
--      are skipped; step d configures clangd with --compile-commands-dir
--      pointing at the *unfiltered* directory found in step a — NOT
--      just removing the flag. The reason: clangd's own discovery walks
--      up from the source file and respects a project-level `.clangd`
--      file's `CompileFlags.CompilationDatabase` setting. If those
--      disagree with where the database actually lives, clangd
--      silently falls back to ad-hoc fixed flags and every project
--      header becomes a "file not found" error. Always-explicit
--      removes that whole class of failure.
--
--   3. **No compile_commands.json anywhere.** Step a returns nil.
--      Step d configures clangd with default flags only (no
--      --compile-commands-dir). This is the only case where clangd's
--      built-in discovery and any `.clangd` config get to decide where
--      the database lives — if scoper can't find one, neither can it
--      point clangd at one.
--
-- Step e (restart) runs in all three modes so the swap takes effect
-- immediately, without a Neovim restart. The restart is ASYNCHRONOUS:
-- the old clients get a graceful shutdown that Client:stop() turns into
-- a forced one after 2 s, and a libuv timer (50 ms) polls for them to
-- exit before re-attaching. Only if one is still alive 1.5 s after that
-- is the re-attach skipped (to avoid duplicate clients), with a hint to
-- :ScoperLspReload.
--
-- One project per Neovim instance (State.root()), but vim.lsp.config is
-- global: the configured cmd is a function, so a clangd started for a
-- root outside this project gets the plain flags rather than this
-- project's --compile-commands-dir, and restarts leave such clients alone.
--
-- Net behaviour:
--   * `:ScoperToggle` on  → mode 1 (filtered cache)
--   * `:ScoperToggle` off → mode 2 (unfiltered project file)
--   * no CC.json anywhere → mode 3 (built-in discovery)
--
-- Setup integration (opt-in): require("scoper").setup({ lsp = { clangd = true } })
-- will hook scope changes to auto-rerun this. Otherwise the user calls
-- :ScoperLspReload manually.
--
-- Why bother filtering at all? clangd's index walks every TU in
-- compile_commands.json on startup, which is the actual slow part on
-- big projects. Slimming the JSON cuts that walk linearly with TU
-- count.

local State = require("scoper.state")
local Path = require("scoper.path")
local Util = require("scoper.util")
local Cdb = require("scoper.cdb")

local M = {}

-- ---------------------------------------------------------------------------
-- Find the project's compile_commands.json. Returns the absolute path or
-- nil. Search order matches what cmake / build tools commonly produce.
-- ---------------------------------------------------------------------------
local function find_compile_commands(start_dir)
  -- Forward slashes on every OS: the result is compared as a string by
  -- the freshness cache below.
  start_dir = Path.normalize(start_dir or State.root())
  local candidates = {
    start_dir .. "/compile_commands.json",
    start_dir .. "/build/compile_commands.json",
    start_dir .. "/out/compile_commands.json",
  }
  -- cmake-build-debug / cmake-build-release / etc. (CLion-style)
  local handle = vim.uv.fs_scandir(start_dir)
  if handle then
    while true do
      local name, t = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if t == "directory" and name:match("^cmake%-build%-") then
        table.insert(candidates, start_dir .. "/" .. name .. "/compile_commands.json")
      end
    end
  end

  for _, cand in ipairs(candidates) do
    if vim.uv.fs_stat(cand) then return Path.normalize(cand) end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Compute the cache directory for the filtered output. Per-project (cwd
-- hash), scope name, and scope contents. Two Neovim instances may retain
-- different includes/excludes under the same name; their clangd clients
-- must never watch a shared file that either instance can overwrite.
-- ---------------------------------------------------------------------------
local function cache_dir(fingerprint)
  -- Same identity as state.store_path: util.cwd_hash of Path.key(root)
  -- (case-insensitive on Windows), so the state file and this cache
  -- always agree on which project they belong to.
  local hash = Util.cwd_hash(Path.key(State.root()))
  -- Scope names are validated at creation (state.new_scope rejects
  -- anything outside [%w_%-.]), but a hand-edited state file may still
  -- carry unsafe names. Sanitize before using one as a directory
  -- component; '/' would nest, '..' would traverse, ':' fails mkdir on
  -- Windows.
  local scope = State.active_name():gsub("[^%w_%-%.]", "_")
  return Path.normalize(
    vim.fn.stdpath("cache") .. "/scoper/" .. hash .. "/" .. scope .. "/" .. fingerprint:sub(1, 32)
  )
end

-- Extra flags from the last clangd_cmd(extra_args) call. Reloads rebuild
-- the cmd without arguments, so they must be remembered here.
M._extra_args = nil

-- ---------------------------------------------------------------------------
-- The baseline clangd cmd. Both the filtered path (scope on, valid
-- compile_commands.json) and the unfiltered path (scope off / empty /
-- missing CC.json) build on this — the filtered path additionally
-- prepends `--compile-commands-dir=<cache>`. Centralising the flag set
-- here is what guarantees the two paths can't disagree about which
-- clangd options we want.
--
-- The flags themselves come from setup()'s `lsp.clangd_args` (defaults
-- in scoper/init.lua), NOT from a hardcoded list here: which tidy /
-- completion / header-insertion behaviour a project wants is a user
-- style choice, and a plugin shouldn't bake one in. require("scoper")
-- at call time is safe — init.lua is always loaded before any LSP
-- entry point runs (setup() or a :Scoper* command got us here).
-- ---------------------------------------------------------------------------
local function base_clangd_cmd()
  local cfg = require("scoper").config or {}
  local cmd = { "clangd" }
  vim.list_extend(cmd, (cfg.lsp and cfg.lsp.clangd_args) or {})
  vim.list_extend(cmd, M._extra_args or {})
  return cmd
end

-- ---------------------------------------------------------------------------
-- Decide which compile_commands entries fall inside the active scope, given
-- the project root `cwd`. Extracted (underscore = internal) so lsp_spec can
-- assert cdb.filter's path-resolution rule without touching the filesystem.
-- ---------------------------------------------------------------------------
function M._filter_entries(entries, cwd)
  return Cdb.filter(entries, State.matcher(cwd))
end

local function read_json(path)
  local ok, v = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  return ok and type(v) == "table" and v or nil
end

local prepare, finish

-- ---------------------------------------------------------------------------
-- Filter compile_commands.json, write the result, return either:
--   * out_dir, info, changed — filter applied. out_dir is the path to
--                     pass to clangd via --compile-commands-dir; `changed`
--                     says whether the database clangd reads differs from
--                     what was there before.
--   * nil, info     — no filter applied (by design or by impossibility).
--                     `info` says ONLY why; the caller (clangd_cmd) is
--                     responsible for deciding what to do next (point
--                     clangd at the unfiltered file vs. fall back to
--                     built-in discovery) and appending that decision
--                     to the message.
--
-- With `opts.stale_ok`, nothing is filtered: an out-of-date filtered file
-- is returned as it is, and without one the result is nil, "filter
-- pending"; the fourth value (true) tells the caller to refresh later.
--
-- The `info` strings carry no "Scoper LSP: " prefix and no
-- speculation about clangd's behavior; the notify path adds the prefix
-- once and clangd_cmd appends the actual disposition.
--
-- Runs the filter in THIS Neovim; reloads use M._filter_async instead.
-- ---------------------------------------------------------------------------
function M.write_filtered_compile_commands(opts)
  local res, job = prepare(opts)
  return finish(res or Cdb.run(job))
end

-- The cheap half of the filter: the state checks and the freshness cache.
-- Returns a finished result ({ dir, info, changed, stale }, as returned
-- by cdb.run) or nil plus the job for cdb.run.
function prepare(opts)
  -- Cheap state checks first — no point reading the file off disk if
  -- the active scope already implies "no filter".
  if not State.is_enabled() then return { info = "disabled" } end
  local scope = State.active_scope()
  if not scope or #scope.include == 0 then return { info = "active scope is empty" } end

  local cc = find_compile_commands()
  if not cc then
    return {
      info = "compile_commands.json not found (looked in ./, ./build, ./out, ./cmake-build-*)",
    }
  end

  -- -------------------------------------------------------------------
  -- Freshness cache. setup() applies the clangd cmd at startup, so
  -- without a cache every launch would readfile + decode + filter +
  -- rewrite the compile database (~400-500 ms for 10k entries / 20 MB)
  -- even though nothing changed — the overwhelmingly common case.
  --
  -- The filtered output only depends on two inputs: the SOURCE
  -- compile_commands.json (identified by path + mtime sec/nsec + size)
  -- and the SCOPE CONTENT (include + exclude lists — fingerprinted,
  -- because :ScoperAdd/:ScoperExclude mutate a scope without renaming
  -- it; the scope NAME and cwd are already part of cache_dir's path).
  -- A tiny meta file next to the output records those inputs and a
  -- sha256 of the output; when the inputs match and the output still
  -- exists, skip everything. Any cmake regen (mtime/size), scope edit
  -- (fingerprint), scope switch (different dir), or deleted cache
  -- (missing output) invalidates naturally. Kept/total counts are stored
  -- too so the skip path can report the same message as a real run.
  -- -------------------------------------------------------------------
  local fingerprint = vim.fn.sha256(vim.json.encode({
    Path.key(State.root()),
    scope.include,
    scope.exclude,
  }))
  local out_dir = cache_dir(fingerprint)
  local out_path = out_dir .. "/compile_commands.json"
  local meta_path = out_dir .. "/.scoper-meta.json"
  local st = vim.uv.fs_stat(cc)
  local meta = read_json(meta_path)
  local out_st = vim.uv.fs_stat(out_path)
  local have_out = out_st ~= nil and out_st.type == "file"
  local have_intact_out = have_out and meta and meta.out_size == out_st.size
  -- The output must still have the size the filter wrote (a cheap check:
  -- hashing it on every start would cost what the cache saves), so a
  -- truncated or hand-edited cache is filtered again.
  if
    have_intact_out
    and st
    and meta
    and meta.src == cc
    and meta.mtime_sec == st.mtime.sec
    and meta.mtime_nsec == st.mtime.nsec
    and meta.size == st.size
    and meta.fingerprint == fingerprint
  then
    return {
      dir = out_dir,
      info = ("%d/%d entries kept → %s (cached)"):format(
        meta.kept or 0,
        meta.total or 0,
        out_path
      ),
      changed = false,
    }
  end
  if opts and opts.stale_ok then
    if not have_intact_out then return { info = "filter pending", stale = true } end
    return {
      dir = out_dir,
      info = ("previous filter result → %s (refresh pending)"):format(out_path),
      changed = false,
      stale = true,
    }
  end

  return nil,
    {
      cc = cc,
      root = State.root(),
      scope = { include = scope.include, exclude = scope.exclude },
      out_dir = out_dir,
      -- The inputs that produced the output (see the cache block above).
      meta = {
        src = cc,
        mtime_sec = st and st.mtime.sec or 0,
        mtime_nsec = st and st.mtime.nsec or 0,
        size = st and st.size or 0,
        fingerprint = fingerprint,
      },
      old_digest = have_intact_out and meta.digest or nil,
    }
end

-- For :DiagnosticDump-style reports: the last filter result, and how the
-- last background run ended.
M._last_filter, M._last_worker = nil, nil

function finish(res)
  M._last_filter = { info = res.info, changed = res.changed, at = os.date("%Y-%m-%d %H:%M:%S") }
  if res.warn then vim.notify(res.warn, vim.log.levels.WARN) end
  return res.dir, res.info, res.changed, res.stale
end

-- ---------------------------------------------------------------------------
-- Background filter: cdb.run in a separate `nvim --clean --headless`
-- process, so reading, filtering and writing a big database never freezes
-- the editor. The job goes in and the result comes back as JSON files next
-- to the output. If the process can't run, the job runs here instead (one
-- warning per session); a run that times out leaves clangd on the
-- unfiltered database.
-- ---------------------------------------------------------------------------
local worker_script =
  Path.normalize(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/cdb_worker.lua")

-- A function so lsp_spec can make the process fail.
function M._worker_cmd(job_path, result_path)
  return { vim.v.progpath, "--clean", "--headless", "-l", worker_script, job_path, result_path }
end

M._worker_timeout = 120000

local job_seq, warned_fallback = 0, false

-- Calls cb(result) on the main loop, exactly once.
local function run_in_background(job, cb)
  job_seq = job_seq + 1
  local base = ("%s/.scoper-job-%d-%d"):format(job.out_dir, vim.fn.getpid(), job_seq)
  local job_path, result_path = base .. ".json", base .. ".result.json"
  local started = vim.uv.hrtime()
  local function cleanup(outcome)
    os.remove(job_path)
    os.remove(result_path)
    M._last_worker = { outcome = outcome, ms = math.floor((vim.uv.hrtime() - started) / 1e6) }
  end
  local function run_here(why)
    cleanup("failed (" .. why .. "), filtered in this Neovim")
    if not warned_fallback then
      warned_fallback = true
      vim.notify(
        "Scoper LSP: background filter failed (" .. why .. "); filtering in this Neovim instead",
        vim.log.levels.WARN
      )
    end
    local ok, res = pcall(Cdb.run, job)
    cb(ok and res or { info = "filter failed: " .. tostring(res) })
  end

  vim.fn.mkdir(job.out_dir, "p")
  local wrote, write_result = pcall(vim.fn.writefile, { vim.json.encode(job) }, job_path)
  if not wrote or write_result ~= 0 then return run_here("can't write " .. job_path) end
  local ok, err = pcall(
    vim.system,
    M._worker_cmd(job_path, result_path),
    { text = true, timeout = M._worker_timeout },
    function(proc)
      vim.schedule(function()
        local res = proc.code == 0 and read_json(result_path)
        if res then
          cleanup("ok")
          return cb(res)
        end
        if proc.code == 124 then
          cleanup("timed out")
          return cb({ info = ("filter timed out after %d s"):format(M._worker_timeout / 1000) })
        end
        run_here(("exit %d: %s"):format(proc.code, vim.trim(proc.stderr or "")))
      end)
    end
  )
  if not ok then run_here(tostring(err)) end
end

-- write_filtered_compile_commands without blocking: calls
-- cb(dir, info, changed, stale) once the background filter is done, or
-- right away (synchronously) when there is nothing to filter.
function M._filter_async(cb, opts)
  local res, job = prepare(opts)
  if res then return cb(finish(res)) end
  run_in_background(job, function(r)
    cb(finish(r))
  end)
end

-- The clangd cmd for a filter result (what write_filtered_compile_commands
-- returns); passes `stale` through as the fourth value.
local function cmd_from(filtered_dir, info, changed, stale)
  local cmd = base_clangd_cmd()

  if filtered_dir then
    -- Scoped path: point clangd at the filtered cache.
    table.insert(cmd, 2, "--compile-commands-dir=" .. filtered_dir)
    return cmd, info, changed, stale
  end

  -- Unscoped path: filtering didn't apply (scoper off, empty scope, no
  -- CC.json, or parse error). Still point clangd at the project's
  -- actual compile_commands.json if we can find one — this is the
  -- "always explicit" rationale above. find_compile_commands() may
  -- have already been called inside write_filtered_compile_commands;
  -- calling it again is cheap (a handful of fs_stat() calls,
  -- debounced 500 ms by attach_auto in practice).
  local raw = find_compile_commands()
  if raw then
    local raw_dir = Path.normalize(vim.fs.dirname(raw))
    table.insert(cmd, 2, "--compile-commands-dir=" .. raw_dir)
    return cmd, info .. "; clangd pointed at " .. raw_dir, nil, stale
  end

  -- No compile_commands.json anywhere we know to look — leave clangd
  -- to its own discovery.
  return cmd, info .. "; clangd will use built-in discovery", nil, stale
end

-- clangd_cmd() minus the remembered-extras bookkeeping; passes `opts` to
-- write_filtered_compile_commands.
local function build_cmd(opts)
  return cmd_from(M.write_filtered_compile_commands(opts))
end

-- ---------------------------------------------------------------------------
-- Build the clangd `cmd` array. ALWAYS returns a non-nil cmd. The
-- `--compile-commands-dir` flag is prepended in two cases:
--
--   1. Filtering succeeded — dir points at the scoper cache holding the
--      filtered JSON.
--   2. Filtering didn't apply but scoper can still locate the
--      project's real compile_commands.json — dir points at that
--      file's containing directory.
--
-- Only when neither holds (no CC.json anywhere in scoper's candidate
-- list) is the flag omitted, and clangd is left to its own discovery
-- (the upward walk and `.clangd` config).
--
-- Why always-explicit when we can: clangd's discovery is fragile. It
-- walks up from the source file, and a project-level `.clangd` file's
-- `CompileFlags.CompilationDatabase` setting can redirect that search
-- to a directory that doesn't contain the database (e.g. `.clangd`
-- says `build/` but the file actually lives at the root, or vice
-- versa). When that happens clangd silently falls back to fixed
-- ad-hoc flags and every project include becomes a "file not found"
-- error. Passing `--compile-commands-dir` overrides `.clangd`'s
-- setting and removes that whole class of failure.
--
-- `extra_args` are appended after `lsp.clangd_args` and remembered: every
-- later reload (scope edits, :ScoperLspReload) keeps them until the next
-- call that passes a list.
--
-- Returns cmd, info, changed (see write_filtered_compile_commands).
--
-- Contract: the returned cmd is ALWAYS usable (never nil), so callers can
-- wire `cmd = require("scoper").clangd_cmd(...)` straight into
-- vim.lsp.config; when filtering isn't possible it is plain clangd. That
-- means a cache miss filters synchronously, in this Neovim.
-- ---------------------------------------------------------------------------
function M.clangd_cmd(extra_args)
  if extra_args ~= nil then M._extra_args = extra_args end
  local cmd, info, changed = build_cmd()
  return cmd, info, changed
end

-- Does a clangd rooted at `dir` belong to this project? Either directory
-- may contain the other (cwd in a subfolder of the repository, or a root
-- marker below the cwd). No root (single-file mode) counts as ours.
local function ours(dir)
  if type(dir) ~= "string" or dir == "" then return true end
  local root = State.root()
  return Path.is_under(dir, root) or Path.is_under(root, dir)
end

-- clangd's cmd. The config is global, so this decides per client at spawn
-- time: clangd for this project gets the latest scoped cmd, clangd for
-- another project's root the plain flags.
local function spawn(dispatchers, config)
  local cmd = ours(config.root_dir) and M._cmd or base_clangd_cmd()
  return vim.lsp.rpc.start(cmd, dispatchers, {
    cwd = config.cmd_cwd,
    env = config.cmd_env,
    detached = config.detached,
  })
end

local C_FAMILY = { c = true, cpp = true, objc = true, objcpp = true, cuda = true }

-- Install `cmd` as this project's clangd command. vim.lsp.enable() quietly
-- skips a list cmd whose program isn't installed but warns about a failing
-- function on every C buffer, so the function needs clangd on PATH.
--
-- A clangd from mason.nvim is on PATH only once mason has loaded, which is
-- often after setup(). Until then a C buffer's FileType installs the
-- function as soon as clangd is there. That handler runs before
-- vim.lsp.enable()'s if setup() ran before the first vim.lsp.enable()
-- (autocmds for one event run oldest first).
function M._apply(cmd)
  M._cmd = cmd
  if vim.fn.executable(cmd[1]) == 1 then
    vim.lsp.config("clangd", { cmd = spawn })
    return
  end
  vim.lsp.config("clangd", { cmd = cmd })
  local group = vim.api.nvim_create_augroup("scoper_clangd_cmd", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = vim.tbl_keys(C_FAMILY),
    callback = function()
      if vim.fn.executable(M._cmd[1]) ~= 1 then return end
      vim.lsp.config("clangd", { cmd = spawn })
      -- one autocmd per pattern: returning true would delete only this one
      vim.api.nvim_clear_autocmds({ group = group })
    end,
  })
end

-- Running clangd clients of this project.
local function our_clients()
  return vim.tbl_filter(function(c)
    return not c:is_stopped() and ours(c.root_dir)
  end, vim.lsp.get_clients({ name = "clangd" }))
end

-- C-family buffers to start clangd in again: the ones the stopped clients
-- had (`stopped_bufs` is a set), plus this project's buffers that have no
-- clangd.
local function reattach_targets(stopped_bufs)
  local root = State.root()
  local out = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(buf)
      and C_FAMILY[vim.bo[buf].filetype]
      and #vim.lsp.get_clients({ name = "clangd", bufnr = buf }) == 0
      and (stopped_bufs[buf] or Path.is_under(vim.api.nvim_buf_get_name(buf), root))
    then
      table.insert(out, buf)
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Re-fire FileType on loaded C-family buffers (all of them, or the list
-- `bufs`) so the auto-attach autocmd installed by vim.lsp.enable starts
-- clangd with the new cmd. (`:lsp restart clangd` would restart other
-- projects' clangd too, and never starts it in a buffer without one.)
--
-- Only the `nvim.lsp.enable` augroup is re-fired. A bare `doautocmd
-- FileType` would re-run EVERY FileType handler on every C/C++ buffer —
-- treesitter.start, indentexpr, formatoptions, ufo, textobjects… — for
-- what is purely an LSP re-attach. Without that group clangd was started
-- some other way (nvim-lspconfig's legacy setup(), a manual
-- vim.lsp.start()), and only the user knows how to start it again.
-- ---------------------------------------------------------------------------
function M._reattach(bufs)
  local targets = {}
  for _, buf in ipairs(bufs or vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and C_FAMILY[vim.bo[buf].filetype] then
      table.insert(targets, buf)
    end
  end
  if #targets == 0 then return end
  if not pcall(vim.api.nvim_get_autocmds, { group = "nvim.lsp.enable" }) then
    vim.notify(
      "Scoper LSP: clangd isn't started by vim.lsp.enable(); restart it yourself to apply the new config",
      vim.log.levels.WARN
    )
    return
  end
  for _, buf in ipairs(targets) do
    vim.api.nvim_exec_autocmds("FileType", {
      group = "nvim.lsp.enable",
      buffer = buf,
      modeline = false,
    })
  end
end

-- ---------------------------------------------------------------------------
-- Apply the configuration via vim.lsp.config and restart this project's
-- running clangd clients.
--
-- Proceeds unconditionally — clangd_cmd() always returns a usable
-- cmd, whether scoped (--compile-commands-dir pointing at the filtered
-- cache), unscoped-but-located (pointing at the project's actual
-- compile_commands.json directory), or fully-unconfigured (no flag).
-- The toggle-on / toggle-off round trip therefore swaps between the
-- first two cases in the same session, restarting clangd each time so
-- the swap takes effect immediately.
--
-- opts.auto (set by the ScoperChanged listener): skip the restart when it
-- would change nothing — same cmd as the one last applied, the filtered
-- database unchanged, and clangd already running — so edits that don't
-- affect clangd (any edit while scoping is off, or a database edit to
-- out-of-scope files) keep its warm in-memory index. Automatic reloads are also
-- silent when no clangd of this project runs. :ScoperLspReload always
-- restarts and reports.
-- ---------------------------------------------------------------------------
function M.reload_clangd(opts)
  opts = opts or {}
  -- Re-entrancy guard + pending flag. The reload below is ASYNCHRONOUS
  -- (a libuv timer polls for the old clients to exit instead of
  -- blocking), so a ScoperChanged debounce can absolutely fire while a
  -- reload is mid-flight. Dropping that call would lose the LAST update
  -- (clangd stuck on a stale scope), so a reload requested during a
  -- reload is remembered and replayed exactly once when the in-flight one
  -- finishes.
  if M._reloading then
    -- A forced request must not be downgraded by a later automatic one.
    M._pending = { auto = opts.auto and (not M._pending or M._pending.auto) }
    return
  end
  M._reloading = true
  local ok, err = pcall(M._start_reload, M._finish_reload, opts)
  if not ok then
    -- Don't strand the guard. Also drop any pending request: replaying
    -- into the same persistent error (unwritable cache dir, …) would
    -- loop forever.
    M._reloading = false
    M._pending = false
    vim.notify("Scoper LSP: reload failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- Completion hook for _start_reload. Clears the guard and, if another
-- reload was requested mid-flight, schedules exactly one more pass.
function M._finish_reload()
  M._reloading = false
  if M._pending then
    local pending = M._pending
    M._pending = false
    -- Schedule rather than call directly so the stack unwinds and the
    -- guard logic in reload_clangd runs fresh.
    vim.schedule(function()
      M.reload_clangd(pending)
    end)
  end
end

local function notify_result(info, restarted)
  vim.notify(
    "Scoper LSP: "
      .. info
      .. (restarted > 0 and (" — restarted %d clangd client(s)"):format(restarted) or "")
  )
end

local restart

-- Restart timing in ms: the poll interval; the graceful-shutdown budget,
-- after which Client:stop() kills the process (clangd with a busy
-- background index routinely needs more than a second; nothing of value
-- is lost, the index is on disk); then how long the killed process gets
-- to be reaped. A table so lsp_spec can shorten it.
M._timing = { poll = 50, grace = 2000, kill = 1500 }

-- The actual reload logic: filter in the background, then restart. `done`
-- MUST be called exactly once on every path — it clears the re-entrancy
-- guard (and replays a queued reload), so the guard also covers the filter.
-- A result that lands after `:cd` loaded another project belongs to the
-- old one: it is dropped and the reload replayed for the new project.
function M._start_reload(done, opts)
  local root = Path.key(State.root())
  M._filter_async(function(dir, info, changed)
    if Path.key(State.root()) ~= root then
      M._pending = { auto = opts.auto and (not M._pending or M._pending.auto) }
      done()
      return
    end
    local ok, err = pcall(function()
      restart(done, opts, cmd_from(dir, info, changed))
    end)
    if not ok then
      M._pending = false
      done()
      vim.notify("Scoper LSP: reload failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

-- `cmd` is guaranteed non-nil; `info` describes whether we filtered (and
-- by how much) or whether we restored the baseline cmd.
function restart(done, opts, cmd, info, changed)
  local key = table.concat(cmd, "\0")
  local clients = our_clients()
  if opts.auto and not changed and key == M._applied_cmd and #clients > 0 then
    done()
    return
  end
  M._applied_cmd = key
  M._apply(cmd)

  if #clients == 0 then
    -- Nothing to restart. An automatic reload stops here, quietly: with
    -- the integration on globally, most projects have no clangd at all.
    if not opts.auto then
      M._reattach(reattach_targets({}))
      notify_result(info, 0)
    end
    done()
    return
  end

  -- Only these ids are waited for: a clangd started meanwhile already has
  -- the new cmd and must be left running.
  local t = M._timing
  local ids, stopped_bufs = {}, {}
  for _, client in ipairs(clients) do
    table.insert(ids, client.id)
    for buf in pairs(client.attached_buffers or {}) do
      stopped_bufs[buf] = true
    end
    client:stop(t.grace)
  end

  -- Returns true once the restart is over (re-attached, or given up).
  local waited = 0
  local function tick()
    waited = waited + t.poll
    local remaining = 0
    for _, id in ipairs(ids) do
      if vim.lsp.get_client_by_id(id) then remaining = remaining + 1 end
    end
    if remaining > 0 and waited < t.grace + t.kill then return false end
    if remaining > 0 then
      -- Deliberately do NOT re-fire FileType here: starting a fresh clangd
      -- while the old one is alive yields two clients indexing the same
      -- project. Surface it and let the user retry once the exit finishes.
      vim.notify(
        (
          "Scoper LSP: %d clangd client(s) still exiting after %d ms "
          .. "(even after a forced stop) — skipped re-attach to avoid "
          .. "duplicate clients; run :ScoperLspReload to retry"
        ):format(remaining, waited),
        vim.log.levels.WARN
      )
    else
      M._reattach(reattach_targets(stopped_bufs))
      notify_result(info, #ids)
    end
    return true
  end

  local finished = false
  local timer = assert(vim.uv.new_timer())
  timer:start(
    t.poll,
    t.poll,
    vim.schedule_wrap(function()
      -- Ticks queued before timer:close() still run afterwards when the main
      -- loop was busy; they must not touch the closed handle or call done()
      -- a second time.
      if finished then return end
      -- Any error ends the restart too: a timer left running would retry
      -- the error every tick and the guard would never clear.
      local ok, over = pcall(tick)
      if ok and not over then return end
      finished = true
      timer:stop()
      timer:close()
      done()
      if not ok then
        vim.notify("Scoper LSP: clangd restart failed: " .. tostring(over), vim.log.levels.ERROR)
      end
    end)
  )
end

-- ---------------------------------------------------------------------------
-- setup() hook: install the clangd cmd before any client exists, so a
-- persisted enabled scope filters the very first index. Startup never
-- filters: on a cache miss (a CMake re-run touched compile_commands.json)
-- the previous filtered file is used as it is, and without one (first use
-- of a scope) the unfiltered database; the background refresh scheduled
-- here then restarts clangd only if the filtered database really changed.
-- ---------------------------------------------------------------------------
function M.apply_initial()
  local cmd, _, _, stale = build_cmd({ stale_ok = true })
  M._apply(cmd)
  M._applied_cmd = table.concat(cmd, "\0")
  if not stale then return end
  vim.schedule(function()
    M.reload_clangd({ auto = true })
  end)
end

-- ---------------------------------------------------------------------------
-- Auto-hook: re-run on every ScoperChanged event. Opt-in from setup().
-- ---------------------------------------------------------------------------
function M.attach_auto()
  vim.api.nvim_create_autocmd("User", {
    pattern = "ScoperChanged",
    group = vim.api.nvim_create_augroup("scoper_lsp_auto", { clear = true }),
    callback = function()
      -- Throttle: scope changes can fire rapidly during multi-add; debounce
      -- by 500ms so we only reload once after the last change.
      --
      -- vim.defer_fn returns a uv_timer that auto-closes itself when it
      -- fires. If we cancel it before it fires, we must close it manually
      -- or the libuv handle leaks — one per cancelled debounce.
      if M._timer and not M._timer:is_closing() then
        M._timer:stop()
        M._timer:close()
      end
      M._timer = vim.defer_fn(function()
        M.reload_clangd({ auto = true })
      end, 500)
    end,
  })
end

return M
