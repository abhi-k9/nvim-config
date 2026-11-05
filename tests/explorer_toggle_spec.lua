describe("explorer buffers/files toggle", function()
  local command, manager, notify, preload, mapping, spec
  local states, calls, messages, windows, tabs, buffers, original_win, original_tab

  before_each(function()
    command, manager =
      package.loaded["neo-tree.command"], package.loaded["neo-tree.sources.manager"]
    notify, preload = vim.notify, package.preload["neo-tree.command"]
    original_win, original_tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
    states, calls, messages, windows, tabs, buffers = {}, {}, {}, {}, {}, {}
    package.loaded["neo-tree.sources.manager"] = {
      get_state_for_window = function(win)
        return states[win or vim.api.nvim_get_current_win()]
      end,
    }
    package.loaded["neo-tree.command"] = {
      execute = function(args)
        calls[#calls + 1] = args
      end,
    }
    vim.notify = function(message)
      messages[#messages + 1] = message
    end
    spec = dofile(vim.fn.getcwd() .. "/lua/plugins/explorer.lua")
    for _, key in ipairs(spec.keys) do
      if key[1] == "<leader>be" then mapping = key[2] end
    end
  end)

  after_each(function()
    package.loaded["neo-tree.command"], package.loaded["neo-tree.sources.manager"] =
      command, manager
    package.preload["neo-tree.command"], vim.notify = preload, notify
    for _, tab in ipairs(tabs) do
      if vim.api.nvim_tabpage_is_valid(tab) then
        vim.api.nvim_set_current_tabpage(tab)
        vim.cmd("tabclose!")
      end
    end
    if vim.api.nvim_tabpage_is_valid(original_tab) then
      vim.api.nvim_set_current_tabpage(original_tab)
    end
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
    if vim.api.nvim_win_is_valid(original_win) then vim.api.nvim_set_current_win(original_win) end
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
  end)

  local function tree(source, position)
    local buf = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = buf
    local config = position == "float"
        and { relative = "editor", row = 2, col = 2, width = 20, height = 4 }
      or { split = "left", width = 20 }
    local win = vim.api.nvim_open_win(buf, false, config)
    windows[#windows + 1] = win
    states[win] = { name = source, current_position = position, winid = win }
    return win
  end

  it("opens buffers when closed without retaining a separate toggle flag", function()
    mapping()
    assert.equals("buffers", calls[1].source)
    assert.is_nil(calls[1].position)
    mapping()
    assert.equals("buffers", calls[2].source)
  end)

  it("switches the focused tree and preserves position without root or reveal overrides", function()
    local win = tree("filesystem", "right")
    vim.api.nvim_set_current_win(win)
    mapping()
    assert.same(
      { source = "buffers", action = "focus", position = "right", reveal = false },
      calls[1]
    )
    states[win].name = "buffers"
    mapping()
    assert.same(
      { source = "filesystem", action = "focus", position = "right", reveal = false },
      calls[2]
    )
  end)

  it("returns a visible buffers tree to files when invoked from an editor", function()
    local win = tree("buffers", "left")
    mapping()
    assert.equals(win, vim.api.nvim_get_current_win())
    assert.equals("filesystem", calls[1].source)
    assert.equals("left", calls[1].position)
  end)

  it("prefers the focused tree over another visible source", function()
    tree("buffers", "left")
    local focused = tree("git_status", "right")
    vim.api.nvim_set_current_win(focused)
    mapping()
    assert.equals("buffers", calls[1].source)
    assert.equals("right", calls[1].position)
  end)

  it("finds a visible filesystem source before switching to buffers", function()
    tree("filesystem", "right")
    mapping()
    assert.equals("buffers", calls[1].source)
    assert.equals("right", calls[1].position)
  end)

  it("does not treat another tab's buffers source as this tab's toggle state", function()
    vim.cmd("tabnew")
    tabs[#tabs + 1] = vim.api.nvim_get_current_tabpage()
    states[vim.api.nvim_get_current_win()] = { name = "buffers", current_position = "left" }
    vim.api.nvim_set_current_tabpage(original_tab)
    mapping()
    assert.equals("buffers", calls[1].source)
    assert.is_nil(calls[1].position)
  end)

  it("targets the existing current-position tree rather than replacing an editor", function()
    local win = tree("buffers", "current")
    mapping()
    assert.equals(win, vim.api.nvim_get_current_win())
    assert.equals("filesystem", calls[1].source)
    assert.equals("current", calls[1].position)
  end)

  it("keeps a floating tree floating", function()
    tree("buffers", "float")
    mapping()
    assert.equals("filesystem", calls[1].source)
    assert.equals("float", calls[1].position)
  end)

  it("reports an unavailable explorer without throwing", function()
    package.loaded["neo-tree.command"] = nil
    package.preload["neo-tree.command"] = function()
      error("fixture: neo-tree missing")
    end
    assert.has_no.errors(mapping)
    assert.equals(1, #messages)
    assert.matches("Neo%-tree is unavailable", messages[1])
    assert.equals(0, #calls)
  end)

  it("reports an execution failure once without throwing", function()
    package.loaded["neo-tree.command"].execute = function()
      error("fixture: command failure")
    end
    assert.has_no.errors(mapping)
    assert.equals(1, #messages)
    assert.matches("fixture: command failure", messages[1])
  end)

  it("maps contextual help through Neo-tree's native help command", function()
    assert.equals("show_help", spec.opts.window.mappings["<F1>"])
    assert.equals("show_help", spec.opts.window.mappings["g?"])
  end)
end)
