-- lua/config/dap.lua
--
-- nvim-dap setup, called from the nvim-dap spec in lua/plugins/dap.lua
-- (which keeps the keymaps and the other debugger plugins):
--   * dap.pause without the thread picker (toggle: <leader>dT)
--   * breakpoint / stopped-line signs
--   * :DapLoadLaunchJSON (validate .vscode/launch.json)
--   * adapter types: cppdbg, codelldb, python (debugpy), bashdb
--   * fallback configurations for C/C++/Rust, Python and Bash

local M = {}
local Settings = require("config.settings")
local instances = setmetatable({}, { __mode = "k" })

function M.root()
  return Settings.resolve(Settings.get("debug.root", "cwd"))
end

function M.launch_file(root)
  root = root or M.root()
  local path = Settings.get("debug.launch_file", ".vscode/launch.json")
  if type(path) == "function" then path = path(root, vim.api.nvim_get_current_buf()) end
  if path == false then return nil end
  assert(type(path) == "string" and path ~= "", "debug.launch_file must return a path or false")
  path = vim.fs.normalize(path, { expand_env = false })
  if path:sub(1, 1) ~= "/" and not path:match("^%a:[/\\]") and path:sub(1, 2) ~= "\\\\" then
    path = vim.fs.joinpath(root, path)
  end
  return vim.fs.normalize(path, { expand_env = false })
end

-- Bind only workspace variables; nvim-dap retains ownership of file/env/input
-- expansion. A callable VS Code configuration keeps its input prompt behavior.
local function bind_workspace(value, root)
  if type(value) == "string" then
    return (
      value
        :gsub("%${workspaceFolderBasename}", function()
          return vim.fs.basename(root)
        end)
        :gsub("%${workspaceFolder}", function()
          return root
        end)
    )
  end
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do
    result[key] = bind_workspace(item, root)
  end
  local mt = getmetatable(value)
  if mt and mt.__call then
    local wrapped = vim.tbl_extend("force", mt, {
      __call = function(_, ...)
        return bind_workspace(value(...), root)
      end,
    })
    return setmetatable(result, wrapped)
  end
  return setmetatable(result, mt)
end

local function configure_launch_provider(dap, owned)
  local providers = dap.providers and dap.providers.configs
  if not providers then return end -- also supports minimal adapter-only hosts
  -- Install once even when the initial project has no override. Trusted
  -- project overlays can change later, so root/source policy is resolved on
  -- invocation. A user replacing our provider takes ownership permanently;
  -- repeated setup must not silently replace that later customization.
  if owned.provider then return end
  owned.previous_provider = providers["dap.launch.json"]
  owned.provider = function(...)
    local configured = Settings.get("debug.root") ~= nil or Settings.get("debug.launch_file") ~= nil
    if not configured then
      if owned.previous_provider then return owned.previous_provider(...) end
      return {}
    end
    local root = M.root()
    local path = M.launch_file(root)
    if not path then return {} end
    local ok, configs = pcall(require("dap.ext.vscode").getconfigs, path)
    if not ok then
      vim.notify_once(
        "Cannot read debugger launch file: " .. tostring(configs),
        vim.log.levels.WARN
      )
      return {}
    end
    return bind_workspace(configs, root)
  end
  providers["dap.launch.json"] = owned.provider
end

function M.setup()
  local dap = require("dap")
  local owned = instances[dap]
  if not owned then
    owned = { adapters = {}, fallbacks = {} }
    instances[dap] = owned
  end
  local adapters, fallbacks = {}, { cpp = {}, python = {}, sh = {}, bash = {} }

  -- -----------------------------------------------------------------------
  -- Pause without the "which thread?" picker (with an escape hatch).
  --
  -- DAP's `pause` request targets a single threadId, so nvim-dap prompts
  -- you to choose when a session has multiple threads. codelldb is
  -- ALL-STOP: pausing any one thread halts the whole program, so the
  -- choice is meaningless and we just grab the first thread.
  --
  -- Some adapters DO support meaningful per-thread pausing (non-stop mode).
  -- Flip vim.g.dap_pause_pick_thread via <leader>dT to restore nvim-dap's
  -- built-in picker for those. An EXPLICIT threadId — e.g. the dap-ui
  -- Threads panel's own pause action — bypasses both paths and pauses
  -- that requested thread ID unchanged regardless of the toggle; whether
  -- other threads stop too is the adapter's execution model.
  -- -----------------------------------------------------------------------
  if vim.g.dap_pause_pick_thread == nil then
    vim.g.dap_pause_pick_thread = Settings.get("debug.pause_pick_thread", false)
  end
  local _pause = dap.pause == owned.pause and owned.previous_pause or dap.pause
  owned.previous_pause = _pause
  owned.pause = function(thread_id)
        -- stylua: ignore start
        if thread_id then return _pause(thread_id) end          -- explicit id wins
        if vim.g.dap_pause_pick_thread then return _pause() end  -- restore picker
    -- stylua: ignore end
    local s = dap.session()
    if not s then return _pause() end
    s:request("threads", nil, function(_, resp)
      -- The threads request is async; the session can terminate (or
      -- be replaced by a restart) before this callback runs. Pausing
      -- into a dead/different session is at best a warning, at worst
      -- targets a thread id from the wrong process — just drop it.
      if dap.session() ~= s then return end
      local t = resp and resp.threads and resp.threads[1]
      _pause(t and t.id or nil) -- all-stop: any thread halts all
    end)
  end

  dap.pause = owned.pause

  -- Pretty signs for breakpoints, the stopped line, etc.
  local sign = vim.fn.sign_define
  local icons = Settings.get("ui.icons", true) ~= false
  local function glyph(symbol, ascii)
    return icons and symbol or ascii
  end
      -- stylua: ignore start
      sign("DapBreakpoint",          { text = glyph("●", "B"),  texthl = "DiagnosticError", linehl = "", numhl = "" })
      sign("DapBreakpointCondition", { text = glyph("◆", "*"),  texthl = "DiagnosticError", linehl = "", numhl = "" })
      sign("DapLogPoint",            { text = glyph("◆", "*"),  texthl = "DiagnosticInfo",  linehl = "", numhl = "" })
      sign("DapStopped",             { text = glyph("▶", ">"),  texthl = "DiagnosticWarn",
                                       linehl = "DapStoppedLine", numhl = "DiagnosticWarn" })
  -- stylua: ignore end
  sign(
    "DapBreakpointRejected",
    { text = glyph("○", "?"), texthl = "DiagnosticError", linehl = "", numhl = "" }
  )

  -- -----------------------------------------------------------------------
  -- Per-project .vscode/launch.json support
  -- -----------------------------------------------------------------------
  -- Modern nvim-dap reads .vscode/launch.json through its providers when
  -- selecting a new configuration. Continuing, Run Last and Restart use
  -- the existing configuration; select anew to apply launch-file edits.
  --
  -- We still expose `:DapLoadLaunchJSON` (and bind <leader>dL to it)
  -- because it's useful for a different reason: to *validate* the file
  -- and preview which configurations it parsed out, without starting
  -- a debug session. Handy when "<leader>dc doesn't show my entry"
  -- and you want to know whether the file even parsed.
  --
  -- We use the non-deprecated `getconfigs()` API rather than the old
  -- `load_launchjs()` (which still works but emits a warning since it
  -- duplicates what the provider does).
  --
  -- The provider and this validator use the same resolved root/source. With
  -- no override, nvim-dap keeps its normal invocation-time cwd behavior.
  vim.api.nvim_create_user_command("DapLoadLaunchJSON", function()
    local cwd = M.root()
    local path = M.launch_file(cwd)
    if not path then
      vim.notify("Project launch files are disabled", vim.log.levels.INFO)
      return
    end
    if vim.fn.filereadable(path) == 0 then
      vim.notify(("No %s in debug root (%s)"):format(path, cwd), vim.log.levels.WARN)
      return
    end
    local ok, vscode = pcall(require, "dap.ext.vscode")
    if not ok then
      vim.notify("dap.ext.vscode not available", vim.log.levels.ERROR)
      return
    end
    local parsed_ok, configs = pcall(vscode.getconfigs, path)
    if not parsed_ok then
      vim.notify(("Failed to parse %s:\n%s"):format(path, tostring(configs)), vim.log.levels.ERROR)
      return
    end
    if not configs or #configs == 0 then
      vim.notify(("%s parsed OK but contains no configurations"):format(path), vim.log.levels.WARN)
      return
    end
    local lines = { ("launch.json OK — %d config(s):"):format(#configs) }
    for _, c in ipairs(configs) do
      table.insert(
        lines,
        ("  • %s (type=%s, request=%s)"):format(
          c.name or "<unnamed>",
          c.type or "?",
          c.request or "?"
        )
      )
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Validate & preview .vscode/launch.json" })

  -- -----------------------------------------------------------------------
  configure_launch_provider(dap, owned)

  -- Adapters
  -- -----------------------------------------------------------------------
  -- These are the shipped `type` registrations; debug.adapters and other
  -- plugin/user code can add more. Mason installs the selected binaries
  -- (the defaults are in lua/plugins/formatting.lua).
  --
  -- Mason's Windows bin/ entries are .cmd shims. nvim-dap uses uv.spawn,
  -- which cannot execute batch files directly. Use the package's native
  -- image/runtime with an argv list there, keeping literal spaces and shell
  -- metacharacters out of a command interpreter. Unix keeps Mason's shims.
  local settings = package.loaded["mason.settings"]
  local mason_root = Settings.get("debug.mason_root")
    or settings and settings.current and settings.current.install_root_dir
    or vim.fs.joinpath(vim.fn.stdpath("data"), "mason")
  local mason_bin = vim.fs.joinpath(mason_root, "bin")
  local mason_packages = vim.fs.joinpath(mason_root, "packages")
  local is_windows = vim.fn.has("win32") == 1
  local function mason_exe(name, package, ...)
    if is_windows then return vim.fs.joinpath(mason_packages, package, ...) end
    return vim.fs.joinpath(mason_bin, name)
  end

  -- cpptools / OpenDebugAD7 — Microsoft's C/C++ debug adapter.
  -- nvim-dap spawns adapters detached by default; keep Windows starts in
  -- this process group instead of opening a separate console.
  adapters.cppdbg = {
    id = "cppdbg",
    type = "executable",
    command = mason_exe(
      "OpenDebugAD7",
      "cpptools",
      "extension",
      "debugAdapters",
      "bin",
      "OpenDebugAD7.exe"
    ),
    options = { detached = not is_windows },
  }

  -- codelldb — alternate C/C++/Rust adapter (LLDB-based, often snappier).
  -- Uses the `server` type because codelldb starts a TCP server and
  -- nvim-dap connects to it; the port is filled in dynamically.
  adapters.codelldb = {
    type = "server",
    port = "${port}",
    -- nvim-dap retries the TCP connect 14 × 250 ms (3.5 s) by default.
    -- codelldb listens after ~0.4 s here, but a cold start on Windows
    -- (Defender scanning the freshly unpacked LLDB) can take longer,
    -- and then the session fails with "Couldn't connect … ECONNREFUSED".
    -- 40 retries = 10 s of patience; a healthy start is unaffected.
    options = { max_retries = 40 },
    executable = {
          -- stylua: ignore start
          command  = mason_exe("codelldb", "codelldb", "extension", "adapter", "codelldb.exe"),
          args     = { "--port", "${port}" },
          detached = not is_windows,
      -- stylua: ignore end
    },
  }

  -- debugpy.listen() already starts an adapter in the target process's
  -- environment. Socket attach must connect to that adapter directly;
  -- spawning an unrelated stdio adapter leaves it waiting for a debug
  -- server that will never connect. Launch, PID attach and reverse-listen
  -- attach still need their own stdio adapter.
  adapters.python = function(callback, config)
    local connect = config.request == "attach" and (config.connect or config)
    if connect and connect.port then
      callback({
        type = "server",
        host = connect.host or "127.0.0.1",
        port = connect.port,
      })
    else
      callback({
        type = "executable",
        command = mason_exe("debugpy-adapter", "debugpy", "venv", "Scripts", "python.exe"),
        args = is_windows and { "-m", "debugpy.adapter" } or nil,
        options = is_windows and { detached = false } or nil,
      })
    end
  end

  -- bashdb — Bash. Mason package "bash-debug-adapter"; the sh
  -- configuration below must point at the bashdb copy VENDORED
  -- inside that package (extension/bashdb_dir) — a system bashdb
  -- won't match the adapter's expected version. Practical on
  -- Unix-likes; on Windows it additionally needs bash/cat/mkfifo/
  -- pkill on PATH (e.g. Git Bash), which is why it's fallback-only.
  local node = is_windows and vim.fn.exepath("node.exe") or ""
  adapters.bashdb = {
    type = "executable",
    command = is_windows and (node ~= "" and node or "node.exe") or mason_exe("bash-debug-adapter"),
    args = is_windows
        and {
          vim.fs.joinpath(mason_packages, "bash-debug-adapter", "extension", "out", "bashDebug.js"),
        }
      or nil,
    options = is_windows and { detached = false } or nil,
    name = "bashdb",
  }

  -- -----------------------------------------------------------------------
  -- Lua fallback configurations
  -- -----------------------------------------------------------------------
  -- These appear in the <leader>dc picker BEFORE any .vscode/launch.json
  -- entries (nvim-dap lists its providers in name order: dap.global, then
  -- dap.launch.json). Use them for quick one-offs when you don't want to
  -- commit a launch.json to the repo — they prompt for the executable
  -- for native launch/attach so those examples are project-agnostic.
  --
  -- MIMode picks the debugger backend cppdbg drives. gdb is standard on
  -- Linux/Windows (Windows requires gdb to be on PATH — install via
  -- mingw/msys2 if missing). macOS prefers lldb because Apple stopped
  -- signing gdb a decade ago and getting it to attach is a chore.
  local default_mimode = Settings.get("debug.mimode", vim.fn.has("mac") == 1 and "lldb" or "gdb")

  -- "Path to executable" prompt shared by the fallbacks below. <Esc>
  -- (empty input) or accepting the pre-filled directory returns
  -- dap.ABORT, which cancels cleanly. Returning "" instead started a
  -- session anyway: cppdbg failed with "property 'program' is missing
  -- or empty" and codelldb with "'<cwd>' is not a valid executable".
  local function ask_program()
    local p = vim.fn.input("Path to executable: ", M.root() .. "/", "file")
    if p == "" or vim.fn.isdirectory(p) == 1 then return dap.ABORT end
    return p
  end

  table.insert(fallbacks.cpp, {
    name = "‹fallback› Pick executable (cppdbg)",
    type = "cppdbg",
    request = "launch",
    program = ask_program,
    cwd = M.root,
    stopAtEntry = false,
    MIMode = default_mimode,
    setupCommands = default_mimode == "gdb" and {
      {
        description = "Enable pretty-printing for gdb",
        text = "-enable-pretty-printing",
        ignoreFailures = true,
      },
    } or nil,
  })
  table.insert(fallbacks.cpp, {
    name = "‹fallback› Attach to process (cppdbg)",
    type = "cppdbg",
    request = "attach",
    program = ask_program,
    processId = require("dap.utils").pick_process,
    MIMode = default_mimode,
  })

  -- codelldb fallbacks (LLDB-based; cross-platform). codelldb uses its
  -- OWN field names, so this block has NO MIMode / setupCommands /
  -- stopAtEntry — codelldb silently IGNORES those cppdbg fields. Key
  -- differences baked in here:
  --   * stopOnEntry  (not stopAtEntry — cppdbg's spelling is a no-op)
  --   * terminal = "console"  routes the debuggee's stdio to the dap
  --     REPL instead of opening a separate [dap-terminal] window, AND
  --     avoids the Windows runInTerminal hang that codelldb's default
  --     ("integrated") can trigger. The field and value behave the same
  --     on Linux / macOS / Windows, so this stays cross-platform.
  --   * attach uses `pid` (cppdbg uses processId).
  table.insert(fallbacks.cpp, {
    name = "‹fallback› Pick executable (codelldb)",
    type = "codelldb",
    request = "launch",
    program = ask_program,
    cwd = M.root,
    stopOnEntry = false,
    terminal = Settings.get("debug.codelldb_terminal", "console"),
    -- Disable eager symbol-table loading. The project launch template also
    -- demonstrates optional symbols.load-on-demand tuning, which can affect
    -- function-name breakpoints and type/global lookups. Keep that choice
    -- explicit per project or through debug.codelldb_init_commands.
    -- See docs/debug-terminal-configuration.md for tradeoffs and compatibility.
    initCommands = Settings.get(
      "debug.codelldb_init_commands",
      { "settings set target.preload-symbols false" }
    ),
  })
  table.insert(fallbacks.cpp, {
    name = "‹fallback› Attach to process (codelldb)",
    type = "codelldb",
    request = "attach",
    pid = require("dap.utils").pick_process,
    cwd = M.root,
  })

      -- Use deepcopy so the three filetype tables are independent — a plain
      -- assignment would alias them, and any future mutation of one (e.g. a
      -- .vscode/launch.json appending a Rust-only config) would silently
      -- mutate cpp and c too.
      -- stylua: ignore start
      fallbacks.c    = vim.deepcopy(fallbacks.cpp)
      fallbacks.rust = vim.deepcopy(fallbacks.cpp)
  -- stylua: ignore end

  -- Python fallback. An explicit debug.python path/resolver wins; otherwise
  -- prefer the activated environment, project .venv/venv, then PATH.
  table.insert(fallbacks.python, {
    name = "‹fallback› Launch current file (debugpy)",
    type = "python",
    request = "launch",
    program = "${file}",
    cwd = M.root,
    pythonPath = function()
      local python = Settings.get("debug.python")
      if type(python) == "function" then python = python(M.root()) end
      if python ~= nil then
        assert(
          type(python) == "string" and python ~= "",
          "debug.python must return an interpreter path"
        )
        return python
      end
      -- Interpreter inside an environment root (venv or conda layout).
      local function env_python(root)
        if not root or root == "" then return nil end
        local candidates = is_windows and { "Scripts/python.exe", "python.exe" }
          or { "bin/python", "bin/python3" }
        for _, rel in ipairs(candidates) do
          local p = vim.fs.joinpath(root, rel)
          if vim.fn.executable(p) == 1 then return p end
        end
      end
      -- Activated env first ($VIRTUAL_ENV, then conda's $CONDA_PREFIX),
      -- then an un-activated project env in the cwd (.venv / venv — the
      -- uv / poetry / python -m venv convention), then PATH.
      local cwd = M.root()
      return env_python(os.getenv("VIRTUAL_ENV"))
        or env_python(os.getenv("CONDA_PREFIX"))
        or env_python(vim.fs.joinpath(cwd, ".venv"))
        or env_python(vim.fs.joinpath(cwd, "venv"))
        or (is_windows and "python" or "python3")
    end,
  })

  -- Bash fallback. The path* fields are required by the adapter —
  -- it drives the vendored bashdb through named pipes, hence the
  -- cat/mkfifo/pkill dependencies (see the adapter comment above).
  local bash_debug_dir = vim.fs.joinpath(mason_packages, "bash-debug-adapter")
  local bashdb_dir = vim.fs.joinpath(bash_debug_dir, "extension", "bashdb_dir")
  for _, ft in ipairs({ "sh", "bash" }) do
    table.insert(fallbacks[ft], {
      name = "‹fallback› Run current script (bashdb)",
      type = "bashdb",
      request = "launch",
      program = "${file}",
      cwd = M.root,
      pathBashdb = vim.fs.joinpath(bashdb_dir, "bashdb"),
      pathBashdbLib = bashdb_dir,
      pathBash = "bash",
      pathCat = "cat",
      pathMkfifo = "mkfifo",
      pathPkill = "pkill",
      env = {},
      args = {},
    })
  end

  local adapter_overrides = Settings.get("debug.adapters", {})
  for name, adapter in pairs(adapters) do
    local override = adapter_overrides[name]
    if override == false then
      dap.adapters[name], owned.adapters[name] = nil, nil
    elseif
      override ~= nil
      or dap.adapters[name] == nil
      or dap.adapters[name] == owned.adapters[name]
    then
      adapter = override ~= nil and override or adapter
      dap.adapters[name], owned.adapters[name] = adapter, adapter
    end
  end
  for name, adapter in pairs(adapter_overrides) do
    if adapters[name] == nil then dap.adapters[name] = adapter ~= false and adapter or nil end
  end

  -- Remove only this module's old fallback objects, never user configurations.
  for _, configurations in pairs(dap.configurations) do
    for i = #configurations, 1, -1 do
      if owned.fallbacks[configurations[i]] then table.remove(configurations, i) end
    end
  end
  owned.fallbacks = {}
  if Settings.get("debug.fallbacks", true) ~= false then
    for ft, configurations in pairs(fallbacks) do
      dap.configurations[ft] = dap.configurations[ft] or {}
      for _, config in ipairs(configurations) do
        local present = vim.tbl_contains(dap.configurations[ft], function(existing)
          return existing.name == config.name
        end, { predicate = true })
        if not present and dap.adapters[config.type] ~= nil then
          table.insert(dap.configurations[ft], config)
          owned.fallbacks[config] = true
        end
      end
    end
  end
  for ft, configurations in pairs(Settings.get("debug.configurations", {})) do
    assert(
      configurations == false or vim.islist(configurations),
      "debug.configurations entries must be lists or false"
    )
    dap.configurations[ft] = configurations == false and {} or configurations
  end
  local configure = Settings.get("debug.configure")
  if configure ~= nil then
    assert(type(configure) == "function", "debug.configure must be a function")
    configure(dap)
  end
end

return M
