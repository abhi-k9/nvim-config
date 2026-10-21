-- tests/util_spec.lua
--
-- Unit tests for scoper.util. Pure-function helpers, plus atomic_write
-- (in temp dirs). These tests exist primarily to nail down the split_args contract
-- because the command dispatchers in plugin/scoper.lua depend on it
-- distinguishing "no args" (returns nil → caller invokes the picker)
-- from "one or more args" (returns a list → caller acts directly).

describe("scoper.util.split_args", function()
  local split_args

  before_each(function()
    package.loaded["scoper.util"] = nil
    split_args = require("scoper.util").split_args
  end)

  ---------------------------------------------------------------------------
  -- The nil-returning cases: caller will route to picker.
  ---------------------------------------------------------------------------
  it("returns nil for nil input", function()
    assert.is_nil(split_args(nil))
  end)

  it("returns nil for empty string", function()
    assert.is_nil(split_args(""))
  end)

  it("returns nil for whitespace-only string", function()
    -- This matters because nargs='*' can deliver " " when the user
    -- types `:ScoperDelete <Tab>` and tab-completes nothing — we
    -- want the picker, not a list of empty tokens.
    assert.is_nil(split_args("   "))
    assert.is_nil(split_args("\t"))
    assert.is_nil(split_args(" \t  \t"))
  end)

  ---------------------------------------------------------------------------
  -- The list-returning cases: caller will act directly.
  ---------------------------------------------------------------------------
  it("returns a singleton list for a single token", function()
    assert.are.same({ "foo" }, split_args("foo"))
  end)

  it("splits multiple whitespace-separated tokens", function()
    assert.are.same({ "foo", "bar", "baz" }, split_args("foo bar baz"))
  end)

  it("collapses runs of whitespace", function()
    assert.are.same({ "foo", "bar" }, split_args("foo    bar"))
    assert.are.same({ "foo", "bar" }, split_args("foo\tbar"))
    assert.are.same({ "foo", "bar" }, split_args("foo \t  bar"))
  end)

  it("trims leading and trailing whitespace", function()
    assert.are.same({ "foo" }, split_args("  foo  "))
    assert.are.same({ "foo", "bar" }, split_args("\tfoo bar\t"))
  end)

  it("preserves token order", function()
    -- :ScoperDelete a b c d e — the loop in M.delete must see them
    -- in this order so the last-scope-guard fires on the right name.
    assert.are.same({ "a", "b", "c", "d", "e" }, split_args("a b c d e"))
  end)

  ---------------------------------------------------------------------------
  -- Path-like tokens. Splitting is on unescaped whitespace only; paths are
  -- not parsed here.
  ---------------------------------------------------------------------------
  it("keeps slashes and dots inside tokens intact", function()
    assert.are.same({ "src/foo", "./bar/baz" }, split_args("src/foo ./bar/baz"))
  end)

  it("keeps Windows-style backslash paths as single tokens", function()
    -- Backslashes are not whitespace; they survive splitting. Path
    -- normalization happens downstream in state/path.lua.
    assert.are.same(
      { [[C:\Users\me\proj]], [[D:\other]] },
      split_args([[C:\Users\me\proj D:\other]])
    )
  end)

  it("splits paths with embedded spaces into multiple tokens", function()
    -- Quotes mean nothing to nargs='*'; a space inside a path must be
    -- escaped ("\ ", as dir completion inserts it), or use the picker.
    assert.are.same({ [[C:\Program]], [[Files\foo]] }, split_args([[C:\Program Files\foo]]))
  end)
end)

describe("scoper.util.split_args escaped spaces", function()
  local split_args = require("scoper.util").split_args

  it("keeps a backslash-escaped space inside the token (what dir completion inserts)", function()
    assert.are.same({ "my dir", "other" }, split_args([[my\ dir other]]))
  end)

  it("leaves Windows separators alone", function()
    assert.are.same({ [[C:\src\app]], [[D:\x y]] }, split_args([[C:\src\app D:\x\ y]]))
  end)
end)

describe("scoper.util.atomic_write", function()
  local Util = require("scoper.util")

  it("replaces the file and leaves no temp file behind", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "old" }, dir .. "/f.json")
    assert.is_true(Util.atomic_write(dir .. "/f.json", { "new" }))
    assert.are.same({ "new" }, vim.fn.readfile(dir .. "/f.json"))
    assert.are.same({ "f.json" }, vim.fn.readdir(dir))
    vim.fn.delete(dir, "rf")
  end)

  it("returns an error instead of throwing when the write fails", function()
    local ok, res, err = pcall(Util.atomic_write, vim.fn.tempname() .. "/missing/f.json", { "x" })
    assert.is_true(ok)
    assert.is_false(res)
    assert.is_truthy(err:find("write failed", 1, true))
  end)
end)
