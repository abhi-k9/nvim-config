local Scoper = require("scoper")
local State = require("scoper.state")
local Pipeline = require("scoper.pipeline")
local Database = require("scoper.database")
local LSP = require("scoper.lsp")
local Cdb = require("scoper.cdb")

describe("operation-local compilation database resolution", function()
  local root, previous, config, resolve, run, calls, env
  before_each(function()
    root, previous = vim.fn.tempname(), vim.fn.getcwd()
    env = { vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME }
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = root .. "/data", root .. "/cache"
    vim.fn.mkdir(root .. "/src", "p")
    vim.fn.writefile({
      vim.json.encode({ { directory = root, file = "src/a.c", command = "cc -c src/a.c" } }),
    }, root .. "/compile_commands.json")
    vim.fn.chdir(root)
    config = Scoper.config
    Scoper.config = vim.deepcopy(config)
    Scoper.config.compilation_database = {}
    Scoper.config.lsp = { mode = "selected" }
    State.configure_project(nil)
    State.load()
    Pipeline._last_result = nil
    calls, resolve, run = 0, Database.resolve, Cdb.run
    Database.resolve = function(...)
      calls = calls + 1
      return resolve(...)
    end
  end)
  after_each(function()
    Database.resolve, Scoper.config, Cdb.run = resolve, config, run
    vim.fn.chdir(previous)
    State.configure_project(config.project and config.project.root)
    State.load()
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = env[1], env[2]
    vim.fn.delete(root, "rf")
  end)

  it("discovers once per status and observes external discovery changes", function()
    assert.equals(root .. "/compile_commands.json", Pipeline.status().selection.path)
    assert.equals(1, calls)
    vim.fn.mkdir(root .. "/cmake-build-new", "p")
    vim.fn.writefile({ "[]" }, root .. "/cmake-build-new/compile_commands.json")
    assert.is_true(Pipeline.status().selection.ambiguous)
    assert.equals(2, calls)
    vim.fn.delete(root .. "/compile_commands.json")
    assert.equals(
      root .. "/cmake-build-new/compile_commands.json",
      Pipeline.status().selection.path
    )
    assert.equals(3, calls)
  end)

  it("shares a selected command resolution without retaining it between commands", function()
    assert.is_true(vim.tbl_contains(LSP.clangd_cmd(), "--compile-commands-dir=" .. root))
    assert.equals(1, calls)
    vim.fn.delete(root .. "/compile_commands.json")
    local command = LSP.clangd_cmd()
    assert.equals(2, calls)
    for _, arg in ipairs(command) do
      assert.is_nil(arg:match("^%-%-compile%-commands%-dir="))
    end
  end)

  it("resolves arbitrary callbacks afresh for each command", function()
    local selected = root .. "/compile_commands.json"
    Scoper.config.compilation_database.resolver = function()
      return selected
    end
    LSP.clangd_cmd()
    selected = false
    local command = LSP.clangd_cmd()
    assert.equals(2, calls)
    for _, arg in ipairs(command) do
      assert.is_nil(arg:match("^%-%-compile%-commands%-dir="))
    end
  end)

  it("shares warm filtered preparation but revalidates cold work", function()
    Scoper.config.lsp.mode = "filtered"
    State.state.enabled = true
    State.state.scopes.default = { include = { "src" }, exclude = {} }
    local first = LSP.clangd_cmd()
    assert.equals(2, calls)
    calls = 0
    assert.are.same(first, LSP.clangd_cmd())
    assert.equals(1, calls)
    calls = 0
    local delivered
    Pipeline._filter_async(function(_, _, _, _, obsolete)
      delivered = true
      assert.is_nil(obsolete)
    end)
    assert.is_true(delivered)
    assert.equals(1, calls)
  end)

  it("re-resolves an external selection changed during cold preparation", function()
    Scoper.config.lsp.mode = "filtered"
    State.state.enabled = true
    State.state.scopes.default = { include = { "src" }, exclude = {} }
    local selected = root .. "/compile_commands.json"
    Scoper.config.compilation_database.resolver = function()
      return selected
    end
    vim.fn.mkdir(root .. "/alternate", "p")
    vim.fn.writefile({ "[]" }, root .. "/alternate/compile_commands.json")
    Cdb.run = function(job)
      assert.equals(root .. "/compile_commands.json", job.cc)
      selected = root .. "/alternate/compile_commands.json"
      -- A failed cold preparation falls back to the currently selected input.
      return { info = "preparation failed while external build selection changed" }
    end
    local command = LSP.clangd_cmd()
    assert.is_true(vim.tbl_contains(command, "--compile-commands-dir=" .. root .. "/alternate"))
    assert.equals(selected, Pipeline._last_result.selection.path)
    assert.equals(2, calls)
  end)
end)
