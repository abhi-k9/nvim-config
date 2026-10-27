-- lua/plugins/which-key.lua
--
-- which-key.nvim — pops up a hint window after you start a leader keymap.
-- Indispensable for discovering your own keybindings.
--
-- This file does TWO things:
--   1. Configures which-key itself.
--   2. Registers "groups" so the popup shows nice category labels for
--      `<leader>f`, `<leader>g`, etc., instead of just listing leaves.

local icon_options = { mappings = require("config.settings").get("ui.icons", true) ~= false }
if not icon_options.mappings then
  icon_options.keys = {}
  for _, key in ipairs({
    "Up",
    "Down",
    "Left",
    "Right",
    "C",
    "M",
    "D",
    "S",
    "CR",
    "Esc",
    "ScrollWheelDown",
    "ScrollWheelUp",
    "NL",
    "BS",
    "Space",
    "Tab",
  }) do
    icon_options.keys[key] = key .. " "
  end
  for number = 1, 12 do
    icon_options.keys["F" .. number] = "F" .. number
  end
end

return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    icons = icon_options,
    preset = "modern", -- modern | classic | helix
    -- Register the leader-key "namespaces". Each entry below tells
    -- which-key the human-readable name of a prefix. The actual keymaps
    -- still come from each plugin's own spec.
    spec = {
      { "<leader>b", group = "buffer" },
      { "<leader>c", group = "code" },
      { "<leader>d", group = "debug" },
      { "<leader>f", group = "find" },
      { "<leader>F", group = "fzf-lua" },
      { "<leader>g", group = "git" },
      { "<leader>l", group = "lsp" },
      { "<leader>s", group = "search/replace" },
      { "<leader>t", group = "terminal" },
      { "<leader>w", group = "window/session" },
      -- stylua: ignore start
      { "<leader>x", group = "diagnostics/trouble" },
      { "[",         group = "prev" },
      { "]",         group = "next" },
      { "g",         group = "goto" },
      { "gz",        group = "surround" },
      -- stylua: ignore end
    },
  },
  keys = {
    -- Show buffer-local keymaps (LSP, plugin-attached) for the current buffer.
    {
      "<leader>?",
      function()
        require("which-key").show({ global = false })
      end,
      desc = "Buffer keymaps",
    },
  },
}
