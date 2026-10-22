local Path = require("scoper.path")
local State = require("scoper.state")

describe("Windows short-path scope identity", function()
  local windows, has, native, realpath, expanded, calls
  local root = "c:/Users/RUNNER~1/project"

  before_each(function()
    windows, has, native, realpath =
      Path.is_windows, vim.fn.has, package.loaded["scoper.windows"], vim.uv.fs_realpath
    Path.is_windows, expanded, calls = true, "c:/Users/runneradmin", 0
    vim.fn.has = function(feature)
      return feature == "win32" and 1 or has(feature)
    end
    package.loaded["scoper.windows"] = {
      expand = function(path)
        assert.equals("c:/Users/RUNNER~1", path)
        calls = calls + 1
        return expanded .. "/"
      end,
    }
    vim.uv.fs_realpath = function()
      error("scope matching must not resolve symbolic links")
    end
  end)

  after_each(function()
    Path.is_windows, vim.fn.has, package.loaded["scoper.windows"], vim.uv.fs_realpath =
      windows, has, native, realpath
  end)

  local function matcher(include, exclude)
    return State.build_matcher({ include = include or { "src" }, exclude = exclude or {} }, root)
  end

  it("accepts native buffer names expanded from an 8.3 project path", function()
    local match = matcher(nil, { "**/gen/**" })
    assert.is_true(match([[C:\Users\runneradmin\project\src\a.c]]))
    assert.is_false(match([[C:\Users\runneradmin\project\src\gen\b.c]]))
    assert.is_false(match([[C:\Users\runneradmin\elsewhere\src\a.c]]))
  end)

  it("also accepts filenames that retain their short prefix", function()
    local match = matcher(nil, { "**/gen/**" })
    assert.is_true(match(root .. "/src/a.c"))
    assert.is_false(match(root .. "/src/gen/b.c"))
  end)

  it("expands only the literal prefix of include and absolute exclude globs", function()
    local match = matcher({ "src/**/*.c" }, { root .. "/src/gen/**" })
    assert.is_true(match("c:/Users/runneradmin/project/src/a.c"))
    assert.is_false(match("c:/Users/runneradmin/project/src/gen/a.c"))
    assert.is_false(match("c:/Users/runneradmin/project/src/a.h"))
  end)

  it("does not perform filesystem expansion for ordinary logical symlink paths", function()
    local match = State.build_matcher({ include = { "src" }, exclude = {} }, "c:/link")
    assert.is_true(match("c:/link/src/a.c"))
    assert.is_false(match("c:/target/src/a.c"))
    assert.equals(0, calls)
  end)

  it("caches alias expansion within one matcher rather than across project changes", function()
    local match = matcher()
    for _ = 1, 10 do
      assert.is_true(match(root .. "/src/a.c"))
    end
    assert.equals(1, calls)
    expanded = "c:/Users/renamed"
    local next_match = matcher()
    assert.is_true(next_match("c:/Users/renamed/project/src/a.c"))
    assert.is_false(next_match("c:/Users/runneradmin/project/src/a.c"))
    assert.equals(2, calls)
  end)
end)

describe("native Windows path expansion", function()
  it("expands the runner's real short temporary path and preserves UTF-8", function()
    if vim.fn.has("win32") == 0 then
      pending("requires the Windows API")
      return
    end
    local base = vim.fn.tempname()
    local root = base .. "/long folder é 漢字"
    vim.fn.mkdir(root, "p")
    local ok, err = pcall(function()
      local expanded = require("scoper.windows").expand(root)
      assert.is_string(expanded)
      assert.equals(Path.key(vim.uv.fs_realpath(root)), Path.key(expanded))
      assert.equals(Path.key(expanded), Path.key(Path.expand_short(root, {})))
      assert.is_nil(require("scoper.windows").expand(root .. "/missing"))
    end)
    vim.fn.delete(base, "rf")
    assert.is_true(ok, tostring(err))
  end)
end)
