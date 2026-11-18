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
  it("searches current-buffer changes and opens the exact byte column", function()
    require("lazy.core.loader").load("telescope.nvim", { cmd = "jumplist test" })
    local previous, getchangelist = vim.api.nvim_get_current_win(), vim.fn.getchangelist
    local buf = vim.api.nvim_create_buf(true, false)
    local path = vim.fn.tempname() .. "-long directory-name/source.lua"
    local line = string.rep("long text | ", 30) .. "end"
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line, "second line" })
    vim.fn.getchangelist = function(source)
      assert.equals(buf, source)
      return {
        {
          { lnum = 1, col = 5 },
          { lnum = 2, col = 0 },
        },
        3,
      }
    end
    vim.api.nvim_set_current_buf(buf)
    local prompt
    local ok, err = pcall(function()
      for _, key in ipairs(require("plugins.finder")[1].keys) do
        if key[1] == "<leader>fC" then key[2]() end
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
      assert.matches("^#2 ", entries[1].display)
      assert.matches("^#1 ", entries[2].display)
      assert.is_truthy(entries[2].display:find(line, 1, true))
      assert.equals(path, entries[2].filename)
      picker:set_selection(1)
      require("telescope.actions").select_default(prompt)
      prompt = nil
      assert.equals(buf, vim.api.nvim_get_current_buf())
      assert.same({ 1, 5 }, vim.api.nvim_win_get_cursor(0))
    end)
    vim.fn.getchangelist = getchangelist
    if prompt and vim.api.nvim_buf_is_valid(prompt) then
      require("telescope.actions").close(prompt)
    end
    if vim.api.nvim_win_is_valid(previous) then vim.api.nvim_set_current_win(previous) end
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(ok, err)
  end)
end)

describe("change history across files", function()
  it("includes other files, skips special buffers and preserves per-file positions", function()
    require("lazy").load({ plugins = { "telescope.nvim" } })
    local original, previous = vim.fn.getchangelist, vim.api.nvim_get_current_buf()
    local first, second, special =
      vim.api.nvim_create_buf(true, false),
      vim.api.nvim_create_buf(true, false),
      vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(first, 0, -1, false, { "first edit" })
    vim.api.nvim_buf_set_lines(second, 0, -1, false, { "other edit" })
    vim.api.nvim_set_current_buf(first)
    vim.fn.getchangelist = function(buf)
      if buf == first or buf == second or buf == special then
        return { { { lnum = 1, col = 2 } }, 1 }
      end
      return { {}, 0 }
    end
    local prompt
    local ok, err = pcall(function()
      for _, key in ipairs(require("plugins.finder")[1].keys) do
        if key[1] == "<leader>fE" then key[2]() end
      end
      prompt = vim.api.nvim_get_current_buf()
      local picker = require("telescope.actions.state").get_current_picker(prompt)
      assert.is_true(vim.wait(1000, function()
        return picker.manager and picker.manager:num_results() == 2
      end))
      local entries = {}
      for entry in picker.manager:iter() do
        entries[#entries + 1] = entry
      end
      assert.equals(first, entries[1].bufnr)
      assert.equals(second, entries[2].bufnr)
      assert.matches("^#1 ", entries[1].display)
      assert.matches("^#1 ", entries[2].display)
      picker:set_selection(1)
      require("telescope.actions").select_default(prompt)
      prompt = nil
      assert.equals(second, vim.api.nvim_get_current_buf())
      assert.same({ 1, 2 }, vim.api.nvim_win_get_cursor(0))
    end)
    vim.fn.getchangelist = original
    if prompt and vim.api.nvim_buf_is_valid(prompt) then
      require("telescope.actions").close(prompt)
    end
    vim.api.nvim_set_current_buf(previous)
    for _, buf in ipairs({ first, second, special }) do
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    assert.is_true(ok, err)
  end)
end)
