-- DAP UI closes nested layouts in an order that can give a removed sidebar's
-- width to adjacent Neo-tree, even with winfixwidth. Protect the live width at
-- each synchronous operation rather than keeping an obsolete session snapshot.
local M = {}
local owners = setmetatable({}, { __mode = "k" })

local function sidebars()
  local result = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local position = vim.b[buf].neo_tree_position
    local config = vim.api.nvim_win_get_config(win)
    if
      vim.bo[buf].filetype == "neo-tree"
      and (position == "left" or position == "right")
      and config.relative == ""
      and not config.external
    then
      result[win] = { buf = buf, position = position, width = vim.api.nvim_win_get_width(win) }
    end
  end
  return result
end

local function restore(widths)
  for win, saved in pairs(widths) do
    if
      vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == saved.buf
      and vim.bo[saved.buf].filetype == "neo-tree"
      and vim.b[saved.buf].neo_tree_position == saved.position
      and vim.api.nvim_win_get_width(win) > saved.width
    then
      -- Narrow screens may need to shrink a sidebar. Prevent unrequested
      -- growth without forcing the old width back into a constrained layout.
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
        local widths = sidebars()
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
