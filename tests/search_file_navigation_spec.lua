describe("search result file navigation", function()
  local root, previous, old_cwd, instance, buf, headers

  before_each(function()
    require("lazy.core.loader").load("grug-far.nvim", { cmd = "spec" })
    previous, old_cwd = vim.api.nvim_get_current_buf(), vim.fn.getcwd()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "first", "", "second" }, root .. "/a.txt")
    vim.fn.writefile({ "third", "", "fourth" }, root .. "/b.txt")
    vim.api.nvim_set_current_dir(root)
    instance = require("grug-far").open({
      prefills = { search = "^.*", paths = root, flags = "--sort=path" },
      debounceMs = 1,
    })
    buf = instance:get_buf()
    assert.is_true(vim.wait(3000, function()
      local info = instance:get_status_info()
      return info.stats and info.stats.matches == 6
    end))
    headers = {}
    for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if line == "a.txt" or line == "b.txt" then headers[#headers + 1] = row end
    end
    assert.equals(2, #headers)
  end)

  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.api.nvim_set_current_dir(old_cwd)
    if vim.api.nvim_buf_is_valid(previous) then vim.api.nvim_set_current_buf(previous) end
    vim.fn.delete(root, "rf")
  end)

  it("skips matching source lines after blank matches in both directions", function()
    vim.api.nvim_win_set_cursor(0, { headers[1], 0 })
    vim.cmd.normal("]f")
    assert.equals(headers[2], vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd.normal("[f")
    assert.equals(headers[1], vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("does not move when there is no further file header", function()
    vim.api.nvim_win_set_cursor(0, { headers[2], 0 })
    vim.cmd.normal("]f")
    assert.equals(headers[2], vim.api.nvim_win_get_cursor(0)[1])
    vim.api.nvim_win_set_cursor(0, { headers[1], 0 })
    vim.cmd.normal("[f")
    assert.equals(headers[1], vim.api.nvim_win_get_cursor(0)[1])
  end)
end)
