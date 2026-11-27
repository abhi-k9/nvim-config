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

  it("reads machine settings without resolving cwd until an overlay is registered", function()
    settings.configure({ example = { enabled = true } })
    local getcwd = vim.fn.getcwd
    vim.fn.getcwd = function()
      error("machine-only settings must not resolve cwd")
    end
    local ok, value = pcall(settings.get, "example.enabled")
    vim.fn.getcwd = getcwd
    assert.is_true(ok, value)
    assert.is_true(value)

    settings.for_project(root .. "/project", { example = { enabled = false } })
    vim.cmd.cd(root .. "/project")
    assert.is_false(settings.get("example.enabled"))
    vim.cmd.cd(root .. "/other")
    assert.is_true(settings.get("example.enabled"))
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

  it("rejects a non-regular local configuration before opening it", function()
    local path = root .. "/local.json"
    local stat, read = vim.uv.fs_stat, vim.fn.readfile
    local opened = false
    vim.uv.fs_stat = function(file)
      if file == path then return { type = "fifo" } end
      return stat(file)
    end
    vim.fn.readfile = function()
      opened = true
      return { "{}" }
    end
    local ok, result = pcall(settings.load, path)
    vim.uv.fs_stat, vim.fn.readfile = stat, read
    assert.is_true(ok)
    assert.is_false(opened)
    assert.is_false(result)
    assert.equals(1, #messages)
  end)

  it("accepts JSON objects but rejects arrays, null and malformed JSON", function()
    local path = root .. "/local.json"
    for _, input in ipairs({ "[]", "[1]", "null", "{" }) do
      vim.fn.writefile({ input }, path)
      assert.is_false(settings.load(path), input)
    end
    vim.fn.writefile({ '{"explorer":{"scope_markers":false}}' }, path)
    assert.is_true(settings.load(path))
    assert.is_false(settings.get("explorer.scope_markers", true))
    vim.fn.writefile({ "{}" }, path)
    assert.is_true(settings.load(path))
  end)

  it("uses JSON only when the default Lua file is absent", function()
    vim.g.config_local_file = nil
    vim.fn.writefile({ '{"example":"json"}' }, root .. "/local.json")
    settings.bootstrap(root)
    assert.equals("json", settings.get("example"))
    settings.reset()
    vim.fn.writefile({ 'return { example = "lua" }' }, root .. "/local.lua")
    settings.bootstrap(root)
    assert.equals("lua", settings.get("example"))
    settings.reset()
    local stat = vim.uv.fs_stat
    vim.uv.fs_stat = function(path, ...)
      if path == root .. "/local.lua" then return nil, "permission denied", "EACCES" end
      return stat(path, ...)
    end
    local ok, err = pcall(settings.bootstrap, root)
    vim.uv.fs_stat = stat
    assert.is_true(ok, err)
    assert.is_nil(settings.get("example"))
    assert.equals(root .. "/local.lua", settings.info().source)
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

  it("resolves platform-specific separators from the project base", function()
    vim.cmd.cd(root)
    if vim.fn.has("win32") == 1 then
      local drive = root:match("^%a:")
      if drive then
        assert.equals(vim.fs.normalize(drive .. "/src"), settings.resolve("/src"))
        assert.equals(settings.resolve("/src"), settings.resolve([[\src]]))
      end
    else
      assert.equals(root .. [[/~\draft]], settings.resolve([[~\draft]]))
    end
  end)

  it("keeps the share prefix when resolving relative project roots", function()
    local getcwd = vim.fn.getcwd
    vim.fn.getcwd = function()
      return "//server/share"
    end
    local ok, result = pcall(settings.resolve, "nested/code")
    vim.fn.getcwd = getcwd
    assert.is_true(ok)
    assert.equals("//server/share/nested/code", result)
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

  it("uses global cwd when Scoper's fallback resolver returns an empty path", function()
    vim.cmd.cd(root)
    vim.cmd.lcd(root .. "/other")
    local function use_default_root()
      return ""
    end
    settings.configure({ scoper = { project = { root = use_default_root } } })
    assert.equals(root, settings.resolve("project"))
    assert.equals(root .. "/other", settings.resolve("cwd"))
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

  it("restores pre-set options when the local options section is malformed", function()
    vim.o.shiftwidth = 3
    settings.capture_options()
    vim.o.shiftwidth = 8
    settings.configure({ options = "invalid" })
    assert.is_false(settings.apply_options())
    assert.equals(3, vim.o.shiftwidth)
    assert.equals(1, #messages)
  end)

  it("reports malformed global, option and plugin sections without stopping startup", function()
    settings.configure({ globals = false, options = "bad", plugins = true })
    assert.is_false(settings.apply_globals())
    assert.is_false(settings.apply_options())
    assert.same({}, settings.plugin_specs())
    assert.equals(3, #messages)
  end)
end)
