describe("swap directory option decoding", function()
  local swap = require("config.autocmds.swap")
  local root, current, original_directory, original_confirm, original_notify
  local created

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    current = vim.api.nvim_get_current_buf()
    original_directory, original_confirm = vim.o.directory, vim.fn.confirm
    original_notify = vim.notify
    created = {}
    vim.fn.confirm = function()
      return 1
    end
    vim.notify = function() end
  end)

  after_each(function()
    vim.o.directory, vim.fn.confirm = original_directory, original_confirm
    vim.notify = original_notify
    if vim.api.nvim_buf_is_valid(current) then vim.api.nvim_set_current_buf(current) end
    for _, buf in ipairs(created) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    vim.fn.delete(root, "rf")
  end)

  local function normalized(path)
    return (vim.fs.normalize(path, { expand_env = true }):gsub("[/\\]+$", ""))
  end

  local function directories(value)
    vim.o.directory = value
    local _, dirs = swap.inventory()
    return dirs
  end

  -- Produce a genuine leftover with this version of Neovim rather than
  -- inventing a header. SIGKILL targets only this fixture's own process;
  -- normal exit would remove the swap that the discovery test needs.
  local function native_leftover(directory)
    vim.fn.mkdir(directory, "p")
    local file, ready, fixture = root .. "/file.txt", root .. "/ready", root .. "/fixture.lua"
    local option = directory:gsub(",", "\\,") .. "//"
    vim.fn.writefile({ "on disk" }, file)
    vim.fn.writefile({
      ("vim.o.directory = %q"):format(option),
      "vim.o.updatecount = 1", -- -l otherwise disables swap creation
      ("vim.cmd.edit({ args = { %q } })"):format(file),
      "vim.cmd.preserve()",
      ("vim.fn.writefile({ vim.fn.swapname('%%') }, %q)"):format(ready),
      "vim.uv.kill(vim.fn.getpid(), 9)",
    }, fixture)
    local result = vim
      .system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", fixture })
      :wait(10000)
    assert.equals(1, vim.fn.filereadable(ready), result.stderr)
    local path = vim.fn.readfile(ready)[1]
    assert.is_not_nil(vim.uv.fs_stat(path))
    assert.equals(0, vim.fn.swapinfo(path).pid)
    vim.o.directory = option
    return path, file
  end

  it("discovers a native swap created in a directory containing a comma", function()
    local directory = root .. "/comma,dir"
    local path = native_leftover(directory)
    local list, dirs = swap.inventory()
    assert.same({ normalized(directory) }, dirs)
    assert.equals(1, #list)
    assert.equals(normalized(path), normalized(list[1].swap))
    assert.equals("clean", list[1].kind)
  end)

  it("finds that leftover for no-argument SwapDelete without relying on swapname", function()
    local path, file = native_leftover(root .. "/comma,dir")
    local buf = vim.api.nvim_create_buf(true, false)
    created[#created + 1] = buf
    vim.bo[buf].swapfile = false
    vim.api.nvim_buf_set_name(buf, file)
    vim.api.nvim_set_current_buf(buf)
    assert.equals("", vim.fn.swapname("%"))
    vim.cmd("SwapDelete")
    assert.is_nil(vim.uv.fs_stat(path))
  end)

  it("also discovers native swaps with a backslash immediately before the comma", function()
    local directory = root .. "/back\\,slash"
    local path = native_leftover(directory)
    local list, dirs = swap.inventory()
    assert.same({ normalized(directory) }, dirs)
    assert.equals(1, #list)
    assert.equals(normalized(path), normalized(list[1].swap))
  end)

  it("preserves drive and UNC backslashes and ignores spaces after separators", function()
    assert.same({
      normalized([[C:\Users\alice\swap//]]),
      normalized([[\\server\share\swap//]]),
    }, directories([[C:\Users\alice\swap//,   \\server\share\swap//]]))
  end)

  it("quotes a comma after either an odd or even run of backslashes", function()
    for count = 1, 4 do
      local prefix = root .. "/name"
      local value = prefix .. string.rep("\\", count) .. ",part//"
      local decoded = prefix .. string.rep("\\", count - 1) .. ",part"
      assert.same({ normalized(decoded) }, directories(value))
    end
  end)

  it("preserves ordinary and space-adjacent backslashes in the stored value", function()
    assert.same({
      normalized([[C:\space dir\swap]]),
      normalized([[\ leading space]]),
    }, directories([[C:\space dir\swap//,\ leading space//]]))
  end)

  it("retains native current-directory entries but treats an empty option as disabled", function()
    assert.same({}, directories(""))
    assert.same(
      { normalized(vim.fn.getcwd()), normalized(root .. "/other") },
      directories("," .. root .. "/other//")
    )
    assert.same({ normalized(root .. "/other") }, directories(root .. "/other//,"))
  end)
end)
