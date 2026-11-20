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

  it("applies exclusions from every admitting outside include in either order", function()
    local lib = root .. "/outside/lib"
    local project = root .. "/src"
    for _, includes in ipairs({
      { lib, lib .. "/generated" },
      { lib .. "/generated", lib },
      { lib .. "/generated", lib .. "/**/*.c" },
    }) do
      local definition = { include = includes, exclude = { "generated/**" } }
      local query = Scope.query(definition, project, true)
      local entry = { directory = lib, file = "generated/a.c" }
      assert.is_false(query.matches(lib .. "/" .. entry.file))
      assert.same({}, require("scoper.cdb").filter({ entry }, Scope.compile(definition, project)))
      assert.is_true(query.matches(lib .. "/ok.c"))
    end
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

  it("applies excludes with empty includes while bounding searches to the project", function()
    local definition = { include = {}, exclude = { "**/nested/**" } }
    local query = Scope.query(definition, root, true)
    assert.is_true(query.restricted)
    assert.same({ root }, query.roots)
    assert.same(definition.exclude, query.excludes)
    for _, matches in ipairs({ query.matches, Scope.compile(definition, root) }) do
      assert.is_true(matches(root .. "/src/main.c"))
      assert.is_true(matches(root .. "/../other.c"))
      assert.is_false(matches(root .. "/src/nested/hidden.c"))
    end
    definition.exclude = { "**" }
    assert.is_false(Scope.query(definition, root, true).matches(root .. "/src/main.c"))
  end)

  it("retains unrestricted disabled and empty-definition semantics", function()
    for _, fixture in ipairs({
      { scope = { include = { "src" }, exclude = { "**" } }, enabled = false },
      { scope = { include = {}, exclude = {} }, enabled = true },
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

describe("conservative directory exclusions", function()
  it("keeps root-relative descendant exclusions anchored", function()
    local root = Path.normalize(vim.fn.getcwd())
    local scope = { include = {}, exclude = { "vendor/**" } }
    local excluded = Scope.excluded_directory_matcher(scope, root, true)
    assert.is_true(excluded(root .. "/vendor"))
    assert.is_false(excluded(root .. "/src/vendor"))
    assert.is_true(Scope.compile(scope, root)("src/vendor/keep.c"))
    scope.exclude = { "*/**" }
    assert.is_false(Scope.excluded_directory_matcher(scope, root, true)(root))
    assert.is_true(Scope.compile(scope, root)("keep.c"))
  end)

  it("marks excluded subtrees but not mixed directories or include mismatches", function()
    local root = require("scoper.path").normalize(vim.fn.getcwd())
    local excluded = Scope.excluded_directory_matcher({
      include = { "**/*.cpp" },
      exclude = { "**/vendor/**", "build", "src/generated/**", "**/*.o" },
    }, root, true)
    for _, name in ipairs({ "vendor", "vendor/nested", "src/vendor", "build", "src/generated" }) do
      assert.is_true(excluded(root .. "/" .. name), name)
    end
    for _, name in ipairs({ "src", "headers", "vendor-other", "" }) do
      assert.is_false(excluded(root .. "/" .. name), name)
    end
    assert.is_false(excluded(root .. "-other/vendor"))
    local disabled = Scope.excluded_directory_matcher({ exclude = { "build" } }, root, false)
    assert.is_false(disabled(root .. "/build"))
  end)
end)

describe("include-aware directory markers", function()
  local root = Path.normalize(vim.fn.getcwd())
  local function matcher(include, exclude, enabled)
    return Scope.excluded_directory_matcher(
      { include = include, exclude = exclude or {} },
      root,
      enabled
    )
  end

  it("keeps literal includes and ancestors but marks disjoint subtrees", function()
    local excluded = matcher({ "src/lib", "tests/unit.cpp" }, { "src/lib/generated/**" })
    for _, name in ipairs({
      "docs",
      "src/other",
      "src/library",
      "tests/integration",
      "src/lib/generated",
    }) do
      assert.is_true(excluded(root .. "/" .. name), name)
    end
    for _, name in ipairs({ "", "src", "src/lib", "src/lib/nested", "tests" }) do
      assert.is_false(excluded(root .. "/" .. name), name)
    end
  end)

  it("bounds uncertain globs by complete literal path components", function()
    local excluded = matcher({ "src/**/*.cpp", "assets/{images,icons}/**" })
    assert.is_true(excluded(root .. "/docs"))
    assert.is_true(excluded(root .. "/src-other"))
    assert.is_false(excluded(root .. "/src/headers"))
    assert.is_false(excluded(root .. "/assets/other"))
    for _, glob in ipairs({ "**/*.cpp", "test*/unit/*.cpp", "{src,docs}/**" }) do
      assert.is_false(matcher({ glob })(root .. "/docs"), glob)
    end
  end)

  it("captures includes and preserves empty, disabled and outside-root behavior", function()
    local includes = { "src" }
    local excluded = matcher(includes)
    includes[1] = "docs"
    assert.is_true(excluded(root .. "/docs"))
    assert.is_false(excluded(root .. "/src"))
    assert.is_false(matcher({ "src" }, {}, false)(root .. "/docs"))
    assert.is_false(matcher({})(root .. "/docs"))
    assert.is_false(excluded(root .. "-elsewhere/docs"))
  end)

  it("handles literal Windows paths and component boundaries", function()
    local windows = Path.is_windows
    Path.is_windows = true
    local ok, err = pcall(function()
      local excluded = Scope.excluded_directory_matcher({
        include = { [[SRC\Library]] },
        exclude = {},
      }, [[C:\Work $NAME\Project]], true)
      assert.is_false(excluded("c:/work $name/project/src/library/nested"))
      assert.is_false(excluded("C:/Work $NAME/Project/SRC"))
      assert.is_true(excluded("C:/Work $NAME/Project/docs"))
      assert.is_true(excluded("C:/Work $NAME/Project/src/library-other"))
    end)
    Path.is_windows = windows
    assert.is_true(ok, err)
  end)
  it("reuses results during redraws without directory scans", function()
    local scan, under = vim.uv.fs_scandir, Path.key_under
    local checks = 0
    vim.uv.fs_scandir = function()
      error("must not scan directories")
    end
    Path.key_under = function(...)
      checks = checks + 1
      return under(...)
    end
    local ok, err = pcall(function()
      local excluded = matcher({ "src" })
      assert.is_true(excluded(root .. "/docs"))
      local first = checks
      assert.is_true(first > 0)
      for _ = 1, 100 do
        assert.is_true(excluded(root .. "/docs"))
      end
      assert.equals(first, checks)
      assert.is_false(matcher({ "docs" })(root .. "/docs"))
    end)
    vim.uv.fs_scandir, Path.key_under = scan, under
    assert.is_true(ok, err)
  end)
end)
