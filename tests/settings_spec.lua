describe("local customization lifecycle", function()
  local settings = require("config.settings")
  local root, cwd, notify, messages
  local leader, localleader, exrc, shiftwidth

  before_each(function()
    settings.reset()
    cwd, notify = vim.fn.getcwd(-1, -1), vim.notify
    leader, localleader = vim.g.mapleader, vim.g.maplocalleader
    exrc, shiftwidth = vim.o.exrc, vim.o.shiftwidth
    root, messages = vim.fn.tempname(), {}
    vim.fn.mkdir(root .. "/project/nested", "p")
    vim.fn.mkdir(root .. "/other", "p")
    vim.notify = function(message)
      messages[#messages + 1] = message
    end
  end)

  after_each(function()
    settings.reset()
    vim.notify = notify
    vim.cmd.cd(cwd)
    vim.g.mapleader, vim.g.maplocalleader = leader, localleader
    vim.g.config_local_file = false
    vim.o.exrc, vim.o.shiftwidth = exrc, shiftwidth
    vim.fn.delete(root, "rf")
  end)

  it("keeps false, empty lists and functions and returns isolated table values", function()
    local resolver = function()
      return root
    end
    settings.configure({ tools = { servers = {} }, flag = false, project = { root = resolver } })
    settings.configure({})
    assert.is_false(settings.get("flag", true))
    assert.is_false(settings.get("missing", false))
    assert.same({}, settings.get("tools.servers", { "lua_ls" }))
    assert.equals(resolver, settings.get("project.root"))
    local list = settings.get("tools.servers")
    list[1] = "pyright"
    assert.same({}, settings.get("tools.servers"))
  end)

  it("loads machine policy before options and preserves explicit pre-set false", function()
    vim.fn.writefile(
      { 'return { globals = { mapleader = "," }, options = { shiftwidth = 7 } }' },
      root .. "/local.lua"
    )
    vim.g.config_local_file = nil
    vim.g.maplocalleader = ";"
    vim.o.exrc = false
    settings.bootstrap(root)
    dofile(cwd .. "/lua/config/options.lua")
    settings.apply_options()
    assert.equals(",", vim.g.mapleader)
    assert.equals(";", vim.g.maplocalleader)
    assert.is_false(vim.o.exrc)
    assert.equals(7, vim.o.shiftwidth)
    assert.equals(root .. "/local.lua", settings.info().source)
  end)

  it("does not execute disabled or missing local files and reports invalid files", function()
    vim.fn.writefile({ 'error("must not execute")' }, root .. "/local.lua")
    assert.is_true(settings.load(false))
    assert.is_true(settings.load(root .. "/absent.lua"))
    assert.is_false(settings.load(root .. "/local.lua"))
    vim.fn.writefile({ "return false" }, root .. "/local.lua")
    assert.is_false(settings.load(root .. "/local.lua"))
    assert.equals(2, #messages)
    assert.is_nil(settings.get("tools"))
  end)

  it("layers trusted project dictionaries and replaces lists without leaking on cd", function()
    settings.configure({ example = { machine = true, list = { "base" } } })
    settings.for_project(root .. "/project", { example = { parent = true, list = {} } })
    settings.for_project(root .. "/project/nested", { example = { nested = true } })
    vim.cmd.cd(root .. "/project/nested")
    assert.same(
      { machine = true, parent = true, nested = true, list = {} },
      settings.get("example")
    )
    vim.cmd.cd(root .. "/other")
    assert.same({ machine = true, list = { "base" } }, settings.get("example"))
  end)

  it("resolves invocation cwd, global project and current file independently", function()
    vim.cmd.cd(root .. "/project")
    settings.configure({
      project = {
        root = function(ctx)
          assert.equals(root .. "/project", ctx.cwd)
          return root .. "/project"
        end,
      },
    })
    vim.cmd.lcd(root .. "/other")
    assert.equals(root .. "/other", settings.resolve("cwd"))
    assert.equals(root .. "/project", settings.resolve("project"))
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_name(buf, root .. "/project/nested/code.lua")
    assert.equals(root .. "/project/nested", settings.resolve("file"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("does not expand literal path metacharacters in explicit roots", function()
    vim.cmd.cd(root)
    settings.configure({ project = { root = "literal $HOME % #" } })
    assert.equals(root .. "/literal $HOME % #", settings.project_root())
  end)

  it("adapts the standalone Scoper root callback to global cwd", function()
    vim.cmd.cd(root)
    settings.configure({
      scoper = {
        project = {
          root = function(global_cwd)
            assert.equals(root, global_cwd)
            return global_cwd .. "/project"
          end,
        },
      },
    })
    assert.equals(root .. "/project", settings.project_root())
  end)

  it("uses the same parent replacement semantics for leaf and dictionary reads", function()
    vim.cmd.cd(root .. "/project")
    settings.configure({
      tools = { executables = { compiler = "/machine/cc" }, servers = { "lua_ls" } },
    })
    settings.for_project(root .. "/project", { tools = { executables = {}, servers = {} } })
    assert.same({}, settings.get("tools.executables"))
    assert.is_nil(settings.get("tools.executables.compiler"))
    assert.same({}, settings.get("tools.servers"))
    vim.cmd.cd(root .. "/other")
    assert.equals("/machine/cc", settings.get("tools.executables.compiler"))
  end)

  it("reports malformed global, option and plugin sections without stopping startup", function()
    settings.configure({ globals = false, options = "bad", plugins = true })
    assert.is_false(settings.apply_globals())
    assert.is_false(settings.apply_options())
    assert.same({}, settings.plugin_specs())
    assert.equals(3, #messages)
  end)
end)
