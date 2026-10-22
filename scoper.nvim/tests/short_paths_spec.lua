local Path = require("scoper.path")
local State = require("scoper.state")

describe("Windows short-path scope identity", function()
  local windows, has, modify, realpath, expanded, calls
  local root = "c:/Users/RUNNER~1/project"

  before_each(function()
    windows, has, modify, realpath =
      Path.is_windows, vim.fn.has, vim.fn.fnamemodify, vim.uv.fs_realpath
    Path.is_windows, expanded, calls = true, "c:/Users/runneradmin", 0
    vim.fn.has = function(feature)
      return feature == "win32" and 1 or has(feature)
    end
    vim.fn.fnamemodify = function(path, modifiers)
      assert.equals("c:/Users/RUNNER~1", path)
      assert.equals(":p", modifiers)
      calls = calls + 1
      return expanded .. "/"
    end
    vim.uv.fs_realpath = function()
      error("scope matching must not resolve symbolic links")
    end
  end)

  after_each(function()
    Path.is_windows, vim.fn.has, vim.fn.fnamemodify, vim.uv.fs_realpath =
      windows, has, modify, realpath
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
