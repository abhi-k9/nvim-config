describe("deferred big-file cleanup", function()
  local dir, path, buf, limit
  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    path = dir .. "/reread.lua"
    limit = vim.g.big_file_size
    vim.g.big_file_size = 50
  end)
  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.g.big_file_size = limit
    vim.fn.delete(dir, "rf")
  end)

  it("does not stop a new small-file highlighter after a rapid reread", function()
    vim.fn.writefile({ "local value = " .. string.rep("1", 100) }, path)
    vim.api.nvim_cmd({ cmd = "edit", args = { path } }, {})
    buf = vim.api.nvim_get_current_buf()
    assert.is_true(vim.b[buf].big_file)
    -- Both reads finish before the first read's scheduled stop executes.
    vim.fn.writefile({ "local value = 1" }, path)
    vim.cmd("edit!")
    assert.is_nil(vim.b[buf].big_file)
    vim.treesitter.start(buf, "lua")
    assert.is_not_nil(vim.treesitter.highlighter.active[buf])
    vim.wait(50)
    assert.is_not_nil(vim.treesitter.highlighter.active[buf])
  end)
end)
