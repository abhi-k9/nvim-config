-- lua/plugins/trouble.lua
--
-- trouble.nvim — a much better quickfix/diagnostics panel.
-- Lists LSP diagnostics, references, definitions, todo-comments, the
-- quickfix and loclist, etc. in a single navigable window.

return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    -- stylua: ignore start
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",                            desc = "Diagnostics" },
    { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",               desc = "Buffer diagnostics" },
    { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>",                    desc = "Symbols (LSP)" },
    { "<leader>xl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",     desc = "LSP refs / defs / impl" },
    { "<leader>xL", "<cmd>Trouble loclist toggle<cr>",                                desc = "Location list" },
    { "<leader>xq", "<cmd>Trouble qflist toggle<cr>",                                 desc = "Quickfix list" },
    -- stylua: ignore end

    -- Smart [q / ]q: jump to next/prev item in whatever Trouble list is
    -- open, falling back to quickfix. The quickfix fallback is wrapped in
    -- pcall because :cnext/:cprev raise E42 ("No Errors") when the qflist
    -- is empty, which makes the keymap feel broken.
    {
      "[q",
      function()
        if require("trouble").is_open() then
          require("trouble").prev({ jump = true })
        else
          -- vim.v.count1: `3[q` moves three entries, like :3cprev.
          local ok, err = pcall(vim.cmd.cprev, { count = vim.v.count1 })
          if not ok then vim.notify(err, vim.log.levels.INFO) end
        end
      end,
      desc = "Prev trouble/quickfix item",
    },
    {
      "]q",
      function()
        if require("trouble").is_open() then
          require("trouble").next({ jump = true })
        else
          local ok, err = pcall(vim.cmd.cnext, { count = vim.v.count1 })
          if not ok then vim.notify(err, vim.log.levels.INFO) end
        end
      end,
      desc = "Next trouble/quickfix item",
    },
  },
  -- Gutter icons come from vim.diagnostic's sign config (lsp.lua). The
  -- preview keeps trouble's default: the main editor window, with an
  -- ephemeral buffer that stays out of :ls.
  opts = {
    auto_close = true, -- close the panel when its list becomes empty
    focus = true, -- jump cursor into the panel when it opens
  },
}
