-- tests/lsp_spec.lua
--
-- Unit tests for scoper.lsp: the compile_commands scope filter and its
-- cache, the clangd cmd, and the restart logic. Clients are fakes behind
-- stubbed vim.lsp.get_clients / get_client_by_id, so no clangd is needed.
--
-- The filter rule that is easiest to get wrong: a RELATIVE `file` in a
-- compile_commands entry is resolved against that entry's own `directory`
-- (per the JSON Compilation Database spec), NOT against nvim's cwd.

local lsp = require("scoper.lsp")
local State = require("scoper.state")
local Path = require("scoper.path")

-- A throwaway project with build/compile_commands.json (src/a.c, lib/b.c)
-- as the global cwd and loaded state, and stdpath("data") / ("cache") in
-- temp dirs. `sub` puts the project below a temp dir instead of at it.
local function setup_project(sub)
  local base = vim.fn.tempname()
  local p = {
    base = base,
    root = Path.normalize(sub and (base .. "/" .. sub) or base),
    prev = vim.fn.getcwd(),
    env = { vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME },
    data = vim.fn.tempname(),
    cache = vim.fn.tempname(),
  }
  vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = p.data, p.cache
  for _, d in ipairs({ "src", "lib", "build" }) do
    vim.fn.mkdir(p.root .. "/" .. d, "p")
  end
  p.cc = p.root .. "/build/compile_commands.json"
  function p.entry(file)
    return { directory = p.root .. "/build", file = p.root .. "/" .. file, command = "cc -c x.c" }
  end
  function p.write_cc(extra)
    local entries = vim.list_extend({ p.entry("src/a.c"), p.entry("lib/b.c") }, extra or {})
    vim.fn.writefile({ vim.json.encode(entries) }, p.cc)
  end
  p.write_cc()
  vim.fn.chdir(p.root)
  State.load()
  return p
end

local function teardown_project(p)
  vim.fn.chdir(p.prev)
  vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = p.env[1], p.env[2]
  for _, d in ipairs({ p.base, p.data, p.cache }) do
    vim.fn.delete(d, "rf")
  end
end

local function read_json(file)
  return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
end

local function flag(dir)
  return "--compile-commands-dir=" .. Path.normalize(dir)
end

describe("scoper.lsp._reattach", function()
  it("re-fires ONLY the vim.lsp.enable FileType handlers on C-family buffers", function()
    local lsp_hits, other_hits = 0, 0
    -- vim.lsp.enable() normally owns this group; recreate it for the test.
    local g = vim.api.nvim_create_augroup("nvim.lsp.enable", { clear = false })
    local other = vim.api.nvim_create_augroup("scoper_test_other", { clear = true })
    local id1 = vim.api.nvim_create_autocmd("FileType", {
      group = g,
      callback = function()
        lsp_hits = lsp_hits + 1
      end,
    })
    vim.api.nvim_create_autocmd("FileType", {
      group = other,
      callback = function()
        other_hits = other_hits + 1
      end,
    })

    local cpp = vim.api.nvim_create_buf(true, false)
    vim.bo[cpp].filetype = "cuda" -- also covers the cuda entry
    local txt = vim.api.nvim_create_buf(true, false)
    vim.bo[txt].filetype = "text"
    lsp_hits, other_hits = 0, 0

    lsp._reattach()

    assert.are.equal(1, lsp_hits)
    assert.are.equal(0, other_hits)

    vim.api.nvim_del_autocmd(id1)
    vim.api.nvim_del_augroup_by_id(other)
    vim.api.nvim_buf_delete(cpp, { force = true })
    vim.api.nvim_buf_delete(txt, { force = true })
  end)

  it("re-fires only the buffers it is given", function()
    local g = vim.api.nvim_create_augroup("nvim.lsp.enable", { clear = true })
    local hits = {}
    vim.api.nvim_create_autocmd("FileType", {
      group = g,
      callback = function(ev)
        table.insert(hits, ev.buf)
      end,
    })
    local a, b = vim.api.nvim_create_buf(true, false), vim.api.nvim_create_buf(true, false)
    vim.bo[a].filetype = "c"
    vim.bo[b].filetype = "c"
    hits = {}

    lsp._reattach({ b })

    assert.are.same({ b }, hits)
    vim.api.nvim_del_augroup_by_id(g)
    vim.api.nvim_buf_delete(a, { force = true })
    vim.api.nvim_buf_delete(b, { force = true })
  end)

  it("warns instead when clangd isn't started by vim.lsp.enable()", function()
    pcall(vim.api.nvim_del_augroup_by_name, "nvim.lsp.enable")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.bo[buf].filetype = "cpp"
    local orig, msg = vim.notify, nil
    vim.notify = function(m)
      msg = m
    end

    lsp._reattach({ buf })

    vim.notify = orig
    assert.is_truthy(msg and msg:find("vim.lsp.enable", 1, true))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("scoper.lsp._filter_entries", function()
  local orig_matcher

  before_each(function()
    orig_matcher = State.matcher
  end)

  after_each(function()
    State.matcher = orig_matcher
  end)

  -- Replaces the scope with `accept` (default: everything) and returns the
  -- list of paths it gets asked about.
  local function stub_scope(accept)
    local seen = {}
    State.matcher = function()
      return function(file)
        table.insert(seen, file)
        return accept == nil or accept(file)
      end
    end
    return seen
  end

  it("resolves a relative file against the entry's directory, not cwd", function()
    local seen = stub_scope()
    lsp._filter_entries({ { file = "main.cpp", directory = "/proj/src" } }, "/somewhere/else")
    assert.are.same({ "/proj/src/main.cpp" }, seen)
  end)

  it("passes an absolute file through unchanged", function()
    local seen = stub_scope()
    lsp._filter_entries({ { file = "/abs/x.cpp", directory = "/proj/src" } }, "/cwd")
    assert.are.same({ "/abs/x.cpp" }, seen)
  end)

  it("keeps only the entries the scope accepts", function()
    stub_scope(function(file)
      return file == "/keep.cpp"
    end)
    local kept = lsp._filter_entries({
      { file = "/keep.cpp", directory = "/d" },
      { file = "/drop.cpp", directory = "/d" },
    }, "/cwd")
    assert.are.equal(1, #kept)
    assert.are.equal("/keep.cpp", kept[1].file)
  end)

  it("skips entries that have no file field", function()
    stub_scope()
    local kept = lsp._filter_entries({
      { directory = "/d" },
      { file = "/x.cpp", directory = "/d" },
    }, "/cwd")
    assert.are.equal(1, #kept)
  end)

  it("prepares the scope once per pass, not once per entry", function()
    local calls = 0
    State.matcher = function()
      calls = calls + 1
      return function()
        return true
      end
    end
    lsp._filter_entries({ { file = "/a.c" }, { file = "/b.c" }, { file = "/c.c" } }, "/cwd")
    assert.equals(1, calls)
  end)
end)

describe("scoper.lsp filtered compile_commands", function()
  local p

  before_each(function()
    p = setup_project()
    State.set_enabled(true)
    State.add_paths("src")
  end)

  after_each(function()
    teardown_project(p)
  end)

  it("writes the entries in scope and points clangd at them", function()
    local dir, info, changed = lsp.write_filtered_compile_commands()
    assert.is_truthy(info:find("1/2 entries kept", 1, true))
    assert.is_true(changed)
    local out = read_json(dir .. "/compile_commands.json")
    assert.equals(1, #out)
    assert.equals(flag(dir), lsp.clangd_cmd()[2])
  end)

  it("reuses the previous result while nothing changed", function()
    lsp.write_filtered_compile_commands()
    local _, info, changed = lsp.write_filtered_compile_commands()
    assert.is_truthy(info:find("(cached)", 1, true))
    assert.is_false(changed)
  end)

  it("reports no change when a scope edit filters to the same entries", function()
    lsp.write_filtered_compile_commands()
    State.add_excludes("**/nothing/**")
    local _, info, changed = lsp.write_filtered_compile_commands()
    assert.is_nil(info:find("(cached)", 1, true))
    assert.is_false(changed)
  end)

  it("reports a change when the database changes what's in scope", function()
    lsp.write_filtered_compile_commands()
    p.write_cc({ p.entry("src/c.c") })
    local _, info, changed = lsp.write_filtered_compile_commands()
    assert.is_truthy(info:find("2/3 entries kept", 1, true))
    assert.is_true(changed)
  end)

  it("hands out the previous result on request while the database is newer", function()
    local dir = lsp.write_filtered_compile_commands()
    p.write_cc({ p.entry("src/c.c") })
    local dir2, info, changed, stale = lsp.write_filtered_compile_commands({ stale_ok = true })
    assert.equals(dir, dir2)
    assert.is_true(stale)
    assert.is_false(changed)
    assert.is_truthy(info:find("refresh pending", 1, true))
    assert.equals(1, #read_json(dir .. "/compile_commands.json"))
  end)

  it("doesn't let an exclude match the folders the project lives in", function()
    teardown_project(p)
    p = setup_project("build/proj")
    State.set_enabled(true)
    State.add_paths({ "src", "lib" })
    State.add_excludes("**/build/**")
    p.write_cc({ p.entry("build/gen.c") })
    local _, info = lsp.write_filtered_compile_commands()
    assert.is_truthy(info:find("2/3 entries kept", 1, true))
  end)

  -- Runs _filter_async to completion; returns its four values. `started`
  -- runs right after the call, before the result can have arrived.
  local function filter_async(started)
    local got
    lsp._filter_async(function(...)
      got = { n = select("#", ...), ... }
    end)
    if started then started(got) end
    vim.wait(10000, function()
      return got ~= nil
    end, 10)
    assert.is_table(got, "background filter never finished")
    return unpack(got, 1, got.n)
  end

  it("filters in a background process without blocking the caller", function()
    local dir, info, changed = filter_async(function(got)
      assert.is_nil(got)
    end)
    assert.is_truthy(info:find("1/2 entries kept", 1, true))
    assert.is_true(changed)
    assert.equals(1, #read_json(dir .. "/compile_commands.json"))
    assert.are.same({}, vim.fn.glob(dir .. "/.scoper-job-*", true, true))
    local _, info2, changed2 = lsp.write_filtered_compile_commands()
    assert.is_truthy(info2:find("(cached)", 1, true))
    assert.is_false(changed2)
  end)

  it("answers a cache hit right away", function()
    lsp.write_filtered_compile_commands()
    local info
    lsp._filter_async(function(_, i)
      info = i
    end)
    assert.is_truthy(info:find("(cached)", 1, true))
  end)

  it("filters in this Neovim when the background process can't start", function()
    local orig_cmd, orig_notify = lsp._worker_cmd, vim.notify
    lsp._worker_cmd = function()
      return { "scoper-no-such-program" }
    end
    vim.notify = function() end
    local ok, dir, info, changed = pcall(filter_async)
    lsp._worker_cmd, vim.notify = orig_cmd, orig_notify
    assert.is_true(ok, dir)
    assert.is_truthy(info:find("1/2 entries kept", 1, true))
    assert.is_true(changed)
    assert.equals(1, #read_json(dir .. "/compile_commands.json"))
  end)
end)

describe("scoper.cdb.invalid", function()
  local Cdb = require("scoper.cdb")

  it("accepts a compilation database and names what is wrong with anything else", function()
    assert.is_nil(Cdb.invalid({}))
    assert.is_nil(Cdb.invalid({ { file = "a.c", directory = "/d", command = "cc a.c" } }))
    assert.is_nil(Cdb.invalid({ { file = "a.c", directory = "/d", arguments = { "cc", "a.c" } } }))
    assert.is_truthy(Cdb.invalid({ oops = 1 }))
    assert.is_truthy(Cdb.invalid({ "wrong" }))
    assert.is_truthy(Cdb.invalid({ { file = "a.c", command = "cc" } }))
    assert.is_truthy(Cdb.invalid({ { file = "a.c", directory = "/d" } }))
    assert.is_truthy(Cdb.invalid({ { file = "a.c", directory = "/d", arguments = { "cc", 1 } } }))
  end)
end)

describe("scoper.lsp.clangd_cmd", function()
  local p, orig_extra

  before_each(function()
    p = setup_project()
    orig_extra = lsp._extra_args
  end)

  after_each(function()
    lsp._extra_args = orig_extra
    teardown_project(p)
  end)

  it("points clangd at the project's own database while scoping is off", function()
    local cmd, info = lsp.clangd_cmd()
    assert.equals(flag(p.root .. "/build"), cmd[2])
    assert.is_truthy(info:find("disabled", 1, true))
  end)

  it("leaves clangd to its own discovery without a database", function()
    vim.fn.delete(p.cc)
    local cmd, info = lsp.clangd_cmd()
    for _, arg in ipairs(cmd) do
      assert.is_nil(arg:find("--compile-commands-dir", 1, true))
    end
    assert.is_truthy(info:find("built-in discovery", 1, true))
  end)

  it("keeps extra args for later reloads until new ones are passed", function()
    lsp.clangd_cmd({ "--query-driver=/usr/bin/gcc" })
    assert.is_true(vim.tbl_contains(lsp.clangd_cmd(), "--query-driver=/usr/bin/gcc"))
    lsp.clangd_cmd({})
    assert.is_false(vim.tbl_contains(lsp.clangd_cmd(), "--query-driver=/usr/bin/gcc"))
  end)
end)

describe("scoper.lsp clangd config", function()
  local p, orig_executable, orig_start, started

  before_each(function()
    p = setup_project()
    orig_executable, orig_start = vim.fn.executable, vim.lsp.rpc.start
    vim.fn.executable = function()
      return 1
    end
    started = {}
    vim.lsp.rpc.start = function(cmd, _, opts)
      table.insert(started, { cmd = cmd, opts = opts })
      return {}
    end
  end)

  after_each(function()
    vim.fn.executable, vim.lsp.rpc.start = orig_executable, orig_start
    pcall(vim.api.nvim_del_augroup_by_name, "scoper_clangd_cmd")
    teardown_project(p)
  end)

  -- What the configured cmd starts for a client rooted at `root_dir`.
  local function spawn(root_dir)
    local cmd = vim.lsp.config.clangd.cmd
    assert.is_function(cmd)
    cmd({}, { root_dir = root_dir, cmd_cwd = root_dir })
    return started[#started]
  end

  it("gives this project's clangd the scoped cmd and other projects the plain one", function()
    local scoped = { "clangd", "--compile-commands-dir=/cache/x" }
    lsp._apply(scoped)
    local mine = spawn(p.root .. "/src")
    assert.are.same(scoped, mine.cmd)
    assert.equals(p.root .. "/src", mine.opts.cwd)
    assert.are.same(scoped, spawn(nil).cmd)
    local other = spawn(Path.is_windows and "z:/elsewhere" or "/elsewhere").cmd
    assert.equals("clangd", other[1])
    assert.is_false(vim.tbl_contains(other, "--compile-commands-dir=/cache/x"))
  end)

  it("uses the newest cmd for a clangd started later", function()
    lsp._apply({ "clangd", "--one" })
    local cmd = vim.lsp.config.clangd.cmd
    lsp._apply({ "clangd", "--two" })
    cmd({}, { root_dir = p.root })
    assert.are.same({ "clangd", "--two" }, started[#started].cmd)
  end)

  it("installs a plain list when clangd isn't installed", function()
    vim.fn.executable = function()
      return 0
    end
    lsp._apply({ "clangd", "--x" })
    assert.are.same({ "clangd", "--x" }, vim.lsp.config.clangd.cmd)
  end)

  it("installs the per-project cmd in the first C buffer after clangd turns up", function()
    local found = 0
    vim.fn.executable = function()
      return found
    end
    lsp._apply({ "clangd", "--x" })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "c"
    assert.are.same({ "clangd", "--x" }, vim.lsp.config.clangd.cmd)
    found = 1
    vim.bo[buf].filetype = "cpp"
    assert.are.same({ "clangd", "--x" }, spawn(p.root).cmd)
    assert.are.same({}, vim.api.nvim_get_autocmds({ group = "scoper_clangd_cmd" }))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("scoper.lsp restart", function()
  local p, saved, alive, clients, notes, reattached
  local next_id = 100

  local function fake_client(root, bufs)
    next_id = next_id + 1
    local c = { id = next_id, name = "clangd", root_dir = root, attached_buffers = bufs or {} }
    function c.is_stopped()
      return false
    end
    function c:stop(timeout)
      self.stopped_with = timeout
    end
    alive[c.id] = c
    table.insert(clients, c)
    return c
  end

  local function exit(c)
    alive[c.id] = nil
  end

  local function settle()
    vim.wait(1000, function()
      return not lsp._reloading
    end, 5)
  end

  before_each(function()
    p = setup_project()
    saved = {
      get_clients = vim.lsp.get_clients,
      get_client_by_id = vim.lsp.get_client_by_id,
      notify = vim.notify,
      reattach = lsp._reattach,
      timing = lsp._timing,
    }
    alive, clients, notes, reattached = {}, {}, {}, nil
    vim.lsp.get_clients = function(filter)
      return vim.tbl_filter(function(c)
        return alive[c.id] ~= nil
          and (filter == nil or filter.bufnr == nil or c.attached_buffers[filter.bufnr] ~= nil)
      end, clients)
    end
    vim.lsp.get_client_by_id = function(id)
      return alive[id]
    end
    vim.notify = function(msg, level)
      table.insert(notes, { msg = msg, level = level })
    end
    lsp._reattach = function(bufs)
      reattached = bufs
    end
    lsp._timing = { poll = 5, grace = 40, kill = 40 }
    lsp._reloading, lsp._pending, lsp._applied_cmd = false, false, nil
  end)

  after_each(function()
    vim.lsp.get_clients, vim.lsp.get_client_by_id = saved.get_clients, saved.get_client_by_id
    vim.notify, lsp._reattach, lsp._timing = saved.notify, saved.reattach, saved.timing
    teardown_project(p)
  end)

  it("restarts only this project's clangd, and re-attaches once it has exited", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, p.root .. "/src/a.c")
    vim.bo[buf].filetype = "c"
    local mine = fake_client(p.root, { [buf] = "c" })
    local theirs = fake_client(Path.is_windows and "z:/other" or "/other")

    lsp.reload_clangd()
    assert.equals(lsp._timing.grace, mine.stopped_with)
    assert.is_nil(theirs.stopped_with)
    exit(mine)
    settle()

    assert.are.same({ buf }, reattached)
    assert.is_truthy(notes[#notes].msg:find("restarted 1 clangd client", 1, true))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("neither waits for nor stops a clangd started during the restart", function()
    local mine = fake_client(p.root)
    lsp.reload_clangd()
    local fresh = fake_client(p.root)
    exit(mine)
    settle()
    assert.is_nil(fresh.stopped_with)
    assert.is_truthy(notes[#notes].msg:find("restarted 1 clangd client", 1, true))
  end)

  it("skips the re-attach while a stopped clangd is still alive", function()
    fake_client(p.root)
    lsp.reload_clangd()
    settle()
    assert.is_false(lsp._reloading)
    assert.is_nil(reattached)
    assert.equals(vim.log.levels.WARN, notes[#notes].level)
  end)

  it("ends the restart and clears the guard when a poll fails", function()
    fake_client(p.root)
    lsp.reload_clangd()
    vim.lsp.get_client_by_id = function()
      error("boom")
    end
    settle()
    assert.is_false(lsp._reloading)
    assert.equals(vim.log.levels.ERROR, notes[#notes].level)
  end)

  it("stays quiet on an automatic reload with no clangd running", function()
    lsp.reload_clangd({ auto = true })
    assert.is_false(lsp._reloading)
    assert.are.same({}, notes)
    assert.is_nil(reattached)
  end)

  it("reports a forced reload with no clangd running, and starts it", function()
    lsp.reload_clangd()
    assert.is_false(lsp._reloading)
    assert.equals(1, #notes)
    assert.is_table(reattached)
  end)

  it("skips an automatic restart that would change nothing", function()
    local first = fake_client(p.root)
    lsp.reload_clangd()
    exit(first)
    settle()
    local second = fake_client(p.root)
    lsp.reload_clangd({ auto = true })
    assert.is_nil(second.stopped_with)
    assert.is_false(lsp._reloading)
  end)

  it("restarts automatically when the filtered database changed", function()
    local first = fake_client(p.root)
    lsp.reload_clangd()
    exit(first)
    settle()
    State.set_enabled(true)
    State.add_paths("src")
    local second = fake_client(p.root)
    lsp.reload_clangd({ auto = true })
    -- The filter runs in the background, behind the reload guard.
    assert.is_nil(second.stopped_with)
    assert.is_true(lsp._reloading)
    vim.wait(10000, function()
      return second.stopped_with ~= nil
    end, 10)
    assert.equals(lsp._timing.grace, second.stopped_with)
    exit(second)
    settle()
  end)

  it("replays one reload requested mid-restart, forced if any request was", function()
    lsp._reloading = true
    lsp.reload_clangd({ auto = true })
    lsp.reload_clangd()
    lsp.reload_clangd({ auto = true })
    lsp._finish_reload()
    vim.wait(200, function()
      return #notes > 0
    end, 5)
    assert.equals(1, #notes) -- a forced reload reports, an automatic one wouldn't
  end)

  it("starts from the previous filter result and refreshes it after startup", function()
    State.set_enabled(true)
    State.add_paths("src")
    local dir = lsp.write_filtered_compile_commands()
    p.write_cc({ p.entry("src/c.c") })
    local orig_reload, requested = lsp.reload_clangd, nil
    lsp.reload_clangd = function(opts)
      requested = opts
    end
    lsp.apply_initial()
    assert.equals(flag(dir), lsp._cmd[2])
    vim.wait(200, function()
      return requested ~= nil
    end, 5)
    lsp.reload_clangd = orig_reload
    assert.are.same({ auto = true }, requested)
  end)

  it("starts on the unfiltered database when there is no filter result yet", function()
    State.set_enabled(true)
    State.add_paths("src")
    local orig_reload, requested = lsp.reload_clangd, nil
    lsp.reload_clangd = function(opts)
      requested = opts
    end
    lsp.apply_initial()
    assert.equals(flag(p.root .. "/build"), lsp._cmd[2])
    vim.wait(200, function()
      return requested ~= nil
    end, 5)
    lsp.reload_clangd = orig_reload
    assert.are.same({ auto = true }, requested)
  end)
end)
