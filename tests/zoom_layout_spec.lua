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
