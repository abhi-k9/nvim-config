describe("buffer menu split placement", function()
  local options, original_equalalways, original_splitright, original_splitbelow, panel, file

  before_each(function()
    original_equalalways, original_splitright, original_splitbelow =
      vim.o.equalalways, vim.o.splitright, vim.o.splitbelow
    vim.o.equalalways, vim.o.splitright, vim.o.splitbelow = false, true, true
    vim.cmd("silent! only!")
    file = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, file)
    vim.cmd("vsplit")
    panel = vim.api.nvim_get_current_win()
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(panel, scratch)
    vim.bo[scratch].filetype = "neo-tree"
    vim.api.nvim_win_set_width(panel, 20)
    for _, spec in ipairs(dofile(vim.fn.getcwd() .. "/lua/plugins/ui.lua")) do
      if spec[1] == "akinsho/bufferline.nvim" then options = spec.opts().options end
    end
  end)

  after_each(function()
    vim.cmd("silent! only!")
    vim.o.equalalways, vim.o.splitright, vim.o.splitbelow =
      original_equalalways, original_splitright, original_splitbelow
  end)

  local function pick(index)
    options.right_mouse_command(file, "cursor")
    local action = vim.fn.maparg(tostring(index), "n", false, true).callback
    assert.equals("function", type(action))
    action()
    vim.wait(100, function()
      return vim.api.nvim_get_current_buf() == file
    end)
  end

  it("opens vertical splits beside the file instead of inside the focused panel", function()
    pick(1)
    local split = vim.api.nvim_get_current_win()
    assert.is_not.equals(panel, split)
    assert.equals(file, vim.api.nvim_win_get_buf(split))
    assert.is_true(
      vim.api.nvim_win_get_position(split)[2] < vim.api.nvim_win_get_position(panel)[2]
    )
    assert.equals(20, vim.api.nvim_win_get_width(panel))
  end)

  it("opens horizontal splits in the file area and leaves the panel full height", function()
    local height = vim.api.nvim_win_get_height(panel)
    pick(2)
    local split = vim.api.nvim_get_current_win()
    assert.equals(file, vim.api.nvim_win_get_buf(split))
    assert.is_true(
      vim.api.nvim_win_get_position(split)[2] < vim.api.nvim_win_get_position(panel)[2]
    )
    assert.equals(height, vim.api.nvim_win_get_height(panel))
  end)
end)
