describe("session scope ordering", function()
  local spec, core, first_buf, second_buf, first_tab, second_tab

  before_each(function()
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! %bwipeout!")
    core = require("scope.core")
    core.cache = {}
    spec = dofile(vim.fn.getcwd() .. "/lua/plugins/session.lua")
    vim.cmd("enew")
    first_buf, first_tab = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_tabpage()
    vim.api.nvim_buf_set_name(first_buf, vim.fn.tempname() .. "-first.txt")
    vim.cmd("tabnew")
    second_buf, second_tab = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_tabpage()
    vim.api.nvim_buf_set_name(second_buf, vim.fn.tempname() .. "-second.txt")
    vim.cmd("tabmove 0")
  end)

  after_each(function()
    vim.g.ScopeState = nil
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! %bwipeout!")
    core.cache = {}
  end)

  local function save_scopes()
    local hook = spec.opts.pre_save_cmds[3]
    if type(hook) == "string" then
      vim.cmd(hook)
    else
      hook()
    end
  end

  it("serializes in visual tab order after moving a tab", function()
    save_scopes()
    local saved = vim.json.decode(vim.g.ScopeState)
    assert.are.equal(vim.api.nvim_buf_get_name(second_buf), saved.cache[1][1])
    assert.are.equal(vim.api.nvim_buf_get_name(first_buf), saved.cache[2][1])
  end)

  it("restores moved tabs without assigning their buffers to another tab", function()
    save_scopes()
    spec.opts.post_restore_cmds[1]()
    assert.are.same({ second_buf }, core.cache[second_tab])
    assert.are.same({ first_buf }, core.cache[first_tab])
  end)
end)
