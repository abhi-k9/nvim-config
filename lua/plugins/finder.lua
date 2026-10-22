-- lua/plugins/finder.lua
--
-- Two fuzzy finders side-by-side. Pick a favorite over time; for now:
--   <leader>f...   → telescope (lua-native, hugely extensible)
--   <leader>F...   → fzf-lua   (uses real fzf binary, snappier on huge repos)
--
-- Telescope shines for things like LSP picker UIs, diagnostics, and
-- extensions (todo-comments, ui-select, etc.). fzf-lua wins on a 100k-file
-- monorepo where telescope's pure-lua sorter starts to chug.

-- Telescope buffers-picker delete action (<C-d> / <M-d>). Collect the
-- targets, hand them to the shared helper, then drop exactly the rows
-- whose buffers are gone (skipped/dirty ones stay listed).
local function picker_delete_buffers(prompt_bufnr)
  local state = require("telescope.actions.state")
  local picker = state.get_current_picker(prompt_bufnr)
  local targets = picker:get_multi_selection()
  if #targets == 0 then
    local entry = state.get_selected_entry()
    if not entry then return end
    targets = { entry }
  end
  local bufs = {}
  for _, entry in ipairs(targets) do
    bufs[#bufs + 1] = entry.bufnr
  end
  require("config.util").delete_buffers_from_picker(bufs)
  picker:delete_selection(function(selection)
    local b = selection.bufnr
    return not (vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted)
  end)
end

-- fzf-lua ctrl-x for the buffers and tabs pickers (same shared helper).
local fzf_delete_buffers = {
  fn = function(selected, opts)
    local fzf_path = require("fzf-lua.path")
    local bufs = {}
    for _, sel in ipairs(selected) do
      bufs[#bufs + 1] = fzf_path.entry_to_file(sel, opts).bufnr
    end
    require("config.util").delete_buffers_from_picker(bufs)
  end,
  reload = true,
}

return {
  -- -------------------------------------------------------------------------
  -- telescope.nvim
  -- -------------------------------------------------------------------------
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- Native C sorter; massively speeds up the matching algorithm. Built
      -- at install/update time. Rather than guess by OS, pick whichever build
      -- toolchain is available: prefer `make` (cc on Unix, gcc on Windows),
      -- else fall back to `cmake` (needs CMake + a C toolchain,
      -- e.g. the MSVC Build Tools on Windows where `make` is usually absent).
      -- Detected when the spec loads; if you install a tool later, restart
      -- Neovim so this re-evaluates, then :Lazy build telescope-fzf-native.
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = require("config.tooling").native_sorter_build(),
      },
      -- Routes vim.ui.select (code actions, etc.) through telescope.
      "nvim-telescope/telescope-ui-select.nvim",
    },
    -- telescope loads on first use, but vim.ui.select should reach
    -- ui-select from the start: the first call loads telescope (its config
    -- replaces vim.ui.select) and is then handed to the new function.
    init = function()
      local builtin_select = vim.ui.select
      local function stub(...)
        require("lazy").load({ plugins = { "telescope.nvim" } })
        if vim.ui.select == stub then vim.ui.select = builtin_select end
        return vim.ui.select(...)
      end
      vim.ui.select = stub
    end,
    keys = {
      -- Files / text
      -- stylua: ignore start
      { "<leader>ff", "<cmd>Telescope find_files<cr>",                desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",                 desc = "Live grep" },
      { "<leader>fw", "<cmd>Telescope grep_string<cr>",               desc = "Grep word under cursor" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>",                  desc = "Recent files" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>",                   desc = "Buffers (this tab)" },
      -- stylua: ignore end
      -- With scope.nvim, <leader>fb shows only the current tab's buffers.
      -- This reaches buffers across ALL tabs (scope's telescope extension
      -- is loaded on first use).
      {
        "<leader>fB",
        function()
          require("telescope").load_extension("scope")
          vim.cmd("Telescope scope buffers")
        end,
        desc = "Buffers (all tabs)",
      },
      { "<leader>f/", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Search in buffer" },
      -- Vim things
      -- stylua: ignore start
      { "<leader>fh", "<cmd>Telescope help_tags<cr>",                 desc = "Help tags" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>",                   desc = "Keymaps" },
      { "<leader>fc", "<cmd>Telescope commands<cr>",                  desc = "Commands" },
      { "<leader>fm", "<cmd>Telescope marks<cr>",                     desc = "Marks" },
      { "<leader>f:", "<cmd>Telescope command_history<cr>",           desc = "Command history" },
      { "<leader>fR", "<cmd>Telescope registers<cr>",                 desc = "Registers" },
      -- stylua: ignore end
      -- LSP / diagnostics
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document symbols" },
      {
        "<leader>fS",
        "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>",
        desc = "Workspace symbols",
      },
      { "<leader>fd", "<cmd>Telescope diagnostics<cr>", desc = "Diagnostics" },
      -- Git
      { "<leader>fG", "<cmd>Telescope git_status<cr>", desc = "Git status" },
    },
    opts = function()
      local actions = require("telescope.actions")
      return {
        defaults = {
          prompt_prefix = require("config.icons").misc.search .. " ",
          -- selection_caret drives the leading column on the SELECTED row.
          -- Telescope lays out every row assuming the caret occupies the
          -- same number of display CELLS as entry_prefix (2). When the
          -- caret is a multibyte Nerd-Font glyph, the cell width telescope
          -- computes (strdisplaywidth) can disagree with what the terminal
          -- actually renders for that glyph+font — and then the selected
          -- row's text shifts left/right by a cell relative to the others,
          -- and the drift smears as the cursor moves (you also see stray
          -- spaces / stacked multi markers). Using an ASCII caret of the
          -- same 2-cell width sidesteps the glyph-width ambiguity entirely
          -- and keeps every row aligned. entry_prefix and multi_icon are
          -- pinned to telescope's defaults explicitly so the
          -- caret/prefix/icon set stays width-consistent (2 / 2 / 1 cells).
          --
          -- Want the arrow glyph back? It works ONLY if your terminal +
          -- Nerd Font render it as exactly one cell; if rows drift, the
          -- font is the reason, not this config.
          -- stylua: ignore start
          selection_caret = "> ", -- 2 cells, cell-stable (ASCII)
          entry_prefix    = "  ", -- 2 cells
          multi_icon      = "+", -- 1 cell, replaces the caret's trailing space
          -- stylua: ignore end
          -- "smart" = shorten paths intelligently (drop common prefixes).
          path_display = { "smart" },
          -- "ascending" puts the prompt at the top and results below it,
          -- which matches fzf-lua's layout. The default "descending" feels
          -- inverted once you're used to terminal fuzzy finders.
          sorting_strategy = "ascending",
          layout_config = {
            -- stylua: ignore start
            horizontal = { prompt_position = "top", preview_width = 0.55 },
            vertical   = { mirror = false },
            -- stylua: ignore end
          },
          mappings = {
            i = {
              -- C-j / C-k for navigation are the dominant convention from
              -- vim/tmux/fzf — easier on the wrist than the default arrows.
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
              -- `false` removes telescope's default <C-u> binding so the
              -- standard "clear prompt to cursor" works as in any other
              -- terminal-like input.
              ["<C-u>"] = false,
              -- Single-press exit. Telescope normally requires Esc-Esc
              -- because the first Esc puts you in its normal-mode picker;
              -- override to close immediately, which feels less surprising.
              ["<Esc>"] = actions.close,
              -- Send all results to quickfix in one go, then open them
              -- (Trouble will pick up the qflist). Handy when a grep
              -- returns 100+ hits you want to walk through systematically.
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,

              -- <C-y> ("yank") yanks the highlighted entry's full absolute
              -- path to both the system clipboard and the unnamed register,
              -- and echoes it via vim.notify. Non-closing — you can keep
              -- navigating to peek at multiple paths.
              --
              -- Workaround for the buffers / git_files / git_status pickers
              -- where path_display is ignored and visible paths get truncated
              -- at the column edge. Press <C-y> on a row to see the full
              -- path; even if the notification is blocked by the picker UI,
              -- the path is in the clipboard, so you can close the picker
              -- and paste/view it.
              ["<C-y>"] = function(prompt_bufnr)
                local state = require("telescope.actions.state")
                local entry = state.get_selected_entry()
                if not entry then return end
                -- File/buffer entries can carry both an absolute `path` and
                -- a display-relative `filename`. Prefer the actual path;
                -- the picker's cwd can differ from the current window's.
                local raw = entry.path or entry.filename
                if type(raw) ~= "string" or raw == "" or raw == "[No Name]" then return end
                local full = raw
                if not raw:match("^%a[%w+.-]*://") then
                  if vim.fn.isabsolutepath(raw) == 0 then
                    local picker = state.get_current_picker(prompt_bufnr)
                    full = vim.fs.joinpath(entry.cwd or picker.cwd or vim.fn.getcwd(), raw)
                  end
                  full = vim.fn.fnamemodify(full, ":p")
                end
                vim.fn.setreg("+", full)
                vim.fn.setreg('"', full)
                vim.notify(full, vim.log.levels.INFO, { title = "Yanked path" })
              end,
            },
          },
          -- Always-ignored patterns. Deliberately minimal. The fd /
          -- ripgrep binaries behind find_files and live_grep already
          -- respect .gitignore, so build output (dist/, build/, target/)
          -- is normally excluded at the source. Telescope matches these
          -- as UNANCHORED Lua patterns against the full path, so a
          -- "build/" entry would hide sources under any */build*/
          -- directory and "%.lock" would hide Cargo.lock / flake.lock
          -- from grep. Keep only the two that are never useful in
          -- interactive finding; [/\\] because Windows paths use either
          -- separator.
          file_ignore_patterns = { "%.git[/\\]", "node_modules[/\\]" },
        },
        pickers = {
          -- Dotfiles are shown, but .git/ is excluded AT THE SOURCE: with
          -- hidden=true fd/rg otherwise list every object under .git/ and
          -- file_ignore_patterns throws them away afterwards (tens of
          -- thousands of entries on a large repo). nil command = telescope's
          -- own default search when neither tool is installed.
          find_files = {
            hidden = true,
            find_command = (function()
              for _, fd in ipairs({ "fd", "fdfind" }) do
                if vim.fn.executable(fd) == 1 then
                  return { fd, "--type", "f", "--hidden", "--exclude", ".git", "--color", "never" }
                end
              end
              if vim.fn.executable("rg") == 1 then
                return { "rg", "--files", "--hidden", "--glob", "!**/.git/*" }
              end
            end)(),
          },
          buffers = {
            -- <Tab>/<S-Tab> multi-select, then <C-d> deletes every selected
            -- buffer (or the highlighted one). Dirty buffers are skipped
            -- and keep their windows; the picker stays open with the
            -- deleted rows removed. The logic is shared with fzf-lua's <C-x>
            -- (util.delete_buffers_from_picker). <M-d> is telescope's own
            -- default for the stock actions.delete_buffer, which closes
            -- every window showing the buffer (:h :bdelete) — it is bound to
            -- the same safe action so there is no layout-breaking variant.
            mappings = {
              i = {
                ["<C-d>"] = picker_delete_buffers,
                ["<M-d>"] = picker_delete_buffers,
              },
              n = {
                ["<M-d>"] = picker_delete_buffers,
              },
            },
          },
        },
        extensions = {
          -- ui-select uses the "dropdown" theme — small popup near the
          -- cursor, no preview. Right for short choice lists (LSP code
          -- actions, refactor menus) where a full split would be overkill.
          ["ui-select"] = { require("telescope.themes").get_dropdown({}) },
          -- telescope-fzf-native: C sorter built via make or cmake,
          -- whichever is on PATH (see the dependency spec above). Override
          -- the generic + file sorters to use it; smart_case matches
          -- case-insensitively until you type uppercase.
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },
        },
      }
    end,
    config = function(_, opts)
      local ts = require("telescope")
      ts.setup(opts)
      ts.load_extension("ui-select")
      -- The native sorter is a build artefact: when the make/cmake build
      -- failed, telescope still works with its Lua sorter.
      pcall(ts.load_extension, "fzf")
    end,
  },

  -- -------------------------------------------------------------------------
  -- fzf-lua — same idea, different engine. Particularly fast on huge repos.
  -- -------------------------------------------------------------------------
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      -- stylua: ignore start
      { "<leader>Ff", "<cmd>FzfLua files<cr>",          desc = "Files (fzf)" },
      { "<leader>Fg", "<cmd>FzfLua live_grep<cr>",      desc = "Live grep (fzf)" },
      { "<leader>Fw", "<cmd>FzfLua grep_cword<cr>",     desc = "Grep cword (fzf)" },
      { "<leader>Fb", "<cmd>FzfLua buffers<cr>",        desc = "Buffers (fzf)" },
      { "<leader>Fr", "<cmd>FzfLua oldfiles<cr>",       desc = "Recent (fzf)" },
      { "<leader>Fh", "<cmd>FzfLua help_tags<cr>",      desc = "Help (fzf)" },
      { "<leader>Fk", "<cmd>FzfLua keymaps<cr>",        desc = "Keymaps (fzf)" },
      -- stylua: ignore end
      { "<leader>Fd", "<cmd>FzfLua diagnostics_document<cr>", desc = "Diagnostics (fzf)" },
      { "<leader>Fs", "<cmd>FzfLua lsp_document_symbols<cr>", desc = "Symbols (fzf)" },
    },
    opts = {
      "default-title", -- preset; sets sane defaults including a title bar
      -- Defaults applied to every picker that displays path entries
      -- (files, buffers, oldfiles, grep results, LSP locations, etc.).
      -- `formatter = "path.filename_first"` puts the filename at the
      -- left of each row with the directory shown in dim color after
      -- it, so the most-scanned part of the line is always visible
      -- regardless of how narrow the picker is. This is fzf-lua's
      -- built-in equivalent of the path display we couldn't get to
      -- stick on telescope's buffers picker. The other valid value is
      -- `"path.dirname_first"` for the inverse layout.
      defaults = {
        formatter = "path.filename_first",
      },
      winopts = {
        -- stylua: ignore start
        height = 0.85, -- 85% of editor height; large enough to be useful
        width  = 0.85,
        border = "rounded",
        -- stylua: ignore end
        -- Previewer choice. "builtin" uses Neovim's own buffer with
        -- treesitter highlighting — no external binary, works anywhere.
        -- "bat" is prettier and faster on huge files, but requires the
        -- bat binary on PATH (not present on a fresh Windows install,
        -- and the resulting error in the preview pane is opaque:
        -- "operable program or batch file"). Switch to "bat" if you
        -- install it (`scoop install bat` / `cargo install bat`).
        preview = { default = "builtin", border = "rounded" },
      },
      -- Buffers picker <C-x>: the same layout-safe delete as telescope's
      -- <C-d> (util.delete_buffers_from_picker) instead of the stock
      -- actions.buf_del, which closes every window showing the buffer.
      -- <Tab>/<S-Tab> mark entries; reload keeps the picker open with the
      -- deleted rows removed.
      buffers = { actions = { ["ctrl-x"] = fzf_delete_buffers } },
      -- :FzfLua tabs (buffers grouped by tab) has the same stock ctrl-x.
      tabs = { actions = { ["ctrl-x"] = fzf_delete_buffers } },
    },
  },
}
