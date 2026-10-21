-- Recovery files can change while a cleanup confirmation is open. Keep all
-- filesystem operations real; only swap-header decoding and the user choice
-- are controlled so the race is deterministic without timing two editors.
describe("swap cleanup revalidates confirmed targets", function()
  local swap = require("config.autocmds.swap")
  local dir, path, notes
  local original_confirm, original_swapinfo, original_notify, original_directory
  local info

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    path = dir .. "/leftover.swp"
    vim.fn.writefile({ "clean" }, path)
    info = { pid = 0, dirty = 0, fname = dir .. "/file.txt" }
    notes = {}
    original_confirm, original_swapinfo = vim.fn.confirm, vim.fn.swapinfo
    original_notify, original_directory = vim.notify, vim.o.directory
    vim.o.directory = dir .. "//"
    vim.fn.swapinfo = function(name)
      if name == path then return vim.deepcopy(info) end
      return original_swapinfo(name)
    end
    vim.fn.confirm = function()
      return 1
    end
    vim.notify = function(message)
      notes[#notes + 1] = message
    end
  end)

  after_each(function()
    vim.fn.confirm, vim.fn.swapinfo = original_confirm, original_swapinfo
    vim.notify, vim.o.directory = original_notify, original_directory
    vim.fn.delete(dir, "rf")
  end)

  it("still removes an unchanged clean leftover", function()
    assert.equals("clean", swap.inventory()[1].kind)
    vim.cmd("SwapClean")
    assert.is_nil(vim.uv.fs_stat(path))
    assert.matches("removed 1 swap file", notes[#notes])
  end)

  it("leaves a different file moved into the path during confirmation", function()
    vim.fn.confirm = function()
      local replacement = dir .. "/replacement"
      vim.fn.writefile({ "replacement recovery data" }, replacement)
      assert(vim.uv.fs_rename(replacement, path))
      return 1
    end
    vim.cmd("SwapClean")
    assert.same({ "replacement recovery data" }, vim.fn.readfile(path))
    assert.matches("not deleted", notes[#notes])
  end)

  it("leaves recovery data updated in place during confirmation", function()
    local inode = vim.uv.fs_stat(path).ino
    vim.fn.confirm = function()
      vim.fn.writefile({ "unsaved edits from another editor" }, path)
      return 1
    end
    vim.cmd("SwapClean")
    assert.equals(inode, vim.uv.fs_stat(path).ino)
    assert.same({ "unsaved edits from another editor" }, vim.fn.readfile(path))
  end)

  it("rechecks dirty state even when file metadata appears unchanged", function()
    vim.fn.confirm = function()
      info.dirty = 1
      return 1
    end
    vim.cmd("SwapClean")
    assert.is_not_nil(vim.uv.fs_stat(path))
    assert.matches("now active, dirty or unreadable", notes[#notes])
  end)

  it("rechecks live ownership even when file metadata appears unchanged", function()
    vim.fn.confirm = function()
      info.pid = vim.fn.getpid()
      return 1
    end
    vim.cmd("SwapClean")
    assert.is_not_nil(vim.uv.fs_stat(path))
  end)

  it("keeps a formerly readable swap whose header is now unreadable", function()
    vim.fn.confirm = function()
      info = { error = "Cannot read file" }
      return 1
    end
    vim.cmd("SwapClean")
    assert.is_not_nil(vim.uv.fs_stat(path))
  end)

  it("still removes an unchanged old empty swap", function()
    vim.fn.writefile({}, path)
    assert(vim.uv.fs_utime(path, os.time() - 120, os.time() - 120))
    info = { error = "Cannot read file" }
    vim.cmd("SwapClean")
    assert.is_nil(vim.uv.fs_stat(path))
  end)

  it("does not let SwapDelete discard changes made after its prompt opened", function()
    vim.fn.confirm = function()
      vim.fn.writefile({ "new recovery data" }, path)
      return 1
    end
    vim.cmd("SwapDelete " .. path)
    assert.same({ "new recovery data" }, vim.fn.readfile(path))
  end)

  it("still allows explicit confirmed deletion of an unchanged dirty swap", function()
    info.dirty = 1
    vim.cmd("SwapDelete " .. path)
    assert.is_nil(vim.uv.fs_stat(path))
  end)
end)
