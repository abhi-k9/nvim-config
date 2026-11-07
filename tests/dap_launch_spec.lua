describe("debug launch discovery", function()
  local module = require("config.dap_launch")
  local saved, select, executable, notify, dap, chosen, items, options, notes, buf, cwd, root
  local async, widgets, native_run
  before_each(function()
    require("lazy.core.loader").load("nvim-dap", { cmd = "launch spec" })
    saved, select, executable, notify =
      package.loaded.dap, vim.ui.select, vim.fn.executable, vim.notify
    async, widgets = package.loaded["dap.async"], package.loaded["dap.ui.widgets"]
    native_run = saved.run
    cwd, root = vim.fn.getcwd(-1, -1), vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(root, "p")
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "cpp"
    chosen, items, notes = nil, nil, {}
    local config = {
      name = "Example",
      type = "native",
      request = "launch",
      program = "/build/program",
      cwd = "/build",
    }
    dap = {
      adapters = { native = { type = "executable", command = "/adapter" } },
      providers = {
        configs = {
          example = function()
            return { config }
          end,
        },
      },
      session = function()
        return nil
      end,
      sessions = function()
        return {}
      end,
      run = function(c, opts)
        chosen = { config = c, opts = opts }
      end,
    }
    package.loaded.dap = dap
    vim.fn.executable = function()
      return 1
    end
    vim.ui.select = function(rows, opts, callback)
      items, options = rows, opts
      dap.choose = callback
    end
    vim.notify = function(message)
      notes[#notes + 1] = message
    end
  end)
  after_each(function()
    package.loaded.dap, vim.ui.select, vim.fn.executable, vim.notify =
      saved, select, executable, notify
    package.loaded["dap.async"], package.loaded["dap.ui.widgets"] = async, widgets
    saved.run = native_run
    require("config.settings").reset()
    vim.cmd.cd(cwd)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(root, "rf")
  end)
  it("labels choices without evaluating program functions or adapter factories", function()
    local calls = 0
    local dynamic = function()
      calls = calls + 1
      error("must not run during inspection")
    end
    dap.adapters.native = dynamic
    local config = setmetatable({
      name = "Prompted",
      type = "native",
      request = "launch",
      program = dynamic,
      cwd = "${workspaceFolder}",
    }, { __call = dynamic })
    dap.providers.configs.example = function()
      return { config }
    end
    module.choose()
    local label = options.format_item(items[1])
    assert.is_truthy(label:find("computed at launch", 1, true))
    assert.is_truthy(label:find("dynamic adapter", 1, true))
    assert.is_truthy(label:find("${workspaceFolder}", 1, true))
    assert.equals(0, calls)
    dap.choose(items[1])
    assert.equals(config, chosen.config)
    assert.equals("Prompted", chosen.config.name)
    assert.equals("cpp", chosen.opts.filetype)
    assert.equals(0, calls)
  end)
  it("offers even one configuration and leaves cancellation inert", function()
    module.choose()
    assert.equals(1, #items)
    assert.is_truthy(options.format_item(items[1]):find("program=/build/program", 1, true))
    assert.is_truthy(options.format_item(items[1]):find("cwd=/build", 1, true))
    dap.choose(nil)
    assert.is_nil(chosen)
  end)
  it("continues existing sessions without enumerating providers", function()
    dap.providers.configs.example = function()
      error("should not enumerate")
    end
    local calls = 0
    dap.continue = function()
      calls = calls + 1
    end
    dap.session = function()
      return {}
    end
    module.start()
    dap.session = function()
      return nil
    end
    dap.sessions = function()
      return { other = {} }
    end
    module.start()
    assert.equals(2, calls)
    assert.is_nil(items)
  end)
  it("reports missing commands and rechecks if an adapter becomes available", function()
    local found = 0
    vim.fn.executable = function()
      return found
    end
    module.choose()
    assert.is_truthy(options.format_item(items[1]):find("missing command", 1, true))
    dap.choose(items[1])
    assert.is_nil(chosen)
    assert.is_truthy(notes[#notes]:find(":checkhealth config", 1, true))
    found = 1
    dap.choose(items[1])
    assert.is_not_nil(chosen)
  end)
  it(
    "checks relative adapter commands in the source window when a picker has its own cwd",
    function()
      local source = vim.api.nvim_get_current_win()
      vim.api.nvim_win_call(source, function()
        vim.cmd.lcd(root)
      end)
      dap.adapters.native.command = "./adapter"
      vim.fn.executable = function()
        return vim.fs.normalize(vim.fn.getcwd()) == root and 1 or 0
      end
      module.choose()
      local picker = vim.api.nvim_open_win(
        buf,
        true,
        { relative = "editor", row = 0, col = 0, width = 20, height = 2, noautocmd = true }
      )
      vim.api.nvim_cmd({ cmd = "lcd", args = { cwd }, mods = { noautocmd = true } }, {})
      assert.equals(root, vim.fs.normalize(vim.fn.getcwd(source)))
      assert.equals(buf, vim.api.nvim_win_get_buf(source))
      assert.equals(cwd, vim.fn.getcwd(-1, -1))
      dap.choose(items[1])
      vim.api.nvim_win_close(picker, true)
      assert.is_not_nil(chosen, table.concat(notes, "\n"))
    end
  )
  it("opens a configured launch path with literal filename metacharacters", function()
    local settings = require("config.settings")
    settings.configure({ debug = { root = root, launch_file = "launch % # $literal.json" } })
    vim.api.nvim_buf_set_name(buf, root .. "/source.cpp")
    local source = vim.api.nvim_get_current_win()
    local ok, err = pcall(module.edit)
    local path = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
    if vim.api.nvim_get_current_win() ~= source then vim.api.nvim_win_close(0, true) end
    assert.is_true(ok, err)
    assert.equals(root .. "/launch % # $literal.json", path)
  end)
  it("cancels when the original directory or buffer changes", function()
    module.choose()
    vim.cmd.cd(root)
    dap.choose(items[1])
    assert.is_nil(chosen)
    assert.is_truthy(notes[#notes]:find("directory changed", 1, true))
    module.choose()
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(other)
    dap.choose(items[1])
    assert.is_nil(chosen)
    vim.api.nvim_buf_delete(other, { force = true })
  end)
  it("isolates malformed/failing providers and keeps provider order stable", function()
    local order = {}
    local config = { name = "Valid", type = "native", request = "launch" }
    dap.providers.configs = {
      z = function()
        order[#order + 1] = "z"
        return { config }
      end,
      a = function()
        order[#order + 1] = "a"
        error("bad JSON")
      end,
      m = function()
        order[#order + 1] = "m"
        return { invalid = true }
      end,
    }
    local rows = module.collect(dap, buf)
    assert.same({ "a", "m", "z" }, order)
    assert.equals(config, rows[1].config)
    assert.equals(2, #notes)
    assert.is_truthy(notes[1]:find(":DapLoadLaunchJSON", 1, true))
  end)

  it("cancels discovery if a provider outlives its source context", function()
    dap.providers.configs.example = function()
      vim.cmd.cd(root)
      return { { name = "Stale", type = "native", request = "launch" } }
    end
    module.choose()
    assert.is_nil(items)
    assert.is_truthy(notes[#notes]:find("discovery cancelled", 1, true))
  end)
  it("leaves remote and computed adapters to DAP instead of probing a connection", function()
    dap.adapters.native = { type = "server", host = "example.invalid", port = 1234 }
    assert.equals("remote adapter", module.describe({ type = "native" }, "test", dap).adapter)
    local config = setmetatable({}, {
      __call = function()
        error("must not evaluate")
      end,
    })
    local row = module.describe(config, "test", dap)
    assert.equals("dynamic configuration", row.adapter)
    assert.is_false(row.unavailable)
  end)
  it(
    "delegates custom adapter lookup contexts instead of rejecting valid launch overrides",
    function()
      vim.fn.executable = function()
        error("must not inspect the editor PATH")
      end
      dap.adapters.native = { type = "executable", command = "./adapter", options = { cwd = root } }
      local row = module.describe({ type = "native" }, "test", dap)
      assert.equals("custom launch context", row.adapter)
      assert.is_false(row.unavailable)
      dap.adapters.native = { type = "server", executable = { command = "./adapter", cwd = root } }
      assert.is_false(module.describe({ type = "native" }, "test", dap).unavailable)
      dap.adapters.native =
        { type = "executable", command = "adapter", options = { env = { "PATH=other" } } }
      assert.is_false(module.describe({ type = "native" }, "test", dap).unavailable)
    end
  )
  it("reads the native launch provider and preserves its callable input configuration", function()
    package.loaded.dap = saved
    require("config.settings").configure({ debug = { root = root, launch_file = "launch.json" } })
    vim.fn.writefile({
      vim.json.encode({
        configurations = {
          {
            name = "Native inputs",
            type = "codelldb",
            request = "launch",
            program = "${workspaceFolder}/program",
            cwd = "${workspaceFolder}",
            args = { "${input:argument}" },
          },
        },
        inputs = { { id = "argument", type = "promptString" } },
      }),
    }, root .. "/launch.json")
    saved.run = function(config)
      chosen = config
    end
    module.choose()
    local row
    for _, item in ipairs(items or {}) do
      if item.name == "Native inputs" then row = item end
    end
    assert.is_not_nil(row)
    assert.equals(root .. "/program", row.program)
    assert.equals(root, row.cwd)
    assert.is_function(getmetatable(row.config).__call)
    assert.equals("${input:argument}", row.config.args[1])
    dap.choose(row)
    assert.equals(row.config, chosen)
    assert.equals("${input:argument}", chosen.args[1])
  end)
  it("opens the configured launch file without writing or losing unsaved code", function()
    local settings = require("config.settings")
    settings.configure({ debug = { root = root } })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved code" })
    module.edit()
    local launch_win = vim.api.nvim_get_current_win()
    assert.equals(root .. "/.vscode/launch.json", vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
    assert.equals(0, vim.fn.isdirectory(root .. "/.vscode"))
    assert.same({ "unsaved code" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    vim.api.nvim_win_close(launch_win, true)
    settings.reset()
  end)

  it("keeps immediate launch errors actionable without losing the original cause", function()
    dap.run = function()
      error("bad launch schema")
    end
    module.choose()
    dap.choose(items[1])
    assert.is_truthy(notes[#notes]:find("bad launch schema", 1, true))
    assert.is_truthy(notes[#notes]:find(":DapShowLog", 1, true))
  end)
  it("handles deferred selection failures while returning to the source window", function()
    module.choose()
    local enter = vim.api.nvim_set_current_win
    vim.api.nvim_set_current_win = function()
      error("source window entry failed")
    end
    local ok, err = pcall(dap.choose, items[1])
    vim.api.nvim_set_current_win = enter
    assert.is_true(ok, err)
    assert.is_nil(chosen)
    assert.is_truthy(notes[#notes]:find("source window entry failed", 1, true))
    assert.is_truthy(notes[#notes]:find(":DapShowLog", 1, true))
  end)
  it("handles incomplete debugger APIs without launching or opening a picker", function()
    package.loaded.dap = true
    module.start()
    assert.is_truthy(notes[#notes]:find("Debugger unavailable", 1, true))
    package.loaded.dap = dap
    package.loaded["dap.async"] = true
    module.choose()
    assert.is_truthy(notes[#notes]:find("installation is incomplete", 1, true))
    package.loaded["dap.async"] = async
    dap.providers = true
    module.choose()
    assert.is_truthy(notes[#notes]:find("providers are unavailable", 1, true))
    dap.session = function()
      error("session inspection failed")
    end
    module.start()
    assert.is_truthy(notes[#notes]:find("session inspection failed", 1, true))
    assert.is_nil(items)
    assert.is_nil(chosen)
  end)
  it("keeps a failed selector inert and offers a direct inspection command", function()
    vim.ui.select = function()
      error("selector failed")
    end
    module.choose()
    assert.is_nil(chosen)
    assert.is_truthy(notes[#notes]:find(":DapLaunchInfo", 1, true))
    module.info()
    local report = vim.api.nvim_get_current_buf()
    assert.is_truthy(
      table
        .concat(vim.api.nvim_buf_get_lines(report, 0, -1, false), "\n")
        :find("/build/program", 1, true)
    )
    vim.api.nvim_win_close(0, true)
  end)
  it("handles missing widget APIs and preserves widget failure details", function()
    package.loaded["dap.ui.widgets"] = true
    require("config.dap").hover()
    assert.is_truthy(notes[#notes]:find("preview unavailable", 1, true))
    package.loaded["dap.ui.widgets"] = {
      hover = function()
        error("widget failed")
      end,
    }
    require("config.dap").hover()
    assert.is_truthy(notes[#notes]:find("widget failed", 1, true))
    assert.is_truthy(notes[#notes]:find(":DapShowLog", 1, true))
  end)
  it("keeps debugger commands actionable in a bare editor without the plugin", function()
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({
      ("vim.opt.rtp:prepend(%q)"):format(vim.fn.getcwd()),
      "require('config.commands')",
      "local notes = {}; vim.notify = function(message) notes[#notes + 1] = message end",
      "vim.cmd.DapLaunch(); vim.cmd.DapLaunchInfo(); require('config.dap').hover()",
      "assert(#notes == 3 and notes[1]:find('Debugger unavailable', 1, true))",
      "assert(not package.loaded.dap)",
    }, path)
    local result = vim
      .system({ vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", path }, { text = true })
      :wait(5000)
    vim.fn.delete(path)
    assert.equals(0, result.code, result.stderr)
  end)

  it("adds an Escape close hint to the native value float without closing code", function()
    -- This case uses the real native widget implementation, without an adapter.
    package.loaded.dap = saved
    local source_win, border = vim.api.nvim_get_current_win(), vim.o.winborder
    vim.o.winborder = "none"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "value" })
    local ok, view = pcall(require("config.dap").hover)
    vim.o.winborder = border
    assert.is_true(ok, view)
    local win = view.win
    local win_config = vim.api.nvim_win_get_config(win)
    assert.is_truthy(
      vim.inspect(win_config.footer):find("q / Esc", 1, true),
      vim.inspect(win_config)
    )
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(win), "n")) do
      if mapping.lhs == "<Esc>" then
        mapping.callback()
        break
      end
    end
    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.is_true(vim.api.nvim_win_is_valid(source_win))
    assert.same({ "value" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)
end)
