-- tests/path_spec.lua
--
-- Unit tests for scoper.path. These run inside a headless Neovim, so
-- vim.* APIs (vim.fs.normalize, vim.glob.to_lpeg, vim.uv.cwd, …) are
-- available.
--
-- Native-platform cases follow Path.is_windows. Separate forced-branch cases
-- also exercise Windows string rules on Unix, using the same flag consumed by
-- the implementation. This does not replace native Windows filesystem tests.

local Path = require("scoper.path")

describe("path.normalize", function()
  it("returns empty for nil or empty input", function()
    assert.equals("", Path.normalize(nil))
    assert.equals("", Path.normalize(""))
  end)

  it("strips trailing slash from non-root paths", function()
    assert.equals("/foo", Path.normalize("/foo/"))
    assert.equals("/foo/bar", Path.normalize("/foo/bar/"))
  end)

  it("preserves the Unix root", function()
    assert.equals("/", Path.normalize("/"))
  end)

  it("collapses redundant separators and . segments", function()
    assert.equals("/foo/bar", Path.normalize("/foo//./bar"))
  end)

  it("resolves .. segments", function()
    assert.equals("/foo", Path.normalize("/foo/bar/.."))
  end)

  if Path.is_windows then
    it("converts backslashes to forward slashes (windows)", function()
      assert.equals("c:/foo/bar", Path.normalize([[C:\foo\bar]]))
    end)

    it("lowercases the drive letter (windows)", function()
      assert.equals("c:/foo", Path.normalize("C:/foo"))
    end)

    it("strips the long-path prefix \\\\?\\ (windows)", function()
      assert.equals("c:/foo", Path.normalize([[\\?\C:\foo]]))
    end)

    it("preserves drive root (windows)", function()
      assert.equals("c:/", Path.normalize("C:/"))
    end)
  end
end)

-- Path.is_windows also selects vim.fs.normalize's Windows rules, so forcing
-- it covers the Windows paths on Linux/macOS runs too.
describe("path.normalize long-path prefix (forced windows branch)", function()
  local saved
  before_each(function()
    saved = Path.is_windows
    Path.is_windows = true
  end)
  after_each(function()
    Path.is_windows = saved
  end)

  it("removes a leading \\\\?\\", function()
    local out = Path.normalize([[\\?\C:/foo]])
    assert.is_nil(out:find("?", 1, true))
    assert.are.equal("c:/foo", out)
  end)

  it("leaves a UNC path alone", function()
    assert.is_nil(Path.normalize("//server/share/x"):find("?", 1, true))
    assert.are.equal("//server/share/x", Path.normalize("//server/share/x"))
  end)
end)

describe("path.is_absolute", function()
  it("recognises Unix absolute paths", function()
    -- On Windows "/foo" is relative to the current drive.
    assert.are.equal(not Path.is_windows, Path.is_absolute("/foo"))
    assert.are.equal(not Path.is_windows, Path.is_absolute("/"))
  end)

  it("rejects relative paths", function()
    assert.is_false(Path.is_absolute("foo"))
    assert.is_false(Path.is_absolute("./foo"))
    assert.is_false(Path.is_absolute("../foo"))
  end)

  it("rejects nil and empty", function()
    assert.is_false(Path.is_absolute(nil))
    assert.is_false(Path.is_absolute(""))
  end)

  if Path.is_windows then
    it("recognises windows drive-letter absolute paths", function()
      assert.is_true(Path.is_absolute("c:/foo"))
      assert.is_true(Path.is_absolute("C:/foo"))
    end)
  end
end)

describe("path.absolute", function()
  it("returns absolute paths unchanged (modulo normalization)", function()
    -- On Unix the input is already absolute; on Windows it would be
    -- considered relative — we test the platform-appropriate input.
    if Path.is_windows then
      assert.equals("c:/foo/bar", Path.absolute("C:/foo/bar"))
    else
      assert.equals("/foo/bar", Path.absolute("/foo/bar"))
    end
  end)

  it("joins relative against an explicit base", function()
    if Path.is_windows then
      assert.equals("c:/base/foo", Path.absolute("foo", "C:/base"))
    else
      assert.equals("/base/foo", Path.absolute("foo", "/base"))
    end
  end)

  it("returns empty for empty input", function()
    assert.equals("", Path.absolute(""))
  end)
end)

describe("path.is_under", function()
  it("considers a path to be under itself", function()
    assert.is_true(Path.is_under("/foo/bar", "/foo/bar"))
  end)

  it("recognises descendants", function()
    assert.is_true(Path.is_under("/foo/bar/baz.txt", "/foo/bar"))
  end)

  it("rejects siblings and ancestors", function()
    assert.is_false(Path.is_under("/foo", "/foo/bar"))
    assert.is_false(Path.is_under("/foo/baz", "/foo/bar"))
  end)

  it("respects the path-segment boundary (/foo is no parent of /foobar)", function()
    -- What the +"/" check in is_under guards against: without it, "/foo"
    -- looks like a prefix of "/foobar".
    assert.is_false(Path.is_under("/foobar", "/foo"))
    assert.is_false(Path.is_under("/foobar/inner", "/foo"))
  end)

  it("returns false when parent is empty", function()
    assert.is_false(Path.is_under("/foo", ""))
  end)

  it("recognises children of the filesystem root", function()
    -- A root parent keeps its trailing slash after normalize, so a naive
    -- `parent .. "/"` boundary would be "//" and match no real child. The
    -- "/" root case holds on every platform.
    assert.is_true(Path.is_under("/foo", "/"))
    assert.is_true(Path.is_under("/foo/bar", "/"))
  end)

  if Path.is_windows then
    it("compares case-insensitively on windows", function()
      assert.is_true(Path.is_under("C:/Foo/Bar", "c:/foo"))
    end)

    it("recognises children of a drive root (windows)", function()
      -- The same boundary as in the "/" case, for "c:/".
      assert.is_true(Path.is_under("c:/foo", "c:/"))
      assert.is_true(Path.is_under("C:/Foo/Bar", "c:/"))
    end)
  end
end)

describe("path.relative", function()
  it("returns relative form when path is under base", function()
    assert.equals("bar/baz", Path.relative("/foo/bar/baz", "/foo"))
  end)

  it("returns '.' when path equals base", function()
    assert.equals(".", Path.relative("/foo", "/foo"))
  end)

  it("returns the absolute (normalized) path when not under base", function()
    -- Unix: not under base
    if not Path.is_windows then
      assert.equals("/other/path", Path.relative("/other/path", "/foo"))
    end
  end)

  it("makes paths relative to the filesystem root", function()
    -- A root base already ends in its slash: skipping one more character
    -- for the separator would drop the first real one ("oo" for "/foo").
    -- The "/" root holds on every platform.
    assert.equals("foo", Path.relative("/foo", "/"))
    assert.equals("foo/bar", Path.relative("/foo/bar", "/"))
  end)

  if Path.is_windows then
    it("makes paths relative to a drive root (windows)", function()
      assert.equals("foo", Path.relative("c:/foo", "c:/"))
      assert.equals("foo/bar", Path.relative("C:/foo/bar", "c:/"))
    end)
  end
end)

describe("path.match_glob", function()
  it("matches a literal absolute path", function()
    assert.is_true(Path.match_glob("/foo/bar.lua", "/foo/bar.lua"))
  end)

  it("matches a '**' pattern across directories", function()
    assert.is_true(Path.match_glob("/proj/sub/node_modules/x/y.js", "**/node_modules/**"))
  end)

  it("does not match unrelated paths", function()
    assert.is_false(Path.match_glob("/proj/src/main.rs", "**/node_modules/**"))
  end)

  -- The cache stores `false` for a pattern that failed to compile; a
  -- truthiness check on the lookup would compile it again on every call.
  it("does not re-attempt compilation of an invalid pattern", function()
    local original = vim.glob.to_lpeg
    local calls = 0
    -- Intercept the lpeg compiler to count how many times an invalid
    -- pattern hits it. We restore the original after.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.glob.to_lpeg = function(p)
      calls = calls + 1
      return original(p) -- delegate; this will error for our bad pattern
    end

    local bad = "[" -- unterminated character class — lpeg compile fails
    for _ = 1, 5 do
      assert.is_false(Path.match_glob("/whatever.txt", bad))
    end

    vim.glob.to_lpeg = original

    assert.equals(1, calls, ("expected 1 compile attempt for bad pattern, got %d"):format(calls))
  end)
end)

describe("path identity on Windows (forced branch)", function()
  local saved
  before_each(function()
    saved = Path.is_windows
    Path.is_windows = true
  end)
  after_each(function()
    Path.is_windows = saved
  end)

  it("key() ignores case and trailing slashes", function()
    assert.are.equal(Path.key("C:/Proj/Src/"), Path.key("c:/proj/src"))
  end)

  it("match_glob is case-insensitive", function()
    assert.is_true(Path.match_glob("c:/proj/build/x.o", "**/Build/**", "c:/proj"))
  end)
end)

describe("path.match_exclude (rg / fd semantics)", function()
  it("slashless patterns match any component, at any depth", function()
    assert.is_true(Path.match_exclude("/p/src/build/a.c", "build", "/p"))
    assert.is_true(Path.match_exclude("/p/src/x/y.o", "*.o", "/p"))
    assert.is_false(Path.match_exclude("/p/src/builder/a.c", "build", "/p"))
    assert.is_false(Path.match_exclude("/p/src/x/y.oo", "*.o", "/p"))
  end)

  it("patterns with a slash match the relative path or an ancestor", function()
    assert.is_true(Path.match_exclude("/p/src/gen/deep/z.c", "src/gen", "/p"))
    assert.is_true(Path.match_exclude("/p/src/gen/z.c", "**/gen/**", "/p"))
    assert.is_false(Path.match_exclude("/p/lib/gen/z.c", "src/gen", "/p"))
  end)

  it("accepts a trailing slash", function()
    assert.is_true(Path.match_exclude("/p/src/tmp/q.c", "tmp/", "/p"))
  end)

  it("never looks at the folders above the search root", function()
    -- A project that itself lives under a "build" folder.
    local root = "/w/build/proj"
    assert.is_false(Path.match_exclude(root .. "/src/a.c", "**/build/**", root))
    assert.is_false(Path.match_exclude(root .. "/src/a.c", "build", root))
    assert.is_true(Path.match_exclude(root .. "/build/a.c", "**/build/**", root))
    assert.is_true(Path.match_exclude(root .. "/src/build/a.c", "build", root))
  end)

  it("anchors a leading slash at the search root", function()
    assert.is_true(Path.match_exclude("/p/build/a.c", "/build", "/p"))
    assert.is_false(Path.match_exclude("/p/src/build/a.c", "/build", "/p"))
  end)

  it("matches an absolute pattern against the absolute path", function()
    local root = Path.is_windows and "c:/p" or "/p"
    assert.is_true(Path.match_exclude(root .. "/vendor/x.c", root .. "/vendor/**", root))
    assert.is_true(Path.match_exclude(root .. "/vendor/x.c", root .. "/vendor", root))
    assert.is_false(Path.match_exclude(root .. "/src/x.c", root .. "/vendor", root))
  end)
end)

describe("path.valid_glob", function()
  it("accepts the pattern forms the matchers use", function()
    for _, pat in ipairs({ "build", "build/", "/build", "**/x/**", "*.{c,h}", "src/[ab]*" }) do
      assert.is_true(Path.valid_glob(pat), pat)
    end
  end)

  it("rejects what vim.glob can't parse, and bare slashes", function()
    for _, pat in ipairs({ "x[", "/", "//" }) do
      assert.is_false(Path.valid_glob(pat), pat)
    end
  end)
end)

describe("path on Windows: prefixes, root- and drive-relative paths (forced branch)", function()
  local saved, saved_drive_cwd
  before_each(function()
    saved, saved_drive_cwd = Path.is_windows, Path._drive_cwd
    Path.is_windows = true
  end)
  after_each(function()
    Path.is_windows, Path._drive_cwd = saved, saved_drive_cwd
  end)

  it("drops device prefixes", function()
    assert.are.equal("c:/x/y", Path.normalize([[\\?\C:\x\y]]))
    assert.are.equal("c:/x", Path.normalize([[\\.\C:\x]]))
    assert.are.equal("//srv/share/x", Path.normalize([[\\?\UNC\srv\share\x]]))
  end)

  it("lower-cases the drive letter only", function()
    assert.are.equal("c:/Proj/Src", Path.normalize([[C:\Proj\Src\]]))
  end)

  it("counts neither root- nor drive-relative paths as absolute", function()
    assert.is_false(Path.is_absolute("/src"))
    assert.is_false(Path.is_absolute("c:src"))
    assert.is_true(Path.is_absolute("c:/src"))
    assert.is_true(Path.is_absolute("//srv/share/src"))
  end)

  it("resolves a root-relative path on the base's drive or share", function()
    assert.are.equal("d:/src", Path.absolute([[\src]], "D:/proj"))
    assert.are.equal("//srv/share/src", Path.absolute("/src", "//srv/share/proj"))
    assert.is_true(Path.is_under("d:/src/a.c", Path.absolute([[\src]], "d:/proj")))
  end)

  it("resolves a drive-relative path on the base's drive against the base", function()
    assert.are.equal("d:/proj/foo", Path.absolute("D:foo", "d:/proj"))
    assert.are.equal("d:/proj", Path.absolute("d:", "d:/proj"))
  end)

  it("resolves a drive-relative path on another drive against that drive's directory", function()
    Path._drive_cwd = function(drive)
      return drive .. "/cur"
    end
    assert.are.equal("e:/cur/foo", Path.absolute("e:foo", "d:/proj"))
  end)

  it("compares case-insensitively but keeps the case in relative()", function()
    assert.is_true(Path.is_under("//SRV/Share/x", "//srv/share"))
    assert.are.equal("Src/a.c", Path.relative("C:/Proj/Src/a.c", "c:/proj"))
  end)

  it("matches excludes case-insensitively", function()
    assert.is_true(Path.match_exclude("c:/p/Build/a.c", "build", "C:/P"))
    assert.is_true(Path.match_exclude("c:/p/vendor/x.c", "C:/P/Vendor", "c:/p"))
  end)
end)
