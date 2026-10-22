describe("session filetype rescue", function()
  local buffers = {}
  after_each(function()
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    buffers = {}
  end)

  local function buffer(name, special)
    local buf = vim.api.nvim_create_buf(false, special)
    buffers[#buffers + 1] = buf
    vim.api.nvim_buf_set_name(buf, name)
    return buf
  end

  it("does not run filetype plugins on special or URI buffers", function()
    local special = buffer("plugin://special.lua", true)
    local virtual = buffer("plugin://virtual.lua", false)
    vim.api.nvim_exec_autocmds("SessionLoadPost", { group = "user_filetype_session_restore" })
    vim.wait(20)
    assert.are.equal("", vim.bo[special].filetype)
    assert.are.equal("", vim.bo[virtual].filetype)
    assert.is_nil(vim.treesitter.highlighter.active[special])
    assert.is_nil(vim.treesitter.highlighter.active[virtual])
  end)

  it("still detects a loaded ordinary file buffer", function()
    local ordinary = buffer(vim.fn.tempname() .. ".lua", false)
    vim.api.nvim_exec_autocmds("SessionLoadPost", { group = "user_filetype_session_restore" })
    vim.wait(20)
    assert.are.equal("lua", vim.bo[ordinary].filetype)
  end)
end)
