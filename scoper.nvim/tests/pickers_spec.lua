-- tests/pickers_spec.lua
--
-- Unit tests for scoper.pickers. The pure helpers (the plain-vim :find
-- 'path', shell and grug-far quoting, the telescope pattern translation)
-- are tested directly; the fzf-lua and telescope calls against stub
-- modules that record the options they get.
--
-- M._find_path must append the recursive "/**" glob to EVERY scope dir:
-- `table.concat(dirs, ",") .. "/**"` attaches it to the last one only, and
-- `:find` treats the others as non-recursive.

local pickers = require("scoper.pickers")
local State = require("scoper.state")
local Path = require("scoper.path")

describe("scoper.pickers._find_path", function()
  it("appends /** to EVERY dir, not just the last", function()
    assert.are.equal("/a/**,/b/**,/c/**", pickers._find_path({ "/a", "/b", "/c" }))
  end)

  it("handles a single dir", function()
    assert.are.equal("/only/**", pickers._find_path({ "/only" }))
  end)

  it("backslash-escapes spaces for 'path'", function()
    assert.are.equal([[/a\ b/dir/**]], pickers._find_path({ "/a b/dir" }))
  end)

  it("returns an empty string when there are no dirs", function()
    assert.are.equal("", pickers._find_path({}))
  end)
end)

describe("scoper.pickers._rg_exclude", function()
  it("shell-quotes the whole flag so globs reach ripgrep intact", function()
    -- cmd.exe on Windows (with 'shellslash' off), a POSIX shell elsewhere.
    local expected = vim.fn.has("win32") == 1 and [["--glob=!**/node_modules/**"]]
      or [['--glob=!**/node_modules/**']]
    assert.are.equal(expected, pickers._rg_exclude("**/node_modules/**"))
  end)

  it("quotes with the escaper it is given", function()
    local function escape(s)
      return "<" .. s .. ">"
    end
    assert.are.equal("<--glob=!build>", pickers._rg_exclude("build", escape))
  end)

  it("keeps a glob with a space as ONE shell word", function()
    local flag = pickers._rg_exclude("my dir/**")
    -- Round-trip through the shell's own word splitting: one argument out.
    -- cmd.exe has no such round trip; there the space must sit inside
    -- one pair of double quotes.
    if vim.fn.has("win32") == 0 then
      local out = vim.fn.systemlist("printf '%s\\n' " .. flag)
      assert.are.same({ "--glob=!my dir/**" }, out)
    else
      assert.are.equal([["--glob=!my dir/**"]], flag)
    end
  end)
end)

describe("scoper.pickers path escaping", function()
  it("_find_path escapes commas and spaces so :find sees one dir each", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/a,b/sub", "p")
    vim.fn.mkdir(root .. "/c d", "p")
    vim.fn.writefile({ "x" }, root .. "/a,b/sub/t1.txt")
    vim.fn.writefile({ "x" }, root .. "/c d/t2.txt")
    local saved = vim.o.path
    vim.o.path = pickers._find_path({ root .. "/a,b", root .. "/c d" })
    local f1, f2 = vim.fn.findfile("t1.txt"), vim.fn.findfile("t2.txt")
    vim.o.path = saved
    vim.fn.delete(root, "rf")
    assert.is_truthy(f1:find("t1.txt", 1, true))
    assert.is_truthy(f2:find("t2.txt", 1, true))
  end)

  it("_grug_path escapes spaces the way grug-far's splitter expects", function()
    assert.are.equal("/p/my\\ dir", pickers._grug_path("/p/my dir"))
    assert.are.equal([[C:\src\app]], pickers._grug_path([[C:\src\app]])) -- separators untouched
  end)

  it("_grug_prefills passes the dirs and the excludes, case-insensitive on Windows", function()
    local pre =
      pickers._grug_prefills({ dirs = { "/p/my dir", "/p/b" }, excludes = { "**/gen/**" } }, "/p")
    assert.are.equal("/p/my\\ dir /p/b", pre.paths)
    local case = Path.is_windows and "--glob-case-insensitive " or ""
    assert.are.equal(case .. "--glob=!**/gen/**", pre.flags)
  end)

  it("_grug_prefills writes ? for whitespace in a dir: grug-far splits its flags there", function()
    local saved = Path.is_windows
    Path.is_windows = false
    local pre = pickers._grug_prefills({ dirs = { "/w/my lib" }, excludes = { "old" } }, "/p")
    Path.is_windows = saved
    assert.are.equal("--glob=!/old --glob=!?*/**/old --glob=!//w/my?lib/**/old", pre.flags)
  end)

  it("_grug_prefills refuses an exclude with whitespace instead of changing its meaning", function()
    local pre, err =
      pickers._grug_prefills({ dirs = { "/p/src" }, excludes = { "old stuff" } }, "/p")
    assert.is_nil(pre)
    assert.is_truthy(err:find('"old stuff"', 1, true), err)
  end)

  it("_vimgrep_pattern escapes only the unescaped delimiters", function()
    assert.are.equal([[abc\/def]], pickers._vimgrep_pattern("abc/def"))
    assert.are.equal([[abc\/def]], pickers._vimgrep_pattern([[abc\/def]]))
    assert.are.equal([[a\\\/b]], pickers._vimgrep_pattern([[a\\/b]]))
    assert.are.equal([[x|y "q"]], pickers._vimgrep_pattern([[x|y "q"]]))
  end)
end)

describe("scoper.pickers._rg_globs", function()
  local saved

  before_each(function()
    saved = Path.is_windows
  end)

  after_each(function()
    Path.is_windows = saved
  end)

  it("passes the excludes as written while every dir is inside the cwd", function()
    Path.is_windows = false
    local globs = { "**/gen/**", "build", "/out", "src/tmp" }
    assert.are.same(globs, pickers._rg_globs(globs, { "/p/src", "/p/lib" }, "/p"))
  end)

  it("anchors excludes below a dir outside the cwd, and the cwd's off its parents", function()
    Path.is_windows = false
    assert.are.same({
      "/build/**",
      "?*/**/build/**",
      "//w/build/ext/**/build/**",
      "src/gen",
      "//w/build/ext/src/gen",
    }, pickers._rg_globs({ "**/build/**", "src/gen" }, { "/p/src", "/w/build/ext" }, "/p"))
    assert.are.same(
      { "/x", "?*/**/x", "//w/o[[]1][{]a[}]/**/x" },
      pickers._rg_globs({ "x" }, { "/w/o[1]{a}" }, "/p")
    )
  end)

  it("keeps the cwd's forms off a drive on Windows", function()
    Path.is_windows = true
    assert.are.same(
      { "/*.o", "?/**/*.o", "?*[!:]/**/*.o", "d:/x/**/*.o" },
      pickers._rg_globs({ "*.o" }, { "d:/x" }, "c:/p")
    )
  end)

  it("makes an absolute exclude relative to the cwd or the outside dir it is in", function()
    Path.is_windows = true
    local excludes = { "C:/P/Vendor/**", "D:/Ext/gen", "e:/elsewhere/**", "c:/p" }
    assert.are.same(
      { "/Vendor/**", "d:/ext/gen", "/**" },
      pickers._rg_globs(excludes, { "c:/p/src", "d:/ext" }, "c:/p")
    )
  end)

  it("on Unix, anchors an absolute exclude in neither at each root", function()
    Path.is_windows = false
    assert.are.same(
      { "/vendor/**", "//w/ext/vendor/**", "/third/**" },
      pickers._rg_globs({ "/vendor/**", "/p/third/**" }, { "/p/src", "/w/ext" }, "/p")
    )
  end)
end)

describe("scoper.pickers telescope ignore patterns", function()
  local function ignored(glob, path, root)
    for _, pat in ipairs(pickers._glob_to_lua_pats(glob, root)) do
      if path:find(pat) then return true end
    end
    return false
  end

  it("matches slashless globs as whole components at any depth", function()
    assert.is_true(ignored("build", "src/build/a.c"))
    assert.is_true(ignored("build", "build/a.c"))
    assert.is_false(ignored("build", "src/builder/a.c"))
    assert.is_true(ignored("*.o", "x/y.o"))
    assert.is_false(ignored("*.o", "x/y.oo"))
  end)

  it("matches a leading **/ at any depth, but anchors other globs with a slash", function()
    assert.is_true(ignored("**/gen/**", "src/gen/z.c"))
    assert.is_false(ignored("**/gen/**", "src/my_gen/z.c"))
    assert.is_true(ignored("src/gen", "src/gen/z.c"))
    assert.is_true(ignored("src/gen", "./src/gen/z.c"))
    assert.is_false(ignored("src/gen", "lib/src/gen/z.c"))
    assert.is_false(ignored("src/gen", "mysrc/gen/z.c"))
    assert.is_true(ignored("/build", "build/a.c"))
    assert.is_false(ignored("/build", "src/build/a.c"))
  end)

  it("matches Windows separators too", function()
    assert.is_true(ignored("build", [[p\src\build\a.c]]))
    assert.is_true(ignored("**/gen/**", [[p\src\gen\z.c]]))
  end)

  it("translates character classes", function()
    assert.is_true(ignored("*.[ch]", "p/a.h"))
    assert.is_false(ignored("*.[ch]", "p/a.o"))
  end)

  it("ignores letter case on Windows only", function()
    local saved = Path.is_windows
    Path.is_windows = true
    local folded = ignored("build", "p/Build/a.c") and ignored("*.[ch]", "p/A.H")
    Path.is_windows = false
    local exact = ignored("build", "p/Build/a.c")
    Path.is_windows = saved
    assert.is_true(folded)
    assert.is_false(exact)
  end)

  it("matches below a search dir outside the cwd, never above it", function()
    local ext = "/w/build/ext"
    assert.is_true(ignored("**/build/**", ext .. "/sub/build/a.c", ext))
    assert.is_true(ignored("build", [[/w/build/ext\build\a.c]], ext))
    assert.is_false(ignored("**/build/**", ext .. "/a.c", ext))
    assert.is_true(ignored("/vendor/**", ext .. "/vendor/v.c", ext))
    assert.is_false(ignored("/vendor/**", ext .. "/sub/vendor/v.c", ext))
    assert.is_false(ignored("**/build/**", ext .. "/a.c"))
  end)

  it("keeps cwd patterns off a full path with a drive", function()
    local saved = Path.is_windows
    Path.is_windows = true
    local above = ignored("build", [[C:\w\build\ext\a.c]])
    local below = ignored("build", [[C:\W\Ext\Build\a.c]], "c:/w/ext")
    Path.is_windows = saved
    assert.is_false(above)
    assert.is_true(below)
  end)
end)

-- A project (src/, src/gen/, and lib/ missing on purpose) as the global
-- cwd, in `sub` of a temp dir, with the state in another one.
local function setup_project(sub)
  local p = { base = vim.fn.tempname(), data = vim.fn.tempname(), prev = vim.fn.getcwd() }
  p.root = p.base .. (sub or "")
  p.env = vim.env.XDG_DATA_HOME
  vim.env.XDG_DATA_HOME = p.data
  vim.fn.mkdir(p.root .. "/src/gen", "p")
  vim.fn.chdir(p.root)
  State.load()
  State.add_paths("src")
  State.add_excludes("**/gen/**")
  return p
end

local function teardown_project(p)
  vim.fn.chdir(p.prev)
  vim.env.XDG_DATA_HOME = p.env
  vim.fn.delete(p.base, "rf")
  vim.fn.delete(p.data, "rf")
end

describe("scoper.pickers scope context", function()
  local p

  before_each(function()
    p = setup_project()
  end)

  after_each(function()
    teardown_project(p)
  end)

  it("treats scoping off as everything in scope", function()
    local ctx = pickers._context()
    assert.equals("all", ctx.name)
    assert.is_nil(ctx.dirs)
    assert.are.same({}, ctx.excludes)
  end)

  it("treats an empty include list as everything in scope", function()
    State.set_enabled(true)
    State.clear_active()
    assert.is_nil(pickers._context().dirs)
  end)

  it("uses the include dirs and excludes while scoping is on", function()
    State.set_enabled(true)
    local ctx = pickers._context()
    assert.are.same({ Path.normalize(p.root .. "/src") }, ctx.dirs)
    assert.are.same({ "**/gen/**" }, ctx.excludes)
  end)

  it("refuses to search a scope whose includes don't exist", function()
    State.set_enabled(true)
    State.clear_active()
    State.add_paths("lib")
    local orig, level = vim.notify, nil
    vim.notify = function(_, l)
      level = l
    end
    local ctx = pickers._context()
    vim.notify = orig
    assert.is_nil(ctx)
    assert.equals(vim.log.levels.WARN, level)
  end)
end)

describe("scoper.pickers with fzf-lua", function()
  local p, saved, got

  local function escape(s)
    return "<" .. s .. ">"
  end
  local case = Path.is_windows and " --glob-case-insensitive" or ""

  before_each(function()
    p = setup_project()
    saved = {
      fzf = package.loaded["fzf-lua"],
      libuv = package.loaded["fzf-lua.libuv"],
      executable = vim.fn.executable,
    }
    got = {}
    package.loaded["fzf-lua"] = {
      files = function(opts)
        got.files = opts
      end,
      live_grep = function(opts)
        got.grep = opts
      end,
    }
    package.loaded["fzf-lua.libuv"] = { shellescape = escape }
    vim.fn.executable = function(name)
      return name == "rg" and 1 or 0
    end
  end)

  after_each(function()
    package.loaded["fzf-lua"], package.loaded["fzf-lua.libuv"] = saved.fzf, saved.libuv
    vim.fn.executable = saved.executable
    teardown_project(p)
  end)

  it("finds in the whole project while scoping is off", function()
    pickers.find()
    assert.are.equal(
      "rg --files --color=never --hidden --follow" .. case .. " <--glob=!.git>",
      got.files.cmd
    )
    assert.are.equal("Find [all]> ", got.files.prompt)
  end)

  it("finds in the scope's dirs with its excludes while scoping is on", function()
    State.set_enabled(true)
    pickers.find()
    assert.are.equal(
      "rg --files --color=never --hidden --follow"
        .. case
        .. " <--glob=!.git> <--glob=!**/gen/**> <src>",
      got.files.cmd
    )
  end)

  it("hands fd the excludes and the dirs when there is no ripgrep", function()
    vim.fn.executable = function()
      return 0
    end
    State.set_enabled(true)
    pickers.find()
    assert.is_nil(got.files.cmd)
    assert.are.equal(
      "--color=never --type f --type l --hidden --follow --exclude <.git> --exclude <**/gen/**>",
      got.files.fd_opts
    )
    assert.are.same({ Path.normalize(p.root .. "/src") }, got.files.search_paths)
  end)

  it("doesn't follow directory links with vim.g.scoper_follow_links = false", function()
    vim.g.scoper_follow_links = false
    pickers.find()
    vim.g.scoper_follow_links = nil
    assert.is_nil(got.files.cmd:find("--follow", 1, true), got.files.cmd)
  end)

  it("greps with -e last, so a query starting with '-' stays a pattern", function()
    State.set_enabled(true)
    pickers.grep("-Wall")
    assert.are.equal("-Wall", got.grep.query)
    assert.is_true(vim.endswith(got.grep.rg_opts, case .. " <--glob=!**/gen/**> -e"))
    assert.are.same({ Path.normalize(p.root .. "/src") }, got.grep.search_paths)
  end)

  it("greps the whole project while scoping is off", function()
    pickers.grep()
    assert.is_nil(got.grep.search_paths)
    assert.is_nil(got.grep.rg_opts:find("gen", 1, true))
  end)

  it("hands ripgrep an absolute exclude relative to the project", function()
    State.add_excludes(Path.normalize(p.root) .. "/src/gen")
    State.set_enabled(true)
    pickers.grep()
    assert.is_true(vim.endswith(got.grep.rg_opts, " <--glob=!**/gen/**> <--glob=!/src/gen> -e"))
  end)
end)

describe("scoper.pickers with telescope", function()
  local p, saved, got

  before_each(function()
    p = setup_project()
    saved = {
      builtin = package.loaded["telescope.builtin"],
      action_state = package.loaded["telescope.actions.state"],
      picker = vim.g.scoper_picker,
    }
    got = {}
    package.loaded["telescope.builtin"] = {
      find_files = function(opts)
        got.find = opts
      end,
      live_grep = function(opts)
        got.grep = opts
      end,
    }
    package.loaded["telescope.actions.state"] = {}
    vim.g.scoper_picker = "telescope"
  end)

  after_each(function()
    package.loaded["telescope.builtin"] = saved.builtin
    package.loaded["telescope.actions.state"] = saved.action_state
    vim.g.scoper_picker = saved.picker
    teardown_project(p)
  end)

  local function ignored(patterns, path)
    for _, pat in ipairs(patterns) do
      if path:find(pat) then return true end
    end
    return false
  end

  it("hides .git and the excludes when finding", function()
    State.set_enabled(true)
    pickers.find()
    assert.is_true(ignored(got.find.file_ignore_patterns, "src/.git/config"))
    assert.is_true(ignored(got.find.file_ignore_patterns, "src/gen/x.c"))
    assert.is_false(ignored(got.find.file_ignore_patterns, "src/x.c"))
    assert.are.same({ "src" }, got.find.search_dirs)
  end)

  it("follows directory links like fzf-lua, unless vim.g.scoper_follow_links is false", function()
    pickers.find()
    assert.is_true(got.find.follow)
    vim.g.scoper_follow_links = false
    pickers.find()
    vim.g.scoper_follow_links = nil
    assert.is_false(got.find.follow)
  end)

  it("lists the project's dirs relative to it, so excludes never see the folders above", function()
    teardown_project(p)
    p = setup_project("/build/proj")
    State.add_excludes("**/build/**")
    State.set_enabled(true)
    pickers.grep()
    assert.are.same({ "src" }, got.grep.search_dirs)
    assert.is_false(ignored(got.grep.file_ignore_patterns, [[src\x.c]]))
    assert.is_true(ignored(got.grep.file_ignore_patterns, [[src\build\x.c]]))
  end)

  it("matches the excludes below an include outside the project, not above it", function()
    local base = vim.fn.tempname()
    local ext = Path.normalize(base .. "/build/ext")
    vim.fn.mkdir(ext, "p")
    State.add_paths(ext)
    State.add_excludes("**/build/**")
    State.set_enabled(true)
    pickers.grep()
    vim.fn.delete(base, "rf")
    local pats = got.grep.file_ignore_patterns
    assert.is_false(ignored(pats, ext .. "/a.c"))
    assert.is_true(ignored(pats, ext .. "/sub/build/a.c"))
    assert.is_true(ignored(pats, [[src\build\x.c]]))
  end)

  it("searches the whole project while scoping is off", function()
    pickers.grep()
    assert.is_nil(got.grep.search_dirs)
    assert.are.same({}, got.grep.file_ignore_patterns)
  end)

  it("registers the show-path key through telescope's map, keeping the defaults", function()
    pickers.find()
    local maps = {}
    local keep = got.find.attach_mappings(0, function(modes, key)
      table.insert(maps, { modes = modes, key = key })
    end)
    assert.is_true(keep)
    assert.are.same({ { modes = { "i", "n" }, key = "<M-p>" } }, maps)
  end)
end)

describe("scoper.pickers plain-vim grep", function()
  local p

  before_each(function()
    p = setup_project()
    vim.fn.writefile({ "needle" }, p.root .. "/src/a.c")
    vim.fn.writefile({ "needle" }, p.root .. "/src/gen/b.c")
  end)

  after_each(function()
    vim.cmd("cclose")
    vim.fn.setqflist({}, "r")
    teardown_project(p)
  end)

  local function hits()
    return vim.tbl_map(function(item)
      return vim.fs.basename(vim.api.nvim_buf_get_name(item.bufnr))
    end, vim.fn.getqflist())
  end

  it("drops matches in excluded files from the quickfix list", function()
    State.set_enabled(true)
    pickers.grep("needle")
    assert.are.same({ "a.c" }, hits())
  end)

  it("takes slashes, escaped slashes, bars and quotes as part of the pattern", function()
    vim.fn.writefile({ 'abc/def x|y "q"' }, p.root .. "/src/s.c")
    State.set_enabled(true)
    for _, pat in ipairs({ "abc/def", [[abc\/def]], "x|y", '"q"' }) do
      vim.fn.setqflist({}, "r")
      pickers.grep(pat)
      assert.are.same({ "s.c" }, hits(), pat)
    end
  end)
end)

describe("scoper.pickers plain-vim find", function()
  local p

  before_each(function()
    p = setup_project()
    vim.fn.mkdir(p.root .. "/src/gen", "p")
    vim.fn.writefile({ "x" }, p.root .. "/src/gen/dup.h")
    vim.fn.writefile({ "x" }, p.root .. "/src/gen/only.h")
  end)

  after_each(function()
    teardown_project(p)
  end)

  it("skips files the scope's excludes hide", function()
    vim.fn.mkdir(p.root .. "/src/inc", "p")
    vim.fn.writefile({ "x" }, p.root .. "/src/inc/dup.h")
    State.set_enabled(true)
    local file, found = pickers._find_in_scope(pickers._context(), "dup.h")
    assert.are.equal(2, found)
    assert.are.equal(Path.normalize(p.root .. "/src/inc/dup.h"), Path.normalize(file))
    assert.is_nil((pickers._find_in_scope(pickers._context(), "only.h")))
  end)

  it("leaves 'path' alone while the prompt is open and after it", function()
    State.set_enabled(true)
    local saved_input, pending = vim.ui.input, nil
    vim.ui.input = function(_, cb)
      pending = cb
    end
    local before = vim.o.path
    pickers.find()
    assert.are.equal(before, vim.o.path)
    vim.ui.input = saved_input
    pending(nil)
    assert.are.equal(before, vim.o.path)
  end)
end)

describe("scoper.pickers replace", function()
  it("refuses an exclude with whitespace rather than open a wider replace", function()
    local p = setup_project()
    State.add_excludes("old stuff")
    State.set_enabled(true)
    local saved, opened, msg = package.loaded["grug-far"], false, nil
    package.loaded["grug-far"] = {
      open = function()
        opened = true
      end,
    }
    local notify = vim.notify
    vim.notify = function(m)
      msg = m
    end
    pickers.replace()
    vim.notify, package.loaded["grug-far"] = notify, saved
    teardown_project(p)
    assert.is_false(opened)
    assert.is_truthy(msg and msg:find("old stuff", 1, true), msg)
  end)
end)
