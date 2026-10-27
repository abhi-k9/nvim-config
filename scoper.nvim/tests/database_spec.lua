local Database = require("scoper.database")
local Path = require("scoper.path")

describe("compilation database selection", function()
  local root, external
  before_each(function()
    root, external = Path.normalize(vim.fn.tempname()), Path.normalize(vim.fn.tempname())
    vim.fn.mkdir(root .. "/nested/debug", "p")
    vim.fn.mkdir(root .. "/build", "p")
    vim.fn.mkdir(external, "p")
  end)
  after_each(function()
    vim.fn.delete(root, "rf")
    vim.fn.delete(external, "rf")
  end)
  local function put(path)
    vim.fn.writefile({ "[]" }, path)
    return path
  end
  it("accepts an explicit nested directory and external filename", function()
    local path = put(root .. "/nested/debug/compile_commands.json")
    assert.equals(path, Database.resolve(root, { path = "nested/debug" }, {}).path)
    path = put(external .. "/custom.json")
    assert.equals(path, Database.resolve(root, { path = path }, {}).path)
  end)
  it("reports a missing explicit selection without silently choosing another build", function()
    put(root .. "/build/compile_commands.json")
    local result = Database.resolve(root, { path = "missing.json" }, {})
    assert.is_nil(result.path)
    assert.equals(root .. "/missing.json", result.requested)
    assert.is_true(result.explicit)
  end)
  it("rejects ambiguous default discovery while preserving legacy first-match", function()
    local first = put(root .. "/compile_commands.json")
    put(root .. "/build/compile_commands.json")
    assert.is_true(Database.resolve(root, {}, {}).ambiguous)
    assert.equals(first, Database.resolve(root, {}, {}, true).path)
    assert.equals(
      root .. "/build/compile_commands.json",
      Database.resolve(root, {
        candidates = { "build", "compile_commands.json" },
      }, {}).path
    )
  end)
  it("uses only the configured candidate list, including an empty list", function()
    put(root .. "/compile_commands.json")
    assert.is_nil(Database.resolve(root, { candidates = {} }, {}).path)
  end)
  it("resolves callbacks in the editor using a copy of the context", function()
    local context = { scope = "work", revision = 4 }
    local path = put(external .. "/custom.json")
    local result = Database.resolve(root, {
      resolver = function(ctx)
        assert.equals("work", ctx.scope)
        ctx.scope = "changed"
        return path
      end,
    }, context)
    assert.equals(path, result.path)
    assert.equals("work", context.scope)
  end)
  it("bounds explicit candidate work", function()
    local candidates = {}
    for i = 1, 257 do
      candidates[i] = tostring(i)
    end
    assert.has_error(function()
      Database.resolve(root, { candidates = candidates }, {})
    end)
  end)
end)
