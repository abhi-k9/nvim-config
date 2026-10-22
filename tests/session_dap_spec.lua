describe("session debugger cleanup", function()
  local original_dap, original_dapui
  local spec

  before_each(function()
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
    vim.cmd("silent! %bwipeout!")
    original_dap, original_dapui = package.loaded.dap, package.loaded.dapui
    package.loaded.dap = {
      session = function()
        return nil
      end,
    }
    package.loaded.dapui = { close = function() end }
    spec = dofile(vim.fn.getcwd() .. "/lua/plugins/session.lua")
  end)

  after_each(function()
    package.loaded.dap, package.loaded.dapui = original_dap, original_dapui
    vim.cmd("silent! only!")
    vim.cmd("silent! %bwipeout!")
  end)

  it("keeps an ordinary file whose name contains a debugger-like marker", function()
    vim.cmd("enew")
    vim.cmd("new")
    local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "-[dap-notes.txt")
    assert.are.equal("", vim.bo[buf].buftype)

    spec.opts.pre_save_cmds[2]()

    assert.is_true(vim.api.nvim_win_is_valid(win), "ordinary file window was closed")
    assert.is_true(vim.api.nvim_buf_is_valid(buf), "ordinary file buffer was deleted")
  end)

  it("still closes a runtime-only debugger window", function()
    vim.cmd("enew")
    vim.cmd("split")
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "[dap-terminal] audit debugger")
    vim.api.nvim_win_set_buf(win, buf)

    spec.opts.pre_save_cmds[2]()

    assert.is_false(vim.api.nvim_win_is_valid(win))
  end)
end)
