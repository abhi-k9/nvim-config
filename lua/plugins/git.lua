-- lua/plugins/git.lua
--
-- Git integration. Two plugins that don't overlap:
--   * gitsigns.nvim – the gutter signs + inline hunk operations
--   * diffview+    – proper diff/merge UI for `:DiffviewOpen` (diffview-plus.nvim)

local icons = require("config.icons")

return {
  -- -------------------------------------------------------------------------
  -- gitsigns — the most-used git plugin. Sign column markers, blame,
  -- stage/reset/preview hunks, etc.
  -- -------------------------------------------------------------------------
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        -- stylua: ignore start
        add          = { text = "▎" },
        change       = { text = "▎" },
        delete       = { text = icons.misc.git_delete },
        topdelete    = { text = icons.misc.git_delete },
        changedelete = { text = "▎" },
        untracked    = { text = "▎" },
        -- stylua: ignore end
      },
      current_line_blame = false, -- toggle with the keymap below
      current_line_blame_opts = { delay = 500 },

      on_attach = function(buffer)
        local gs = package.loaded.gitsigns
        local function map(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { buffer = buffer, desc = "Git: " .. desc })
        end

        -- Navigation between hunks. The function form respects diff-mode and
        -- uses the modern `nav_hunk("next" | "prev")` API; `next_hunk()` and
        -- `prev_hunk()` are deprecated.
        map("n", "]h", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end, "Next hunk")
        map("n", "[h", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end, "Prev hunk")

        -- Stage / reset hunks. Works in both normal and visual mode.
        -- `stage_hunk` is itself a toggle on already-staged hunks, which
        -- replaces the deprecated `undo_stage_hunk`.
        -- stylua: ignore start
        map({ "n", "x" }, "<leader>gs", ":Gitsigns stage_hunk<CR>",      "Stage hunk (toggle)")
        map({ "n", "x" }, "<leader>gr", ":Gitsigns reset_hunk<CR>",      "Reset hunk")
        map("n", "<leader>gS", gs.stage_buffer,                          "Stage buffer")
        map("n", "<leader>gR", gs.reset_buffer,                          "Reset buffer")
        map("n", "<leader>gp", gs.preview_hunk_inline,                   "Preview hunk")
        map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, "Blame line")
        map("n", "<leader>gB", gs.toggle_current_line_blame,             "Toggle line blame")
        -- stylua: ignore end

        -- Text object: `ih` selects the current hunk.
        map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "Select hunk")
      end,
    },
  },

  -- -------------------------------------------------------------------------
  -- diffview+ (dlyongemallo/diffview-plus.nvim) — full diff/merge UI. A
  -- maintained fork of sindrets/diffview.nvim (frozen since 2024): same
  -- commands and `require("diffview")` module, plus multi-file selection,
  -- file history pinned to the working copy, the worktree overview and
  -- out-of-git file/dir diffs. `:DiffviewOpen` shows the working tree vs
  -- the index, `:DiffviewFileHistory %` the history of the current file.
  -- -------------------------------------------------------------------------
  {
    "dlyongemallo/diffview-plus.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewToggle",
      "DiffviewClose",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
      "DiffviewFileHistory",
      "DiffviewRefresh",
      "DiffviewDiffFiles",
      "DiffviewDiffDirs",
      "DiffviewMergeFiles",
      "DiffviewWorktreeOverview",
      "DiffviewLog",
    },
    keys = {
      -- stylua: ignore start
      { "<leader>gd", "<cmd>DiffviewToggle<cr>",                   desc = "Diffview: toggle" },
      { "<leader>gD", "<cmd>DiffviewClose<cr>",                    desc = "Diffview: close" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>",            desc = "File history (current file)" },
      { "<leader>gh", ":DiffviewFileHistory<cr>", mode = "x",      desc = "File history (selected lines)" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>",              desc = "File history (repo)" },
      { "<leader>gl", "<cmd>DiffviewFileHistory --pin-local %<cr>", desc = "File history vs working copy" },
      { "<leader>gw", "<cmd>DiffviewWorktreeOverview<cr>",         desc = "Git worktrees overview" },
      -- stylua: ignore end
    },
    opts = {
      enhanced_diff_hl = true, -- punchier highlighting for +/- lines
      view = {
        -- 3-way merge view for resolving conflicts: shows OURS / THEIRS /
        -- BASE alongside the merged result, instead of the unhelpful
        -- ascii-only <<<<<<< / ======= / >>>>>>> markers in the file.
        merge_tool = {
          layout = "diff3_mixed",
          disable_diagnostics = true, -- LSP errors mid-conflict are noise
        },
      },
      file_panel = {
        listing_style = "tree", -- "list" is flatter; tree is easier to scan
        win_config = { width = 35 },
      },
    },
  },
}
