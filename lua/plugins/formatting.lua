-- lua/plugins/formatting.lua
--
-- conform.nvim — runs external formatters (prettier, stylua, clang-format,
-- …) and falls back to LSP formatting when no external one is configured.
-- We deliberately do NOT format-on-save by default: it's a foot-gun on
-- shared repos where everyone has slightly different formatter versions.
-- Use `<leader>lf` (LSP) or `<leader>cf` (conform) to format explicitly.
--
-- To enable format-on-save: set `format_on_save = ...` in the `opts`
-- table below (commented-out examples are right there). For a toggle,
-- use the function form and the bundled `:FormatToggle` command.
--
-- INSTALLING THE FORMATTERS: conform only RUNS formatters; it never
-- installs them. mason-lspconfig (lsp.lua) installs LSP servers; the
-- second spec in this file (mason-tool-installer) installs everything
-- else via Mason on startup: formatters, shellcheck and the debug
-- adapters. Without it, `<leader>cf` silently falls back to LSP
-- formatting where available (lua_ls can; pyright can't — so Python
-- wouldn't format at all).

return {
  -- =========================================================================
  -- conform.nvim — the formatter runner.
  -- =========================================================================
  {
    "stevearc/conform.nvim",
    -- Lazy-load on keymap or :ConformInfo only. format_on_save (off by
    -- default) needs `event = "BufWritePre"` so conform is loaded before
    -- the first write: add it when you enable format_on_save below.
    --
    -- :FormatToggle is deliberately NOT listed in `cmd` even though this
    -- file defines it. The `init` block below creates the real command at
    -- startup; listing the same name in `cmd` ALSO makes lazy.nvim
    -- register a loader stub for it, and the two clobber each other —
    -- since conform's setup never (re-)defines the command, the stub path
    -- ends in "load conform, delete stub, re-run a command that no longer
    -- exists". The command only flips vim.g/vim.b flags anyway, so it
    -- needs no plugin load and no lazy trigger.
    cmd = { "ConformInfo" },
    -- `init` runs at startup, before conform is required. We register
    -- :FormatToggle here (rather than in `config`) so the command exists
    -- even before conform has been loaded — otherwise the first invocation
    -- after a fresh nvim would fail until something else triggered conform.
    init = function()
      vim.api.nvim_create_user_command("FormatToggle", function(args)
        if args.bang then
          vim.g.disable_autoformat = not vim.g.disable_autoformat
          vim.notify("Format-on-save (global) → " .. (vim.g.disable_autoformat and "OFF" or "ON"))
        else
          vim.b.disable_autoformat = not vim.b.disable_autoformat
          vim.notify("Format-on-save (buffer) → " .. (vim.b.disable_autoformat and "OFF" or "ON"))
        end
      end, { bang = true, desc = "Toggle format-on-save (buffer; ! for global)" })
    end,
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ async = true })
        end,
        mode = { "n", "x" },
        desc = "Format buffer/selection",
      },
      { "<leader>cF", "<cmd>ConformInfo<cr>", desc = "Conform info" },
    },
    opts = {
      -- LSP formatting when a filetype has no formatter available. Set
      -- here rather than in each format() call: an explicit lsp_format
      -- in the call would override the per-filetype one on `_` below.
      default_format_opts = { lsp_format = "fallback" },

      -- ------------------------------------------------------------------
      -- formatters_by_ft: list of formatters to run for each filetype, in
      -- order. Conform skips ones that aren't installed; see `:Mason` ->
      -- "Formatter", or rely on the mason-tool-installer spec below.
      -- ------------------------------------------------------------------
      formatters_by_ft = require("config.tooling").formatters({
        lua = { "stylua" },
        -- C / C++: conform's formatter name is `clang_format` (underscore);
        -- the Mason PACKAGE is `clang-format` (dash — see the installer
        -- spec below). clang-format auto-discovers your project-root
        -- .clang-format, so `<leader>cf` follows the same style as
        -- `<leader>lf` (clangd drives clang-format under the hood).
        -- stylua: ignore start
        c          = { "clang_format" },
        cpp        = { "clang_format" },
        python     = require("config.tooling").python_formatters(), -- ruff is faster than black+isort
        javascript = { "prettierd", "prettier", stop_after_first = true },
        typescript = { "prettierd", "prettier", stop_after_first = true },
        -- stylua: ignore end
        javascriptreact = { "prettierd", "prettier", stop_after_first = true },
        typescriptreact = { "prettierd", "prettier", stop_after_first = true },
        -- stylua: ignore start
        json       = { "prettierd", "prettier", stop_after_first = true },
        jsonc      = { "prettierd", "prettier", stop_after_first = true },
        yaml       = { "prettierd", "prettier", stop_after_first = true },
        markdown   = { "prettierd", "prettier", stop_after_first = true },
        html       = { "prettierd", "prettier", stop_after_first = true },
        css        = { "prettierd", "prettier", stop_after_first = true },
        go         = { "goimports", "gofmt" },
        rust       = { "rustfmt", lsp_format = "fallback" }, -- rustfmt ships with rustup, not Mason
        sh         = { "shfmt" },
        bash       = { "shfmt" },
        toml       = { "taplo" },
        -- stylua: ignore end
        -- Fallback for any other filetype: LSP formatting when a client
        -- offers it (cssls for scss/less, clangd for objc/cuda), else
        -- whitespace trimming — e.g. scheme and Windows batch (.bat/.cmd),
        -- which have no formatter in the Mason / conform ecosystem.
        -- "prefer", not the default "fallback": trim_whitespace is always
        -- available, so "fallback" would never reach the LSP.
        ["_"] = { "trim_whitespace", lsp_format = "prefer" },
      }),

      -- Run on save? Off by default. To enable it with the :FormatToggle
      -- escape hatches, uncomment:
      -- format_on_save = function(bufnr)
      --   if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      --     return
      --   end
      --   return { timeout_ms = 500 }
      -- end,
      --
      --       Then run `:FormatToggle` (the `init = function` block at the
      --       top of this file defines it) to flip the buffer flag, or
      --       `:FormatToggle!` for the global one.

      -- Formatter-specific tweaks.
      formatters = {
        -- Visual-selection formatting (<leader>cf in x mode): conform's
        -- built-in passes the offset of the selection's LAST character as
        -- --range-end, but stylua only reformats statements that end BEFORE
        -- range-end, so a linewise selection would never cover its own last
        -- statement. Same arguments as conform's built-in, end offset + 1.
        stylua = {
          range_args = function(_, ctx)
            local s, e = require("conform.util").get_offsets_from_range(ctx.buf, ctx.range)
            return {
              "--search-parent-directories",
              "--stdin-filepath",
              "$FILENAME",
              "--range-start",
              tostring(s),
              "--range-end",
              tostring(e + 1),
              "-",
            }
          end,
        },
        -- Indent switch cases, unless the project has an .editorconfig:
        -- shfmt ignores EditorConfig as soon as it gets a formatting flag.
        -- (conform itself adds `-i <shiftwidth>` only without one.)
        shfmt = {
          prepend_args = function(_, ctx)
            local found = vim.fs.find(".editorconfig", { path = ctx.dirname, upward = true })
            return found[1] and {} or { "-ci" }
          end,
        },
      },
    },
  },

  -- =========================================================================
  -- mason-tool-installer — installs the formatters conform needs, plus
  -- shellcheck and the debug adapters, queuing installs once on startup.
  --
  -- Only the tools for the languages actually in use are listed:
  --   stylua        → Lua
  --   clang-format  → C / C++   (Mason package name uses a DASH; conform
  --                              references it as `clang_format`)
  --   shfmt         → Bash / sh
  --   shellcheck    → Bash / sh diagnostics (bashls calls it; see below)
  --   prettierd     → JS/TS/JSON/YAML/Markdown/HTML/CSS
  --   debugpy, codelldb, cpptools, bash-debug-adapter → the DAP adapters
  --                 lua/config/dap.lua registers (python, codelldb, cppdbg,
  --                 bashdb)
  --
  -- clang-format and debugpy come from PyPI, so Mason needs Python 3 for
  -- them (:checkhealth config reports it).
  --
  -- ruff (Python) and taplo (TOML) are DELIBERATELY absent here — they're
  -- installed by mason-lspconfig in lsp.lua as language servers, and the
  -- same binary is the formatter conform calls (ruff_format /
  -- ruff_organize_imports, taplo). Single owner avoids the fresh-install
  -- "already installing" race; see the ruff note in ensure_installed below.
  --
  -- Deliberately NOT listed:
  --   rustfmt    — ships with the rustup toolchain and is found on PATH;
  --                a second Mason copy would just shadow it.
  --   scheme     — no Scheme formatter exists in Mason/conform; Scheme
  --                files fall through to trim_whitespace (above).
  --   batch      — likewise nothing for Windows .bat/.cmd.
  --   js-debug-adapter, delve — vscode-js-debug builds from source with
  --                npm + gulp, and delve installs via `go install`; Mason
  --                would retry a failing build on every startup. Add them
  --                once node/npm or Go are on PATH and you debug JS/TS or Go
  --                (and register the adapter in lua/config/dap.lua).
  --
  -- Keep every package here out of mason-lspconfig's ensure_installed list
  -- in lsp.lua: two installers queuing the same package on a fresh install
  -- race ("Package is already installing").
  -- =========================================================================
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    -- NO lazy trigger here on purpose → loads eagerly (this config's
    -- default, since no event/cmd/keys is set). mason-tool-installer fires
    -- its install from a VimEnter autocmd registered in its OWN plugin/
    -- file. If we lazy-load it on VeryLazy (or any event that lands after
    -- VimEnter), the plugin is sourced AFTER VimEnter has already fired,
    -- so that autocmd registers too late and never runs — setup() stores
    -- the list but nothing ever installs it. Eager loading sources the plugin
    -- before VimEnter, so the hook fires. You can always trigger it by
    -- hand with :MasonToolsInstall / :MasonToolsUpdate regardless.
    opts = {
      ensure_installed = require("config.tool_intent").option("packages", {
        "stylua", -- Lua
        "clang-format", -- C / C++ (dash — this is the Mason package name)
        -- ruff is NOT listed here even though conform uses it (ruff_format /
        -- ruff_organize_imports above): it's installed once via
        -- mason-lspconfig in lua/plugins/lsp.lua, where it also runs as
        -- the Python LINT server. Listing the same Mason package in two
        -- ensure_installed sets can race on a fresh install ("Package is
        -- already installing"), so ruff has a single owner (the LSP spec) and
        -- conform simply calls the binary that install provides.
        "shfmt", -- Bash / sh
        -- Not a formatter, but installed here for the same reason: bashls
        -- produces NO diagnostics by itself — it shells out to shellcheck
        -- when it finds it on PATH (Mason's bin dir is on PATH). Without it
        -- a script with an unquoted $var and an unclosed `if` showed 0
        -- diagnostics under bashls.
        "shellcheck",
        -- JS/TS/JSON/YAML/Markdown/HTML/CSS formatter (formatters_by_ft
        -- tries prettierd, then prettier). Without it those files fall
        -- back to LSP formatting, or none for YAML/Markdown.
        "prettierd",
        -- Debug adapters (Mason package names; lua/config/dap.lua points
        -- the adapters at their bin/ shims).
        "debugpy",
        "codelldb",
        "cpptools",
        "bash-debug-adapter",
      }),
      -- The list above uses MASON PACKAGE NAMES, so no name translation is
      -- needed. With the mason-lspconfig integration on (the default),
      -- setup() does pcall(require, "mason-lspconfig"), and lazy.nvim's
      -- require hook would turn that into a full plugin load at startup,
      -- defeating its BufReadPre trigger in lsp.lua (~30 ms of an ~80 ms
      -- startup, measured with --startuptime). The other two integrations
      -- belong to plugins this config doesn't install.
      integrations = {
        -- stylua: ignore start
        ["mason-lspconfig"] = false,
        ["mason-null-ls"]   = false,
        ["mason-nvim-dap"]  = false,
        -- stylua: ignore end
      },
      -- stylua: ignore start
      run_on_start = true, -- queue installs once on startup
      auto_update  = false, -- don't silently update tools under you
      -- stylua: ignore end
    },
    config = function(_, opts)
      require("config.tool_intent").validate_installation("packages", opts)
      opts = vim.deepcopy(opts)
      local supported = false
      for i, item in ipairs(opts.ensure_installed) do
        local entry = type(item) == "string" and { item } or item
        local package, pin = require("config.tool_intent").package(entry)
        entry[1], entry.version = package, pin
        local condition = entry.condition
        local enabled = require("config.tool_intent").enabled(entry)
        supported = enabled and require("config.tooling").install_supported(package) or supported
        entry.condition = function()
          local selected = condition == nil
            or condition == true
            or type(condition) == "function" and condition() == true
          return selected and require("config.tooling").install_supported(package)
        end
        opts.ensure_installed[i] = entry
      end
      if not supported then opts.run_on_start = false end
      require("mason-tool-installer").setup(opts)
    end,
  },
}
