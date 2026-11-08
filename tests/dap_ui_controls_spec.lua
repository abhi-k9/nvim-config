describe("local DAP control lifecycle adapter", function()
  local fix = require("config.dap_ui_controls")
  local saved_controls, saved_dap, controls, dap, buffers, windows, editor
  local group = "user_dapui_controls"

  local function flush()
    local done = false
    vim.schedule(function()
      done = true
    end)
    assert.is_true(vim.wait(200, function()
      return done
    end, 1))
  end
  local function buffer()
    local buf = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = buf
    return buf
  end
  local function show(buf)
    vim.cmd.vsplit()
    local win = vim.api.nvim_get_current_win()
    windows[#windows + 1] = win
    vim.api.nvim_win_set_buf(win, buf)
    return win
  end
  local function enable(buf)
    controls.enable_controls({
      buffer = function()
        return buf
      end,
    })
  end
  local function commands()
    return vim.api.nvim_get_autocmds({ group = group })
  end

  before_each(function()
    fix.detach()
    saved_controls, saved_dap = package.loaded["dapui.controls"], package.loaded.dap
    buffers, windows, editor = {}, {}, vim.api.nvim_get_current_win()
    controls = {
      enable_controls = function()
        error("native registration unexpectedly used")
      end,
      refresh_control_panel = function() end,
      controls = function(focused)
        return focused and "active toolbar" or "inactive toolbar"
      end,
    }
    dap = {
      listeners = {
        after = setmetatable({}, {
          __index = function(self, key)
            local list = {}
            rawset(self, key, list)
            return list
          end,
        }),
      },
    }
    package.loaded["dapui.controls"], package.loaded.dap = controls, dap
  end)

  after_each(function()
    fix.detach()
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    vim.api.nvim_set_current_win(editor)
    flush()
    package.loaded["dapui.controls"], package.loaded.dap = saved_controls, saved_dap
  end)

  it("keeps one handler set across repeated opens and preserves rendering", function()
    local render = controls.controls
    assert.is_true(fix.attach())
    local wrapper = controls.enable_controls
    assert.is_true(fix.attach())
    assert.equals(wrapper, controls.enable_controls)
    assert.equals(render, controls.controls)
    local buf, count = buffer()
    for _ = 1, 5 do
      local win = show(buf)
      enable(buf)
      controls.refresh_control_panel()
      assert.equals("active toolbar", vim.wo[win].winbar)
      count = count or #commands()
      assert.equals(count, #commands())
      vim.api.nvim_win_close(win, true)
      flush()
    end
    assert.equals(6, count)
  end)

  it("refreshes button states on focus and DAP events in every showing window", function()
    assert.is_true(fix.attach())
    local buf = buffer()
    local first = show(buf)
    enable(buf)
    local second = show(buf)
    assert.equals("inactive toolbar", vim.wo[first].winbar)
    assert.equals("active toolbar", vim.wo[second].winbar)
    controls.controls = function(focused)
      return focused and "running" or "running elsewhere"
    end
    dap.listeners.after.event_continued[group]()
    assert.equals("running elsewhere", vim.wo[first].winbar)
    assert.equals("running", vim.wo[second].winbar)
    vim.api.nvim_set_current_win(first)
    assert.equals("running", vim.wo[first].winbar)
    assert.equals("running elsewhere", vim.wo[second].winbar)
  end)

  it("restores a reused window's original bar without repainting unrelated buffers", function()
    assert.is_true(fix.attach())
    local buf = buffer()
    local win = show(buf)
    vim.wo[win].winbar = "original"
    enable(buf)
    vim.api.nvim_win_set_buf(win, buffer())
    flush()
    assert.equals("", vim.wo[win].winbar)
    dap.listeners.after.event_stopped[group]()
    assert.equals("", vim.wo[win].winbar)
    fix.detach()
    vim.api.nvim_win_set_buf(win, buf)
    assert.equals("original", vim.wo[win].winbar)
  end)

  it("rebinds a wiped or changed buffer without stale deferred registration", function()
    assert.is_true(fix.attach())
    local old = buffer()
    show(old)
    enable(old)
    vim.api.nvim_buf_delete(old, { force = true })
    assert.equals(0, #commands())
    local replacement = buffer()
    local win = show(replacement)
    enable(replacement)
    flush()
    assert.equals("active toolbar", vim.wo[win].winbar)
    for _, command in ipairs(commands()) do
      assert.equals(replacement, command.buffer)
    end
    local changed = buffer()
    enable(changed)
    assert.equals(6, #commands())
    for _, command in ipairs(commands()) do
      assert.equals(changed, command.buffer)
    end
    assert.not_equals("active toolbar", vim.wo[win].winbar)
  end)

  it("cleans a buffer replaced in a window that is not current", function()
    assert.is_true(fix.attach())
    local buf = buffer()
    local win = show(buf)
    vim.wo[win].winbar = "original"
    enable(buf)
    vim.api.nvim_set_current_win(editor)
    vim.api.nvim_win_set_buf(win, buffer())
    flush()
    fix.detach()
    vim.api.nvim_win_set_buf(win, buf)
    assert.equals("original", vim.wo[win].winbar)
  end)

  it("detaches queued work, restores owned hooks and can attach again", function()
    local original_enable, original_refresh =
      controls.enable_controls, controls.refresh_control_panel
    local previous = function() end
    dap.listeners.after.event_stopped[group] = previous
    assert.is_true(fix.attach())
    local buf = buffer()
    local win = show(buf)
    vim.wo[win].winbar = "original"
    enable(buf)
    vim.api.nvim_win_set_buf(win, buffer())
    fix.detach()
    flush()
    assert.equals("", vim.wo[win].winbar)
    vim.api.nvim_win_set_buf(win, buf)
    assert.equals("original", vim.wo[win].winbar)
    assert.equals(original_enable, controls.enable_controls)
    assert.equals(original_refresh, controls.refresh_control_panel)
    assert.equals(previous, dap.listeners.after.event_stopped[group])
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = group }))
    assert.is_true(fix.attach())
    enable(buf)
    assert.equals(6, #commands())
  end)

  it("preserves later user overrides when detached", function()
    assert.is_true(fix.attach())
    local buf = buffer()
    local win = show(buf)
    enable(buf)
    local override = function() end
    controls.enable_controls, controls.refresh_control_panel = override, override
    dap.listeners.after.event_stopped[group] = override
    vim.wo[win].winbar = "user override"
    fix.detach()
    assert.equals(override, controls.enable_controls)
    assert.equals(override, controls.refresh_control_panel)
    assert.equals(override, dap.listeners.after.event_stopped[group])
    assert.equals("user override", vim.wo[win].winbar)
  end)

  it("skips missing or incompatible modules without loading optional plugins", function()
    package.loaded["dapui.controls"] = nil
    assert.is_false(fix.attach())
    assert.is_nil(package.loaded["dapui.controls"])
    package.loaded["dapui.controls"] = controls
    package.loaded.dap = nil
    assert.is_false(fix.attach())
    package.loaded.dap = dap
    controls.controls = nil
    assert.is_false(fix.attach())
    controls.controls = function()
      return ""
    end
    dap.listeners.after = {}
    assert.is_false(fix.attach())
  end)

  it("leaves an already active upstream lifecycle alone", function()
    local native = vim.api.nvim_create_augroup("DAPUIControls", { clear = true })
    vim.api.nvim_create_autocmd("BufWinEnter", { group = native, callback = function() end })
    local original = controls.enable_controls
    local attached = fix.attach()
    vim.api.nvim_del_augroup_by_id(native)
    assert.is_false(attached)
    assert.equals(original, controls.enable_controls)
  end)
end)
