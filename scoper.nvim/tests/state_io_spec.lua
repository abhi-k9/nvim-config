local Path = require("scoper.path")
local Util = require("scoper.util")

describe("Scoper state I/O recovery", function()
  local State, data, old_data, path, original, notes, changed, autocmd

  before_each(function()
    data, old_data = vim.fn.tempname(), vim.env.XDG_DATA_HOME
    vim.env.XDG_DATA_HOME = data
    package.loaded["scoper.state"] = nil
    State = require("scoper.state")
    State.load({ quiet = true })
    path = vim.fn.stdpath("data") .. "/scoper/" .. Util.cwd_hash(Path.key(State.root())) .. ".json"
    original = {
      mkdir = vim.fn.mkdir,
      readfile = vim.fn.readfile,
      copyfile = vim.uv.fs_copyfile,
      stat = vim.uv.fs_stat,
      notify = vim.notify,
    }
    notes, changed = {}, 0
    vim.notify = function(message)
      notes[#notes + 1] = message
    end
    autocmd = vim.api.nvim_create_autocmd("User", {
      pattern = "ScoperChanged",
      callback = function()
        changed = changed + 1
      end,
    })
  end)

  after_each(function()
    vim.fn.mkdir, vim.fn.readfile = original.mkdir, original.readfile
    vim.uv.fs_copyfile, vim.uv.fs_stat = original.copyfile, original.stat
    vim.notify = original.notify
    vim.api.nvim_del_autocmd(autocmd)
    vim.env.XDG_DATA_HOME = old_data
    vim.fn.delete(data, "rf")
  end)

  it(
    "keeps session changes and emits an event when the state directory is blocked by a file",
    function()
      vim.fn.mkdir(vim.fn.stdpath("data"), "p")
      vim.fn.writefile({ "occupied" }, vim.fn.stdpath("data") .. "/scoper")
      assert.has_no.errors(function()
        State.add_paths("src")
      end)
      assert.same({ "src" }, State.active_scope().include)
      assert.equals(1, changed)
      assert.matches("failed to save", notes[#notes])
    end
  )

  it("recovers from a mkdir exception without losing the unsaved session change", function()
    vim.fn.mkdir = function()
      error("permission denied")
    end
    assert.has_no.errors(function()
      State.add_paths("src")
    end)
    assert.is_false(State.save())
    vim.fn.mkdir = original.mkdir
    assert.is_true(State.save())
    State.load({ quiet = true })
    assert.same({ "src" }, State.active_scope().include)
  end)

  it("does not overwrite a state file after a read exception", function()
    State.add_paths("precious")
    local before = vim.fn.readfile(path)
    vim.fn.readfile = function(file, ...)
      if file == path then error("permission denied") end
      return original.readfile(file, ...)
    end
    assert.has_no.errors(function()
      State.load({ quiet = true })
    end)
    State.add_paths("temporary")
    assert.is_false(State.save())
    vim.fn.readfile = original.readfile
    assert.same(before, vim.fn.readfile(path))
    State.load({ quiet = true })
    assert.same({ "precious" }, State.active_scope().include)
    State.add_paths("later")
    assert.is_true(State.save())
  end)

  it("survives a file disappearing between stat and read and resumes after reload", function()
    State.save()
    vim.fn.readfile = function(file, ...)
      if file == path then
        vim.fn.delete(path)
        error("file disappeared")
      end
      return original.readfile(file, ...)
    end
    assert.has_no.errors(function()
      State.load({ quiet = true })
    end)
    State.add_paths("temporary")
    assert.is_nil(vim.uv.fs_stat(path))
    vim.fn.readfile = original.readfile
    State.load({ quiet = true })
    State.add_paths("saved")
    assert.equals(1, vim.fn.filereadable(path))
  end)

  it("preserves corrupt data when its backup cannot be created", function()
    State.save()
    vim.fn.writefile({ "{ precious broken JSON" }, path)
    vim.uv.fs_copyfile = function()
      return nil, "permission denied", "EACCES"
    end
    State.load({ quiet = true })
    State.add_paths("temporary")
    assert.is_false(State.save())
    assert.same({ "{ precious broken JSON" }, vim.fn.readfile(path))
    vim.uv.fs_copyfile = original.copyfile
    State.load({ quiet = true })
    assert.equals(1, #vim.fn.glob(path .. ".corrupt-*", false, true))
    assert.is_true(State.save())
  end)

  it("does not treat an inaccessible state path as an absent file", function()
    State.add_paths("precious")
    local before = vim.fn.readfile(path)
    vim.uv.fs_stat = function(file, ...)
      if file == path then return nil, "permission denied", "EACCES" end
      return original.stat(file, ...)
    end
    assert.has_no.errors(function()
      State.load({ quiet = true })
    end)
    State.add_paths("temporary")
    assert.is_false(State.save())
    vim.uv.fs_stat = original.stat
    assert.same(before, vim.fn.readfile(path))
  end)

  it("never reads a directory, FIFO, socket, or device as state", function()
    State.add_paths("precious")
    local before, reads = vim.fn.readfile(path), 0
    vim.fn.readfile = function(file, ...)
      if file == path then reads = reads + 1 end
      return original.readfile(file, ...)
    end
    for _, kind in ipairs({ "directory", "fifo", "socket", "char", "block" }) do
      vim.uv.fs_stat = function(file, ...)
        if file == path then return { type = kind } end
        return original.stat(file, ...)
      end
      State.load({ quiet = true })
      assert.is_false(State.save())
    end
    assert.equals(0, reads)
    vim.fn.readfile, vim.uv.fs_stat = original.readfile, original.stat
    assert.same(before, vim.fn.readfile(path))
  end)
end)
