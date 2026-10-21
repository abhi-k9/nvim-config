-- lua/config/diagnostics.lua
--
-- :DiagnosticDump  — write a snapshot of nvim's state (version, paths,
--                    swap/undo settings, recent :messages, active LSP
--                    clients, loaded buffers w/ treesitter state, swap
--                    files, scoper's scope and clangd filter state, DAP
--                    session, plugin list, tail of lsp.log) to a single
--                    timestamped file under stdpath("log").
--
-- Intended for "nvim is weird, hand the file to someone" scenarios. The
-- file is plain text, but read it before you share it: :messages and the
-- LSP log tails can contain file paths, source text and environment
-- values (the dump's first line says so too). The DAP adapter and launch
-- config are redacted (M.redact); `:DiagnosticDump!` writes them as is.
--
-- When nvim is TOTALLY hung this command can't run (no input). The
-- workflow then is: force-kill, restart, run :DiagnosticDump in the
-- fresh nvim, and ALSO attach the previous lsp.log (it persists across
-- restarts — the dump points to it).

local M = {}

-- Capture the output of an ex command (e.g. :messages) as a string.
-- Wraps the nvim_exec2 quirks: pcall'd, returns a placeholder on error.
local function capture(cmd)
  local ok, result = pcall(vim.api.nvim_exec2, cmd, { output = true })
  if not ok then return "(failed to capture: " .. tostring(result) .. ")" end
  return result.output or ""
end

-- Return the last `max_bytes` of a file as a string, with a header line
-- noting we truncated. Used for log tails so a 200 MB clangd.log doesn't
-- end up appended to the report.
local function file_tail(path, max_bytes)
  max_bytes = max_bytes or 64 * 1024
  if vim.fn.filereadable(path) == 0 then return "(no file at " .. path .. ")" end
  local f = io.open(path, "rb")
  if not f then return "(could not open " .. path .. ")" end
  -- seek() returns nil for non-seekable files (a FIFO, some network
  -- shares); treat that as "read it all" instead of erroring on nil > n.
  local size = f:seek("end") or 0
  if size > max_bytes then
    f:seek("set", size - max_bytes)
    f:read("l") -- discard the partial first line so output isn't garbled
  else
    f:seek("set", 0)
  end
  local body = f:read("*a") or ""
  f:close()
  local prefix = (size > max_bytes)
      and ("(showing last %d KiB of %d KiB)\n\n"):format(
        math.floor(max_bytes / 1024),
        math.floor(size / 1024)
      )
    or ""
  return prefix .. body
end

-- Keys whose values a DAP adapter or launch config shouldn't leak.
local SECRET =
  { "token", "secret", "passw", "pwd", "auth", "credential", "api_?key", "cookie", "private" }

local function secret_key(k)
  k = tostring(k):lower():gsub("-", "_")
  for _, pat in ipairs(SECRET) do
    if k:find(pat) then return true end
  end
  return false
end

-- A copy of `v` with the values of secret-looking keys, and every value
-- of an `env` table, replaced by "<redacted>". Keys stay, so the shape of
-- the config is still visible.
function M.redact(v, redact_all, seen)
  if type(v) ~= "table" then
    if redact_all and type(v) ~= "function" then return "<redacted>" end
    return v
  end
  seen = seen or {}
  if seen[v] then return "<cycle>" end
  seen[v] = true
  local out = {}
  for k, val in pairs(v) do
    local hide = redact_all or secret_key(k)
    if type(val) == "table" then
      out[k] = M.redact(val, hide or k == "env", seen)
    else
      out[k] = hide and "<redacted>" or val
    end
  end
  return out
end

-- opts.raw: write the DAP section without redaction.
function M.dump(opts)
  opts = opts or {}
  local out = {
    "REVIEW BEFORE SHARING: :messages, the LSP log tails and the DAP config"
      .. " below can contain file paths, source text, environment values or tokens.",
  }
  local function section(title)
    table.insert(out, "\n===== " .. title .. " =====\n")
  end

  section("Generated")
  table.insert(out, os.date("%Y-%m-%d %H:%M:%S"))

  section("Version")
  table.insert(out, capture("version"))

  section("OS / paths")
  table.insert(
    out,
    ("Platform: %s"):format(
      vim.fn.has("win32") == 1 and "Windows" or vim.fn.has("mac") == 1 and "macOS" or "Unix-like"
    )
  )
  -- stylua: ignore start
  table.insert(out, ("stdpath('config') = %s"):format(vim.fn.stdpath("config")))
  table.insert(out, ("stdpath('data')   = %s"):format(vim.fn.stdpath("data")))
  table.insert(out, ("stdpath('log')    = %s"):format(vim.fn.stdpath("log")))
  table.insert(out, ("stdpath('cache')  = %s"):format(vim.fn.stdpath("cache")))
  table.insert(out, ("cwd               = %s"):format(vim.fn.getcwd()))
  -- stylua: ignore end

  section("Settings")
  for _, line in ipairs({
    ("NVIM_APPNAME = %s"):format(vim.env.NVIM_APPNAME or "(unset)"),
    ("swapfile = %s, directory = %s"):format(tostring(vim.o.swapfile), vim.o.directory),
    ("undofile = %s, undodir = %s"):format(tostring(vim.o.undofile), vim.o.undodir),
    ("updatetime = %d"):format(vim.o.updatetime),
    ("g:swap_guard = %s"):format(tostring(vim.g.swap_guard)),
    ("g:big_file_size = %s"):format(tostring(vim.g.big_file_size or "(default 1 MB)")),
    ("g:windows_tar_shim = %s"):format(tostring(vim.g.windows_tar_shim)),
    ("v:this_session = %s"):format(vim.v.this_session ~= "" and vim.v.this_session or "(none)"),
  }) do
    table.insert(out, line)
  end

  section(":messages (everything in the message history)")
  table.insert(out, capture("messages"))

  section("Active LSP clients")
  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    table.insert(out, "(none)")
  else
    for _, c in ipairs(clients) do
      local bufs = c.attached_buffers or {}
      table.insert(
        out,
        ("- %s [id=%d] root=%s buffers=%d"):format(
          c.name,
          c.id,
          c.root_dir or "?",
          vim.tbl_count(bufs)
        )
      )
    end
  end

  section("Loaded buffers")
  -- Useful when the hang correlates with a particular file: a >100k-line
  -- buffer with treesitter active is a common cause. We also report
  -- whether big_file mode kicked in.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      local ts_active = (vim.treesitter.highlighter.active or {})[buf] ~= nil
      table.insert(
        out,
        ("- buf %d: %s (ft=%s, lines=%d, ts=%s, big_file=%s)"):format(
          buf,
          name == "" and "<unnamed>" or vim.fn.fnamemodify(name, ":t"),
          vim.bo[buf].filetype == "" and "-" or vim.bo[buf].filetype,
          vim.api.nvim_buf_line_count(buf),
          tostring(ts_active),
          tostring(vim.b[buf].big_file == true)
        )
      )
    end
  end

  section("Swap files (as :SwapClean sees them)")
  local ok_swap, list, dirs = pcall(function()
    return require("config.autocmds.swap").inventory()
  end)
  if not ok_swap then
    table.insert(out, "(scan failed: " .. tostring(list) .. ")")
  else
    local counts = {}
    for _, s in ipairs(list) do
      counts[s.kind] = (counts[s.kind] or 0) + 1
    end
    local summary = {}
    for _, kind in ipairs({ "own", "live", "dirty", "clean", "empty", "unreadable" }) do
      if counts[kind] then table.insert(summary, ("%s=%d"):format(kind, counts[kind])) end
    end
    table.insert(
      out,
      ("%d in %s%s"):format(
        #list,
        table.concat(dirs, ", "),
        #summary > 0 and (" (" .. table.concat(summary, ", ") .. ")") or ""
      )
    )
    for i, s in ipairs(list) do
      if i > 20 then
        table.insert(out, ("… and %d more"):format(#list - 20))
        break
      end
      table.insert(
        out,
        ("- %-10s %s%s"):format(
          s.kind,
          s.fname or vim.fs.basename(s.swap),
          s.pid > 0 and (" (pid %d)"):format(s.pid) or ""
        )
      )
    end
  end

  section("Scoper")
  if not package.loaded["scoper"] then
    table.insert(out, "(scoper not loaded)")
  else
    local ok_sc, err = pcall(function()
      local State = require("scoper.state")
      local cfg = require("scoper").config or {}
      local scope = State.active_scope() or { include = {}, exclude = {} }
      table.insert(
        out,
        ("root = %s\nenabled = %s, active = %s (%d include, %d exclude)\nclangd integration = %s"):format(
          State.root(),
          tostring(State.is_enabled()),
          State.active_name(),
          #scope.include,
          #scope.exclude,
          tostring(cfg.lsp and cfg.lsp.clangd or false)
        )
      )
      local lsp = package.loaded["scoper.lsp"]
      if not lsp then
        table.insert(out, "(scoper.lsp not loaded)")
        return
      end
      local f, w = lsp._last_filter, lsp._last_worker
      table.insert(
        out,
        ("reloading = %s, pending = %s\napplied cmd = %s\nlast filter = %s\nlast background run = %s"):format(
          tostring(lsp._reloading),
          vim.inspect(lsp._pending),
          lsp._applied_cmd and lsp._applied_cmd:gsub("%z", " ") or "(none)",
          f and ("%s [%s]%s"):format(f.info, f.at, f.changed and " (changed)" or "") or "(none yet)",
          w and ("%s after %d ms"):format(w.outcome, w.ms) or "(none yet)"
        )
      )
    end)
    if not ok_sc then table.insert(out, "(failed: " .. tostring(err) .. ")") end
  end

  section("DAP session")
  local ok_dap, dap = pcall(require, "dap")
  if ok_dap and dap.session() then
    local s = dap.session()
    -- Heads-up first: adapter definitions and launch configs commonly
    -- embed environment blocks, tokens, or credential-bearing command
    -- lines, and this file's whole purpose is to be handed to someone.
    local function show(v)
      return vim.inspect(opts.raw and v or M.redact(v))
    end
    table.insert(
      out,
      opts.raw
          and "(NOTE: written as is (:DiagnosticDump!) — adapter/config below may embed env vars or secrets)"
        or "(env values and secret-looking keys redacted; :DiagnosticDump! writes them as is)"
    )
    table.insert(
      out,
      ("adapter=%s\nstopped_thread=%s\nconfig=%s"):format(
        show(s.adapter),
        tostring(s.stopped_thread_id),
        show(s.config)
      )
    )
  else
    table.insert(out, "(no active session)")
  end

  section("Plugins (lazy.nvim)")
  local ok_lazy, lazy = pcall(require, "lazy")
  if ok_lazy then
    for _, p in ipairs(lazy.plugins()) do
      table.insert(out, ("- %s%s"):format(p.name, p._.loaded and " [loaded]" or ""))
    end
  else
    table.insert(out, "(lazy not loaded)")
  end

  section("LSP log tail (last 64 KiB)")
  -- The LSP log is the highest-yield single artefact for diagnosing
  -- hangs — a misbehaving language server flooding requests or stuck on
  -- a slow operation shows up here in plain text.
  table.insert(out, file_tail(vim.lsp.log.get_filename(), 64 * 1024))

  -- The previous generation too: autocmds/lsplog.lua rotates lsp.log to
  -- lsp.log.old at startup once it passes 20 MB, so after a hang and a
  -- restart the relevant lines are usually THERE, not in the fresh file.
  local old = vim.lsp.log.get_filename() .. ".old"
  if vim.uv.fs_stat(old) then
    section("Previous LSP log (lsp.log.old) tail (last 64 KiB)")
    table.insert(out, file_tail(old, 64 * 1024))
  end

  -- The log directory may not exist on a fresh nvim install — stdpath
  -- returns the path, doesn't create it. mkdir -p is a no-op if the
  -- directory already exists.
  local log_dir = vim.fn.stdpath("log")
  vim.fn.mkdir(log_dir, "p")

  -- Filename: timestamp at second resolution + PID. The PID gives us
  -- uniqueness across (a) rapid double-invocations within the same
  -- second from one instance and (b) concurrent dumps from multiple
  -- Neovim instances debugging the same machine at once. Without it,
  -- collision-overwrite was possible and silent.
  -- A second dump in the same second gets a -2, -3, … suffix.
  local base = ("%s/diagnostic_%s_%d"):format(log_dir, os.date("%Y%m%d_%H%M%S"), vim.uv.os_getpid())
  local dest, n = base .. ".txt", 1
  while vim.uv.fs_stat(dest) do
    n = n + 1
    dest = ("%s-%d.txt"):format(base, n)
  end
  -- writefile returns 0 on success, -1 on failure (disk full, permission
  -- denied, write to a non-writable filesystem). The user typically runs
  -- this command because something is already wrong; failing silently
  -- here would leave them debugging the wrong problem ("the dump says
  -- the LSP attached fine — but actually the dump didn't save").
  if vim.fn.writefile(vim.split(table.concat(out, "\n"), "\n"), dest) ~= 0 then
    vim.notify(
      ("Diagnostic dump FAILED to write %s (disk full? permissions?)"):format(dest),
      vim.log.levels.ERROR
    )
    return nil
  end
  vim.notify(("Diagnostic dump → %s"):format(dest), vim.log.levels.INFO)
  return dest
end

vim.api.nvim_create_user_command("DiagnosticDump", function(cmd)
  M.dump({ raw = cmd.bang })
end, {
  bang = true,
  desc = "Write a diagnostic snapshot to stdpath('log') (! = DAP config unredacted)",
})

return M
