describe("jumplist picker presentation", function()
  it("retains history positions and full text, and opens the exact byte column", function()
    require("lazy.core.loader").load("telescope.nvim", { cmd = "jumplist test" })
    local previous, getjumplist = vim.api.nvim_get_current_win(), vim.fn.getjumplist
    local buf = vim.api.nvim_create_buf(true, false)
    local path = vim.fn.tempname() .. "-long directory-name/source.lua"
    local line = string.rep("long text | ", 30) .. "end"
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line, "second line" })
    vim.fn.getjumplist = function()
      return {
        {
          { bufnr = buf, lnum = 1, col = 5 },
          { bufnr = 999999, lnum = 1, col = 0 },
          { bufnr = buf, lnum = 2, col = 0 },
        },
        3,
      }
    end
    local prompt
    local ok, err = pcall(function()
      for _, key in ipairs(require("plugins.finder")[1].keys) do
        if key[1] == "<leader>fj" then key[2]() end
      end
      prompt = vim.api.nvim_get_current_buf()
      local picker = require("telescope.actions.state").get_current_picker(prompt)
      assert.is_true(vim.wait(1000, function()
        return picker.manager and picker.manager:num_results() == 2
      end))
      assert.is_true(picker.wrap_results)
      assert.equals("vertical", picker.layout_strategy)
      local entries = {}
      for entry in picker.manager:iter() do
        entries[#entries + 1] = entry
      end
      assert.matches("^#3 ", entries[1].display)
      assert.matches("^#1 ", entries[2].display)
      assert.is_truthy(entries[2].display:find(line, 1, true))
      assert.equals(path, entries[2].filename)
      picker:set_selection(1)
      require("telescope.actions").select_default(prompt)
      prompt = nil
      assert.equals(buf, vim.api.nvim_get_current_buf())
      assert.same({ 1, 5 }, vim.api.nvim_win_get_cursor(0))
    end)
    vim.fn.getjumplist = getjumplist
    if prompt and vim.api.nvim_buf_is_valid(prompt) then
      require("telescope.actions").close(prompt)
    end
    if vim.api.nvim_win_is_valid(previous) then vim.api.nvim_set_current_win(previous) end
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(ok, err)
  end)
end)
