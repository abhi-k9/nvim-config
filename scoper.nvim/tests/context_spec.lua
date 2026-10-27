local Scoper = require("scoper")
local State = require("scoper.state")
local UI = require("scoper.ui")
local plugin_root = vim.fn.getcwd()

describe("delayed Scoper selection context", function()
  local root, data, previous, old_data, original_notify, notes, pending, saved_ui, extra_autocmd

  before_each(function()
    root, data, previous, old_data =
      vim.fn.tempname(), vim.fn.tempname(), vim.fn.getcwd(), vim.env.XDG_DATA_HOME
    vim.fn.mkdir(root .. "/a/src", "p")
    vim.fn.mkdir(root .. "/b/src", "p")
    vim.env.XDG_DATA_HOME = data
    vim.cmd.cd(root .. "/a")
    Scoper.setup({ lsp = { clangd = false } })
    State.add_paths("src")
    notes, pending, saved_ui = {}, nil, {}
    extra_autocmd = nil
    original_notify = vim.notify
    vim.notify = function(message)
      notes[#notes + 1] = message
    end
    for _, name in ipairs({ "pick_many", "pick_one", "pick_dirs", "input" }) do
      saved_ui[name] = UI[name]
      UI[name] = function(...)
        local args = { ... }
        pending = args[#args]
      end
    end
  end)

  after_each(function()
    if extra_autocmd then vim.api.nvim_del_autocmd(extra_autocmd) end
    vim.notify = original_notify
    for name, fn in pairs(saved_ui) do
      UI[name] = fn
    end
    pcall(vim.api.nvim_del_augroup_by_name, "scoper_dir")
    vim.cmd.cd(previous)
    vim.env.XDG_DATA_HOME = old_data
    vim.fn.delete(root, "rf")
    vim.fn.delete(data, "rf")
  end)

  local function other_scope()
    State.new_scope("other")
    State.add_paths("src")
    State.add_excludes("build")
  end

  local function cancelled()
    assert.matches("operation cancelled", notes[#notes])
  end

  it("does not remove another project's matching path after a directory change", function()
    Scoper.remove()
    vim.cmd.cd(root .. "/b")
    State.add_paths("src")
    pending({ "src" })
    assert.same({ "src" }, State.active_scope().include)
    cancelled()
  end)

  it("does not remove the same path from another active scope", function()
    Scoper.remove()
    other_scope()
    pending({ "src" })
    assert.same({ "src" }, State.active_scope().include)
    cancelled()
  end)

  it("does not apply a stale selection after editing the same named scope", function()
    Scoper.remove()
    State.add_paths("lib")
    pending({ "src" })
    assert.same({ "src", "lib" }, State.active_scope().include)
    cancelled()
  end)

  it("cancels scope-sensitive selections after changing the selected build", function()
    Scoper.remove()
    State.set_database("build/compile_commands.json")
    pending({ "src" })
    assert.same({ "src" }, State.active_scope().include)
    cancelled()
  end)

  it("does not apply directories selected for another scope", function()
    Scoper.add()
    other_scope()
    pending({ "lib" })
    assert.same({ "src" }, State.active_scope().include)
    cancelled()
  end)

  it("does not apply an exclude input to another scope", function()
    Scoper.exclude()
    other_scope()
    pending("generated")
    assert.same({ "build" }, State.active_scope().exclude)
    cancelled()
  end)

  it("does not remove excludes selected for another scope", function()
    State.add_excludes("build")
    Scoper.remove_exclude()
    other_scope()
    pending({ "build" })
    assert.same({ "build" }, State.active_scope().exclude)
    cancelled()
  end)

  it("does not delete a same-named scope in a different project", function()
    State.new_scope("other")
    Scoper.delete()
    vim.cmd.cd(root .. "/b")
    State.new_scope("other")
    pending({ "other" })
    assert.is_not_nil(State.scope("other"))
    cancelled()
  end)

  it("does not create a scope in a project that did not request it", function()
    Scoper.new()
    vim.cmd.cd(root .. "/b")
    pending("new-name")
    assert.is_nil(State.scope("new-name"))
    cancelled()
  end)

  it("does not switch a different project to a stale selected name", function()
    State.new_scope("other")
    Scoper.use()
    vim.cmd.cd(root .. "/b")
    State.new_scope("other")
    State.set_active("default")
    pending("other")
    assert.equals("default", State.active_name())
    cancelled()
  end)

  it("still applies a selection when its target remains current", function()
    Scoper.remove()
    pending({ "src" })
    assert.same({}, State.active_scope().include)
    assert.matches("removed 1", notes[#notes])
  end)

  it("refreshes another instance's saved scope before applying a selection", function()
    other_scope()
    State.set_active("default")
    Scoper.remove()
    local other = dofile(plugin_root .. "/lua/scoper/state.lua")
    other.load({ quiet = true })
    other.set_active("other")
    pending({ "src" })
    assert.equals("other", State.active_name())
    assert.same({ "src" }, State.active_scope().include)
    cancelled()
  end)

  local function external_switch()
    local file = vim.fn.globpath(data, "**/*.json", false, true)[1]
    local document = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
    document.active = "other"
    local st = assert(vim.uv.fs_stat(file))
    vim.fn.writefile({ vim.json.encode(document) }, file)
    assert(vim.uv.fs_utime(file, st.atime.sec, st.mtime.sec + 5))
  end

  local function observe_changes()
    local events = {}
    extra_autocmd = vim.api.nvim_create_autocmd("User", {
      pattern = "ScoperChanged",
      callback = function()
        events[#events + 1] = State.active_name()
      end,
    })
    return events
  end

  it("announces an external scope refresh even when the stale picker is canceled", function()
    other_scope()
    State.set_active("default")
    Scoper.remove()
    local events = observe_changes()
    external_switch()
    pending({ "src" })
    assert.same({ "other" }, events)
    assert.same({ "src" }, State.active_scope().include)
    cancelled()
    State.context()
    assert.equals(1, #events)
  end)

  it("still emits only one event when a mutator refreshes external state", function()
    other_scope()
    State.set_active("default")
    local events = observe_changes()
    external_switch()
    State.add_paths("lib")
    assert.same({ "other" }, events)
    assert.same({ "src", "lib" }, State.active_scope().include)
  end)
end)
