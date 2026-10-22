-- Recovery files can change while a cleanup confirmation is open. Keep all
-- filesystem operations real; only swap-header decoding and the user choice
-- are controlled so the race is deterministic without timing two editors.
describe("swap cleanup revalidates confirmed targets", function()
  local swap = require("config.autocmds.swap")
  local dir, path, notes
  local original_confirm, original_swapinfo, original_notify, original_directory
  local original_guard, original_choice
  local info

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    path = dir .. "/leftover.swp"
    vim.fn.writefile({ "clean" }, path)
    info = { pid = 0, dirty = 0, fname = dir .. "/file.txt", host = vim.fn.hostname():sub(1, 39) }
    notes = {}
    original_confirm, original_swapinfo = vim.fn.confirm, vim.fn.swapinfo
    original_notify, original_directory = vim.notify, vim.o.directory
    original_guard, original_choice = vim.g.swap_guard, vim.v.swapchoice
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
    vim.g.swap_guard, vim.v.swapchoice = original_guard, original_choice
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

  it("keeps a clean swap from another host without offering cleanup", function()
    info.host = "another-editor-host"
    local asked = false
    vim.fn.confirm = function()
      asked = true
      return 1
    end
    assert.equals("remote", swap.inventory()[1].kind)
    vim.cmd("SwapClean")
    assert.is_false(asked)
    assert.is_not_nil(vim.uv.fs_stat(path))
    assert.matches("another%-editor%-host", notes[#notes])
  end)

  it("does not infer a foreign owner from a coincidentally equal local PID", function()
    info.host = "another-editor-host"
    info.pid = vim.fn.getpid()
    assert.equals("remote", swap.inventory()[1].kind)
  end)

  it("keeps a swap whose hostname is unknown", function()
    info.host = nil
    assert.equals("remote", swap.inventory()[1].kind)
    vim.cmd("SwapClean")
    assert.is_not_nil(vim.uv.fs_stat(path))
  end)

  it("compares local hostnames case-insensitively like Neovim", function()
    info.host = vim.fn.hostname():sub(1, 39):upper()
    assert.equals("clean", swap.inventory()[1].kind)
    vim.cmd("SwapClean")
    assert.is_nil(vim.uv.fs_stat(path))
  end)

  it("matches Neovim's stored 39-byte hostname on machines with longer names", function()
    local hostname = vim.fn.hostname
    vim.fn.hostname = function()
      return string.rep("a", 50)
    end
    info.host = string.rep("A", 39)
    local ok, list = pcall(swap.inventory)
    vim.fn.hostname = hostname
    assert.is_true(ok, tostring(list))
    assert.equals("clean", list[1].kind)
  end)

  it("requires an explicit bang and warns before deleting a foreign-host swap", function()
    info.host = "another-editor-host"
    local asked = 0
    vim.fn.confirm = function(message)
      asked = asked + 1
      assert.matches("liveness UNKNOWN", message)
      return 1
    end
    vim.cmd("SwapDelete " .. path)
    assert.equals(0, asked)
    assert.is_not_nil(vim.uv.fs_stat(path))
    vim.cmd("SwapDelete! " .. path)
    assert.equals(1, asked)
    assert.is_nil(vim.uv.fs_stat(path))
  end)

  it("rechecks hostname before removing a previously local clean swap", function()
    vim.fn.confirm = function()
      info.host = "another-editor-host"
      return 1
    end
    vim.cmd("SwapClean")
    assert.is_not_nil(vim.uv.fs_stat(path))
  end)

  it("rechecks hostname for explicit deletion without the bang", function()
    vim.fn.confirm = function()
      info.host = "another-editor-host"
      return 1
    end
    vim.cmd("SwapDelete " .. path)
    assert.is_not_nil(vim.uv.fs_stat(path))
  end)

  it("opens a foreign-host collision read-only when its PID is absent locally", function()
    info.host = "another-editor-host"
    info.pid = 0
    vim.fn.swapinfo = function()
      return vim.deepcopy(info)
    end
    vim.g.swap_guard = true
    vim.v.swapchoice = ""
    local callback =
      vim.api.nvim_get_autocmds({ group = "user_swap_collision", event = "SwapExists" })[1].callback
    callback({ buf = vim.api.nvim_get_current_buf(), file = info.fname, match = info.fname })
    assert.equals("o", vim.v.swapchoice)
  end)

  it("leaves the stock prompt for foreign-host collisions when the guard is off", function()
    info.host = "another-editor-host"
    vim.fn.swapinfo = function()
      return vim.deepcopy(info)
    end
    vim.g.swap_guard = false
    vim.v.swapchoice = ""
    local callback =
      vim.api.nvim_get_autocmds({ group = "user_swap_collision", event = "SwapExists" })[1].callback
    callback({ buf = vim.api.nvim_get_current_buf(), file = info.fname, match = info.fname })
    assert.equals("", vim.v.swapchoice)
  end)
end)
