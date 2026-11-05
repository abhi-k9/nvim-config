describe("live picker help", function()
  local prompt, picker, buffers, current, columns, lines, messages, notify, tabs

  local function mapping(mode, lhs)
    local function code(key)
      return vim.api.nvim_replace_termcodes(key, true, true, true)
    end
    for _, key in ipairs(vim.api.nvim_buf_get_keymap(prompt, mode)) do
      if code(key.lhs) == code(lhs) then return key end
    end
  end

  local function help_text()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.api.nvim_buf_get_name(buf):match("_TelescopeWhichKey$")
      then
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      end
    end
  end

  local function open(all_tabs)
    if all_tabs then
      for _, key in ipairs(require("plugins.finder")[1].keys) do
        if key[1] == "<leader>fB" then key[2]() end
      end
    else
      require("telescope.builtin").buffers({ initial_mode = "normal", previewer = false })
    end
    prompt = vim.api.nvim_get_current_buf()
    picker = require("telescope.actions.state").get_current_picker(prompt)
    assert.is_true(vim.wait(2000, function()
      return picker.manager and picker.manager:num_results() >= #buffers
    end, 10))
  end

  before_each(function()
    require("lazy.core.loader").load("telescope.nvim", { cmd = "picker help spec" })
    current, columns, lines = vim.api.nvim_get_current_win(), vim.o.columns, vim.o.lines
    tabs = {}
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      tabs[tab] = true
    end
    vim.o.columns, vim.o.lines = 220, 60
    buffers = {}
    for i = 1, 3 do
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "-help-" .. i .. ".txt")
      buffers[#buffers + 1] = buf
    end
    notify, messages = vim.notify, {}
    vim.notify = function(message)
      messages[#messages + 1] = message
    end
  end)

  after_each(function()
    if prompt and vim.api.nvim_buf_is_valid(prompt) then
      require("telescope.actions").close(prompt)
    end
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if not tabs[tab] then
        vim.api.nvim_set_current_tabpage(tab)
        vim.cmd("tabclose!")
      end
    end
    if vim.api.nvim_win_is_valid(current) then vim.api.nvim_set_current_win(current) end
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    vim.o.columns, vim.o.lines, vim.notify = columns, lines, notify
    prompt, picker = nil, nil
  end)

  it("shows real named buffer actions without changing literal query text or focus", function()
    open()
    picker:set_prompt("literal_?g?")
    local before = vim.api.nvim_buf_get_lines(prompt, 0, -1, false)
    local win = vim.api.nvim_get_current_win()
    assert.is_not_nil(mapping("i", "<F1>"))
    assert.is_nil(mapping("i", "g?"))
    assert.is_nil(mapping("i", "?"))
    mapping("n", "<F1>").callback()
    local text = help_text()
    assert.is_truthy(text, vim.inspect(messages))
    assert.is_truthy(text:find("Close buffers (keep windows)", 1, true), text)
    assert.is_truthy(text:find("Mark buffer and next", 1, true), text)
    assert.is_truthy(mapping("i", "<C-y>").desc:find("Copy full path", 1, true))
    assert.same(before, vim.api.nvim_buf_get_lines(prompt, 0, -1, false))
    assert.equals(win, vim.api.nvim_get_current_win())
    assert.is_not_nil(mapping("n", "g?"))
  end)

  it(
    "bulk-closes marked buffers while retaining unsaved rows, the picker and editor windows",
    function()
      open()
      vim.bo[buffers[2]].modified = true
      local windows = {}
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == "" then windows[#windows + 1] = win end
      end
      for index = 1, picker.manager:num_results() do
        local entry = picker.manager:get_entry(index)
        if entry.bufnr == buffers[1] or entry.bufnr == buffers[2] then
          picker:add_selection(picker:get_row(index))
        end
      end
      assert.equals(2, #picker:get_multi_selection())
      assert.is_not_nil(mapping("n", "<C-d>"))
      mapping("i", "<C-d>").callback()
      assert.is_false(vim.api.nvim_buf_is_valid(buffers[1]) and vim.bo[buffers[1]].buflisted)
      assert.is_true(vim.api.nvim_buf_is_valid(buffers[2]))
      assert.is_true(vim.bo[buffers[2]].modified)
      assert.is_true(vim.api.nvim_buf_is_valid(prompt))
      for _, win in ipairs(windows) do
        assert.is_true(vim.api.nvim_win_is_valid(win))
      end
      assert.is_true(#messages > 0)
    end
  )

  it("shares buffer actions and hints with the all-tabs extension", function()
    local original_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")
    local other_tab = vim.api.nvim_get_current_tabpage()
    local other_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(other_buf, vim.fn.tempname() .. "-other-tab.txt")
    buffers[#buffers + 1] = other_buf
    vim.api.nvim_win_set_buf(0, other_buf)
    vim.api.nvim_set_current_tabpage(original_tab)
    open(true)
    assert.equals("Scope Buffers", picker.prompt_title)
    assert.is_not_nil(mapping("i", "<C-d>"))
    assert.is_truthy(mapping("i", "<C-d>").desc:find("Close buffers", 1, true))
    assert.is_not_nil(mapping("n", "g?"))
    assert.is_not_nil(mapping("i", "<C-w>"))
    assert.is_truthy(picker.results_title:find("F1", 1, true))
    assert.is_false(vim.bo[other_buf].buflisted)
    vim.bo[other_buf].modified = true
    for index = 1, picker.manager:num_results() do
      if picker.manager:get_entry(index).bufnr == other_buf then
        picker:set_selection(picker:get_row(index))
        break
      end
    end
    mapping("i", "<C-d>").callback()
    assert.is_true(
      vim.wait(2000, function()
        for index = 1, picker.manager:num_results() do
          if picker.manager:get_entry(index).bufnr == other_buf then
            picker:set_selection(picker:get_row(index))
            return true
          end
        end
        return false
      end, 10),
      "Unsaved buffer from another tab disappeared from the picker"
    )
    assert.is_true(vim.bo[other_buf].modified)
    vim.bo[other_buf].modified = false
    require("telescope.actions").select_default(prompt)
    assert.equals(other_tab, vim.api.nvim_get_current_tabpage())
    assert.equals(other_buf, vim.api.nvim_get_current_buf())
  end)
end)
