local Path = require("scoper.path")
local Util = require("scoper.util")

describe("Scoper cooperating state writers", function()
  local State, data, old_data, path, notify, stat, atomic, notes, processes

  local function instance()
    package.loaded["scoper.state"] = nil
    local state = require("scoper.state")
    state.load({ quiet = true })
    return state
  end

  before_each(function()
    data, old_data = vim.fn.tempname(), vim.env.XDG_DATA_HOME
    vim.fn.mkdir(data, "p")
    vim.env.XDG_DATA_HOME = data
    State = instance()
    path = vim.fn.stdpath("data") .. "/scoper/" .. Util.cwd_hash(Path.key(State.root())) .. ".json"
    notify, stat, atomic = vim.notify, vim.uv.fs_stat, Util.atomic_write
    notes, processes = {}, {}
    vim.notify = function(message)
      notes[#notes + 1] = message
    end
  end)

  after_each(function()
    for _, process in ipairs(processes) do
      pcall(process.kill, process, 15)
    end
    vim.notify, vim.uv.fs_stat, Util.atomic_write = notify, stat, atomic
    vim.env.XDG_DATA_HOME = old_data
    package.loaded["scoper.state"] = nil
    vim.fn.delete(data, "rf")
  end)

  local function persisted()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end

  it("allows a first save only when the unread store is absent", function()
    package.loaded["scoper.state"] = nil
    local first = require("scoper.state")
    assert.is_true(first.save())
    first.add_paths("existing")
    package.loaded["scoper.state"] = nil
    local unread = require("scoper.state")
    assert.is_false(unread.save())
    assert.same({ "existing" }, persisted().scopes.default.include)
  end)

  it("refuses a stale save and retains local edits until an explicit reload", function()
    local other = instance()
    State.state.scopes.default.include = { "first" }
    other.state.scopes.default.include = { "second" }
    assert.is_true(State.save())
    assert.is_false(other.save())
    assert.same({ "first" }, persisted().scopes.default.include)
    other.add_excludes("**/local/**")
    assert.same({ "second" }, other.active_scope().include)
    assert.same({ "**/local/**" }, other.active_scope().exclude)
    assert.same({}, persisted().scopes.default.exclude)
    assert.matches("reload", notes[#notes])
    other.load({ quiet = true })
    other.add_excludes("**/later/**")
    assert.same({ "first" }, persisted().scopes.default.include)
    assert.same({ "**/later/**" }, persisted().scopes.default.exclude)
  end)

  it("refreshes same-size external edits even when timestamps are unchanged", function()
    State.add_paths("ours")
    local old = stat(path)
    local changed = persisted()
    changed.scopes.default.include = { "them" }
    vim.fn.writefile({ vim.json.encode(changed) }, path)
    vim.uv.fs_stat = function(file, ...)
      local result, err, code = stat(file, ...)
      if file == path and result then result.mtime = vim.deepcopy(old.mtime) end
      return result, err, code
    end
    State.add_excludes("**/build/**")
    assert.same({ "them" }, persisted().scopes.default.include)
    assert.same({ "**/build/**" }, persisted().scopes.default.exclude)
  end)

  it("honors an external reset instead of resurrecting deleted scopes", function()
    State.add_paths("obsolete")
    vim.fn.delete(path)
    State.add_excludes("**/build/**")
    assert.same({}, persisted().scopes.default.include)
    assert.same({ "**/build/**" }, persisted().scopes.default.exclude)
  end)

  local function child(mode, ready, start, entry)
    local process = vim.system({
      vim.v.progpath,
      "--headless",
      "--noplugin",
      "-u",
      "NONE",
      "-l",
      "tests/fixtures/state_writer.lua",
      mode,
      ready or "",
      start or "",
      entry or "",
    }, { text = true, env = { XDG_DATA_HOME = data } })
    processes[#processes + 1] = process
    return process
  end

  it("does not silently lose edits when two native editors save simultaneously", function()
    local ready_a, ready_b, start = data .. "/a.ready", data .. "/b.ready", data .. "/start"
    local first, second =
      child("write", ready_a, start, "first"), child("write", ready_b, start, "second")
    assert.is_true(
      vim.wait(15000, function()
        return stat(ready_a) ~= nil and stat(ready_b) ~= nil
      end, 10),
      "editors did not reach the save barrier"
    )
    vim.fn.writefile({ "start" }, start)
    local a, b = first:wait(15000), second:wait(15000)
    assert.equals(0, a.code, a.stderr)
    assert.equals(0, b.code, b.stderr)
    a, b = vim.json.decode(a.stdout), vim.json.decode(b.stdout)
    assert.is_not.equal(a.saved, b.saved)
    assert.same({ "first" }, a.include)
    assert.same({ "second" }, b.include)
    assert.same(a.saved and a.include or b.include, persisted().scopes.default.include)
  end)

  it("recovers a lock after its owning native editor exits during the write", function()
    local result = child("crash"):wait(15000)
    assert.equals(42, result.code, result.stderr)
    assert.is_not_nil(stat(path .. ".lock"))
    State.add_paths("recovered")
    assert.same({ "recovered" }, persisted().scopes.default.include)
    assert.is_nil(stat(path .. ".lock"))
  end)

  it("releases the lock after a thrown write error", function()
    Util.atomic_write = function()
      error("simulated write failure")
    end
    State.add_paths("unsaved")
    assert.is_nil(stat(path .. ".lock"))
    Util.atomic_write = atomic
    assert.is_true(State.save())
    assert.same({ "unsaved" }, persisted().scopes.default.include)
  end)
end)
