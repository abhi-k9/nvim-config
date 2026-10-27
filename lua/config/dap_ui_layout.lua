-- DAP UI can redistribute fixed column widths while opening/closing nested
-- layouts. Protect live widths per operation, without a stale session snapshot.
local M = {}
local owners = setmetatable({}, { __mode = "k" })

local function panel_windows()
  local result, windows = {}, package.loaded["dapui.windows"]
  -- Use window identity: custom elements need not have a dapui filetype.
  for _, layout in ipairs(windows and windows.layouts or {}) do
    for _, win in pairs(layout.opened_wins) do
      result[win] = true
    end
  end
  return result
end

local function without_panels(node, panels)
  if node[1] == "leaf" then return not panels[node[2]] and node or nil end
  local children = {}
  for _, child in ipairs(node[2]) do
    local remaining = without_panels(child, panels)
    if remaining then children[#children + 1] = remaining end
  end
  if #children == 1 then return children[1] end
  if #children > 1 then return { node[1], children } end
end

local function fixed(node)
  if node[1] == "leaf" then return vim.wo[node[2]].winfixwidth, true end
  local single_column = node[1] == "col"
  for _, child in ipairs(node[2]) do
    local child_fixed, child_column = fixed(child)
    if not child_fixed then return false end
    single_column = single_column and child_column
  end
  return true, single_column
end

local function capture(node, widths, column)
  if node[1] == "leaf" then
    if column then
      local win = node[2]
      widths[win] = {
        buf = vim.api.nvim_win_get_buf(win),
        tab = vim.api.nvim_win_get_tabpage(win),
        width = vim.api.nvim_win_get_width(win),
      }
    end
    return
  end
  for _, child in ipairs(node[2]) do
    local child_fixed, child_column = fixed(child)
    if column then
      capture(child, widths, true)
    elseif node[1] == "row" and child_fixed then
      -- A compound grid of fixed windows has coupled inner/outer widths.
      -- Leave it to Neovim rather than impose contradictory per-leaf sizes.
      if child_column then capture(child, widths, true) end
    else
      capture(child, widths, false)
    end
  end
end

local function columns()
  local widths, panels = {}, panel_windows()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local layout = without_panels(vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tab)), panels)
    -- A horizontal panel sharing its width with a flexible editor is not an
    -- independent fixed column. Floats/external windows are absent from winlayout.
    if layout then capture(layout, widths, false) end
  end
  return widths
end

local function restore(widths)
  local panels = panel_windows()
  for win, saved in pairs(widths) do
    if
      vim.api.nvim_win_is_valid(win)
      and not panels[win]
      and vim.api.nvim_win_get_buf(win) == saved.buf
      and vim.api.nvim_win_get_tabpage(win) == saved.tab
      and vim.wo[win].winfixwidth
      and vim.api.nvim_win_get_width(win) ~= saved.width
    then
      -- Neovim clamps requests when the available space cannot fit every column.
      local config = vim.api.nvim_win_get_config(win)
      if config.relative == "" and not config.external then
        pcall(vim.api.nvim_win_set_width, win, saved.width)
      end
    end
  end
end

function M.attach(ui)
  if owners[ui] then return end
  for _, name in ipairs({ "open", "close", "toggle" }) do
    local original = ui[name]
    if type(original) == "function" then
      local wrapper = function(...)
        local widths = columns()
        local result = vim.F.pack_len(pcall(original, ...))
        restore(widths)
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
      end
      ui[name] = wrapper
    end
  end
  -- Repeated setup must not stack wrappers or replace a later user override.
  owners[ui] = true
end

return M
