local State = require("scoper.state")
local Path = require("scoper.path")

describe("outside-project glob include roots", function()
  local cwd = "/tmp/build/project"
  local pattern = "/tmp/build/library/**/*.c"

  local function matcher(excludes, includes)
    return State.build_matcher({ include = includes or { pattern }, exclude = excludes }, cwd)
  end

  it("does not apply a slashless exclude to ancestors above the glob's literal root", function()
    local m = matcher({ "build" })
    assert.is_true(m("/tmp/build/library/src/a.c"))
    assert.is_false(m("/tmp/build/library/src/build/a.c"))
  end)

  it("does not apply a recursive exclude to ancestors above that root", function()
    local m = matcher({ "**/build/**" })
    assert.is_true(m("/tmp/build/library/src/a.c"))
    assert.is_false(m("/tmp/build/library/build/a.c"))
  end)

  it("anchors a relative exclude at the literal root of an outside glob", function()
    local m = matcher({ "/generated" })
    assert.is_false(m("/tmp/build/library/generated/a.c"))
    assert.is_true(m("/tmp/build/library/src/generated/a.c"))
  end)

  it("matches slash-containing excludes relative to the glob root", function()
    local m = matcher({ "src/generated" })
    assert.is_false(m("/tmp/build/library/src/generated/a.c"))
    assert.is_true(m("/tmp/build/library/src/other/a.c"))
  end)

  it("still applies explicit absolute excludes", function()
    local m = matcher({ "/tmp/build/library/src" })
    assert.is_false(m("/tmp/build/library/src/a.c"))
    assert.is_true(m("/tmp/build/library/other/a.c"))
  end)

  it("does not include other files merely because they share the literal prefix", function()
    local m = matcher({})
    assert.is_true(m("/tmp/build/library/src/a.c"))
    assert.is_false(m("/tmp/build/library/src/a.h"))
    assert.is_false(m("/tmp/build/elsewhere/a.c"))
  end)

  it("uses the complete literal ancestor when a wildcard occurs within a component", function()
    local m = matcher({ "/library" }, { "/tmp/build/lib*/**/*.c" })
    assert.is_false(m("/tmp/build/library/a.c"))
    assert.is_true(m("/tmp/build/libother/library/a.c"))
  end)

  it("continues to use the project root for files inside the project", function()
    local m = matcher({ "/generated" }, { "**/*.c" })
    assert.is_false(m(cwd .. "/generated/a.c"))
    assert.is_true(m(cwd .. "/src/generated/a.c"))
  end)

  it("handles a hand-edited include whose glob component normalizes away", function()
    local m = matcher({}, { "/tmp/build/library/*/../src" })
    assert.is_true(m("/tmp/build/library/src/a.c"))
  end)
end)

-- These exercise path rules on Linux; they are not native Windows I/O tests.
describe("outside glob roots with forced Windows path rules", function()
  local windows
  before_each(function()
    windows, Path.is_windows = Path.is_windows, true
  end)
  after_each(function()
    Path.is_windows = windows
  end)

  it("preserves the drive root boundary", function()
    local m =
      State.build_matcher({ include = { "C:/**/*.c" }, exclude = { "build" } }, "C:/project")
    assert.is_true(m("c:/src/a.c"))
    assert.is_false(m("c:/build/a.c"))
  end)

  it("ignores ancestors of a mixed-case absolute glob", function()
    local m = State.build_matcher(
      { include = { "C:/Build/Lib/**/*.c" }, exclude = { "build" } },
      "C:/Build/project"
    )
    assert.is_true(m("c:/build/LIB/src/a.c"))
    assert.is_false(m("c:/build/LIB/build/a.c"))
  end)
end)
