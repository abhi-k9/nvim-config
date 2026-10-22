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
end)
