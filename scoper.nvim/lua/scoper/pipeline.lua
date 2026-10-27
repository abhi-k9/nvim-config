-- Database selection, filtering, immutable cache and background delivery.
-- This module consumes captured scope data; clangd configuration belongs to lsp.lua.
local State = require("scoper.state")
local Path = require("scoper.path")
local Util = require("scoper.util")
local Cdb = require("scoper.cdb")
local M = {}
local runtime = M
function M.bind(owner)
  runtime = owner or M
end
local Database = require("scoper.database")
local function config()
  return require("scoper").config or {}
end
function M.mode()
  return (config().lsp or {}).mode or "filtered"
end
function M.resolve()
  local opts = vim.deepcopy(config().compilation_database or {})
  local selected = State.database and State.database()
  if selected then
    opts.path, opts.resolver = selected, nil
  end
  local context = State.snapshot and State.snapshot()
    or { root = State.root(), scope = State.active_name() }
  local ok, result =
    pcall(Database.resolve, State.root(), opts, context, (config().lsp or {}).mode == nil)
  M._selection = ok and result
    or { candidates = {}, reason = "database resolution failed: " .. tostring(result) }
  return vim.deepcopy(M._selection)
end
function M.context_key()
  local snap = State.snapshot and State.snapshot()
    or { root = State.root(), scope = State.active_name(), definition = State.active_scope() }
  local selection = M.resolve()
  return vim.fn.sha256(vim.json.encode({
    snap.root,
    snap.scope,
    snap.revision or 0,
    snap.definition,
    M.mode(),
    selection.path or selection.requested,
    (config().lsp or {}).cmd,
    (config().lsp or {}).clangd_args,
    (config().lsp or {}).extra_args,
    (config().lsp or {}).query_drivers,
  }))
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
  -- Preserve readable cache paths for ordinary names. Legacy logical names
  -- such as CON or frontend. must remain loadable, but Windows rejects those
  -- components (including device names with extensions); long names also
  -- exceed the component limit on Unix. Encode only those cache components.
  local name = State.active_name()
  local scope = name:gsub("[^%w_%-%.]", "_")
  local stem = (scope:match("^[^%.]+") or ""):upper()
  if
    #scope > 255
    or scope:sub(-1) == "."
    or stem == "CON"
    or stem == "PRN"
    or stem == "AUX"
    or stem == "NUL"
    or stem:match("^COM[1-9]$")
    or stem:match("^LPT[1-9]$")
  then
    scope = "scope-" .. vim.fn.sha256(name):sub(1, 32)
  end
  return Path.normalize(
    vim.fn.stdpath("cache") .. "/scoper/" .. hash .. "/" .. scope .. "/" .. fingerprint:sub(1, 32)
  )
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
  for _ = 1, 2 do
    local res, job = prepare(opts)
    res = res or Cdb.run(job)
    if
      not res.stale_source
      and (not job or not res.dir or Cdb.same_stamp(job.meta.source, Cdb.stamp(job.cc)))
    then
      return finish(res)
    end
  end
  return finish({ info = "compile_commands.json kept changing while filtering" })
end

-- The cheap half of the filter: the state checks and the freshness cache.
-- Returns a finished result ({ dir, info, changed, stale }, as returned
-- by cdb.run) or nil plus the job for cdb.run.
function prepare(opts)
  local mode = M.mode()
  if mode == "disabled" or mode == "native" then return { info = mode, reason = mode } end
  local selection = M.resolve()
  local cc = selection.path
  local scope = vim.deepcopy(State.active_scope())
  local scoped = mode == "filtered" and State.is_enabled() and scope and #scope.include > 0
  -- clangd accepts a directory, not an arbitrary filename. Publish a full,
  -- immutable copy when the selected source has a different basename.
  local copy = cc and vim.fs.basename(cc) ~= "compile_commands.json" and not scoped
  if mode == "selected" and not copy then
    return { info = selection.reason, reason = cc and "selected" or "unavailable", source = cc }
  end
  if not copy and not State.is_enabled() then
    return { info = "disabled", reason = "scope_disabled" }
  end
  if not copy and (not scope or #scope.include == 0) then
    return { info = "active scope is empty", reason = "empty_scope" }
  end
  if not cc then return { info = selection.reason, reason = "unavailable" } end
  scope = scope or { include = {}, exclude = {} }

  -- -------------------------------------------------------------------
  -- Freshness cache. setup() applies the clangd cmd at startup, so
  -- without a cache every launch would readfile + decode + filter +
  -- rewrite the compile database (~400-500 ms for 10k entries / 20 MB)
  -- even though nothing changed — the overwhelmingly common case.
  --
  -- The filtered output only depends on two inputs: the SOURCE
  -- compile_commands.json (identified by path, timestamps, inode and size)
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
    -- Output objects and source/output generation checks changed. Keep older
    -- versions from sharing their mutable output/metadata with this layout.
    4,
    Path.key(State.root()),
    cc,
    mode,
    scope.include,
    scope.exclude,
  }))
  local out_dir = cache_dir(fingerprint)
  local meta_path = out_dir .. "/.scoper-meta.json"
  local source = Cdb.stamp(cc)
  local meta = read_json(meta_path)
  local digest = meta and meta.digest
  local valid_meta = type(digest) == "string"
    and #digest == 64
    and digest:match("^[0-9a-f]+$")
    and type(meta.kept) == "number"
    and meta.kept >= 0
    and meta.kept % 1 == 0
    and type(meta.total) == "number"
    and meta.total >= meta.kept
    and meta.total % 1 == 0
    and meta.fingerprint == fingerprint
  local result_dir = valid_meta and out_dir .. "/objects/" .. digest or nil
  local out_path = result_dir and result_dir .. "/compile_commands.json" or nil
  -- Ordinary same-size rewrites also change mtime/ctime or inode identity.
  -- Keep warm hits stat-only; the publisher hashes each object when reusing it.
  local have_intact_out = out_path and Cdb.same_stamp(meta.out_stamp, Cdb.stamp(out_path))
  if have_intact_out and meta.src == cc and Cdb.same_stamp(meta.source, source) then
    return {
      dir = result_dir,
      info = ("%d/%d entries kept → %s (cached)"):format(
        meta.kept or 0,
        meta.total or 0,
        out_path
      ),
      changed = false,
      reason = copy and "selected" or "cached",
      source = cc,
      kept = meta.kept,
      total = meta.total,
    }
  end
  if opts and opts.stale_ok then
    if not have_intact_out then
      return { info = "filter pending", stale = true, reason = "pending", source = cc }
    end
    return {
      dir = result_dir,
      info = ("previous filter result → %s (refresh pending)"):format(out_path),
      changed = false,
      stale = true,
      reason = "stale",
      source = cc,
      kept = meta.kept,
      total = meta.total,
    }
  end

  return nil,
    {
      cc = cc,
      kind = copy and "copy" or "filter",
      context = M.context_key(),
      root = State.root(),
      scope = { include = scope.include, exclude = scope.exclude },
      out_dir = out_dir,
      -- The inputs that produced the output (see the cache block above).
      meta = {
        src = cc,
        source = source,
        fingerprint = fingerprint,
      },
      old_digest = have_intact_out and meta.digest or nil,
    }
end

-- For :DiagnosticDump-style reports: the last filter result, and how the
-- last background run ended.
M._last_result = nil

function finish(res)
  M._last_result = vim.tbl_extend("force", vim.deepcopy(res), {
    context_key = M.context_key(),
    mode = M.mode(),
    selection = vim.deepcopy(M._selection),
    reason = res.reason or (res.dir and "filtered" or "unavailable"),
    freshness = res.stale and "pending"
      or ((res.dir or res.reason == "selected") and "ready" or "unfiltered"),
    at = os.date("%Y-%m-%d %H:%M:%S"),
  })
  runtime._last_filter = vim.deepcopy(M._last_result)
  if res.warn then vim.notify(res.warn, vim.log.levels.WARN) end
  return res.dir, res.info, res.changed, res.stale
end
function M.status()
  local mode = M.mode()
  if mode == "disabled" or mode == "native" then
    return {
      mode = mode,
      reason = mode,
      freshness = mode,
      selection = {
        candidates = {},
        reason = mode == "native" and "native discovery" or "disabled",
      },
      worker = vim.deepcopy(runtime._last_worker),
    }
  end
  local last = M._last_result or {}
  if last.context_key ~= M.context_key() then last = {} end
  local selection = M.resolve()
  return vim.tbl_extend("force", vim.deepcopy(last), {
    mode = mode,
    selection = selection,
    reason = last.reason or selection.reason,
    freshness = last.freshness or "unprepared",
    worker = vim.deepcopy(runtime._last_worker),
  })
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
local function run_in_background(job, cb, opts)
  job_seq = job_seq + 1
  local base = ("%s/.scoper-job-%d-%d"):format(job.out_dir, vim.fn.getpid(), job_seq)
  local job_path, result_path = base .. ".json", base .. ".result.json"
  local started = vim.uv.hrtime()
  local function cleanup(outcome)
    os.remove(job_path)
    os.remove(result_path)
    runtime._last_worker = { outcome = outcome, ms = math.floor((vim.uv.hrtime() - started) / 1e6) }
  end
  local function run_here(why)
    if opts and opts.no_sync then
      cleanup("failed (" .. why .. ")")
      return cb({ info = "background preparation failed: " .. why, reason = "worker_failed" })
    end
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

  local made, mkdir_error = pcall(vim.fn.mkdir, job.out_dir, "p")
  if not made then
    cleanup("failed (cannot create cache directory)")
    return cb({
      info = "cannot create filter cache: " .. tostring(mkdir_error),
      warn = "Scoper LSP: cannot create filter cache: " .. tostring(mkdir_error),
    })
  end
  local wrote, write_result = pcall(vim.fn.writefile, { vim.json.encode(job) }, job_path)
  if not wrote or write_result ~= 0 then return run_here("can't write " .. job_path) end
  local ok, err = pcall(
    vim.system,
    runtime._worker_cmd(job_path, result_path),
    { text = true, timeout = runtime._worker_timeout },
    function(proc)
      vim.schedule(function()
        local res = proc.code == 0 and read_json(result_path)
        if res then
          cleanup("ok")
          return cb(res)
        end
        if proc.code == 124 then
          cleanup("timed out")
          return cb({
            info = ("filter timed out after %d s"):format(runtime._worker_timeout / 1000),
          })
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
  local function attempt(retries)
    local res, job = prepare(opts)
    if res then return cb(finish(res)) end
    run_in_background(job, function(r)
      if job.context ~= M.context_key() then
        -- The old operation must neither publish status for the new context
        -- nor hand a stale output to a restart caller.
        return cb(nil, "project, scope or database selection changed", false, true, true)
      end
      if r.stale_source or (r.dir and not Cdb.same_stamp(job.meta.source, Cdb.stamp(job.cc))) then
        if retries > 0 then return attempt(retries - 1) end
        return cb(finish({ info = "compile_commands.json kept changing while filtering" }))
      end
      cb(finish(r))
    end, opts)
  end
  attempt(1)
end

return M
