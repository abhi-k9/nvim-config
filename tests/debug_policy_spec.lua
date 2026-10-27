describe("debugger customization lifecycle", function()
  local Settings = require("config.settings")
  local module = require("config.dap")
  local old_dap, old_utils, old_pause, dap, base, previous

  before_each(function()
    Settings.reset()
    old_dap, old_utils = package.loaded.dap, package.loaded["dap.utils"]
    old_pause = vim.g.dap_pause_pick_thread
    vim.g.dap_pause_pick_thread = nil
    previous, base = vim.fn.getcwd(), vim.fs.normalize(vim.fn.tempname(), { expand_env = false })
    vim.fn.mkdir(base, "p")
    dap = {
      adapters = {},
      configurations = {},
      ABORT = {},
      pause = function() end,
      providers = {
        configs = {
          ["dap.launch.json"] = function()
            return {}
          end,
        },
      },
    }
    package.loaded.dap = dap
    package.loaded["dap.utils"] = { pick_process = function() end }
  end)

  after_each(function()
    package.loaded.dap, package.loaded["dap.utils"] = old_dap, old_utils
    vim.g.dap_pause_pick_thread = old_pause
    Settings.reset()
    vim.api.nvim_set_current_dir(previous)
    vim.fn.delete(base, "rf")
  end)

  it("preserves explicit pause, native adapters and per-language configurations", function()
    local custom = { type = "executable", command = "/custom/debug adapter" }
    local c, rust =
      { { name = "C custom", type = "cppdbg" } }, { { name = "Rust custom", type = "codelldb" } }
    dap.adapters.cppdbg, dap.configurations.c, dap.configurations.rust = custom, c, rust
    vim.g.dap_pause_pick_thread = true
    module.setup()
    module.setup()
    assert.is_true(vim.g.dap_pause_pick_thread)
    assert.equals(custom, dap.adapters.cppdbg)
    assert.equals(c, dap.configurations.c)
    assert.equals(rust, dap.configurations.rust)
    assert.equals("C custom", dap.configurations.c[1].name)
    assert.equals("Rust custom", dap.configurations.rust[1].name)
    assert.equals(5, #dap.configurations.c)
    assert.equals(5, #dap.configurations.rust)
    assert.equals(4, #dap.configurations.cpp)
  end)

  it("reuses one pause wrapper and retains explicit thread forwarding", function()
    local calls = {}
    dap.pause = function(id)
      calls[#calls + 1] = id
    end
    module.setup()
    module.setup()
    dap.pause(42)
    assert.same({ 42 }, calls)
  end)

  it("supports adapter disablement and exact custom configuration lists", function()
    local callback, seen = function() end, false
    Settings.configure({
      debug = {
        adapters = { cppdbg = false, embedded = callback },
        configurations = {
          c = {},
          rust = false,
          cpp = { { name = "Only custom", type = "embedded" } },
        },
        configure = function(configured)
          seen = configured == dap and configured.configurations.cpp[1].name == "Only custom"
        end,
      },
    })
    module.setup()
    module.setup()
    assert.is_nil(dap.adapters.cppdbg)
    assert.equals(callback, dap.adapters.embedded)
    assert.same({}, dap.configurations.c)
    assert.same({}, dap.configurations.rust)
    assert.equals(1, #dap.configurations.cpp)
    assert.is_true(seen)
  end)

  it("can disable generated fallbacks without disabling configured adapters", function()
    Settings.configure({ debug = { fallbacks = false, pause_pick_thread = true } })
    module.setup()
    assert.same({}, dap.configurations)
    assert.is_table(dap.adapters.cppdbg)
    assert.is_true(vim.g.dap_pause_pick_thread)
  end)

  it("uses custom root and launch source in the actual DAP provider", function()
    local root = base .. "/project $literal & percent%"
    vim.fn.mkdir(root .. "/debug", "p")
    vim.fn.writefile({
      vim.json.encode({
        configurations = {
          {
            name = "Custom workspace",
            type = "cppdbg",
            request = "launch",
            cwd = "${workspaceFolder}",
            program = "${workspaceFolder}/bin/${workspaceFolderBasename}",
            args = { "${file}" },
          },
        },
      }),
    }, root .. "/debug/native.json")
    Settings.configure({
      debug = {
        root = function()
          return root
        end,
        launch_file = function(actual, bufnr)
          assert.equals(root, actual)
          assert.is_number(bufnr)
          return "debug/native.json"
        end,
      },
    })
    module.setup()
    local configs = dap.providers.configs["dap.launch.json"]()
    assert.equals(root .. "/debug/native.json", module.launch_file())
    assert.equals(root, configs[1].cwd)
    assert.equals(root .. "/bin/" .. vim.fs.basename(root), configs[1].program)
    assert.same({ "${file}" }, configs[1].args)
    assert.equals(root, dap.configurations.cpp[1].cwd())
  end)

  it("rejects malformed root and launch resolver values with specific errors", function()
    Settings.configure({ debug = {
      root = function()
        return 42
      end,
    } })
    assert.has_error(function()
      module.root()
    end, "root resolver must return a path or nil")
    Settings.configure({
      debug = {
        root = base,
        launch_file = function()
          return {}
        end,
      },
    })
    assert.has_error(function()
      module.launch_file()
    end, "debug.launch_file must return a path or false")
  end)

  it("preserves absolute drive and UNC launch paths on Windows", function()
    if vim.fn.has("win32") ~= 1 then
      pending("requires native Windows path semantics")
      return
    end
    for _, path in ipairs({
      [[C:\debug files\launch.json]],
      [[\\server\share\debug files\launch.json]],
    }) do
      Settings.configure({ debug = { root = base, launch_file = path } })
      assert.equals(vim.fs.normalize(path, { expand_env = false }), module.launch_file())
    end
  end)

  it("keeps launch inputs callable and yields ownership to later providers", function()
    local root = base .. "/project"
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({
      vim.json.encode({
        configurations = {
          { name = "Inputs", type = "cppdbg", request = "launch", cwd = "${workspaceFolder}" },
        },
        inputs = { { id = "unused", type = "promptString" } },
      }),
    }, root .. "/launch.json")
    local original_calls = 0
    dap.providers.configs["dap.launch.json"] = function(...)
      original_calls = original_calls + 1
      return { ... }, "original-result"
    end
    Settings.configure({ debug = { root = root, launch_file = "launch.json" } })
    module.setup()
    local configs = dap.providers.configs["dap.launch.json"]()
    assert.is_function(getmetatable(configs[1]).__call)
    assert.equals(root, configs[1]().cwd)
    Settings.reset()
    module.setup()
    local defaults, result = dap.providers.configs["dap.launch.json"]("delegated", 42)
    assert.same({ "delegated", 42 }, defaults)
    assert.equals("original-result", result)
    assert.equals(1, original_calls)
    Settings.configure({ debug = { launch_file = false } })
    module.setup()
    assert.same({}, dap.providers.configs["dap.launch.json"]())
    local replacement = function()
      return { "user" }
    end
    dap.providers.configs["dap.launch.json"] = replacement
    Settings.reset()
    module.setup()
    assert.equals(replacement, dap.providers.configs["dap.launch.json"])
  end)

  it("resolves later trusted project overlays on entry and leaves without leaking", function()
    local project, other = base .. "/project", base .. "/other"
    vim.fn.mkdir(project, "p")
    vim.fn.mkdir(other, "p")
    vim.fn.writefile({
      vim.json.encode({
        configurations = {
          {
            name = "Project source",
            type = "cppdbg",
            request = "launch",
            cwd = "${workspaceFolder}",
          },
        },
      }),
    }, project .. "/custom.json")
    local default_calls = 0
    dap.providers.configs["dap.launch.json"] = function()
      default_calls = default_calls + 1
      return { { name = "Original cwd provider", cwd = vim.fn.getcwd() } }
    end
    vim.api.nvim_set_current_dir(other)
    module.setup()
    local provider = dap.providers.configs["dap.launch.json"]
    Settings.for_project(project, { debug = { root = project, launch_file = "custom.json" } })
    assert.equals("Original cwd provider", provider()[1].name)
    vim.api.nvim_set_current_dir(project)
    local config = provider()[1]
    assert.equals("Project source", config.name)
    assert.equals(project, config.cwd)
    assert.equals(project, dap.configurations.cpp[1].cwd())
    vim.api.nvim_set_current_dir(other)
    config = provider()[1]
    assert.equals("Original cwd provider", config.name)
    assert.equals(other, config.cwd)
    assert.equals(other, dap.configurations.cpp[1].cwd())
    assert.equals(2, default_calls)
    module.setup()
    assert.equals(provider, dap.providers.configs["dap.launch.json"])
  end)

  it("accepts custom interpreter and debugger fallback preferences", function()
    Settings.configure({
      debug = {
        root = base,
        python = function(root)
          return root .. "/custom/python"
        end,
        mimode = "lldb",
        codelldb_terminal = "integrated",
        codelldb_init_commands = {},
      },
    })
    module.setup()
    assert.equals("lldb", dap.configurations.cpp[1].MIMode)
    assert.equals("integrated", dap.configurations.cpp[3].terminal)
    assert.same({}, dap.configurations.cpp[3].initCommands)
    assert.equals(base .. "/custom/python", dap.configurations.python[1].pythonPath())
  end)
end)
