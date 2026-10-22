local Path = require("scoper.path")
local State = require("scoper.state")

-- Pure string rules forced on Linux, not a native Windows/network-share test.
describe("UNC include and exclude globs", function()
  local windows
  before_each(function()
    windows, Path.is_windows = Path.is_windows, true
  end)
  after_each(function()
    Path.is_windows = windows
  end)

  it("accepts a valid UNC glob without accepting malformed internal empty segments", function()
    assert.is_true(Path.valid_glob("//server/share/generated/**"))
    assert.is_false(Path.valid_glob("//server/share//generated/**"))
    assert.is_false(Path.valid_glob("//server/share/["))
  end)

  it("matches an absolute UNC include using Windows case rules", function()
    assert.is_true(Path.match_glob("//SERVER/Share/src/a.c", "//server/share/**/*.c", "c:/project"))
    assert.is_false(
      Path.match_glob("//server/share/src/a.h", "//server/share/**/*.c", "c:/project")
    )
    assert.is_false(Path.match_glob("/server/share/src/a.c", "//server/share/**/*.c", "c:/project"))
    assert.is_false(Path.match_glob("//other/share/src/a.c", "//server/share/**/*.c", "c:/project"))
  end)

  it("matches a UNC exclude and its directory descendants", function()
    local m = Path.exclude_matcher("//SERVER/Share/generated")
    assert.is_not_nil(m)
    assert.is_true(m("//server/share/generated/a.c", "generated/a.c"))
    assert.is_false(m("//other/share/generated/a.c", "generated/a.c"))
    assert.is_false(m("/server/share/generated/a.c", "generated/a.c"))
  end)

  it("handles an outside UNC include root without excluding its ancestors", function()
    local m = State.build_matcher(
      { include = { "//server/build/**/*.c" }, exclude = { "build" } },
      "//server/project"
    )
    assert.is_true(m("//server/build/src/a.c"))
    assert.is_false(m("//server/build/src/build/a.c"))
  end)
end)
