-- tests/commands_spec.lua
--
-- The user commands and their completion. The test runner starts Neovim
-- with --noplugin, so plugin/scoper.lua is sourced here.

local State = require("scoper.state")

local COMMANDS = {
  "ScoperAdd",
  "ScoperRemove",
  "ScoperExclude",
  "ScoperRemoveExclude",
  "ScoperClear",
  "ScoperShow",
  "ScoperNew",
  "ScoperUse",
  "ScoperDelete",
  "ScoperScopes",
  "ScoperToggle",
  "ScoperStatus",
  "ScoperFind",
  "ScoperGrep",
  "ScoperReplace",
  "ScoperTogglePicker",
  "ScoperLspReload",
}

describe("scoper commands", function()
  local root, data, prev, env, notes, orig_notify

  before_each(function()
    root, data, prev, env =
      vim.fn.tempname(), vim.fn.tempname(), vim.fn.getcwd(), vim.env.XDG_DATA_HOME
    vim.env.XDG_DATA_HOME = data
    vim.fn.mkdir(root .. "/src", "p")
    vim.fn.mkdir(root .. "/my dir", "p")
    vim.fn.chdir(root)
    vim.g.loaded_scoper = nil
    vim.cmd.runtime("plugin/scoper.lua")
    State.load()
    notes = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notes, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.fn.chdir(prev)
    vim.env.XDG_DATA_HOME = env
    vim.fn.delete(root, "rf")
    vim.fn.delete(data, "rf")
  end)

  it("registers every command", function()
    for _, name in ipairs(COMMANDS) do
      assert.equals(2, vim.fn.exists(":" .. name), name)
    end
  end)

  it(":ScoperAdd takes several directories, with escaped spaces", function()
    vim.cmd([[ScoperAdd src my\ dir]])
    assert.are.same({ "src", "my dir" }, State.active_scope().include)
  end)

  it(":ScoperAdd warns about a directory that doesn't exist, and keeps it", function()
    vim.cmd("ScoperAdd nope")
    assert.equals(vim.log.levels.WARN, notes[#notes].level)
    assert.are.same({ "nope" }, State.active_scope().include)
  end)

  it(":ScoperExclude takes the whole argument as one glob and refuses invalid ones", function()
    vim.cmd("ScoperExclude **/my gen/**")
    assert.are.same({ "**/my gen/**" }, State.active_scope().exclude)
    vim.cmd("ScoperExclude x[")
    assert.equals(vim.log.levels.WARN, notes[#notes].level)
    assert.are.same({ "**/my gen/**" }, State.active_scope().exclude)
  end)

  it(":ScoperToggle switches scoping and :ScoperStatus reports it", function()
    vim.cmd("ScoperToggle")
    assert.is_true(State.is_enabled())
    vim.cmd("ScoperStatus")
    assert.is_truthy(notes[#notes].msg:find("ON", 1, true))
  end)

  it(":ScoperNew, :ScoperUse and :ScoperDelete manage scopes", function()
    vim.cmd("ScoperNew alpha")
    vim.cmd("ScoperNew beta")
    vim.cmd("ScoperUse alpha")
    assert.equals("alpha", State.active_name())
    vim.cmd("ScoperDelete alpha beta")
    assert.are.same({ "default" }, State.scope_names())
  end)

  it("completes scope names by what has been typed", function()
    vim.cmd("ScoperNew alpha")
    vim.cmd("ScoperNew beta")
    assert.are.same({ "alpha" }, vim.fn.getcompletion("ScoperUse al", "cmdline"))
    assert.are.same({ "beta" }, vim.fn.getcompletion("ScoperDelete alpha b", "cmdline"))
  end)

  it("completes :ScoperRemove from the scope, escaped like directory completion", function()
    vim.cmd([[ScoperAdd src my\ dir]])
    assert.are.same({ [[my\ dir]] }, vim.fn.getcompletion("ScoperRemove my", "cmdline"))
    assert.are.same({ [[my\ dir]] }, vim.fn.getcompletion([[ScoperRemove my\ d]], "cmdline"))
    vim.cmd([[ScoperRemove my\ dir]])
    assert.are.same({ "src" }, State.active_scope().include)
  end)

  it("completes :ScoperRemoveExclude by what has been typed", function()
    vim.cmd("ScoperExclude **/gen/**")
    vim.cmd("ScoperExclude build")
    assert.are.same({ "build" }, vim.fn.getcompletion("ScoperRemoveExclude b", "cmdline"))
  end)
end)
