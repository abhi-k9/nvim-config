describe("escape popup lifecycle", function()
  local floats, buffers, group, escape
  before_each(function()
    floats, buffers = {}, {}
    group = vim.api.nvim_create_augroup("escape_float_lifecycle_spec", { clear = true })
    escape = vim.fn.maparg("<Esc>", "n", false, true).callback
  end)
  after_each(function()
    vim.api.nvim_del_augroup_by_id(group)
    for _, win in ipairs(floats) do
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
  end)

  local function popup(tag)
    local buf = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = buf
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 1,
      style = "minimal",
    })
    floats[#floats + 1] = win
    if tag then vim.w[win][tag] = buf end
    return win
  end

  it("survives a popup-close hook closing another tagged popup", function()
    local first = popup("lsp_floating_bufnr")
    local second = popup("gitsigns_preview")
    local tagged = { [first] = true, [second] = true }
    -- Use the API snapshot order, independent of creation/display order.
    local order = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if tagged[win] then order[#order + 1] = win end
    end
    vim.api.nvim_create_autocmd("WinClosed", {
      group = group,
      pattern = tostring(order[1]),
      once = true,
      callback = function()
        vim.api.nvim_win_close(order[2], true)
      end,
    })

    assert.has_no.errors(escape)
    assert.is_false(vim.api.nvim_win_is_valid(first))
    assert.is_false(vim.api.nvim_win_is_valid(second))
  end)

  it("keeps untagged chrome and ordinary windows while closing tagged popups", function()
    local normal = vim.api.nvim_get_current_win()
    local chrome = popup()
    local tagged = popup("lsp_floating_bufnr")

    escape()

    assert.is_false(vim.api.nvim_win_is_valid(tagged))
    assert.is_true(vim.api.nvim_win_is_valid(chrome))
    assert.is_true(vim.api.nvim_win_is_valid(normal))
  end)
end)
