describe("explorer directory startup", function()
  local root, previous, buf, old_cwd, original_command, original_argv, opened

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/requested directory", "p")
    vim.fn.mkdir(root .. "/unrelated", "p")
    previous, old_cwd = vim.api.nvim_get_current_buf(), vim.fn.getcwd()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    original_command, original_argv = package.loaded["neo-tree.command"], vim.fn.argv
    package.loaded["neo-tree.command"] = {
      execute = function(opts)
        opened = opts
      end,
    }
    opened = nil
  end)

  after_each(function()
    package.loaded["neo-tree.command"], vim.fn.argv = original_command, original_argv
    vim.api.nvim_del_augroup_by_name("user_neotree_dir")
    vim.api.nvim_set_current_dir(old_cwd)
    if vim.api.nvim_buf_is_valid(previous) then vim.api.nvim_set_current_buf(previous) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    vim.fn.delete(root, "rf")
  end)

  local function startup_hook()
    local original_v = vim.v
    vim.v = { vim_did_enter = 0 }
    local ok, err = pcall(require("plugins.explorer").init)
    vim.v = original_v
    assert.is_true(ok, err)
  end

  it("ignores early buffer entries before opening the startup directory once", function()
    startup_hook()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    local directory = root .. "/requested directory"
    vim.api.nvim_buf_set_name(buf, directory)
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    assert.is_true(vim.wait(1000, function()
      return opened ~= nil
    end))
    assert.equals(directory, opened.dir)
    assert.same({}, vim.api.nvim_get_autocmds({ group = "user_neotree_dir" }))
  end)

  it("checks the current directory buffer at VimEnter when BufEnter was missed", function()
    vim.api.nvim_buf_set_name(buf, root .. "/requested directory")
    startup_hook()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    assert.is_true(vim.wait(1000, function()
      return opened ~= nil
    end))
    assert.equals(vim.api.nvim_buf_get_name(buf), opened.dir)
  end)

  it("retires the startup hook at VimEnter without a directory", function()
    startup_hook()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    assert.same({}, vim.api.nvim_get_autocmds({ group = "user_neotree_dir" }))
    assert.is_nil(opened)
  end)

  it("opens an explicit launch directory after the startup session replaces its buffer", function()
    local directory = root .. "/requested directory"
    vim.fn.argv = function()
      return { directory }
    end
    startup_hook()
    vim.api.nvim_buf_set_name(buf, root .. "/restored.lua")
    vim.api.nvim_exec_autocmds("SessionLoadPost", {})
    vim.api.nvim_exec_autocmds("VimEnter", {})
    assert.is_true(vim.wait(1000, function()
      return opened ~= nil
    end))
    assert.equals(vim.fn.fnamemodify(directory, ":p"), opened.dir)
    assert.equals(buf, vim.api.nvim_get_current_buf())
    opened = nil
    vim.api.nvim_exec_autocmds("SessionLoadPost", {})
    vim.wait(20)
    assert.is_nil(opened)
  end)

  it("does not open the startup directory for a later manual session restore", function()
    vim.fn.argv = function()
      return { root .. "/requested directory" }
    end
    startup_hook()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    vim.wait(20)
    vim.api.nvim_exec_autocmds("SessionLoadPost", {})
    vim.wait(20)
    assert.is_nil(opened)
  end)

  it("opens the entered directory even if cwd changes before the scheduled callback", function()
    local directory = root .. "/requested directory"
    vim.api.nvim_buf_set_name(buf, directory)
    require("plugins.explorer").init()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    vim.api.nvim_set_current_dir(root .. "/unrelated")
    assert.is_true(vim.wait(1000, function()
      return opened ~= nil
    end))
    assert.equals(directory, opened.dir)
    assert.equals("filesystem", opened.source)
  end)

  it("does not reopen a startup directory after reloading while entering a regular file", function()
    vim.api.nvim_buf_set_name(buf, root .. "/file.lua")
    vim.fn.argv = function()
      return root .. "/requested directory"
    end
    require("plugins.explorer").init()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    vim.wait(20)
    assert.is_nil(opened)
  end)

  it("discards a scheduled directory open after switching tabs", function()
    vim.api.nvim_buf_set_name(buf, root .. "/requested directory")
    require("plugins.explorer").init()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    vim.cmd("tabnew")
    local tab = vim.api.nvim_get_current_tabpage()
    vim.wait(20)
    local result = opened
    vim.cmd("tabclose!")
    assert.is_false(vim.api.nvim_tabpage_is_valid(tab))
    assert.is_nil(result)
  end)

  it("discards a scheduled open if its directory buffer has been replaced", function()
    vim.api.nvim_buf_set_name(buf, root .. "/requested directory")
    require("plugins.explorer").init()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    vim.api.nvim_set_current_buf(previous)
    vim.wait(20)
    assert.is_nil(opened)
  end)
end)
