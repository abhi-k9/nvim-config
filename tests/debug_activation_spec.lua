describe("debugger first activation", function()
  it("applies local policies before real nvim-dap providers and fallbacks activate", function()
    local Settings = require("config.settings")
    local root = vim.fs.normalize(vim.fn.tempname(), { expand_env = false })
    local old_pause = vim.g.dap_pause_pick_thread
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({
      vim.json.encode({
        configurations = {
          {
            name = "Workspace launch",
            type = "custom",
            request = "launch",
            cwd = "${workspaceFolder}",
          },
        },
      }),
    }, root .. "/debug.json")
    Settings.configure({
      project = { root = root },
      debug = {
        root = "project",
        launch_file = "debug.json",
        pause_pick_thread = true,
        adapters = { custom = { type = "executable", command = "/custom/native-adapter" } },
        configurations = {
          cpp = { { name = "Custom native", type = "custom", request = "launch" } },
        },
      },
    })
    vim.g.dap_pause_pick_thread = nil
    local ok, err = pcall(function()
      assert.is_nil(package.loaded.dap)
      require("lazy.core.loader").load("nvim-dap", { cmd = "spec" })
      local dap = require("dap")
      assert.is_true(vim.g.dap_pause_pick_thread)
      assert.equals("/custom/native-adapter", dap.adapters.custom.command)
      assert.equals(1, #dap.configurations.cpp)
      assert.equals("Custom native", dap.configurations.cpp[1].name)
      local configurations = dap.providers.configs["dap.launch.json"]()
      assert.equals("Workspace launch", configurations[1].name)
      assert.equals(root, configurations[1].cwd)
    end)
    Settings.reset()
    vim.g.dap_pause_pick_thread = old_pause
    vim.fn.delete(root, "rf")
    if not ok then error(err) end
  end)

  it("retains the real stock provider's invocation-time cwd discovery without overrides", function()
    local Settings = require("config.settings")
    Settings.reset()
    require("lazy.core.loader").load("nvim-dap", { cmd = "spec" })
    local dap = require("dap")
    require("config.dap").setup()
    local previous, base =
      vim.fn.getcwd(), vim.fs.normalize(vim.fn.tempname(), { expand_env = false })
    for _, name in ipairs({ "first", "second" }) do
      vim.fn.mkdir(base .. "/" .. name .. "/.vscode", "p")
      vim.fn.writefile({
        vim.json.encode({
          configurations = {
            { name = name, type = "cppdbg", request = "launch", cwd = "${workspaceFolder}" },
          },
        }),
      }, base .. "/" .. name .. "/.vscode/launch.json")
    end
    local ok, err = pcall(function()
      for _, name in ipairs({ "first", "second" }) do
        vim.api.nvim_set_current_dir(base .. "/" .. name)
        local configs = dap.providers.configs["dap.launch.json"]()
        assert.equals(name, configs[1].name)
        -- The original provider leaves workspace expansion to nvim-dap.
        assert.equals("${workspaceFolder}", configs[1].cwd)
      end
    end)
    vim.api.nvim_set_current_dir(previous)
    vim.fn.delete(base, "rf")
    Settings.reset()
    if not ok then error(err) end
  end)
end)
