-- lua/plugins/explorer.lua
--
-- neo-tree.nvim — file explorer in a side panel (or float).
-- Press <leader>e to toggle. Inside the tree:
--   a   = add file (end with `/` to make a dir)     d = delete   r = rename
--   y/x/p = COPY/cut/paste FILES via neo-tree's OWN clipboard (y, then
--           navigate to a dir, then p duplicates the file). This is NOT
--           the system clipboard or a register — you can't paste it into
--           a buffer; <C-r> clears it. To copy a path as TEXT, use Y.
--   Y / <C-S-c> = copy the node's absolute path to the "+" register
--           (custom; mapped below). <C-S-c> is usually swallowed by the
--           terminal's own copy shortcut, so Y is the dependable one.
--   / = fuzzy-filter visible items     D = fuzzy-find directories
--   H = toggle hidden files            <CR>/l = open       h = close node
--   s/S = open in vsplit/split         P = toggle floating preview
--   <C-s> = quick-jump (labels each node; type a label to jump+open/toggle)
--   <Tab> = multi-select toggle        <C-;> = clear selection
--   ?   = full keymap help
-- (<C-s> quick-jump and <Tab>/<C-;> select are neo-tree defaults that only
-- exist on branch="main", set below. Many terminals don't transmit <C-;>.)
--
-- We also map <leader>E to "reveal current file in tree", which is the
-- single most-used shortcut once you have many buffers open.

-- Copy the absolute path of the node under the cursor to the system
-- clipboard ("+") as plain TEXT. This is deliberately different from
-- neo-tree's `y` (copy_to_clipboard), which stages a FILE-copy in
-- neo-tree's OWN in-memory clipboard for a later `p` and never touches
-- the OS clipboard or any register. Bound to <C-S-c> and Y in
-- window.mappings below. (state.tree:get_node() is the node under the
-- cursor; for the filesystem source its id is the absolute path.)
local function copy_node_path(state)
  local node = state.tree:get_node()
  if not node then return end
  local path = node:get_id()
  vim.fn.setreg("+", path)
  vim.notify("Copied path: " .. path, vim.log.levels.INFO)
end

-- Buffers view `d` / `bd`. neo-tree's stock buffer_delete calls
-- nvim_buf_delete directly: that closes every window showing the buffer
-- (:h :bdelete) and, on a modified buffer, throws E89 out of the mapping.
-- Route it through the same helper as <leader>bd, bufferline and both
-- fuzzy-finder pickers: layout kept, dirty buffers skipped with a
-- message, terminals forced.
local function buffer_delete_keep_windows(state)
  local node = state.tree:get_node()
  local bufnr = node and node.extra and node.extra.bufnr
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then return end
  local util = require("config.util")
  util.notify_undeleted(bufnr, util.delete_buffer_keep_windows(bufnr))
  require("neo-tree.sources.manager").refresh("buffers")
end

return {
  "nvim-neo-tree/neo-tree.nvim",
  -- `main`, NOT `v3.x`: the quick_jump / select / clear_selection commands
  -- behind the default <C-s> / <Tab> / <C-;> keys only exist on neo-tree's
  -- main branch (v3.x predates them). main is the active DEVELOPMENT
  -- branch — less frozen than v3.x — so if a regression appears, pin back
  -- to `branch = "v3.x"` and lose those three keys. After changing this
  -- line, run :Lazy sync to re-checkout the branch (a plain restart won't
  -- switch it).
  branch = "main",
  cmd = "Neotree",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim", -- UI primitives required by neo-tree
  },
  keys = {
    -- stylua: ignore start
    { "<leader>e", "<cmd>Neotree toggle<cr>",            desc = "Explorer toggle" },
    { "<leader>E", "<cmd>Neotree reveal<cr>",            desc = "Explorer reveal current file" },
    { "<leader>fe", "<cmd>Neotree focus<cr>",            desc = "Explorer focus" },
    { "<leader>ge", "<cmd>Neotree git_status<cr>",       desc = "Explorer: git status" },
    { "<leader>be", "<cmd>Neotree buffers<cr>",          desc = "Explorer: open buffers" },
    -- stylua: ignore end
  },
  -- Auto-open neo-tree if Neovim is launched with a directory argument
  -- (e.g. `nvim .`). Without this, you'd get an empty buffer instead.
  init = function()
    vim.api.nvim_create_autocmd("BufEnter", {
      group = vim.api.nvim_create_augroup("user_neotree_dir", { clear = true }),
      desc = "Open neo-tree when nvim is launched on a directory",
      once = true, -- ← only fires once: at startup, or after a reload
      callback = function()
        -- The `isdirectory(f) == 1` guard makes this reload-safe. On
        -- `:Lazy reload neo-tree.nvim` the augroup is cleared and this
        -- autocmd re-registers, then fires on the NEXT BufEnter — which
        -- is almost always a regular file, not a directory. The guard
        -- turns that into a no-op instead of accidentally popping
        -- neo-tree open mid-session.
        local f = vim.fn.argv(0)
        if f ~= "" and vim.fn.isdirectory(f) == 1 then
          vim.schedule(function() -- ← defer until the event loop is idle
            require("neo-tree.command").execute({
              action = "show",
              source = "filesystem",
              position = "left",
            })
          end)
        end
      end,
    })
  end,
  opts = {
    -- Off (neo-tree's default, pinned for visibility), deliberately ("quit
    -- nvim when neo-tree is the last window standing"). Its upstream
    -- implementation has a race that produces a broken layout:
    --
    --   neo-tree implements it as a WinClosed autocmd (plugin/neo-tree.lua)
    --   that, when the tree is the last pane and a modified buffer exists,
    --   SCHEDULES "warn + vsplit + show the modified buffer". Two flaws:
    --   (1) it fires for every WinClosed, including floating windows, and
    --   (2) the scheduled callback never re-checks the layout — it splits
    --   whatever window is current when it finally runs.
    --
    --   incline.nvim (ui.lua) tears down its floating winbar with a
    --   debounced nvim_win_close after the file window closes — a SECOND
    --   WinClosed. If that lands while the tree is still the only pane
    --   (timing-dependent; more likely under load), the handler schedules
    --   a second pass, which splits the just-reopened file window:
    --   you end up with [tree | file | file], the same modified buffer
    --   twice, and two "Cannot close because one of the files is
    --   modified" warnings. Reproduced end-to-end on nvim 0.12.2 with
    --   this config; the trigger is ":q on the last file window while
    --   any modified buffer exists" (classically: a readonly buffer you
    --   forced edits into).
    --
    -- Trade-off accepted: :q on the last file window now leaves neo-tree
    -- open as the sole window — quit with :q again (or :qa). What we keep:
    -- no surprise triple-split, and no surprise nvim-exit when a buffer
    -- drop leaves the tree last (<leader>bd never did that anyway; see
    -- smart_bdelete in lua/config/keymaps.lua). If the upstream handler
    -- gains re-validation, this can go back to true.
    close_if_last_window = false,
    enable_diagnostics = true, -- show LSP errors/warnings on file rows
    enable_git_status = true,
    popup_border_style = "rounded",
    -- Visual tweaks. Symbols are Nerd Font glyphs — they render as boxes if
    -- you don't have a Nerd Font set in your terminal.
    default_component_configs = {
      indent = { with_markers = true, with_expanders = true },
      modified = { symbol = "●" },
      git_status = {
        symbols = {
          -- gitsigns already shows +/-/~ in the buffer's sign column, so
          -- we leave neo-tree's `added` blank to avoid duplication. The
          -- other symbols keep neo-tree's defaults.
          added = "",
        },
      },
    },
    window = {
      width = 32, -- columns; 32 is a comfortable default
      mappings = {
        -- A handful of muscle-memory overrides for h/j/k/l navigation.
        -- neo-tree's defaults work fine if you remove these.
        ["<space>"] = "none", -- free <space> so leader still works in the tree
        ["l"] = "open",
        ["h"] = "close_node",

        -- ---- copy path-as-text (custom; branch-independent) ----
        -- <C-S-c> follows the Windows "copy path" convention; Y is a
        -- reliable fallback. TERMINAL CAVEAT: most terminals (Windows
        -- Terminal included) grab Ctrl+Shift+C as their OWN copy shortcut
        -- and never pass it to Neovim, so <C-S-c> usually only fires in GUI
        -- builds (neovide). Y works everywhere.
        -- stylua: ignore start
        ["<C-S-c>"] = copy_node_path,
        ["Y"]       = copy_node_path,
        -- stylua: ignore end
      },
    },
    buffers = {
      window = {
        mappings = {
          -- stylua: ignore start
          ["d"]  = buffer_delete_keep_windows,
          ["bd"] = buffer_delete_keep_windows,
          -- stylua: ignore end
        },
      },
    },
    filesystem = {
      -- Show dotfiles and gitignored files by default; press `H` inside
      -- the tree to toggle hidden-file visibility on/off. Hard-hiding a
      -- few perennially-noisy names (DS_Store, thumbs.db, node_modules)
      -- keeps the tree readable in JS projects without affecting fuzzy
      -- finding (telescope/fzf-lua have their own ignore rules).
      filtered_items = {
        hide_dotfiles = false,
        hide_gitignored = false,
        hide_by_name = { ".DS_Store", "thumbs.db", "node_modules" },
      },
      -- Keep the tree's cursor on the file you're currently editing.
      follow_current_file = { enabled = true },
      -- Use libuv's filesystem watcher so external file changes
      -- (e.g. `git checkout` from a terminal) refresh the tree in real
      -- time, without a manual `r`.
      use_libuv_file_watcher = true,
    },
  },
}
