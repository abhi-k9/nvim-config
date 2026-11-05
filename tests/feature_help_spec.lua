describe("native help in additional features", function()
  local current, columns, lines, prompt

  before_each(function()
    current, columns, lines = vim.api.nvim_get_current_win(), vim.o.columns, vim.o.lines
    vim.o.columns, vim.o.lines = 180, 60
  end)

  after_each(function()
    if prompt and vim.api.nvim_buf_is_valid(prompt) then
      require("telescope.actions").close(prompt)
    end
    prompt = nil
    if package.loaded["diffview"] then pcall(vim.cmd, "DiffviewClose") end
    if package.loaded["atone.core"] then require("atone.core").close() end
    if vim.api.nvim_win_is_valid(current) then vim.api.nvim_set_current_win(current) end
    vim.o.columns, vim.o.lines = columns, lines
  end)

  it("reuses each Diffview context's own native help callback", function()
    require("lazy.core.loader").load("diffview-plus.nvim", { cmd = "help spec" })
    local config = require("diffview.config")
    local defaults_before = vim.deepcopy(config.defaults.keymaps)
    dofile("lua/plugins/git.lua")[2].opts()
    assert.same(defaults_before, config.defaults.keymaps, "Native defaults were mutated")
    local groups = 0
    for group, defaults in pairs(config.defaults.keymaps) do
      if type(defaults) == "table" then
        local native
        for _, mapping in ipairs(defaults) do
          if mapping[1] == "n" and mapping[2] == "g?" then native = mapping[3] end
        end
        if native then
          groups = groups + 1
          local found
          for _, mapping in ipairs(config.get_config().keymaps[group]) do
            if mapping[1] == "n" and mapping[2] == "<F1>" then found = mapping end
          end
          assert.is_truthy(found, group)
          assert.equals(native, found[3], group)
        end
      end
    end
    assert.is_true(groups > 0)
  end)

  it("opens Atone's real help from the tree and diff panes without changing the file", function()
    require("lazy.core.loader").load("atone.nvim", { cmd = "help spec" })
    local core = require("atone.core")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "second" })
    local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    core.open()
    for _, pane in ipairs({ core._tree_buf, core._auto_diff_buf }) do
      assert.is_true(vim.api.nvim_buf_is_valid(pane))
      local keys = {}
      for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(pane, "n")) do
        keys[mapping.lhs] = mapping
      end
      assert.is_truthy(keys["?"])
      assert.is_truthy(keys["g?"])
      assert.is_truthy(keys["<F1>"])
      keys["<F1>"].callback()
      local help = table.concat(vim.api.nvim_buf_get_lines(core._help_buf, 0, -1, false), "\n")
      assert.is_truthy(help:find("<F1>", 1, true), help)
      assert.is_truthy(help:find("Show help page", 1, true), help)
      assert.same(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      local help_win = core._float_win
      for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(core._help_buf, "n")) do
        if mapping.lhs == "<Esc>" then
          mapping.callback()
          break
        end
      end
      assert.is_false(vim.api.nvim_win_is_valid(help_win))
      assert.is_true(vim.api.nvim_win_is_valid(core._tree_win))
    end
    core.close()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("makes Scoper's native multi-selection help and confirmation discoverable", function()
    require("lazy.core.loader").load("telescope.nvim", { cmd = "help spec" })
    local util = require("scoper.util")
    local preference, result = util.prefer_fzf
    util.prefer_fzf = function()
      return false
    end
    local ok, err = pcall(require("scoper.ui").pick_many, { "alpha", "beta" }, {}, function(picked)
      result = picked
    end)
    util.prefer_fzf = preference
    assert.is_true(ok, err)
    prompt = vim.api.nvim_get_current_buf()
    local picker = require("telescope.actions.state").get_current_picker(prompt)
    assert.is_true(vim.wait(1000, function()
      return picker.manager and picker.manager:num_results() == 2
    end, 10))
    local keys = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt, "n")) do
      keys[mapping.lhs] = mapping
    end
    assert.is_truthy(keys["<F1>"])
    assert.is_truthy(keys["g?"])
    assert.is_truthy(keys["<CR>"].desc:find("Confirm selected items", 1, true))
    assert.is_truthy(picker.results_title:find("Tab: mark", 1, true))
    local selected = picker.manager:get_entry(1).value
    picker:add_selection(picker:get_row(1))
    keys["<CR>"].callback()
    assert.same({ selected }, result)
  end)
end)
