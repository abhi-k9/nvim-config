-- lua/plugins/treesitter.lua
--
-- Treesitter, on the new `main` branch of both nvim-treesitter and
-- nvim-treesitter-textobjects.
--
-- Why `main`: `master` is frozen and calls helpers Neovim removed
-- (textobjects/move errors like "tsrange.lua:27: attempt to call method
-- 'start'" on 0.12). The two plugins' `main` branches must be used
-- together, so both are pinned.
--
-- `main` specifics:
--   * lazy = false is required (the plugin doesn't support lazy-loading).
--   * setup() before install(); install() returns an async task — not
--     waited on, so parsers build in the background.
--   * highlighting/indent aren't automatic: the FileType autocmd below
--     enables them, and installs a missing parser on first use.
--   * parsers are compiled locally, so the `tree-sitter` CLI (0.26.1+) and
--     a C compiler are required.
--   * incremental selection comes from Neovim 0.12 itself: in visual mode
--     `an` / `in` grow / shrink the selection by node, `]n` / `[n` move it.

-- The `doxygen` parser doesn't run on its own files — it's *injected*
-- into C/C++ comment nodes by the c/cpp queries that ship with
-- nvim-treesitter. Once present, `@param`, `@brief`, `[in,out]`,
-- `\code`/`\endcode`, etc. inside `///` and `/** ... */` comments get
-- their own highlight groups and become navigable nodes. Without it,
-- the doxygen tags are just plain-comment colored text.
local PARSERS = {
  "bash",
  "c",
  "cpp",
  "css",
  "diff",
  "dockerfile",
  "doxygen",
  -- Installed up front: nvim often runs as $GIT_EDITOR for a few seconds,
  -- and quitting kills an on-demand parser build mid-way.
  "git_rebase",
  "gitcommit",
  "go",
  "html",
  "javascript",
  "json",
  "lua",
  "luadoc",
  "luap",
  "markdown",
  "markdown_inline",
  "python",
  "query",
  "regex",
  "rust",
  "scheme",
  "toml",
  "tsx",
  "typescript",
  "vim",
  "vimdoc",
  "yaml",
}

-- NOTE: scheme has a treesitter parser (highlighting) but NO LSP and NO
-- formatter in the Mason/conform ecosystem — so highlighting is the only
-- automatic tooling Scheme gets here. The FileType autocmd below starts
-- it like any other parser once `:TSUpdate` compiles it. For structural
-- editing (paredit/parinfer-style), add a dedicated plugin; none is
-- bundled.

-- NOTE: there is intentionally NO "jsonc" here. It was a parser on the old
-- `master` branch but does not exist on `main` (which has json / json5 /
-- jsonnet only), so listing it made install() emit
-- "skipping unsupported language: jsonc". Nothing maps jsonc -> json
-- automatically (core's ft_to_lang only covers help/checkhealth), so
-- jsonc-filetype files (.jsonc, tsconfig.json, VS Code settings.json,
-- .eslintrc, …) fall back to Vim's built-in syntax — which is fine and
-- comment-aware. To get treesitter highlighting on them instead, add
-- "json5" above and `vim.treesitter.language.register("json5", "jsonc")`
-- (json5 tolerates comments + trailing commas; plain json would mark them
-- as errors). Not done by default: json5 is a looser superset and ships
-- no folds/indents queries on main.

return {
  -- -------------------------------------------------------------------------
  -- nvim-treesitter — parser manager. On main this is a much smaller
  -- plugin: it installs parsers and exposes an indentexpr helper, and
  -- that's about it. Highlighting comes from Neovim's built-in
  -- vim.treesitter.start(), which we trigger ourselves on FileType.
  -- -------------------------------------------------------------------------
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false, -- REQUIRED — see top-of-file comment.
    build = ":TSUpdate",
    -- Not setup() options: config() installs them, and
    -- scripts/offline-seed-check.lua reads them from the resolved spec.
    opts = { parsers = PARSERS },
    config = function(_, opts)
      -- setup() MUST be called first; it's what attaches the install
      -- function to the module table. No options needed for our use.
      local ts = require("nvim-treesitter")
      ts.setup()

      -- Install any missing parsers in the background. Deferring to the
      -- next event-loop tick lets the rest of startup finish first so
      -- nvim is interactive sooner. install() does its own up-to-date
      -- check, so this is a near-instant no-op when nothing is missing.
      -- Without the tree-sitter CLI every build fails, so skip it instead
      -- of re-downloading and erroring for each parser on every launch
      -- (:checkhealth config explains what to install).
      if vim.fn.executable("tree-sitter") == 1 then
        vim.defer_fn(function()
          require("nvim-treesitter").install(opts.parsers)
        end, 0)
      end

      -- Enable highlighting (and optional indent) on every FileType.
      -- pcall'd so filetypes without an installed parser don't throw —
      -- common on first launch before install() finishes in the
      -- background, or for filetypes outside PARSERS.
      -- Highlighting + treesitter indent for one buffer.
      --   * big_file buffers (vim.b.big_file, set in autocmds/bigfile.lua on
      --     BufReadPre) are skipped here rather than relying on autocmd
      --     ordering to switch treesitter off again afterwards.
      --   * treesitter indent only when the language ships `indents.scm`;
      --     query.get() is pcall'd because it throws when a query file is
      --     on rtp without its parser.
      local function attach(buf)
        if vim.b[buf].big_file then return end
        pcall(vim.treesitter.start, buf)
        local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
        local okq, indents = pcall(vim.treesitter.query.get, lang or "", "indents")
        if lang and okq and indents then
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end

      -- Install a missing parser on first use: opening a filetype that
      -- nvim-treesitter supports but PARSERS doesn't list builds its parser
      -- in the background (needs the tree-sitter CLI), then attaches every
      -- open buffer of that filetype. One install per language at a time;
      -- without the CLI nothing is recorded, so it starts once the CLI is
      -- on PATH, and a failed install is retried 5 minutes later at the
      -- earliest. Opt out with `vim.g.treesitter_auto_install = false`.
      local state = {} -- lang -> { status = "pending" | "failed" | "unavailable", at = os.time() }
      local RETRY_AFTER = 300
      local function maybe_install(buf)
        local ft = vim.bo[buf].filetype
        local lang = vim.treesitter.language.get_lang(ft)
        if not lang or vim.g.treesitter_auto_install == false then return end
        local s = state[lang]
        if s and not (s.status == "failed" and os.time() - s.at >= RETRY_AFTER) then return end
        if vim.treesitter.language.add(lang) then return end -- already available
        if vim.fn.executable("tree-sitter") == 0 then return end
        if not vim.tbl_contains(ts.get_available(), lang) then
          state[lang] = { status = "unavailable", at = os.time() }
          return
        end
        state[lang] = { status = "pending", at = os.time() }
        vim.notify(("Treesitter: installing the %s parser…"):format(lang))
        ts.install({ lang }):await(function(err, success)
          vim.schedule(function()
            -- Failed downloads/builds return false without throwing, so
            -- the task's error argument alone does not establish success.
            if err or not success then
              state[lang] = { status = "failed", at = os.time() }
              vim.notify(
                ("Treesitter: %s parser install failed: %s\nRetried on the next %s buffer after %d minutes, or run :TSInstall %s."):format(
                  lang,
                  tostring(err or "parser download or build failed (see :messages)"),
                  ft,
                  RETRY_AFTER / 60,
                  lang
                ),
                vim.log.levels.WARN
              )
              return
            end
            state[lang] = nil
            for _, b in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == ft then attach(b) end
            end
          end)
        end)
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
        callback = function(args)
          attach(args.buf)
          maybe_install(args.buf)
        end,
      })

      -- Session restore: a buffer whose filetype came back through
      -- sessionoptions' `localoptions` can miss the FileType handler above.
      -- Scheduled because vim.treesitter.start() parses synchronously and a
      -- big session would otherwise lengthen the visible restore stall.
      vim.api.nvim_create_autocmd("SessionLoadPost", {
        group = vim.api.nvim_create_augroup("user_treesitter_session", { clear = true }),
        callback = function()
          vim.schedule(function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then attach(buf) end
            end
          end)
        end,
      })
    end,
  },

  -- -------------------------------------------------------------------------
  -- nvim-treesitter-textobjects — select, move, swap.
  --
  -- Like nvim-treesitter above, this can't be lazy-loaded reliably on
  -- main: when its require() runs partway through nvim-treesitter's
  -- initialization, the resulting module table is incomplete and
  -- subsequent calls (like setup()) report "attempt to call field 'setup'
  -- (a nil value)". Pinning both to `lazy = false` keeps the load order
  -- predictable and the module tables intact.
  -- -------------------------------------------------------------------------
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    lazy = false,
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    -- Disable Neovim's built-in ftplugin keymaps that might collide with
    -- ours (e.g. some filetypes define `]m` for method navigation). Per
    -- the textobjects README's recommended init block.
    --
    -- IMPORTANT: `vim.g.no_plugin_maps` is a GLOBAL switch — it suppresses
    -- the default keymaps from EVERY built-in ftplugin (Python's `]]`,
    -- Markdown's `]]`/`[[`, etc.), not just the ones that would collide
    -- with textobjects. If some `]m`-style or `]]`-style motion from a
    -- built-in ftplugin stops working, this is why.
    init = function()
      vim.g.no_plugin_maps = true
    end,
    config = function()
      -- Configure global behavior. We pcall the setup so that an unusual
      -- main-branch commit (where setup may not exist) still leaves the
      -- keymaps below working with the helper modules' defaults.
      local ok, mod = pcall(require, "nvim-treesitter-textobjects")
      if ok and type(mod.setup) == "function" then
        mod.setup({
          select = {
            lookahead = true, -- jump forward to nearest match
            include_surrounding_whitespace = false,
          },
          move = {
            set_jumps = true, -- add to <C-o>/<C-i> jumplist
          },
        })
      end

      -- ---- Select textobjects (af / if / ac / ic / aa / ia / al / il / ai / ii) ----
      local select = require("nvim-treesitter-textobjects.select")
      local function map_select(lhs, query, desc)
        vim.keymap.set({ "x", "o" }, lhs, function()
          select.select_textobject(query, "textobjects")
        end, { desc = desc })
      end
      -- stylua: ignore start
      map_select("af", "@function.outer",      "a function")
      map_select("if", "@function.inner",      "inner function")
      map_select("ac", "@class.outer",         "a class")
      map_select("ic", "@class.inner",         "inner class")
      map_select("aa", "@parameter.outer",     "an argument")
      map_select("ia", "@parameter.inner",     "inner argument")
      map_select("al", "@loop.outer",          "a loop")
      map_select("il", "@loop.inner",          "inner loop")
      map_select("ai", "@conditional.outer",   "an if")
      map_select("ii", "@conditional.inner",   "inner if")
      -- stylua: ignore end

      -- ---- Move keymaps (]f / [f / ]k / [k / ]a / [a) ----
      -- ]c / [c are deliberately left to Vim's built-in diff-mode and
      -- to gitsigns' hunk navigation; we use ]k / [k for "class" instead.
      -- ]a / [a DO shadow a built-in: Neovim 0.11 maps them to :next /
      -- :previous (argument list). Kept on purpose — argument-list
      -- navigation is rare here, "next argument" is not — and `:next` /
      -- `:prev` still work as commands.
      local move = require("nvim-treesitter-textobjects.move")
      local function map_move(lhs, fn, query, desc)
        vim.keymap.set({ "n", "x", "o" }, lhs, function()
          fn(query, "textobjects")
        end, { desc = desc })
      end
      -- stylua: ignore start
      map_move("]f", move.goto_next_start,     "@function.outer",  "Next function start")
      map_move("[f", move.goto_previous_start, "@function.outer",  "Prev function start")
      map_move("]k", move.goto_next_start,     "@class.outer",     "Next class start")
      map_move("[k", move.goto_previous_start, "@class.outer",     "Prev class start")
      map_move("]a", move.goto_next_start,     "@parameter.inner", "Next argument")
      map_move("[a", move.goto_previous_start, "@parameter.inner", "Prev argument")
      -- stylua: ignore end

      -- ---- Swap parameters (<leader>cs / <leader>cS) ----
      local swap = require("nvim-treesitter-textobjects.swap")
      vim.keymap.set("n", "<leader>cs", function()
        swap.swap_next("@parameter.inner")
      end, { desc = "Swap parameter forward" })
      vim.keymap.set("n", "<leader>cS", function()
        swap.swap_previous("@parameter.inner")
      end, { desc = "Swap parameter backward" })
    end,
  },

  -- -------------------------------------------------------------------------
  -- treesitter-context — sticky function/class header at the top of
  -- the window while you scroll. Uses native vim.treesitter APIs, so
  -- the master/main split doesn't affect it. Safe to lazy-load on a
  -- buffer event since it only reads from buffers, never installs.
  -- -------------------------------------------------------------------------
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = { "BufReadPost", "BufNewFile" },
    keys = {
      {
        "<leader>cC",
        function()
          require("treesitter-context").go_to_context(vim.v.count1)
        end,
        desc = "Jump to context",
      },
    },
    opts = {
      max_lines = 3, -- never let context grow taller than 3 lines
      multiline_threshold = 1, -- one line per context level (keeps it compact)
    },
  },
}
