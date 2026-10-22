-- lua/plugins/ui.lua
--
-- The "chrome": statusline, bufferline, per-window filename, icons, and
-- LSP progress spinner. scope.nvim and bufferline load at startup because
-- session restore needs them (see their specs); lualine loads on VeryLazy,
-- incline with the first file, fidget with the first LSP client.

local icons = require("config.icons")

-- fg of a highlight group as a lualine colour, so it follows the
-- colorscheme.
local function hl_fg(name)
  local fg = vim.api.nvim_get_hl(0, { name = name, link = false }).fg
  return fg and { fg = ("#%06x"):format(fg) } or nil
end

return {
  -- -------------------------------------------------------------------------
  -- nvim-web-devicons — file-type icons. Required by lualine, bufferline,
  -- telescope, trouble, etc. Loaded as a dependency of those plugins, but
  -- declared here so we can configure it once.
  -- -------------------------------------------------------------------------
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
    opts = {
      -- Use the colored Nerd Font glyphs (requires a Nerd Font in your
      -- terminal — install one from https://www.nerdfonts.com).
      color_icons = true,
      default = true,
    },
  },

  -- -------------------------------------------------------------------------
  -- scope.nvim — per-tab buffer scoping. In Vim, buffers are GLOBAL, so
  -- bufferline normally shows every listed buffer in every tab. scope.nvim
  -- tracks which buffers belong to which tabpage and toggles `buflisted` on
  -- tab switch, so bufferline (which only renders listed buffers) shows just
  -- the current tab's set — a VS-Code-style "each tab owns its files" model.
  -- No bufferline config change is needed; they compose automatically.
  --
  -- lazy = false so its tab autocmds exist before auto-session restores on
  -- startup. Session persistence needs three things, all wired up:
  --   1. sessionoptions += "globals"          (lua/config/options.lua)
  --   2. :ScopeSaveState in pre_save_cmds      (lua/plugins/session.lua)
  --   3. :ScopeLoadState in post_restore_cmds  (lua/plugins/session.lua)
  -- Buffers in OTHER tabs are hidden from <leader>fb (now "this tab"); reach
  -- them with <leader>fB (all tabs), or move one with :ScopeMoveBuf <tab_nr>.
  -- -------------------------------------------------------------------------
  {
    "tiagovla/scope.nvim",
    lazy = false,
    config = function()
      require("scope").setup({})
    end,
  },

  -- -------------------------------------------------------------------------
  -- lualine — the statusline at the bottom.
  -- -------------------------------------------------------------------------
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons", "catppuccin/nvim" },
    opts = function()
      return {
        options = {
          -- "auto" derives the theme from the active colorscheme's
          -- highlight groups. This means changing flavours in
          -- colorscheme.lua (mocha → latte → frappe → …) or swapping to
          -- a different scheme entirely Just Works, where a hardcoded
          -- "catppuccin-mocha" would silently stay on the wrong palette.
          theme = "auto",
          globalstatus = true, -- single bar across all splits (laststatus=3)
          -- stylua: ignore start
          component_separators = { left = "│", right = "│" },
          section_separators   = { left = icons.misc.pl_left, right = icons.misc.pl_right },
          -- stylua: ignore end
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = {
            "branch",
            {
              "diff",
              symbols = icons.git,
              -- gitsigns already counts the hunks; without a source lualine
              -- runs its own `git diff` job on every BufEnter and write.
              source = function()
                local g = vim.b.gitsigns_status_dict
                if g then return { added = g.added, modified = g.changed, removed = g.removed } end
              end,
            },
          },
          lualine_c = {
            { "diagnostics", symbols = icons.diagnostics },
            { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
            { "filename", path = 1 }, -- relative path
          },
          lualine_x = {
            -- macro recorder indicator — invaluable if you use macros.
            {
              function()
                return icons.misc.recording .. " " .. vim.fn.reg_recording()
              end,
              cond = function()
                return vim.fn.reg_recording() ~= ""
              end,
              color = function()
                return hl_fg("DiagnosticWarn")
              end,
            },
            "encoding",
            "fileformat",
          },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
        -- stylua: ignore start
        extensions = {
          "lazy", "mason", "trouble", "toggleterm", "quickfix",
          "neo-tree", "nvim-dap-ui", "fzf",
        },
        -- stylua: ignore end
      }
    end,
  },

  -- -------------------------------------------------------------------------
  -- bufferline — tabs at the top, one per open buffer.
  -- -------------------------------------------------------------------------
  {
    "akinsho/bufferline.nvim",
    -- At startup, not VeryLazy: setup() registers the SessionLoadPost
    -- handler that restores pinned buffers, and auto-session restores the
    -- session in VimEnter, before VeryLazy.
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons", "catppuccin/nvim" },
    keys = {
      -- Cycle buffers in the BUFFERLINE'S VISUAL ORDER (pinned first,
      -- custom sort) rather than buffer-number order, which also scrolls
      -- hidden tabs into view: bufferline always keeps the current buffer
      -- visible, so cycling IS the scroll. There is no view-only scroll,
      -- and the "N tabs hidden" markers at the strip's edges have no click
      -- handler. <S-l> / <S-h> ARE `L` / `H`, so they replace Vim's
      -- "cursor to the bottom / top line of the window" motions.
      -- stylua: ignore start
      { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",            desc = "Next buffer (scrolls bufferline)" },
      { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",            desc = "Prev buffer (scrolls bufferline)" },
      -- stylua: ignore end
      -- The right-click tab menu for the CURRENT buffer (pin, copy path,
      -- open in split, close, close others); j/k + <CR> or 1-9 to pick,
      -- q/<Esc> to dismiss.
      {
        "<leader>bm",
        function()
          local menu = require("config.util").buffer_menu
          if menu then menu() end
        end,
        desc = "Buffer tab menu (right-click menu)",
      },
      -- Pin a buffer so it sticks while you cycle through ephemeral ones.
      { "<leader>bp", "<cmd>BufferLineTogglePin<cr>", desc = "Pin buffer" },
      -- Not :BufferLineGroupClose ungrouped: group close force-deletes
      -- (unsaved edits are lost) and bypasses close_command.
      {
        "<leader>bP",
        function()
          local groups = require("bufferline.groups")
          local bufs = {}
          for _, el in ipairs(require("bufferline").get_elements().elements) do
            if not groups._is_pinned(el) then bufs[#bufs + 1] = el.id end
          end
          local util = require("config.util")
          util.notify_bulk_result(util.delete_buffers_keep_windows(bufs))
        end,
        desc = "Close unpinned buffers",
      },
      -- Quick-pick by letter — much faster than cycling with Shift-l.
      -- stylua: ignore start
      { "<leader>bj", "<cmd>BufferLinePick<cr>",                 desc = "Pick buffer" },
      { "<leader>bJ", "<cmd>BufferLinePickClose<cr>",            desc = "Pick buffer (close)" },
      -- stylua: ignore end
      -- Re-order tabs. (Move CURRENT buffer's position in the bufferline.)
      -- These replace Neovim's default [B / ]B (:bfirst / :blast); [b / ]b
      -- (:bprevious / :bnext) stay.
      -- stylua: ignore start
      { "[B",         "<cmd>BufferLineMovePrev<cr>",             desc = "Move buffer left" },
      { "]B",         "<cmd>BufferLineMoveNext<cr>",             desc = "Move buffer right" },
      -- stylua: ignore end
      -- Jump by position: <leader>1 jumps to the leftmost buffer, etc. The
      -- superscripts match only while nothing is pinned: bufferline numbers
      -- tabs before it moves pinned ones to the front.
      -- <leader>0 jumps to the LAST buffer regardless of position
      -- (BufferLineGoToBuffer -1 is the documented "last" sentinel).
      -- stylua: ignore start
      { "<leader>1",  "<cmd>BufferLineGoToBuffer 1<cr>",         desc = "Buffer 1" },
      { "<leader>2",  "<cmd>BufferLineGoToBuffer 2<cr>",         desc = "Buffer 2" },
      { "<leader>3",  "<cmd>BufferLineGoToBuffer 3<cr>",         desc = "Buffer 3" },
      { "<leader>4",  "<cmd>BufferLineGoToBuffer 4<cr>",         desc = "Buffer 4" },
      { "<leader>5",  "<cmd>BufferLineGoToBuffer 5<cr>",         desc = "Buffer 5" },
      { "<leader>6",  "<cmd>BufferLineGoToBuffer 6<cr>",         desc = "Buffer 6" },
      { "<leader>7",  "<cmd>BufferLineGoToBuffer 7<cr>",         desc = "Buffer 7" },
      { "<leader>8",  "<cmd>BufferLineGoToBuffer 8<cr>",         desc = "Buffer 8" },
      { "<leader>9",  "<cmd>BufferLineGoToBuffer 9<cr>",         desc = "Buffer 9" },
      { "<leader>0",  "<cmd>BufferLineGoToBuffer -1<cr>",        desc = "Last buffer" },
      -- stylua: ignore end
    },
    opts = function()
      -- Right-click context menu for a tab. Bufferline calls this with
      -- the clicked buffer's bufnr; we render a small floating-window menu.
      -- Not vim.ui.select: through telescope-ui-select's dropdown theme
      -- these short menus render with a progressive indent.
      --
      -- This replaces bufferline's default `right_mouse_command =
      -- "bdelete! %d"` (close on right-click) which is hostile — there's
      -- no undo for a buffer drop and reopening loses cursor state.

      -- Tracks the currently-open menu so a fresh right-click closes any
      -- existing menu first — otherwise repeated right-clicks pile floats
      -- on top of each other.
      local current_menu_win

      -- `anchor` selects where the float opens: "mouse" (default, for
      -- right-click — the pointer is where the user's attention is) or
      -- "cursor" (for the <leader>bm keyboard entry point). getmousepos()
      -- is useless from the keyboard: it returns wherever the pointer
      -- last was — (0,0) if it never moved.
      local function show_menu(actions, prompt, anchor)
        -- Tear down any stale menu before opening a new one.
        if current_menu_win and vim.api.nvim_win_is_valid(current_menu_win) then
          pcall(vim.api.nvim_win_close, current_menu_win, true)
        end
        current_menu_win = nil

        -- Width must fit BOTH the title and the longest action label.
        -- The "  N. " prefix adds 6 cols to each label; the title has
        -- " ... " padding on each side, so reserve 4 for it. Measure in
        -- display cells (strdisplaywidth), not bytes (#) — a multibyte
        -- filename in the title would otherwise over-allocate the menu
        -- and the title padding would come out wrong.
        local width = vim.fn.strdisplaywidth(prompt) + 4
        for _, item in ipairs(actions) do
          width = math.max(width, vim.fn.strdisplaywidth(item[1]) + 6)
        end
        width = math.max(width, 28)

        local lines = {}
        for i, item in ipairs(actions) do
          table.insert(lines, string.format("  %d. %s", i, item[1]))
        end

        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        -- stylua: ignore start
        vim.bo[buf].modifiable = false
        vim.bo[buf].buftype    = "nofile"
        vim.bo[buf].bufhidden  = "wipe"
        -- stylua: ignore end

        -- Position at the point of attention: the actual mouse click for
        -- right-click invocations, the text cursor for keyboard ones.
        -- Both sources yield screen coordinates suitable for
        -- relative="editor" (screenrow()/screencol() describe the cursor
        -- in the same coordinate space getmousepos() uses for the
        -- pointer). Nudge the menu down by 1 row so it doesn't cover the
        -- row the user clicked / the cursor line.
        local row, col
        if anchor == "cursor" then
          row, col = vim.fn.screenrow(), vim.fn.screencol()
        else
          local mp = vim.fn.getmousepos()
          row, col = mp.screenrow, mp.screencol
        end
        -- Keep the menu on-screen: if it would overflow the bottom or
        -- right edge, flip / shift it.
        local total_rows = vim.o.lines - vim.o.cmdheight - 1
        local total_cols = vim.o.columns
        if row + #lines + 2 > total_rows then row = math.max(0, row - #lines - 2) end
        if col + width + 2 > total_cols then col = math.max(0, total_cols - width - 2) end

        local win = vim.api.nvim_open_win(buf, true, {
          -- stylua: ignore start
          relative   = "editor",
          row        = row,
          col        = col,
          width      = width,
          height     = #lines,
          style      = "minimal",
          title      = " " .. prompt .. " ",
          title_pos  = "center",
          -- stylua: ignore end
        })
        current_menu_win = win
        -- stylua: ignore start
        vim.wo[win].cursorline      = true
        vim.wo[win].number          = false
        vim.wo[win].relativenumber  = false
        -- stylua: ignore end
        vim.api.nvim_win_set_cursor(win, { 1, 0 })

        local function close()
          if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
          if current_menu_win == win then current_menu_win = nil end
        end
        local function pick(idx)
          close()
          if actions[idx] and actions[idx][2] then
            -- Schedule so the window is fully torn down before the
            -- action runs (some actions open new windows / pickers).
            vim.schedule(actions[idx][2])
          end
        end

        -- 1..9 keys jump straight to that item.
        for i = 1, math.min(#actions, 9) do
          vim.keymap.set("n", tostring(i), function()
            pick(i)
          end, { buffer = buf, nowait = true, silent = true })
        end
        vim.keymap.set("n", "<CR>", function()
          pick(vim.api.nvim_win_get_cursor(win)[1])
        end, { buffer = buf, nowait = true, silent = true })
        -- stylua: ignore start
        vim.keymap.set("n", "q",     close, { buffer = buf, nowait = true, silent = true })
        vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })
        -- stylua: ignore end

        -- Also close the menu if the user clicks anywhere outside it.
        vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
          buffer = buf,
          once = true,
          callback = close,
        })
      end

      -- Shared "close one buffer" used by the menu's Close item AND by
      -- bufferline's close_command (<leader>bJ, BufferLineCloseOthers,
      -- BufferLineCloseLeft/Right). Routes through
      -- util.delete_buffer_keep_windows so these close paths share one set
      -- of rules: keep the window layout, never discard unsaved work, force
      -- terminals, and say why when a buffer stays open. Group close
      -- (:BufferLineGroupClose) does NOT call close_command; it
      -- force-deletes, which is why <leader>bP doesn't use it.
      local function close_buffer(bufnum)
        local util = require("config.util")
        util.notify_undeleted(bufnum, util.delete_buffer_keep_windows(bufnum))
      end

      local function buffer_context_menu(bufnum, anchor)
        local name = vim.api.nvim_buf_get_name(bufnum)
        local short = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"

        -- Build a "copy this transformation of the path" action. Pass the
        -- vim.fn.fnamemodify modifier (":p" / ":." / ":t" / etc.) and we
        -- yank the result + notify. No-op on unnamed buffers.
        local function copy_path(modifier)
          return function()
            if name == "" then return end
            local p = vim.fn.fnamemodify(name, modifier)
            vim.fn.setreg("+", p)
            vim.notify("Copied: " .. p, vim.log.levels.INFO)
          end
        end

        -- Right-clicking the tabline keeps the previous window focused.
        -- Run file actions from a normal window so they do not replace or
        -- split a focused neo-tree, terminal, help, or trouble panel. If no
        -- file window exists, use the current window.
        local function in_file_window(fn)
          local cur_win = vim.api.nvim_get_current_win()
          if vim.bo[vim.api.nvim_win_get_buf(cur_win)].buftype ~= "" then
            for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then
                vim.api.nvim_set_current_win(w)
                break
              end
            end
          end
          fn()
        end

        local actions = {
          -- stylua: ignore start
          { "Open in vsplit",       function()
              in_file_window(function() vim.cmd("vertical sbuffer " .. bufnum) end)
            end },
          { "Open in hsplit",       function()
              in_file_window(function() vim.cmd("sbuffer " .. bufnum) end)
            end },
          { "Copy absolute path",   copy_path(":p") },
          { "Copy relative path",   copy_path(":.") },
          { "Copy filename",        copy_path(":t") },
          { "Toggle pin",           function()
              -- BufferLineTogglePin acts on the current buffer; from a
              -- file window, jump to the clicked buffer, toggle, then
              -- restore both the buffer and the originally-focused
              -- window so the action is fully transparent.
              local prev_win = vim.api.nvim_get_current_win()
              in_file_window(function()
                local cur = vim.api.nvim_get_current_buf()
                vim.cmd("buffer " .. bufnum)
                vim.cmd("BufferLineTogglePin")
                if cur ~= bufnum and vim.api.nvim_buf_is_valid(cur) then
                  vim.cmd("buffer " .. cur)
                end
              end)
              if vim.api.nvim_win_is_valid(prev_win) then
                vim.api.nvim_set_current_win(prev_win)
              end
            end },
          -- stylua: ignore end
          {
            "Close",
            function()
              -- Same routine as <leader>bd: dirty buffers are skipped
              -- BEFORE any window is touched; terminals take force.
              close_buffer(bufnum)
            end,
          },
          {
            "Close others",
            function()
              -- Switch a FILE window to `bufnum` first so
              -- BufferLineCloseOthers leaves the right buffer alive.
              -- No focus-restore afterwards because "close others"
              -- by definition leaves only one — `bufnum` is now it.
              in_file_window(function()
                vim.cmd("buffer " .. bufnum)
                vim.cmd("BufferLineCloseOthers")
              end)
            end,
          },
        }

        show_menu(actions, "Buffer: " .. short, anchor)
      end

      -- Expose the menu to the keyboard (<leader>bm above) for the
      -- *current* buffer; bufferline itself calls buffer_context_menu on
      -- right-click. Registered on config.util because these functions are
      -- locals of this opts closure.
      require("config.util").buffer_menu = function()
        local cur = vim.api.nvim_get_current_buf()
        if not vim.bo[cur].buflisted then
          -- e.g. invoked from neo-tree, a terminal, or a help window —
          -- there's no bufferline tab for it, so the menu would act on a
          -- buffer the user can't see in the strip. Bail with a hint.
          vim.notify("No bufferline tab for this buffer", vim.log.levels.WARN)
          return
        end
        buffer_context_menu(cur, "cursor")
      end

      -- Superscript ordinals for the small-number-in-corner effect.
      -- Limited to 1-9 — past that we show nothing because (a) you should
      -- be using <leader>fb to find a specific one if you have 10+ open,
      -- and (b) two-character superscripts like "¹⁰" look cluttered.
      local supers = { "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹" }

      return {
        options = {
          mode = "buffers", -- "tabs" if you prefer tab-pages
          themable = true,
          diagnostics = "nvim_lsp", -- show LSP error/warn counts on each tab
          diagnostics_indicator = function(_, _, diag)
            -- bufferline passes a table with error/warning/info/hint counts;
            -- all four are shown, so an info-only buffer doesn't look clean.
            -- Shared glyphs (config/icons.lua); bufferline calls the WARN
            -- count "warning", hence the one-key adaptor.
            local base = icons.diagnostics
            local sym =
              { error = base.error, warning = base.warn, info = base.info, hint = base.hint }
            local parts = {}
            -- stylua: ignore start
            if diag.error   then table.insert(parts, sym.error   .. diag.error)   end
            if diag.warning then table.insert(parts, sym.warning .. diag.warning) end
            if diag.info    then table.insert(parts, sym.info    .. diag.info)    end
            if diag.hint    then table.insert(parts, sym.hint    .. diag.hint)    end
            -- stylua: ignore end
            return table.concat(parts, " ")
          end,
          -- Show small superscript ordinals on each tab, mapping 1-1 to
          -- the <leader>1..<leader>9 quick-jump keymaps above.
          numbers = function(opts)
            return supers[opts.ordinal] or ""
          end,
          -- Mouse behaviour. The defaults are surprising:
          --   left   = "buffer %d"      → switch to the buffer (sensible)
          --   middle = nil              → no-op  (sensible)
          --   right  = "bdelete! %d"    → CLOSE the buffer  ← hostile default
          --   close  = "bdelete! %d"    → close-icon click  (we hide the icon)
          -- We override right-click to open the context menu and leave
          -- middle disabled. Left-click keeps the default focus behaviour.
          -- stylua: ignore start
          left_mouse_command   = "buffer %d",
          middle_mouse_command = nil,
          right_mouse_command  = buffer_context_menu,
          -- stylua: ignore end
          -- BufferLinePickClose (<leader>bJ), the tab close button and the
          -- close-others/left/right commands route through close_command —
          -- the same close_buffer as the menu's "Close" (see above).
          close_command = close_buffer,
          show_buffer_close_icons = false,
          show_close_icon = false,
          separator_style = "slant",
          always_show_bufferline = false, -- hide when only one buffer is open
          offsets = { -- shift bufferline when the file tree is open
            -- stylua: ignore start
            { filetype = "neo-tree",  text = "File Explorer", highlight = "Directory", text_align = "center" },
            -- stylua: ignore end
          },
        },
        -- catppuccin's bufferline theme (catppuccin has no bufferline
        -- integration switch); a function, so it follows flavour changes.
        highlights = require("catppuccin.special.bufferline").get_theme(),
      }
    end,
  },

  -- -------------------------------------------------------------------------
  -- incline — small floating filename in the top-right of each window.
  -- Makes split layouts much more navigable.
  -- -------------------------------------------------------------------------
  {
    "b0o/incline.nvim",
    event = { "BufReadPre", "BufNewFile" }, -- BufNewFile: `:e newfile` gets a label too
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local devicons = require("nvim-web-devicons")
      require("incline").setup({
        window = {
          padding = 0,
          margin = { horizontal = 0 },
        },
        -- Per-window header content. Called every redraw, so keep it
        -- cheap: no syscalls, no plugin requires. We show the filetype's
        -- devicon (with its language-specific color), the filename, and
        -- a bullet in the error colour for unsaved changes.
        render = function(props)
          local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
          if filename == "" then filename = "[No Name]" end
          local ft_icon, ft_color = devicons.get_icon_color(filename)
          local modified = vim.api.nvim_get_option_value("modified", { buf = props.buf })
          return {
            ft_icon and { " ", ft_icon, " ", guifg = ft_color } or "",
            " ",
            { filename, gui = modified and "bold,italic" or "bold" },
            modified and { " ●", group = "DiagnosticError" } or "",
            " ",
          }
        end,
      })
    end,
  },

  -- -------------------------------------------------------------------------
  -- fidget — tiny LSP progress spinner in the corner ("indexing…",
  -- "rust-analyzer: building"). Invisible when nothing's happening,
  -- essential when something is — without it, you can't tell whether
  -- rust-analyzer is thinking or has hung.
  -- -------------------------------------------------------------------------
  {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts = {
      progress = {
        display = {
          done_icon = "✓",
        },
      },
      notification = {
        window = { winblend = 0 },
      },
    },
  },
}
