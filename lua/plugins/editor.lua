-- lua/plugins/editor.lua
--
-- Small quality-of-life plugins that affect everyday editing: brackets,
-- commenting, motions, smooth scroll, indent guides, TODO highlighting.
-- None of these are huge by themselves; together they make Neovim feel
-- modern without being intrusive.

return {
  -- -------------------------------------------------------------------------
  -- nvim-autopairs — auto-close brackets, quotes, etc. Treesitter-aware,
  -- so it won't add a `)` inside a string literal.
  -- -------------------------------------------------------------------------
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {
      check_ts = true, -- ask treesitter before pairing
      ts_config = {
        lua = { "string" }, -- don't pair inside Lua strings
        javascript = { "template_string" },
      },
      fast_wrap = { -- alt-e to wrap surrounding text in a pair
        map = "<M-e>",
        chars = { "{", "[", "(", '"', "'" },
        pattern = [=[[%'%"%>%]%)%}%,]]=],
        end_key = "$",
        keys = "qwertyuiopzxcvbnmasdfghjkl",
        check_comma = true,
        highlight = "Search",
        highlight_grey = "Comment",
      },
    },
  },

  -- -------------------------------------------------------------------------
  -- Commenting is Neovim's built-in `gc` operator: `gcc` toggles a line,
  -- `gc` (visual) a selection, `gcap` a paragraph; injected languages
  -- (code blocks in Markdown, …) already get their own comment string.
  --
  -- nvim-ts-context-commentstring adds the comment style of the node under
  -- the cursor where one filetype mixes styles (JSX in tsx/jsx, Vue/Svelte
  -- SFCs, …). The built-in commenter asks vim.filetype.get_option() for
  -- 'commentstring' in treesitter-parsed buffers; this hook (the plugin's
  -- documented native-commenting integration) answers with the context's
  -- string and loads the plugin on first use.
  -- -------------------------------------------------------------------------
  {
    "JoosepAlviste/nvim-ts-context-commentstring",
    lazy = true,
    opts = {
      enable_autocmd = false,
      -- The plugin's own entry for C is /* %s */; use // as in C++.
      languages = { c = "// %s" },
    },
    init = function()
      local get_option = vim.filetype.get_option
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.filetype.get_option = function(filetype, option)
        return option == "commentstring"
            and require("ts_context_commentstring.internal").calculate_commentstring()
          or get_option(filetype, option)
      end
    end,
  },

  -- -------------------------------------------------------------------------
  -- flash.nvim — search-and-label jumps + treesitter-aware node selection.
  -- Replaces hop/leap; works for both motions and operator-pending
  -- (e.g. `dSs` deletes to a jump target).
  -- -------------------------------------------------------------------------
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
      modes = {
        -- Char mode (flash's takeover of f/F/t/T/;/,) is DISABLED, for
        -- two reasons, both macro-related and both reproduced on 0.12.4:
        --
        --   1. It corrupts macros — mechanism traced in flash's source
        --      and confirmed by instrumenting char.lua during a real @q
        --      replay of `fCdtsf,xf)xx`:
        --        * char mode keeps per-search STATE, and its cleanup
        --          runs via vim.schedule + a CursorMoved check — both
        --          need the event loop between keystrokes. A macro
        --          replays in one go, so the state from the earlier
        --          `f,` is still alive when the later `f` arrives.
        --        * flash's own macro guard (reg_executing()) then
        --          correctly skips its clever-f repeat and reads `)`
        --          as the new target — but the update is gated on
        --          `if state.pattern:empty()`, and the stale pattern
        --          `,` is NOT empty. The `)` is consumed from the
        --          macro stream and silently DISCARDED, and the jump
        --          re-runs the old `,` search (multi-line!) — landing
        --          on the next comma two lines down, where the
        --          following `xx` then deleted text. Logged:
        --          `getchar=true new_char=) pattern_empty=false
        --           pattern=[,]` → cursor (3,11).
        --        * other execution paths (`:normal @q` clears
        --          reg_executing; recording does too) instead hit the
        --          clever-f branch: `f` repeats the `,` search and `)`
        --          isn't consumed at all, executing as the
        --          sentence-forward motion. Wrong line either way.
        --   2. Even interactively it changes semantics macros and
        --      muscle memory are built on: flash's f/t are MULTI-LINE
        --      by default, so `f)` with no `)` left on the line jumps
        --      to the next line instead of failing — and a failed f is
        --      exactly what safely ABORTS a misapplied macro in stock
        --      Vim.
        --
        -- Flash's actual value here — `s` jump, `S` treesitter select,
        -- `r`/`R` remote and treesitter search — is untouched.
        char = { enabled = false },
      },
    },
    keys = {
      -- stylua: ignore start
      { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
      { "S",     mode = { "n", "x", "o" }, function() require("flash").treesitter() end,         desc = "Flash treesitter" },
      { "r",     mode = "o",               function() require("flash").remote() end,             desc = "Remote flash" },
      { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end,  desc = "Treesitter search" },
      { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,             desc = "Toggle flash search" },
      -- stylua: ignore end
    },
  },

  -- -------------------------------------------------------------------------
  -- neoscroll — smooth Ctrl-d / Ctrl-u / zz scrolling. Subtle but it makes
  -- the editor feel modern. Set duration low; long scroll animations get
  -- annoying fast.
  -- -------------------------------------------------------------------------
  {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    config = function()
      local neoscroll = require("neoscroll")
      neoscroll.setup({
        -- <C-u>/<C-d> (re-center, below) and <C-f>/<C-b> (faster duration,
        -- below) are NOT in this list — we map all four ourselves. The rest
        -- keep neoscroll's default animated mappings.
        mappings = { "<C-y>", "<C-e>", "zt", "zz", "zb" },
        hide_cursor = true,
        stop_eof = true,
        respect_scrolloff = true,
        cursor_scrolls_alone = true,
        easing = "sine",
        duration_multiplier = 0.7, -- speed multiplier; lower = snappier
        -- Runs after the animation ends. Only the half-page jumps pass
        -- info = "center", so only they snap to middle; <C-f>/<C-b> and the
        -- default mappings pass no info and scroll without re-centering.
        post_hook = function(info)
          if info == "center" then vim.cmd("normal! zz") end
        end,
      })
      -- All four custom scroll maps below MUST pass an explicit `duration`:
      -- neoscroll multiplies it by duration_multiplier (0.7) with no nil
      -- fallback, so a duration-less ctrl_* call errors on keypress.
      -- Effective animation time ≈ duration × 0.7.
      --
      -- <C-d>/<C-u>: animated half-page scroll that ENDS centered (info =
      -- "center" → the post_hook runs zz): the <C-d>zz / <C-u>zz habit,
      -- which neoscroll's own default mappings would override.
      vim.keymap.set({ "n", "x" }, "<C-d>", function()
        neoscroll.ctrl_d({ duration = 250, info = "center" })
      end, { desc = "Half page down (centered)" })
      vim.keymap.set({ "n", "x" }, "<C-u>", function()
        neoscroll.ctrl_u({ duration = 250, info = "center" })
      end, { desc = "Half page up (centered)" })

      -- <C-f>/<C-b>: full-page scroll, no centering. neoscroll's built-in
      -- default for these is 450ms (≈315ms after the 0.7 multiplier), which
      -- felt sluggish for such a big jump — dropped to FULLPAGE_MS. Lower =
      -- snappier; raise it back toward 450 if it now feels too abrupt.
      local FULLPAGE_MS = 220
      vim.keymap.set({ "n", "x" }, "<C-f>", function()
        neoscroll.ctrl_f({ duration = FULLPAGE_MS })
      end, { desc = "Full page down" })
      vim.keymap.set({ "n", "x" }, "<C-b>", function()
        neoscroll.ctrl_b({ duration = FULLPAGE_MS })
      end, { desc = "Full page up" })
    end,
  },

  -- -------------------------------------------------------------------------
  -- smear-cursor — animated cursor "smear" effect between positions.
  -- Pure eye candy. Disable if you find motion distracting.
  -- -------------------------------------------------------------------------
  {
    "sphamba/smear-cursor.nvim",
    event = "VeryLazy",
    opts = {
      stiffness = 0.8, -- 0..1, higher = snappier
      trailing_stiffness = 0.5,
      distance_stop_animating = 0.5,
      hide_target_hack = false, -- set true if you see two cursors briefly
    },
  },

  -- -------------------------------------------------------------------------
  -- blink.indent — indent guides. Same author family as blink.cmp; very
  -- lightweight (no autocmd-per-buffer overhead like indent-blankline).
  -- Its default `[i` / `]i` (top / bottom of the current scope) replace
  -- Vim's `[i` / `]i` (show the first / next line with the keyword).
  -- Panels (neo-tree, Trouble, lazy, Mason, terminals, help, …) are
  -- skipped by its default buftype/filetype block list.
  -- -------------------------------------------------------------------------
  {
    "saghen/blink.indent",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      static = {
        enabled = true,
        char = "│",
        priority = 1,
        highlights = { "BlinkIndent" },
      },
      scope = {
        enabled = true,
        char = "│",
        priority = 1024,
        highlights = {
          "BlinkIndentRed",
          "BlinkIndentYellow",
          "BlinkIndentBlue",
          "BlinkIndentOrange",
          "BlinkIndentGreen",
          "BlinkIndentViolet",
          "BlinkIndentCyan",
        },
      },
    },
  },

  -- -------------------------------------------------------------------------
  -- mini.surround — adds surround verbs, on the `gz` prefix:
  -- `gza` / `gzd` / `gzr` (add / delete / replace), `gzf` / `gzF`
  -- (find right / left), `gzh` (highlight), `gzn` (update n_lines).
  -- Examples: `gzaiw"` surrounds a word with quotes; `gzrb)` replaces
  -- `()` with the next bracket type; `gzdt` deletes the surrounding
  -- HTML tag. Tiny, intuitive, and easy to live without — but easy to
  -- love.
  --
  -- WHY `gz` AND NOT THE DEFAULT `s` PREFIX: flash.nvim (above) owns
  -- `s` for jumps. With both registered, every flash jump had
  -- to wait `timeoutlen` (400 ms) while Vim ruled out `sa`/`sd`/…, and
  -- a slow-typed surround chord fell into flash instead. Moving
  -- surround to `gz` removes the prefix overlap entirely — the same
  -- solution LazyVim ships when flash is present.
  -- -------------------------------------------------------------------------
  {
    "nvim-mini/mini.surround",
    keys = function(_, keys)
      -- Set the mappings explicitly so which-key can describe them.
      -- Must match opts.mappings below.
      local maps = {
        gza = "Add",
        gzd = "Delete",
        gzr = "Replace",
        gzf = "Find",
        gzF = "Find left",
        gzh = "Highlight",
        gzn = "Update n_lines",
      }
      -- Visual mode only where mini.surround actually maps it (add and the
      -- two finds). Advertising gzd/gzr/gzh/gzn in visual mode made
      -- which-key offer them there, and since mini has no such visual
      -- maps, `gzd` on a selection fell through to Vim: `gz` is no command
      -- and the trailing `d` DELETED the selection.
      local visual = { gza = true, gzf = true, gzF = true }
      local out = {}
      for k, desc in pairs(maps) do
        out[#out + 1] = { k, mode = visual[k] and { "n", "x" } or "n", desc = "Surround " .. desc }
      end
      -- Extend rather than replace: `keys` holds whatever lazy.nvim
      -- merged from other specs for this plugin (none today, but
      -- discarding the parameter silently would eat them if a second
      -- spec fragment ever added one — and luacheck rightly flagged
      -- the unused argument). Same pattern LazyVim uses here.
      return vim.list_extend(out, keys or {})
    end,
    opts = {
      mappings = {
        -- stylua: ignore start
        add            = "gza",
        delete         = "gzd",
        find           = "gzf",
        find_left      = "gzF",
        highlight      = "gzh",
        replace        = "gzr",
        update_n_lines = "gzn",
        -- stylua: ignore end
      },
    },
  },

  -- -------------------------------------------------------------------------
  -- mini.align — align consecutive lines on a delimiter (=, :, ,, etc).
  -- Triggers: `ga` (interactive) and `gA` (with preview).
  -- Both also act as operators, so `gaip=` aligns the inner paragraph on `=`.
  -- `ga` replaces Vim's "print the character code" (`:ascii` still works).
  --
  -- Typical workflow:
  --   1. Visually select the lines (V, then j to extend).
  --   2. Press `ga` and type the split char (e.g. `=`).
  --   3. Result: every line padded so the split chars line up vertically.
  --
  -- This complements our `.clang-format` setup, which deliberately keeps
  -- `AlignConsecutiveAssignments: None` to avoid noisy diffs. mini.align
  -- gives you the alignment on demand, only where it actually helps
  -- readability (tables of constants, enum value lists, etc.).
  -- -------------------------------------------------------------------------
  {
    "nvim-mini/mini.align",
    keys = {
      { "ga", mode = { "n", "x" }, desc = "Align (interactive)" },
      { "gA", mode = { "n", "x" }, desc = "Align with preview" },
    },
    opts = {},
  },

  -- -------------------------------------------------------------------------
  -- todo-comments — highlights TODO/FIXME/HACK/NOTE/WARN/PERF and lets you
  -- list and jump between them. Use `]t` / `[t` to navigate (they replace
  -- Neovim's default :tnext / :tprevious; the commands still work);
  -- `<leader>xt` opens the Trouble panel showing all of them; `<leader>fT`
  -- is the Telescope variant.
  -- -------------------------------------------------------------------------
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      {
        "]t",
        function()
          require("todo-comments").jump_next()
        end,
        desc = "Next todo comment",
      },
      -- stylua: ignore start
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Prev todo comment" },
      { "<leader>xt", "<cmd>Trouble todo toggle<cr>",              desc = "Todo (Trouble)" },
      { "<leader>fT", "<cmd>TodoTelescope<cr>",                    desc = "Todo (Telescope)" },
      -- stylua: ignore end
    },
    opts = {},
  },

  -- -------------------------------------------------------------------------
  -- render-markdown.nvim — in-buffer rendering of Markdown: styled headings,
  -- rendered bullets/checkboxes, fenced-code backgrounds, table borders,
  -- callouts, etc., drawn with virtual text over the raw source. The raw
  -- markup is revealed on the line your cursor is on (anti_conceal), so it
  -- stays fully editable — you're never fighting a WYSIWYG view.
  --
  -- Worth it here specifically because this config ships a lot of Markdown
  -- you actually edit: README.md, CHANGES.md, the scoper.nvim and
  -- docs/templates READMEs. Purely visual — remove this block and Markdown
  -- just renders as plain text again.
  --
  -- Toggle at runtime with `:RenderMarkdown toggle` (also `:RenderMarkdown
  -- enable` / `disable`). Deliberately NO <leader> keymap: a Markdown-only
  -- toggle doesn't earn a global chord, and adding one under an existing
  -- single-key leader (e.g. <leader>u = atone) would introduce a prefix-wait;
  -- the command is right there when you want it.
  --
  -- Treesitter dependency: it renders via the `markdown` + `markdown_inline`
  -- parsers, both already in PARSERS (treesitter.lua), so nothing extra to
  -- install. Trailing-whitespace note: the trim-on-save autocmd
  -- (lua/config/autocmds/editing.lua) already skips markdown (double-space
  -- hard breaks are load-bearing), so rendering and saving don't fight over
  -- line ends.
  -- -------------------------------------------------------------------------
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    -- Defaults are good and Nerd-Font aware (this config already requires a
    -- Nerd Font). Tune headings/checkbox glyphs/code style here if you want.
    opts = {},
  },
}
