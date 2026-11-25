describe("zoom restoration tracks the ordered window layout", function()
  local toggle, columns
  before_each(function()
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
    vim.t.zoom_state = nil
    columns = vim.o.columns
    vim.o.columns = 180
    vim.cmd("vsplit")
    vim.cmd("vsplit")
    local wins = vim.api.nvim_tabpage_list_wins(0)
    vim.api.nvim_win_set_width(wins[1], 20)
    vim.api.nvim_win_set_width(wins[2], 40)
    toggle = vim.fn.maparg("<Space>wm", "n", false, true).callback
  end)
  after_each(function()
    if vim.t.zoom_state then toggle() end
    vim.cmd("silent! only!")
    vim.o.columns = columns
  end)

  it("restores sizes for the unchanged layout and restores fixed-width state", function()
    local widths = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      widths[win] = vim.api.nvim_win_get_width(win)
    end
    vim.wo.winfixwidth = true
    toggle()
    assert.is_false(vim.wo.winfixwidth)
    toggle()
    assert.is_true(vim.wo.winfixwidth)
    for win, width in pairs(widths) do
      assert.are.equal(width, vim.api.nvim_win_get_width(win))
    end
    vim.wo.winfixwidth = false
  end)

  it("keeps the sizing policy of a replacement buffer in the zoomed split", function()
    vim.wo.winfixwidth = true
    toggle()
    vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))
    vim.wo.winfixwidth = false
    vim.wo.winfixheight = true
    toggle()
    assert.is_false(vim.wo.winfixwidth)
    assert.is_true(vim.wo.winfixheight)
  end)

  it("preserves a fixed height enabled while zoomed", function()
    vim.wo.winfixheight = false
    toggle()
    vim.wo.winfixheight = true
    toggle()
    assert.is_true(vim.wo.winfixheight)
  end)

  it("equalizes surviving splits after the zoomed window closes", function()
    toggle()
    vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
    toggle()
    assert.is_nil(vim.t.zoom_state)
    local wins = vim.api.nvim_tabpage_list_wins(0)
    local difference = vim.api.nvim_win_get_width(wins[1]) - vim.api.nvim_win_get_width(wins[2])
    assert.is_true(math.abs(difference) <= 1)
  end)

  it("equalizes after windows are exchanged instead of replaying stale window numbers", function()
    toggle()
    vim.cmd("wincmd x")
    toggle()
    local smallest, largest = math.huge, 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local width = vim.api.nvim_win_get_width(win)
      smallest, largest = math.min(smallest, width), math.max(largest, width)
    end
    assert.is_true(largest - smallest <= 1)
  end)
end)

describe("closing a floating window above a single split", function()
  it("closes the float and keeps the last editor window", function()
    vim.cmd("only")
    local editor = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 10,
      height = 2,
    })
    vim.fn.maparg("<Space>wc", "n", false, true).callback()
    local closed = not vim.api.nvim_win_is_valid(win)
    if not closed then vim.api.nvim_win_close(win, true) end
    assert.is_true(closed)
    assert.equals(editor, vim.api.nvim_get_current_win())
  end)
end)
