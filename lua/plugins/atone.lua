-- lua/plugins/atone.lua
--
-- atone.nvim — modern undo-tree visualizer.
--
-- Pressing <leader>u opens a side pane showing the buffer's full undo
-- *tree* (not just the linear history). Each node is a buffer state;
-- arrow / j / k walk between nodes, <CR> reverts the buffer to the node
-- under the cursor. A live diff pane shows what each node changed, with
-- treesitter-powered syntax highlighting and word-level inline diff.
--
-- With `undofile = true` the tree includes earlier sessions' edits.
--
-- Neovim 0.12 also ships a plain tree view (`:packadd nvim.undotree`, then
-- :Undotree); atone is kept for the diff pane and the node marks.
--
-- Default in-tree keymaps (set by the plugin once :Atone runs; see the
-- plugin README for the full table):
--   j / k         move between nodes
--   <CR>          revert buffer to the node under cursor
--   u / <C-r>     undo / redo one step in the attached buffer
--   gd            toggle a centred floating diff window
--   m / x         set / delete a node mark
--   '             jump to mark slot
--   s             open mark picker (fuzzy find)
--   q / <C-c>     close all atone panes

return {
  {
    "XXiaoA/atone.nvim",
    -- Lazy-load until first :Atone command or the <leader>u keymap.
    -- No startup cost — the plugin only loads the first time you open
    -- the tree.
    cmd = "Atone",
    keys = {
      { "<leader>u", "<cmd>Atone toggle<cr>", desc = "Undo tree (atone)" },
    },
    ---@module "atone"
    ---@type AtoneConfig
    opts = {
      -- Empty: atone's defaults are good. Customize here later if you
      -- want a different node-label format, different in-pane keymaps,
      -- or different highlight groups (see :h atone.txt after install).
    },
  },
}
