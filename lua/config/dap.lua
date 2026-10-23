-- lua/config/dap.lua
--
-- nvim-dap setup, called from the nvim-dap spec in lua/plugins/dap.lua
-- (which keeps the keymaps and the other debugger plugins):
--   * dap.pause without the thread picker (toggle: <leader>dT)
--   * breakpoint / stopped-line signs
--   * :DapLoadLaunchJSON (validate .vscode/launch.json)
--   * adapters: cppdbg, codelldb, debugpy, bashdb
--   * fallback configurations for C/C++/Rust, Python and Bash

local M = {}

function M.setup()
  local dap = require("dap")

  -- -----------------------------------------------------------------------
  -- Pause without the "which thread?" picker (with an escape hatch).
  --
  -- DAP's `pause` request targets a single threadId, so nvim-dap prompts
  -- you to choose when a session has multiple threads — painful with the
  -- ~30 a GUI/ACIS app spawns. codelldb (like most native debuggers) is
  -- ALL-STOP: pausing any one thread halts the whole program, so the
  -- choice is meaningless and we just grab the first thread.
  --
  -- Some adapters DO support meaningful per-thread pausing (non-stop mode).
  -- Flip vim.g.dap_pause_pick_thread via <leader>dT to restore nvim-dap's
  -- built-in picker for those. An EXPLICIT threadId — e.g. the dap-ui
  -- Threads panel's own pause action — bypasses both paths and pauses
  -- exactly that thread regardless of the toggle.
  -- -----------------------------------------------------------------------
  vim.g.dap_pause_pick_thread = false
  local _pause = dap.pause
  dap.pause = function(thread_id)
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

  -- Pretty signs for breakpoints, the stopped line, etc.
  local sign = vim.fn.sign_define
      -- stylua: ignore start
      sign("DapBreakpoint",          { text = "●",  texthl = "DiagnosticError", linehl = "", numhl = "" })
      sign("DapBreakpointCondition", { text = "◆",  texthl = "DiagnosticError", linehl = "", numhl = "" })
      sign("DapLogPoint",            { text = "◆",  texthl = "DiagnosticInfo",  linehl = "", numhl = "" })
      sign("DapStopped",             { text = "▶",  texthl = "DiagnosticWarn",
                                       linehl = "DapStoppedLine", numhl = "DiagnosticWarn" })
  -- stylua: ignore end
  sign(
    "DapBreakpointRejected",
    { text = "○", texthl = "DiagnosticError", linehl = "", numhl = "" }
  )

  -- -----------------------------------------------------------------------
  -- Per-project .vscode/launch.json support
  -- -----------------------------------------------------------------------
  -- Modern nvim-dap reads .vscode/launch.json on every dap.continue()
  -- via its configuration-provider system, so the file shows up in the
  -- <leader>dc picker automatically — no reload step required.
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
  -- Note: ${workspaceFolder} resolves to vim.fn.getcwd() at the moment
  -- dap.continue() is invoked. Use :cd / :tcd / :lcd to change it.
  vim.api.nvim_create_user_command("DapLoadLaunchJSON", function()
    local path = ".vscode/launch.json"
    local cwd = vim.fn.getcwd()
    if vim.fn.filereadable(path) == 0 then
      vim.notify(("No %s in cwd (%s)"):format(path, cwd), vim.log.levels.WARN)
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
  -- Adapters
  -- -----------------------------------------------------------------------
  -- Every adapter is registered here, so this file is the list of `type`
  -- values a launch.json can use. Mason only installs the binaries
  -- (mason-tool-installer's list in lua/plugins/formatting.lua).
  --
  -- Mason's Windows bin/ entries are .cmd shims. nvim-dap uses uv.spawn,
  -- which cannot execute batch files directly. Use the package's native
  -- image/runtime with an argv list there, keeping literal spaces and shell
  -- metacharacters out of a command interpreter. Unix keeps Mason's shims.
  local settings = package.loaded["mason.settings"]
  local mason_root = settings and settings.current and settings.current.install_root_dir
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
  dap.adapters.cppdbg = {
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
  dap.adapters.codelldb = {
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
  dap.adapters.python = function(callback, config)
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
  dap.adapters.bashdb = {
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
  -- each time so they're project-agnostic.
  --
  -- MIMode picks the debugger backend cppdbg drives. gdb is standard on
  -- Linux/Windows (Windows requires gdb to be on PATH — install via
  -- mingw/msys2 if missing). macOS prefers lldb because Apple stopped
  -- signing gdb a decade ago and getting it to attach is a chore.
  local default_mimode = vim.fn.has("mac") == 1 and "lldb" or "gdb"

  -- "Path to executable" prompt shared by the fallbacks below. <Esc>
  -- (empty input) or accepting the pre-filled directory returns
  -- dap.ABORT, which cancels cleanly. Returning "" instead started a
  -- session anyway: cppdbg failed with "property 'program' is missing
  -- or empty" and codelldb with "'<cwd>' is not a valid executable".
  local function ask_program()
    local p = vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
    if p == "" or vim.fn.isdirectory(p) == 1 then return dap.ABORT end
    return p
  end

  dap.configurations.cpp = dap.configurations.cpp or {}
  table.insert(dap.configurations.cpp, {
    name = "‹fallback› Pick executable (cppdbg)",
    type = "cppdbg",
    request = "launch",
    program = ask_program,
    cwd = "${workspaceFolder}",
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
  table.insert(dap.configurations.cpp, {
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
  table.insert(dap.configurations.cpp, {
    name = "‹fallback› Pick executable (codelldb)",
    type = "codelldb",
    request = "launch",
    program = ask_program,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
    terminal = "console",
    -- Defer symbol-table parsing until a module is actually needed.
    -- For large native binaries (e.g. an ACIS/OpenGL app with many big
    -- DLLs) LLDB otherwise preloads every module's debug info at launch,
    -- which a dap trace showed eating 1–2 MINUTES of cold start. This
    -- is the long-standing, always-safe setting. If your codelldb's LLDB
    -- is recent enough you can add the more aggressive
    --   "settings set symbols.load-on-demand true"
    -- (loads per-compile-unit, so even breakpoint resolution is cheap) —
    -- left out here because it errors on older LLDB. The other half of
    -- the fix is OS-side: exclude your build-output and the Mason
    -- codelldb dir from Windows Defender real-time scanning.
    initCommands = { "settings set target.preload-symbols false" },
  })
  table.insert(dap.configurations.cpp, {
    name = "‹fallback› Attach to process (codelldb)",
    type = "codelldb",
    request = "attach",
    pid = require("dap.utils").pick_process,
    cwd = "${workspaceFolder}",
  })

      -- Use deepcopy so the three filetype tables are independent — a plain
      -- assignment would alias them, and any future mutation of one (e.g. a
      -- .vscode/launch.json appending a Rust-only config) would silently
      -- mutate cpp and c too.
      -- stylua: ignore start
      dap.configurations.c    = vim.deepcopy(dap.configurations.cpp)
      dap.configurations.rust = vim.deepcopy(dap.configurations.cpp)
  -- stylua: ignore end

  -- Python fallback. `pythonPath` prefers the ACTIVE virtualenv
  -- (debugging against the project env, not the global interpreter,
  -- is nearly always what's wanted); falls back to whatever
  -- python/python3 is on PATH.
  dap.configurations.python = dap.configurations.python or {}
  table.insert(dap.configurations.python, {
    name = "‹fallback› Launch current file (debugpy)",
    type = "python",
    request = "launch",
    program = "${file}",
    cwd = "${workspaceFolder}",
    pythonPath = function()
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
      local cwd = vim.fn.getcwd()
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
    dap.configurations[ft] = dap.configurations[ft] or {}
    table.insert(dap.configurations[ft], {
      name = "‹fallback› Run current script (bashdb)",
      type = "bashdb",
      request = "launch",
      program = "${file}",
      cwd = "${workspaceFolder}",
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
end

return M
