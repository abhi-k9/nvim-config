local Scope = require("scoper.scope")
local Path = require("scoper.path")

describe("shared scope query plans", function()
  local root

  before_each(function()
    root = Path.normalize(vim.fn.tempname())
    vim.fn.mkdir(root .. "/src/nested", "p")
    vim.fn.mkdir(root .. "/outside/lib", "p")
    vim.fn.writefile({}, root .. "/src/main.c")
  end)

  after_each(function()
    vim.fn.delete(root, "rf")
  end)

  it("uses literal files as bounded search roots", function()
    local query = Scope.query({ include = { "src/main.c" }, exclude = {} }, root, true)
    assert.is_true(query.restricted)
    assert.same({ root .. "/src/main.c" }, query.roots)
    assert.is_true(query.matches(root .. "/src/main.c"))
    assert.is_false(query.matches(root .. "/src/main.c.old"))
    assert.is_false(query.matches(root .. "/src/other.c"))
  end)

  it("bounds glob searches to their literal ancestor while applying exact membership", function()
    local query =
      Scope.query({ include = { "src/**/*.c" }, exclude = { "**/nested/**" } }, root, true)
    assert.same({ root .. "/src" }, query.roots)
    assert.is_true(query.matches(root .. "/src/main.c"))
    assert.is_false(query.matches(root .. "/src/main.h"))
    assert.is_false(query.matches(root .. "/src/nested/other.c"))
    assert.is_false(query.matches(root .. "/outside/other.c"))
  end)

  it("keeps outside includes and their relative excludes consistent with the matcher", function()
    local query = Scope.query(
      { include = { root .. "/outside/lib/*.c" }, exclude = { "skip.c" } },
      root .. "/src",
      true
    )
    assert.same({ root .. "/outside/lib" }, query.roots)
    assert.is_true(query.matches(root .. "/outside/lib/main.c"))
    assert.is_false(query.matches(root .. "/outside/lib/skip.c"))
  end)

  it("deduplicates roots but captures the full include and exclude predicate", function()
    local definition = { include = { "src/*.c", "src/*.h" }, exclude = { "main.c" } }
    local query = Scope.query(definition, root, true)
    assert.same({ root .. "/src" }, query.roots)
    definition.include[1], definition.exclude[1] = "outside", "nothing"
    assert.is_false(query.matches(root .. "/src/main.c"))
    assert.is_true(query.matches(root .. "/src/other.c"))
    assert.is_true(query.matches(root .. "/src/other.h"))
  end)

  it("refuses to broaden missing paths to the project root", function()
    local query =
      Scope.query({ include = { "missing", "missing/deeper/**/*.c" }, exclude = {} }, root, true)
    assert.is_true(query.restricted)
    assert.same({}, query.roots)
    assert.same({ "missing", "missing/deeper/**/*.c" }, query.missing)
    assert.is_false(query.matches(root .. "/src/main.c"))
  end)

  it("retains unrestricted disabled and empty-include semantics", function()
    for _, fixture in ipairs({
      { scope = { include = { "src" }, exclude = { "**" } }, enabled = false },
      { scope = { include = {}, exclude = { "**" } }, enabled = true },
    }) do
      local query = Scope.query(fixture.scope, root, fixture.enabled)
      assert.is_false(query.restricted)
      assert.is_nil(query.roots)
      assert.is_true(query.matches(root .. "/outside/file.c"))
      assert.same({}, query.excludes)
    end
  end)

  it(
    "keeps symlink membership logical rather than following an alias into another include",
    function()
      local linked = vim.uv.fs_symlink(root .. "/outside", root .. "/src/link", { dir = true })
      if not linked then
        pending("symlink creation is unavailable on this host")
        return
      end
      local query = Scope.query({ include = { "src" }, exclude = {} }, root, true)
      assert.is_true(query.matches(root .. "/src/link/file.c"))
      assert.is_false(query.matches(root .. "/outside/file.c"))
    end
  )
end)
