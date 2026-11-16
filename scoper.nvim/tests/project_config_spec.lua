local Project = require("scoper.project_config")
local Scoper = require("scoper")
local State = require("scoper.state")
local Path = require("scoper.path")

describe("declarative project configuration", function()
  local root, other, previous, data, old_data, notify
  local function write(doc)
    vim.fn.writefile({ vim.json.encode(doc) }, Project.path(root))
  end
  before_each(function()
    root, other, data =
      Path.normalize(vim.fn.tempname()), Path.normalize(vim.fn.tempname()), vim.fn.tempname()
    previous, old_data, notify = vim.fn.getcwd(), vim.env.XDG_DATA_HOME, vim.notify
    vim.env.XDG_DATA_HOME = data
    vim.notify = function() end
    vim.fn.mkdir(root .. "/src", "p")
    vim.fn.mkdir(other, "p")
    vim.fn.chdir(root)
  end)
  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "scoper_dir")
    if package.loaded["scoper.lsp"] then require("scoper.lsp").dispose() end
    vim.fn.chdir(previous)
    vim.env.XDG_DATA_HOME, vim.notify = old_data, notify
    State.project_defaults, State.default_excludes = {}, {}
    for _, path in ipairs({ root, other, data }) do
      vim.fn.delete(path, "rf")
    end
  end)

  it("loads safe settings and initial scopes without writing the project file", function()
    write({
      version = 1,
      settings = { picker = "telescope", default_excludes = { "**/gen/**" } },
      scopes = { cpp = { include = { "src/**/*.cpp" } } },
      active = "cpp",
      enabled = true,
    })
    local before = vim.fn.readfile(Project.path(root))
    Scoper.setup({ default_excludes = { "old" } })
    assert.equals("telescope", Scoper.config.picker)
    assert.equals("cpp", State.active_name())
    assert.same({ "**/gen/**" }, State.active_scope().exclude)
    assert.is_true(State.is_in_scope(root .. "/src/main.cpp"))
    State.add_excludes("**/test/**")
    assert.same(before, vim.fn.readfile(Project.path(root)))
  end)

  it("preserves saved scopes until explicitly applying configured definitions", function()
    Scoper.setup({})
    State.add_paths("src")
    write({ version = 1, scopes = { default = { include = {}, exclude = { "**/gen/**" } } } })
    assert.is_true(Scoper.reload_project_config())
    assert.same({ "src" }, State.active_scope().include)
    assert.is_true(Scoper.reload_project_config(true))
    assert.same({}, State.active_scope().include)
    assert.same({ "**/gen/**" }, State.active_scope().exclude)
  end)

  it("switches project defaults without leaking settings across roots", function()
    write({ version = 1, settings = { picker = "telescope" } })
    Scoper.setup({})
    vim.cmd.cd(vim.fn.fnameescape(other))
    assert.equals("auto", Scoper.config.picker)
    assert.equals(other, State.root())
    vim.cmd.cd(vim.fn.fnameescape(root))
    assert.equals("telescope", Scoper.config.picker)
  end)

  it("gives explicit personal overrides priority and supports opting out", function()
    write({ version = 1, settings = { picker = "telescope" } })
    Scoper.setup({ project_config = { overrides = { picker = "fzf" } } })
    assert.equals("fzf", Scoper.config.picker)
    Scoper.setup({ project_config = { enabled = false } })
    assert.equals("auto", Scoper.config.picker)
  end)

  it("rejects malformed and executable settings without replacing working configuration", function()
    write({ version = 1, settings = { picker = "telescope" } })
    Scoper.setup({})
    for _, doc in ipairs({
      { version = 2 },
      { version = 1, settings = false },
      { version = 1, settings = { lsp = { cmd = { "bad" } } } },
      { version = 1, settings = { lsp = { query_drivers = { "*" } } } },
      { version = 1, scopes = { cpp = { include = { "[" } } } },
    }) do
      write(doc)
      assert.is_false(Scoper.reload_project_config())
      assert.equals("telescope", Scoper.config.picker)
    end
    vim.fn.writefile({ "{" }, Project.path(root))
    assert.is_false(Scoper.reload_project_config())
    Scoper.setup({})
    assert.equals("telescope", Scoper.config.picker)
  end)

  it("exports readable config exclusively and only overwrites explicitly", function()
    Scoper.setup({})
    State.add_paths("src")
    State.set_database(root .. "/build/compile_commands.json")
    local ok, err = Scoper.export_project_config()
    assert.is_true(ok, err)
    assert.is_true(#vim.fn.readfile(Project.path(root)) > 5)
    local doc = assert(Project.read(root))
    assert.equals("build/compile_commands.json", doc.settings.compilation_database.path)
    assert.same({ "src" }, doc.scopes.default.include)
    assert.is_false(Scoper.export_project_config())
    assert.is_true(Scoper.export_project_config(true))
  end)

  it("keeps an existing export intact on publication failure", function()
    write({ version = 1 })
    local before = vim.fn.readfile(Project.path(root))
    local rename = vim.uv.fs_rename
    vim.uv.fs_rename = function()
      return nil, "simulated failure"
    end
    local ok, err = Project.export(root, { version = 1, enabled = true }, true)
    vim.uv.fs_rename = rename
    assert.is_false(ok)
    assert.equals("simulated failure", err)
    assert.same(before, vim.fn.readfile(Project.path(root)))
  end)
end)
