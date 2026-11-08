-- Temporary compatibility adapter for nvim-dap-ui cc9dd33's controls.lua:
-- enable_controls registers another WinClosed/BufWinLeave pair on each reopen.
-- Keep upstream rendering/click actions; own only registration and window state.
-- Remove with its attach call once the upstream lifecycle regression passes.
local M = {}
local owner
local group_name = "user_dapui_controls"
local events = {
  "continue",
  "terminate",
  "restart",
  "disconnect",
  "event_terminated",
  "event_exited",
  "event_stopped",
  "threads",
  "event_continued",
}

local function populated_group(name)
  local ok, commands = pcall(vim.api.nvim_get_autocmds, { group = name })
  return ok and #commands > 0
end

function M.detach()
  if not owner then return end
  local cleanup = owner
  owner = nil
  cleanup()
end

function M.attach()
  if owner then return true end
  -- Called after dapui.setup, before its first open. Never load optional plugins
  -- here, or compete with an already active native/third-party control owner.
  local controls, dap = package.loaded["dapui.controls"], package.loaded.dap
  if
    type(controls) ~= "table"
    or type(controls.enable_controls) ~= "function"
    or type(controls.refresh_control_panel) ~= "function"
    or type(controls.controls) ~= "function"
    or type(dap) ~= "table"
    or type(dap.listeners) ~= "table"
    or type(dap.listeners.after) ~= "table"
    or populated_group("DAPUIControls")
    or populated_group(group_name)
  then
    return false
  end
  local listeners = {}
  for _, event in ipairs(events) do
    local list = dap.listeners.after[event]
    if type(list) ~= "table" then return false end
    listeners[#listeners + 1] = { list = list, previous = list[group_name] }
  end

  local original_enable, original_refresh = controls.enable_controls, controls.refresh_control_panel
  local buffer, group, queued
  local active, bars = true, {}
  local function restore(win)
    local saved = bars[win]
    if
      vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == saved.buffer
      and vim.wo[win].winbar == saved.rendered
    then
      vim.wo[win].winbar = saved.original
    end
    bars[win] = nil
  end
  local function paint(win, focused)
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buffer then return end
    local bar = controls.controls(focused)
    bars[win] = bars[win] or { original = vim.wo[win].winbar, buffer = buffer }
    bars[win].rendered = bar
    vim.wo[win].winbar = bar
  end
  local function refresh()
    if not active then return end
    for win in pairs(bars) do
      if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buffer then
        restore(win)
      end
    end
    if not buffer or not vim.api.nvim_buf_is_valid(buffer) then return end
    for _, win in ipairs(vim.fn.win_findbuf(buffer)) do
      paint(win, win == vim.api.nvim_get_current_win())
    end
  end
  local function schedule_refresh()
    if queued then return end
    queued = true
    vim.schedule(function()
      queued = false
      -- Inspect current ownership after BufWinLeave/BufWipeout complete, rather
      -- than capture an obsolete buffer or recreate one during repeated setup.
      refresh()
    end)
  end
  local function enable(element)
    if type(element) ~= "table" or type(element.buffer) ~= "function" then return end
    local next_buffer = element.buffer()
    if type(next_buffer) ~= "number" or not vim.api.nvim_buf_is_valid(next_buffer) then return end
    if buffer == next_buffer then return end
    for win in pairs(bars) do
      restore(win)
    end
    buffer = next_buffer
    group = vim.api.nvim_create_augroup(group_name, { clear = true })
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
      group = group,
      buffer = buffer,
      callback = refresh,
    })
    vim.api.nvim_create_autocmd("WinLeave", {
      group = group,
      buffer = buffer,
      callback = function()
        paint(vim.api.nvim_get_current_win(), false)
      end,
    })
    vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave" }, {
      group = group,
      buffer = buffer,
      callback = function()
        -- Window options are saved before BufWinLeave. Restore on BufLeave too;
        -- neither event guarantees that the affected window is current.
        for win in pairs(bars) do
          restore(win)
        end
        schedule_refresh()
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = group,
      buffer = buffer,
      callback = function()
        buffer = nil
        vim.api.nvim_clear_autocmds({ group = group })
        schedule_refresh()
      end,
    })
    for _, listener in ipairs(listeners) do
      listener.list[group_name] = refresh
    end
    refresh()
  end

  controls.enable_controls, controls.refresh_control_panel = enable, refresh
  owner = function()
    active = false
    if group then pcall(vim.api.nvim_del_augroup_by_id, group) end
    for win in pairs(bars) do
      restore(win)
    end
    for _, listener in ipairs(listeners) do
      if listener.list[group_name] == refresh then listener.list[group_name] = listener.previous end
    end
    if controls.enable_controls == enable then controls.enable_controls = original_enable end
    if controls.refresh_control_panel == refresh then
      controls.refresh_control_panel = original_refresh
    end
  end
  return true
end

return M
