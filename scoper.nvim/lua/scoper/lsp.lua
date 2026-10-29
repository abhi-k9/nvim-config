-- Optional clangd adapter. Database preparation/worker delivery lives in pipeline.lua.
local State = require("scoper.state")
local Path = require("scoper.path")
local Pipeline = require("scoper.pipeline")
local Cdb = require("scoper.cdb")
local M = {}
Pipeline.bind(M)
M._extra_args = nil
M._worker_cmd = Pipeline._worker_cmd
M._worker_timeout = Pipeline._worker_timeout
function M.write_filtered_compile_commands(opts)
  return Pipeline.write_filtered_compile_commands(opts)
end
function M._filter_async(cb, opts)
  return Pipeline._filter_async(cb, opts)
end
function M._filter_entries(entries, cwd)
  return Cdb.filter(entries, State.matcher(cwd))
end
local function find_compile_commands()
  return Pipeline.resolve().path
end
local function base_clangd_cmd()
  local cfg = require("scoper").config.lsp or {}
  local configured = cfg.cmd or M._base_cmd or { "clangd" }
  if type(configured) == "string" then configured = { configured } end
  assert(
    type(configured) == "table" and vim.islist(configured) and #configured > 0,
    "Scoper lsp.cmd must be a nonempty argv list"
  )
  local cmd = vim.deepcopy(configured)
  vim.list_extend(cmd, cfg.clangd_args or {})
  vim.list_extend(cmd, cfg.extra_args or {})
  if cfg.query_drivers and #cfg.query_drivers > 0 then
    cmd[#cmd + 1] = "--query-driver=" .. table.concat(cfg.query_drivers, ",")
  end
  vim.list_extend(cmd, M._extra_args or {})
  for _, arg in ipairs(cmd) do
    assert(type(arg) == "string", "clangd argv must contain strings")
  end
  return cmd
end
local function cmd_from(filtered_dir, info, changed, stale)
  local cmd = base_clangd_cmd()
  local mode = Pipeline.mode()
  if mode == "native" or mode == "disabled" then return cmd, info, false, false end

  -- A selected database replaces only this argument. All other user flags
  -- (including compiler trust) remain intact.
  local i = 2
  while i <= #cmd do
    if cmd[i] == "--compile-commands-dir" then
      table.remove(cmd, i)
      table.remove(cmd, i)
    elseif cmd[i]:match("^%-%-compile%-commands%-dir=") then
      table.remove(cmd, i)
    else
      i = i + 1
    end
  end

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
  if raw and vim.fs.basename(raw) ~= "compile_commands.json" then
    return cmd,
      info .. "; selected source has no prepared copy; clangd will use built-in discovery",
      nil,
      stale
  end
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
-- Build clangd argv from a valid configured/inherited command. The
-- `--compile-commands-dir` flag is prepended in two cases:
--
--   1. Filtering succeeded — dir points at the scoper cache holding the
--      filtered JSON.
--   2. Filtering didn't apply but scoper can still locate the
--      project's real compile_commands.json — dir points at that
--      file's containing directory.
--
-- A custom-named selected source needs a prepared canonical copy first.
-- Without a usable source/copy, clangd retains its own database discovery.
-- Native/disabled modes preserve existing compilation-directory arguments.
--
-- In managed modes --compile-commands-dir selects the chosen database ahead
-- of .clangd's CompileFlags.CompilationDatabase search setting. Other .clangd
-- flags/configuration still apply; selecting a database does not disable them.
--
-- `extra_args` are appended after `lsp.clangd_args` and remembered: every
-- later reload (scope edits, :ScoperLspReload) keeps them until the next
-- call that passes a list.
--
-- Returns cmd, info, changed (see write_filtered_compile_commands).
--
-- This compatibility API returns ready argv, filtering synchronously on a
-- cold miss. Managed startup can prepare asynchronously instead. Invalid argv
-- configuration raises an error; returning a command does not install clangd.
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
-- function on every C buffer, so install the function only once the executable
-- is available (on PATH or through an explicit command path).
--
-- A clangd from mason.nvim is on PATH only once mason has loaded, which is
-- often after setup(). Until then a C buffer's FileType installs the
-- function as soon as clangd is there. That handler runs before
-- vim.lsp.enable()'s if setup() ran before the first vim.lsp.enable()
-- (autocmds for one event run oldest first).
function M._apply(cmd)
  M._cmd = cmd
  if not M._ownership then M._ownership = { cmd = (vim.lsp.config.clangd or {}).cmd } end
  if vim.fn.executable(cmd[1]) == 1 then
    vim.lsp.config("clangd", { cmd = spawn })
    M._owned_cmd = spawn
    return
  end
  vim.lsp.config("clangd", { cmd = cmd })
  M._owned_cmd = cmd
  local group = vim.api.nvim_create_augroup("scoper_clangd_cmd", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = vim.tbl_keys(C_FAMILY),
    callback = function()
      if vim.fn.executable(M._cmd[1]) ~= 1 then return end
      vim.lsp.config("clangd", { cmd = spawn })
      M._owned_cmd = spawn
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
-- Selected/filtered and legacy manual modes refresh the chosen input. Native
-- and disabled modes return immediately. In filtered mode, toggling the scope
-- swaps between an immutable filtered copy and the selected complete database.
--
-- opts.auto (set by the ScoperChanged listener): skip the restart when it
-- would change nothing — same cmd as the one last applied, the filtered
-- database unchanged, and clangd already running — so edits that don't
-- affect clangd (any edit while scoping is off, or a database edit to
-- out-of-scope files) keep its warm in-memory index. Automatic reloads are also
-- silent when no clangd of this project runs. :ScoperLspReload always
-- restarts and reports.
-- ---------------------------------------------------------------------------
local function stale_auto(opts)
  return opts.auto and opts._generation ~= (M._auto_generation or 0)
end

local function queue_reload(opts)
  -- A forced request must not be downgraded by a later automatic one.
  local auto = opts.auto and (not M._pending or M._pending.auto)
  M._pending = { auto = auto, _generation = auto and opts._generation or nil }
end

function M.reload_clangd(opts)
  if Pipeline.mode() == "disabled" or Pipeline.mode() == "native" then return end
  opts = vim.tbl_extend("force", {}, opts or {})
  if opts.auto then
    opts._generation = opts._generation or (M._auto_generation or 0)
    if stale_auto(opts) then return end
  end
  -- Re-entrancy guard + pending flag. The reload below is ASYNCHRONOUS
  -- (a libuv timer polls for the old clients to exit instead of
  -- blocking), so a ScoperChanged debounce can absolutely fire while a
  -- reload is mid-flight. Dropping that call would lose the LAST update
  -- (clangd stuck on a stale scope), so a reload requested during a
  -- reload is remembered and replayed exactly once when the in-flight one
  -- finishes.
  if M._reloading then
    queue_reload(opts)
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
-- after which Client:stop() kills the process; then how long the killed process
-- gets to be reaped. A forced stop may require rebuilding unfinished index work.
-- A table so lsp_spec can shorten the budgets.
M._timing = { poll = 50, grace = 2000, kill = 1500 }

-- The actual reload logic: filter in the background, then restart. `done`
-- MUST be called exactly once on every path — it clears the re-entrancy
-- guard (and replays a queued reload), so the guard also covers the filter.
-- A result that lands after `:cd` loaded another project belongs to the
-- old one: it is dropped and the reload replayed for the new project.
function M._start_reload(done, opts)
  local root = Path.key(State.root())
  local context = Pipeline.context_key()
  M._filter_async(function(dir, info, changed, _, obsolete)
    if stale_auto(opts) then
      done()
      return
    end
    if Path.key(State.root()) ~= root or obsolete or Pipeline.context_key() ~= context then
      queue_reload(opts)
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
  local context = Pipeline.context_key()
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
    if stale_auto(opts) then return true end
    if Pipeline.context_key() ~= context then
      queue_reload(opts)
      return true
    end
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
-- setup() stages a command without synchronously parsing a database. Fallback
-- startup uses an intact previous object or the complete selected database on a
-- cold miss, then refreshes. Strict prepare startup instead waits at the root
-- callback before attachment; it does not schedule this fallback refresh.
-- ---------------------------------------------------------------------------
function M.apply_initial()
  if Pipeline.mode() == "disabled" or Pipeline.mode() == "native" then return end
  local cmd, _, _, stale = build_cmd({ stale_ok = true })
  M._apply(cmd)
  M._applied_cmd = table.concat(cmd, "\0")
  if (require("scoper").config.lsp or {}).startup == "prepare" then return end
  if not stale then return end
  local generation = M._auto_generation
  vim.schedule(function()
    if generation == M._auto_generation then M.reload_clangd({ auto = true }) end
  end)
end

-- ---------------------------------------------------------------------------
-- Auto-hook: re-run on every ScoperChanged event. Opt-in from setup().
-- ---------------------------------------------------------------------------
function M.detach_auto()
  -- Closing a timer does not cancel a callback already queued on the main
  -- loop. A generation also invalidates that callback and initial refreshes.
  M._auto_generation = (M._auto_generation or 0) + 1
  if M._pending and M._pending.auto then M._pending = false end
  pcall(vim.api.nvim_del_augroup_by_name, "scoper_lsp_auto")
  if M._timer and not M._timer:is_closing() then
    M._timer:stop()
    M._timer:close()
  end
  M._timer = nil
  if M._watcher and not M._watcher:is_closing() then
    M._watcher:stop()
    M._watcher:close()
  end
  M._watcher, M._watch_path, M._watch_stamp = nil, nil, nil
end

function M.attach_auto()
  M.detach_auto()
  local generation = M._auto_generation
  local group = vim.api.nvim_create_augroup("scoper_lsp_auto", { clear = true })
  local function debounce()
    if M._timer and not M._timer:is_closing() then
      M._timer:stop()
      M._timer:close()
    end
    local timer
    timer = vim.defer_fn(function()
      if M._timer ~= timer or generation ~= M._auto_generation then return end
      M._timer = nil
      M.reload_clangd({ auto = true })
    end, (require("scoper").config.lsp or {}).debounce_ms or 500)
    M._timer = timer
  end
  M._debounce = debounce

  local function check_source(force, initial)
    local selection = Pipeline.resolve()
    local path = selection.path or selection.requested
    local changed_path = path ~= M._watch_path
    local stamp = path and Cdb.stamp(path)
    local changed = changed_path or not vim.deep_equal(stamp, M._watch_stamp)
    if changed_path or (path and not M._watcher) then
      if M._watcher and not M._watcher:is_closing() then
        M._watcher:stop()
        M._watcher:close()
      end
      M._watcher = nil
      M._watch_path = path
      if path and (require("scoper").config.lsp or {}).watch ~= false then
        local watcher = vim.uv.new_fs_event()
        if watcher then
          local ok = watcher:start(
            vim.fs.dirname(path),
            {},
            vim.schedule_wrap(function(err, filename)
              if err or generation ~= M._auto_generation then return end
              if not filename or filename == vim.fs.basename(path) then check_source(false) end
            end)
          )
          if ok then
            M._watcher = watcher
          else
            watcher:close()
          end
        end
      end
    end
    M._watch_stamp = stamp
    if not initial and (force or changed) then debounce() end
  end
  M.check_source = check_source
  -- Bind without scheduling a redundant initial reload.
  check_source(false, true)
  vim.api.nvim_create_autocmd("User", {
    pattern = "ScoperChanged",
    group = group,
    callback = function()
      -- Throttle: scope changes can fire rapidly during multi-add; debounce
      -- by lsp.debounce_ms (500ms by default) after the last change.
      --
      -- vim.defer_fn returns a uv_timer that auto-closes itself when it
      -- fires. If we cancel it before it fires, we must close it manually
      -- or the libuv handle leaks — one per cancelled debounce.
      check_source(true)
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      check_source(false)
    end,
  })
end

-- A bounded asynchronous startup gate for vim.lsp.enable(). The root callback
-- contract allows preparation without blocking UI or launching unfiltered first.
-- A timeout keeps the buffer unattached; manual reload can retry afterwards.
local function install_prepare_gate()
  local current = vim.lsp.config.clangd or {}
  local provider = current.root_dir
  M._ownership = M._ownership or { cmd = current.cmd }
  M._ownership.root_dir = provider
  local generation = M._auto_generation
  local function gate(buf, on_dir)
    local function resolved(root)
      if not ours(root) or not Path.is_under(vim.api.nvim_buf_get_name(buf), State.root()) then
        return on_dir(root)
      end
      local finished = false
      local timeout = (require("scoper").config.lsp or {}).prepare_timeout_ms or 5000
      local timer = vim.defer_fn(function()
        if finished then return end
        finished = true
        if generation ~= M._auto_generation then return end
        M._startup =
          { state = "timed_out", reason = "preparation timed out; run :ScoperLspReload to retry" }
        vim.notify("Scoper LSP: " .. M._startup.reason, vim.log.levels.WARN)
      end, timeout)
      M._startup = { state = "preparing" }
      local function complete()
        finished = true
        if not timer:is_closing() then
          timer:stop()
          timer:close()
        end
      end
      local attempt
      attempt = function()
        if finished then return end
        if generation ~= M._auto_generation or not vim.api.nvim_buf_is_valid(buf) then
          return complete()
        end
        if not Path.is_under(vim.api.nvim_buf_get_name(buf), State.root()) then
          complete()
          return on_dir(root)
        end
        local context = Pipeline.context_key()
        M.prepare(function(dir, info, changed, _, obsolete)
          if finished then return end
          if generation ~= M._auto_generation then return complete() end
          if obsolete or context ~= Pipeline.context_key() then
            -- Retry the current selection without resetting the original
            -- timeout budget. Old work can never strand the waiting buffer.
            return vim.schedule(attempt)
          end
          complete()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          local selection = Pipeline.resolve()
          local snapshot = State.snapshot()
          local restricted = Pipeline.mode() == "filtered"
            and snapshot.enabled
            and snapshot.definition
            and #snapshot.definition.include > 0
          local selected_ready = not restricted
            and selection.path
            and vim.fs.basename(selection.path) == "compile_commands.json"
          if not dir and not selected_ready then
            M._startup = { state = "unavailable", reason = info }
            vim.notify("Scoper LSP: database startup unavailable: " .. info, vim.log.levels.WARN)
            return
          end
          local cmd = cmd_from(dir, info, changed)
          M._apply(cmd)
          M._applied_cmd = table.concat(cmd, "\0")
          M._startup = { state = "ready" }
          on_dir(root)
        end)
      end
      attempt()
    end
    if type(provider) == "function" then return provider(buf, resolved) end
    local root = provider
    if root == nil then
      local markers = (vim.lsp.config.clangd or {}).root_markers
      root = markers and vim.fs.root(buf, markers) or nil
    end
    resolved(root)
  end
  M._owned_root = gate
  vim.lsp.config("clangd", { root_dir = gate })
end

function M.configure()
  local cfg = require("scoper").config.lsp or {}
  M._startup = { state = cfg.startup == "prepare" and "waiting" or "fallback" }
  local mode = Pipeline.mode()
  assert(
    vim.tbl_contains({ "disabled", "native", "selected", "filtered" }, mode),
    "invalid Scoper lsp.mode"
  )
  if mode == "disabled" or mode == "native" then
    M._startup = { state = mode }
    return
  end
  local current = (vim.lsp.config.clangd or {}).cmd
  assert(
    type(current) ~= "function" or cfg.cmd ~= nil,
    "selected/filtered integration with a function-valued clangd cmd requires explicit lsp.cmd argv"
  )
  if type(current) == "table" and current ~= M._owned_cmd then
    M._base_cmd = vim.deepcopy(current)
  end
  if mode ~= "native" then M.attach_auto() end
  M.apply_initial()
  if cfg.startup == "prepare" then install_prepare_gate() end
end

-- Multiple C-family buffers opening together share one captured preparation.
function M.prepare(callback)
  local context = Pipeline.context_key()
  if M._preparing and M._preparing.context == context then
    M._preparing.callbacks[#M._preparing.callbacks + 1] = callback
    return
  end
  local pending = { context = context, callbacks = { callback } }
  M._preparing = pending
  M._filter_async(function(...)
    if M._preparing == pending then M._preparing = nil end
    for _, cb in ipairs(pending.callbacks) do
      local ok, err = pcall(cb, ...)
      if not ok then
        vim.notify(
          "Scoper LSP: preparation callback failed: " .. tostring(err),
          vim.log.levels.ERROR
        )
      end
    end
  end, { no_sync = true })
end

function M.dispose()
  M.detach_auto()
  M._preparing = nil
  M._startup, M._cmd = nil, nil
  pcall(vim.api.nvim_del_augroup_by_name, "scoper_clangd_cmd")
  if not M._ownership then return end
  local current = vim.lsp.config.clangd or {}
  local restore = vim.deepcopy(current)
  local changed = false
  if
    current.cmd == M._owned_cmd
    or (type(current.cmd) == "table" and vim.deep_equal(current.cmd, M._owned_cmd))
  then
    restore.cmd, changed = M._ownership.cmd, true
  end
  if current.root_dir == M._owned_root then
    restore.root_dir, changed = M._ownership.root_dir, true
  end
  if changed then
    local configs = vim.lsp.config
    -- Replacement is Neovim's public API; merge cannot remove an owned key.
    configs.clangd = restore -- luacheck: ignore 122
  end
  M._ownership, M._owned_cmd, M._owned_root, M._base_cmd = nil, nil, nil, nil
end

-- Reconcile final server options before activation, without reloading scopes.
function M.reconfigure()
  M.dispose()
  local cfg = require("scoper").config.lsp or {}
  if cfg.mode ~= nil or cfg.clangd then M.configure() end
end

function M.status()
  local result = Pipeline.status()
  result.startup = vim.deepcopy(M._startup or { state = "fallback" })
  result.automatic = result.mode ~= "disabled"
    and result.mode ~= "native"
    and (
      (require("scoper").config.lsp or {}).mode ~= nil
      or (require("scoper").config.lsp or {}).clangd == true
    )
  result.effective = M._owned_cmd and M._cmd and vim.deepcopy(M._cmd) or nil
  return result
end

return M
