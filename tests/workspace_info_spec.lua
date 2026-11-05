describe("workspace context inspection", function()
  local settings = require("config.settings")
  local module = require("config.workspace")
  local saved, clients, cwd, root, buf, current
  before_each(function()
    settings.reset()
    cwd, current = vim.fn.getcwd(-1, -1), vim.api.nvim_get_current_win()
    root = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(root .. "/local", "p")
    vim.cmd.cd(root)
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_name(buf, root .. "/source.cpp")
    saved = {}
    for _, name in ipairs({ "scoper", "neo-tree.sources.manager", "dap" }) do
      saved[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    clients = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return {}
    end
  end)
  after_each(function()
    for _, name in ipairs({ "scoper", "neo-tree.sources.manager", "dap" }) do
      package.loaded[name] = saved[name]
    end
    vim.lsp.get_clients = clients
    settings.reset()
    vim.cmd.cd(cwd)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(root, "rf")
  end)
  it("keeps global, tab and window directories separate without loading plugins", function()
    vim.cmd.lcd(root .. "/local")
    local data = module.snapshot(current)
    assert.equals(root, data.global_cwd)
    assert.equals(root .. "/local", data.window_cwd)
    assert.equals(root, data.project_root)
    assert.equals("not loaded", data.neotree)
    assert.equals("not loaded", data.dap)
    assert.is_nil(package.loaded.scoper)
    assert.is_nil(package.loaded.dap)
    assert.equals(root, vim.fn.getcwd(-1, -1))
  end)
  it(
    "shows existing roots and launch facts without evaluating launch callbacks or dumping secrets",
    function()
      package.loaded.scoper = {
        status_snapshot = function()
          return {
            root = root,
            scope = "api",
            enabled = false,
            database = "build/commands.json",
            lsp = { selection = { path = root .. "/build/commands.json" }, freshness = "ready" },
          }
        end,
      }
      package.loaded["neo-tree.sources.manager"] = {
        get_state_for_window = function(win)
          if win == current then return { name = "filesystem", path = root .. "/local" } end
        end,
      }
      vim.lsp.get_clients = function()
        return { { name = "clangd", root_dir = root .. "/lsp" } }
      end
      package.loaded.dap = {
        session = function()
          return {
            config = {
              name = "Native",
              type = "codelldb",
              cwd = root,
              program = function()
                error("must not execute")
              end,
              env = { TOKEN = "DO-NOT-PRINT" },
            },
          }
        end,
      }
      local data = module.snapshot(current)
      local text = table.concat(module.lines(data), "\n")
      assert.is_truthy(text:find("filter OFF", 1, true))
      assert.is_truthy(text:find(root .. "/build/commands.json", 1, true))
      assert.is_truthy(text:find(root .. "/lsp", 1, true))
      assert.is_truthy(text:find("computed at launch", 1, true))
      assert.is_nil(text:find("DO-NOT-PRINT", 1, true))
    end
  )
  it("reports disabled launch files and isolates resolver failures", function()
    settings.configure({
      debug = { launch_file = false },
      project = {
        root = function()
          error("bad root policy")
        end,
      },
    })
    local text = table.concat(module.lines(module.snapshot(current)), "\n")
    assert.is_truthy(text:find("bad root policy", 1, true))
    assert.is_truthy(text:find("Launch file: disabled", 1, true))
    assert.is_truthy(text:find("Language servers", 1, true))
  end)
  it("reports incomplete plugins and isolates failing status APIs", function()
    for _, name in ipairs({ "scoper", "neo-tree.sources.manager", "dap" }) do
      package.loaded[name] = true
    end
    local text = table.concat(module.lines(module.snapshot(current)), "\n")
    assert.is_truthy(text:find("Neo-tree: status API unavailable", 1, true))
    assert.is_truthy(text:find("Scoper: status API unavailable", 1, true))
    assert.is_truthy(text:find("Debugger: status API unavailable", 1, true))
    package.loaded.scoper = {
      status_snapshot = function()
        return true
      end,
    }
    package.loaded.dap = {
      session = function()
        error("session unavailable")
      end,
    }
    package.loaded["neo-tree.sources.manager"] = {
      get_state_for_window = function()
        error("tree unavailable")
      end,
    }
    text = table.concat(module.lines(module.snapshot(current)), "\n")
    assert.is_truthy(text:find("status snapshot unavailable", 1, true))
    assert.is_truthy(text:find("session unavailable", 1, true))
    assert.is_truthy(text:find("tree unavailable", 1, true))
    assert.is_truthy(text:find("Language servers", 1, true))
  end)
  it("refreshes the source window instead of reporting the report buffer", function()
    local view = module.show(current)
    vim.api.nvim_win_call(current, function()
      vim.cmd.lcd(root .. "/local")
    end)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(view.buf, "n")) do
      if mapping.lhs == "r" then
        mapping.callback()
        break
      end
    end
    local active = vim.api.nvim_get_current_win()
    local report = vim.api.nvim_win_get_buf(active)
    local text = table.concat(vim.api.nvim_buf_get_lines(report, 0, -1, false), "\n")
    assert.is_truthy(text:find(root .. "/source.cpp", 1, true))
    assert.is_truthy(text:find("Window cwd: " .. root .. "/local", 1, true))
    vim.api.nvim_win_close(active, true)
  end)
  it("evaluates buffer-aware status and launch resolvers in the original window", function()
    settings.configure({
      debug = {
        launch_file = function(_, source)
          assert.equals(buf, source)
          return "launch.json"
        end,
      },
    })
    package.loaded.scoper = {
      status_snapshot = function()
        assert.equals(buf, vim.api.nvim_get_current_buf())
        return { root = root }
      end,
    }
    local view = require("config.readonly").open({ "Another reference" })
    local data = module.snapshot(current)
    view.close()
    assert.is_nil(data.launch_error)
    assert.is_nil(data.scope_error)
    assert.equals(root .. "/launch.json", data.launch_file)
    assert.equals(root, data.scope.root)
  end)
end)
