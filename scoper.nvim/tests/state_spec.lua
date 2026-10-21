-- tests/state_spec.lua
--
-- Unit tests for scoper.state.
--
-- state.lua writes its JSON store under stdpath("data"). We override
-- $XDG_DATA_HOME to a temp dir per-spec so tests neither read from nor
-- write to the developer's real Scoper state. We also reset the
-- in-memory state between tests via M.state = fresh — without that,
-- test order would matter.

local Path = require("scoper.path")

local function tmpdir()
  return vim.fn.tempname()
end

-- Reset in-memory state to a clean default. We can't just call
-- `package.loaded["scoper.state"] = nil` and re-require because that
-- triggers `vim.uv.cwd()` reads we don't always want; cheaper to assign.
local function reset_state(State)
  State.state = {
    active = "default",
    enabled = false,
    scopes = { default = { include = {}, exclude = {} } },
  }
end

describe("scoper.state", function()
  local State, data_root

  before_each(function()
    data_root = tmpdir()
    vim.fn.mkdir(data_root, "p")
    -- Make stdpath("data") resolve into our temp dir for this test only.
    vim.env.XDG_DATA_HOME = data_root
    -- Force a fresh require so stdpath() cache (if any) doesn't carry
    -- across tests; on most Neovim versions stdpath() isn't cached but
    -- this is cheap insurance.
    package.loaded["scoper.state"] = nil
    State = require("scoper.state")
    reset_state(State)
  end)

  after_each(function()
    vim.fn.delete(data_root, "rf")
  end)

  ---------------------------------------------------------------------------
  describe("add_paths / remove_paths", function()
    it("adds a path to the active scope's include list", function()
      assert.equals(1, State.add_paths("src"))
      assert.are.same({ "src" }, State.active_scope().include)
    end)

    it("accepts a string or a list", function()
      assert.equals(2, State.add_paths({ "src", "lib" }))
      assert.are.same({ "src", "lib" }, State.active_scope().include)
    end)

    it("silently skips duplicates", function()
      State.add_paths("src")
      assert.equals(0, State.add_paths("src"))
      assert.equals(1, #State.active_scope().include)
    end)

    it("removes a previously-added path", function()
      State.add_paths({ "src", "lib" })
      assert.equals(1, State.remove_paths("src"))
      assert.are.same({ "lib" }, State.active_scope().include)
    end)

    it("returns 0 when removing something not in the list", function()
      State.add_paths("src")
      assert.equals(0, State.remove_paths("notthere"))
    end)

    it("reports added paths that aren't existing directories", function()
      local root = tmpdir()
      vim.fn.mkdir(root .. "/real", "p")
      local n, missing = State.add_paths({ root .. "/real", root .. "/typo", "src/**/*.c" })
      assert.equals(3, n)
      assert.are.same({ Path.normalize(root .. "/typo") }, missing)
      vim.fn.delete(root, "rf")
    end)

    it("expands environment variables in added and removed paths", function()
      local root = tmpdir()
      vim.env.SCOPER_SPEC_DIR = root
      State.add_paths("$SCOPER_SPEC_DIR/src")
      assert.are.same({ Path.normalize(root .. "/src") }, State.active_scope().include)
      assert.equals(1, State.remove_paths("$SCOPER_SPEC_DIR/src"))
      vim.env.SCOPER_SPEC_DIR = nil
    end)
  end)

  ---------------------------------------------------------------------------
  describe("add_excludes / remove_excludes", function()
    it("adds glob patterns to the exclude list", function()
      assert.equals(2, State.add_excludes({ "**/node_modules/**", "**/.git/**" }))
      assert.are.same({ "**/node_modules/**", "**/.git/**" }, State.active_scope().exclude)
    end)

    it("skips empty strings", function()
      assert.equals(0, State.add_excludes({ "" }))
    end)

    it("removes an exclude pattern", function()
      State.add_excludes({ "a", "b" })
      assert.equals(1, State.remove_excludes("a"))
      assert.are.same({ "b" }, State.active_scope().exclude)
    end)

    it("rejects globs vim.glob can't parse", function()
      local n, invalid = State.add_excludes({ "gen/**", "x[" })
      assert.equals(1, n)
      assert.are.same({ "x[" }, invalid)
      assert.are.same({ "gen/**" }, State.active_scope().exclude)
    end)
  end)

  ---------------------------------------------------------------------------
  describe("default_excludes", function()
    after_each(function()
      State.default_excludes = {}
    end)

    it("seed the default scope of a project without a state file", function()
      State.default_excludes = { "**/node_modules/**" }
      State.load()
      assert.are.same({ "**/node_modules/**" }, State.active_scope().exclude)
    end)

    it("seed new scopes", function()
      State.default_excludes = { "**/node_modules/**" }
      State.new_scope("other")
      assert.are.same({ "**/node_modules/**" }, State.active_scope().exclude)
    end)

    it("leave saved scopes alone", function()
      State.save()
      State.default_excludes = { "**/node_modules/**" }
      State.load()
      assert.are.same({}, State.active_scope().exclude)
    end)
  end)

  ---------------------------------------------------------------------------
  describe("scope management", function()
    it("creates a new scope and switches to it", function()
      assert.is_true(State.new_scope("frontend"))
      assert.equals("frontend", State.active_name())
    end)

    it("refuses to create a scope with a taken name", function()
      State.new_scope("frontend")
      local ok, err = State.new_scope("frontend")
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("rejects names that are unsafe as directory components", function()
      -- Scope names end up as a path segment in the clangd cache dir
      -- (stdpath("cache")/scoper/<hash>/<name>/), so anything with
      -- separators, traversal, or Windows-reserved characters must be
      -- refused at creation. See state.valid_scope_name.
      for _, bad in ipairs({
        "foo/bar",
        [[foo\bar]],
        "..",
        ".",
        "a:b",
        "a*b",
        "a?b",
        "has space",
        "",
      }) do
        local ok, err = State.new_scope(bad)
        assert.is_false(ok, ("expected %q to be rejected"):format(bad))
        assert.is_string(err)
      end
      -- And the active scope never switched to a rejected name.
      assert.equals("default", State.active_name())
    end)

    it("accepts names with word chars, dot, dash, underscore", function()
      for _, good in ipairs({ "frontend", "v1.2", "api-tests", "my_scope" }) do
        assert.is_true(State.new_scope(good), ("expected %q to be accepted"):format(good))
      end
    end)

    it("lists scope names sorted", function()
      State.new_scope("alpha")
      State.new_scope("beta")
      local names = State.scope_names()
      -- 'default' is created in setup; alpha + beta added above.
      assert.are.same({ "alpha", "beta", "default" }, names)
    end)

    it("deletes a scope and reselects another when active is deleted", function()
      State.new_scope("frontend")
      assert.equals("frontend", State.active_name())
      assert.is_true(State.delete_scope("frontend"))
      assert.is_not.equals("frontend", State.active_name())
    end)

    it("falls back to 'default', else the first name, when the active scope goes", function()
      State.new_scope("zeta")
      State.new_scope("alpha")
      State.delete_scope("alpha")
      assert.equals("default", State.active_name())
      State.delete_scope("default")
      State.new_scope("beta")
      State.new_scope("gamma")
      State.delete_scope("gamma")
      assert.equals("beta", State.active_name())
    end)

    it("refuses to delete the last scope", function()
      -- Only "default" exists at setup.
      local ok, err = State.delete_scope("default")
      assert.is_false(ok)
      assert.is_string(err)
    end)
  end)

  ---------------------------------------------------------------------------
  describe("is_in_scope", function()
    it("returns true for everything when scoping is disabled", function()
      State.set_enabled(false)
      assert.is_true(State.is_in_scope("/anywhere/at/all.cpp"))
    end)

    it("returns true for everything when the include list is empty", function()
      State.set_enabled(true)
      assert.is_true(State.is_in_scope("/anywhere/at/all.cpp"))
    end)

    it("includes paths under an include directory", function()
      State.set_enabled(true)
      -- Use an absolute path so cwd doesn't matter for this assertion.
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/src", "p")
      State.add_paths(root .. "/src")
      assert.is_true(State.is_in_scope(root .. "/src/main.cpp"))
      assert.is_false(State.is_in_scope(root .. "/other/main.cpp"))
      vim.fn.delete(root, "rf")
    end)

    it("respects excludes even when path is in an include dir", function()
      State.set_enabled(true)
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/src/node_modules", "p")
      State.add_paths(root .. "/src")
      State.add_excludes("**/node_modules/**")
      assert.is_false(State.is_in_scope(root .. "/src/node_modules/x.js"))
      assert.is_true(State.is_in_scope(root .. "/src/main.cpp"))
      vim.fn.delete(root, "rf")
    end)

    it("ignores the folders above the project when matching excludes", function()
      local proj = tmpdir() .. "/build/proj"
      vim.fn.mkdir(proj .. "/src", "p")
      local prev = vim.fn.getcwd()
      vim.fn.chdir(proj)
      State.load()
      State.set_enabled(true)
      State.add_paths("src")
      State.add_excludes("**/build/**")
      local m = State.matcher()
      vim.fn.chdir(prev)
      assert.is_true(m(proj .. "/src/a.c"))
      assert.is_false(m(proj .. "/src/build/a.c"))
    end)

    it("matches excludes of an include outside the project relative to that include", function()
      State.set_enabled(true)
      local ext = tmpdir() .. "/build/ext"
      vim.fn.mkdir(ext, "p")
      State.add_paths(ext)
      State.add_excludes("**/build/**")
      assert.is_true(State.is_in_scope(ext .. "/a.c"))
      assert.is_false(State.is_in_scope(ext .. "/build/a.c"))
    end)

    it("matches glob includes", function()
      State.set_enabled(true)
      State.add_paths("**/*.proto")
      assert.is_true(State.is_in_scope(vim.fn.getcwd() .. "/a/b/x.proto"))
      assert.is_false(State.is_in_scope(vim.fn.getcwd() .. "/a/b/x.c"))
    end)
  end)

  ---------------------------------------------------------------------------
  describe("save / load roundtrip", function()
    it("persists state to disk and reads it back", function()
      State.new_scope("frontend")
      State.add_paths({ "src", "lib" })
      State.add_excludes("**/dist/**")
      State.set_enabled(true)
      State.save()

      -- Drop in-memory state, then load — must recover exactly what we wrote.
      reset_state(State)
      State.load()

      assert.equals("frontend", State.active_name())
      assert.is_true(State.is_enabled())
      assert.are.same({ "src", "lib" }, State.active_scope().include)
      assert.are.same({ "**/dist/**" }, State.active_scope().exclude)
    end)

    it("loads cleanly when the store file is absent", function()
      -- Don't write anything; XDG_DATA_HOME is fresh per test.
      State.load()
      assert.equals("default", State.active_name())
      assert.is_false(State.is_enabled())
    end)

    it("survives JSON nulls and wrong types from a hand-edited file", function()
      -- Write a valid file first so we learn the real store path, then
      -- overwrite it with a hostile-but-parseable document.
      State.save()
      local path
      for _, f in ipairs(vim.fn.globpath(data_root, "**/*.json", false, true)) do
        path = f
      end
      assert.is_not_nil(path)
      vim.fn.writefile({
        vim.json.encode({
          active = vim.NIL,
          enabled = "yes",
          scopes = { a = { include = vim.NIL, exclude = { "x" } }, bad = "not a table" },
        }),
      }, path)

      reset_state(State)
      assert.has_no.errors(function()
        State.load()
      end)
      assert.equals("a", State.active_name())
      assert.are.same({}, State.active_scope().include)
      assert.are.same({ "x" }, State.active_scope().exclude)
      assert.is_nil(State.scope("bad")) -- non-table entry dropped
      assert.is_false(State.is_enabled())
      -- and the loaded state is actually usable
      assert.has_no.errors(function()
        State.is_in_scope("/tmp/whatever")
      end)
    end)

    it("keeps a corrupt state file as a backup before starting over", function()
      State.save()
      local path = vim.fn.globpath(data_root, "**/*.json", false, true)[1]
      vim.fn.writefile({ "{ not json" }, path)
      State.load()
      assert.equals("default", State.active_name())
      local backups = vim.fn.glob(path .. ".corrupt-*", false, true)
      assert.equals(1, #backups)
      assert.are.same({ "{ not json" }, vim.fn.readfile(backups[1]))
      -- a second corrupt version in the same second gets its own backup
      vim.fn.writefile({ "{ also not json" }, path)
      State.load()
      assert.equals(2, #vim.fn.glob(path .. ".corrupt-*", false, true))
    end)

    it("drops scope names and list items a hand-edited file shouldn't hold", function()
      State.save()
      local path = vim.fn.globpath(data_root, "**/*.json", false, true)[1]
      vim.fn.writefile({
        vim.json.encode({
          active = "..",
          scopes = {
            [".."] = { include = { "x" }, exclude = {} },
            ok = { include = { "src", 1, vim.NIL, {} }, exclude = { true, "*.o" } },
          },
        }),
      }, path)
      State.load()
      assert.is_nil(State.scope(".."))
      assert.equals("ok", State.active_name())
      assert.are.same({ "src" }, State.active_scope().include)
      assert.are.same({ "*.o" }, State.active_scope().exclude)
    end)

    it("reports a failed save without throwing and keeps the change in memory", function()
      local Util = require("scoper.util")
      local orig, orig_notify = Util.atomic_write, vim.notify
      local level
      Util.atomic_write = function()
        return false, "write failed: disk full"
      end
      vim.notify = function(_, l)
        level = l
      end
      local ok, n = pcall(State.add_paths, "src")
      Util.atomic_write, vim.notify = orig, orig_notify
      assert.is_true(ok)
      assert.equals(1, n)
      assert.equals(vim.log.levels.ERROR, level)
      assert.are.same({ "src" }, State.active_scope().include)
    end)
  end)

  ---------------------------------------------------------------------------
  describe("project root", function()
    local a, b, prev

    before_each(function()
      a, b, prev = tmpdir(), tmpdir(), vim.fn.getcwd()
      vim.fn.mkdir(a, "p")
      vim.fn.mkdir(b, "p")
      vim.fn.chdir(a)
      State.load()
    end)

    after_each(function()
      vim.cmd("silent! lcd " .. vim.fn.fnameescape(prev))
      vim.cmd("cd " .. vim.fn.fnameescape(prev))
      vim.fn.delete(a, "rf")
      vim.fn.delete(b, "rf")
    end)

    it("stays the loaded project under a window-local directory", function()
      vim.cmd("lcd " .. vim.fn.fnameescape(b))
      State.set_enabled(true)
      State.add_paths("src")
      assert.equals(Path.key(a), Path.key(State.root()))
      assert.is_true(State.is_in_scope(a .. "/src/x.c"))
      assert.is_false(State.is_in_scope(b .. "/src/x.c"))
    end)

    it("follow_cwd reloads only when the global cwd names another project", function()
      State.add_paths("src")
      local fired = 0
      local id = vim.api.nvim_create_autocmd("User", {
        pattern = "ScoperChanged",
        callback = function()
          fired = fired + 1
        end,
      })
      State.follow_cwd()
      assert.equals(0, fired)
      vim.fn.chdir(b)
      State.follow_cwd()
      assert.equals(1, fired)
      assert.are.same({}, State.active_scope().include)
      vim.fn.chdir(a)
      State.follow_cwd()
      assert.are.same({ "src" }, State.active_scope().include)
      vim.api.nvim_del_autocmd(id)
    end)
  end)
end)

describe("scoper.state on Windows (forced case-insensitive paths)", function()
  local State, data_root, saved
  before_each(function()
    data_root = tmpdir()
    vim.fn.mkdir(data_root, "p")
    vim.env.XDG_DATA_HOME = data_root
    package.loaded["scoper.state"] = nil
    State = require("scoper.state")
    saved = Path.is_windows
    Path.is_windows = true
    reset_state(State)
  end)
  after_each(function()
    Path.is_windows = saved
    vim.fn.delete(data_root, "rf")
  end)

  it("treats paths differing only in case as the same include", function()
    assert.equals(1, State.add_paths("Src"))
    assert.equals(0, State.add_paths("src"))
    assert.equals(1, State.remove_paths("SRC"))
    assert.are.same({}, State.active_scope().include)
  end)

  it("still reads a state file saved under the old case-sensitive hash", function()
    -- Run from a directory with upper-case letters so the legacy hash
    -- (case kept) and the new one (lower-cased) actually differ.
    local proj = tmpdir() .. "/MixedCase"
    vim.fn.mkdir(proj, "p")
    local prev = vim.fn.getcwd()
    vim.fn.chdir(proj)
    local Util = require("scoper.util")
    local legacy = Util.cwd_hash(Path.normalize(vim.uv.cwd()))
    assert.are_not.equal(legacy, Util.cwd_hash(Path.key(vim.uv.cwd())))
    local dir = vim.fn.stdpath("data") .. "/scoper"
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({
      vim.json.encode({
        active = "old",
        enabled = true,
        scopes = { old = { include = { "legacy" }, exclude = {} } },
      }),
    }, dir .. "/" .. legacy .. ".json")
    State.load()
    vim.fn.chdir(prev)
    assert.equals("old", State.active_name())
    assert.are.same({ "legacy" }, State.active_scope().include)
  end)
end)

describe("scoper.state with two instances on one project", function()
  local State, data_root
  before_each(function()
    data_root = tmpdir()
    vim.fn.mkdir(data_root, "p")
    vim.env.XDG_DATA_HOME = data_root
    package.loaded["scoper.state"] = nil
    State = require("scoper.state")
    State.load()
  end)
  after_each(function()
    vim.fn.delete(data_root, "rf")
  end)

  it("does not drop a change another instance saved meanwhile", function()
    State.add_paths("mine")
    -- Another Neovim instance adds a path and saves (simulated by editing
    -- the shared file, with a newer mtime).
    local file = vim.fn.glob(data_root .. "/**/scoper/*.json", false, true)[1]
    local other = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
    table.insert(other.scopes[other.active].include, "theirs")
    vim.wait(20) -- make sure the mtime differs
    vim.fn.writefile({ vim.json.encode(other) }, file)
    vim.uv.fs_utime(file, os.time() + 5, os.time() + 5)

    State.add_excludes("**/x/**") -- our next change

    local saved = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
    assert.are.same({ "mine", "theirs" }, saved.scopes[saved.active].include)
    assert.are.same({ "**/x/**" }, saved.scopes[saved.active].exclude)
  end)
end)
