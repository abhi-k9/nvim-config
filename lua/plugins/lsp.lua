-- lua/plugins/lsp.lua
--
-- LSP: language-server config + Mason (the package manager that installs
-- LSP servers, formatters, linters, and DAP adapters for you).
--
-- Architecture:
--   * mason.nvim          – installs binaries (e.g. `lua-language-server`)
--   * mason-lspconfig     – bridges Mason's package names to lspconfig's
--                           server names so a server you install via Mason
--                           is auto-configured and enabled
--   * nvim-lspconfig      – the configs themselves; we use the modern
--                           `vim.lsp.config()` API for per-server tweaks

return {
  -- -------------------------------------------------------------------------
  -- mason.nvim — UI-driven installer. Run `:Mason` to manage.
  -- -------------------------------------------------------------------------
  {
    "mason-org/mason.nvim",
    cmd = "Mason",
    -- Before Mason can install anything: on Windows, make sure `tar` is
    -- Windows' own bsdtar (see util.windows_tar_shim for the failure).
    config = function(_, opts)
      require("config.util").windows_tar_shim()
      require("mason").setup(opts)
    end,
    keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
    build = function()
      if require("config.tooling").mason_download_ready() then vim.cmd.MasonUpdate() end
    end,
    opts = {
      ui = {
        icons = {
          -- stylua: ignore start
          package_installed   = "✓",
          package_pending     = "➜",
          package_uninstalled = "✗",
          -- stylua: ignore end
        },
      },
    },
  },

  -- -------------------------------------------------------------------------
  -- mason-lspconfig — auto-installs/registers LSP servers listed below.
  -- mason-lspconfig 2.x dropped `automatic_installation` and `handlers`
  -- entirely; the new behaviour is: `ensure_installed` drives installation,
  -- and `automatic_enable = true` (the default) calls vim.lsp.enable() on
  -- every installed server. Per-server tweaks go through vim.lsp.config()
  -- in the nvim-lspconfig spec below.
  -- -------------------------------------------------------------------------
  {
    "mason-org/mason-lspconfig.nvim",
    -- FileType as well: a buffer that never touches a file (`:enew`, then
    -- `:set ft=lua`, or a scratch buffer a plugin creates) fires neither
    -- BufReadPre nor BufNewFile, so the LSP stack would never load for it.
    -- lazy.nvim replays the triggering FileType after loading, which is
    -- what vim.lsp.enable() attaches on.
    event = { "BufReadPre", "BufNewFile", "FileType" },
    -- Configure overrides and completion capabilities BEFORE setup() can
    -- automatically enable installed servers. vim.lsp.enable() immediately
    -- activates existing buffers, so configuring after it is too late for
    -- the first client. Keep the dependency one-way to avoid a cycle.
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      -- stylua is installed by Mason for conform (formatting.lua), but it
      -- ALSO has an lspconfig server definition, so automatic_enable was
      -- starting it as a second language server on every Lua buffer — a
      -- duplicate formatter that bypassed conform's per-file condition.
      automatic_enable = { exclude = { "stylua" } },
      -- Each server here is installed by Mason on first launch and
      -- automatically enabled. Edit freely; if you don't write a given
      -- language, drop it.
      ensure_installed = {
        "lua_ls", -- Lua
        "bashls", -- Bash
        "clangd", -- C / C++ / Objective-C
        "pyright", -- Python: types + completion (see pyright/ruff split below)
        "ruff", -- Python: lint diagnostics + import sorting (ruff LSP).
        -- Installed HERE (not via mason-tool-installer in
        -- formatting.lua, which lists the other formatters):
        -- ruff is BOTH an LSP and conform's Python formatter,
        -- and listing the same Mason package in two
        -- ensure_installed sets can collide on a fresh install
        -- ("Package is already installing"). One owner: this
        -- one. The one `ruff` binary serves the LSP here AND
        -- conform's ruff_format / ruff_organize_imports.
        "ts_ls", -- TypeScript / JavaScript (formerly tsserver)
        "rust_analyzer", -- Rust
        --"gopls",          -- Go
        "jsonls", -- JSON
        "yamlls", -- YAML
        "html",
        "cssls",
        "marksman", -- Markdown
        "taplo", -- TOML
      },
    },
    config = function(_, opts)
      require("mason-lspconfig").setup(require("config.tooling").configure_servers(opts))
    end,
  },

  -- -------------------------------------------------------------------------
  -- nvim-lspconfig — the actual LSP setup.
  -- -------------------------------------------------------------------------
  {
    "neovim/nvim-lspconfig",
    -- FileType as well: a buffer that never touches a file (`:enew`, then
    -- `:set ft=lua`, or a scratch buffer a plugin creates) fires neither
    -- BufReadPre nor BufNewFile, so the LSP stack would never load for it.
    -- lazy.nvim replays the triggering FileType after loading, which is
    -- what vim.lsp.enable() attaches on.
    event = { "BufReadPre", "BufNewFile", "FileType" },
    dependencies = {
      "mason-org/mason.nvim",
      "saghen/blink.cmp", -- so completion capabilities are advertised to servers
    },
    config = function()
      -- Remove Neovim's default gr-prefix LSP maps. We bind `gr` itself to
      -- references below, and while a user map doesn't DELETE the
      -- defaults, any remaining gr<x> turns `gr` into an ambiguous prefix:
      -- every press waits out timeoutlen (400 ms) before firing. Their
      -- functionality exists on explicit maps here (<leader>lr rename,
      -- <leader>la code action, gI implementation, gy type definition).
      --
      -- Deleted by DISCOVERY rather than a fixed list: 0.11 shipped
      -- grr/grn/gra/gri, 0.12 added grt (type definition) and grx (codelens
      -- run), and a hard-coded list would let the next one bring the delay
      -- back. Only Neovim's own defaults are touched: gr<x> maps whose
      -- description names a vim.lsp function.
      for _, mode in ipairs({ "n", "x" }) do
        for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
          if m.lhs:match("^gr.") and (m.desc or ""):match("^vim%.lsp%.") then
            pcall(vim.keymap.del, mode, m.lhs)
          end
        end
      end

      -- Diagnostic UI: gutter icons, inline virtual text, etc.
      vim.diagnostic.config({
        severity_sort = true,
        float = { source = "if_many" },
        underline = { severity = vim.diagnostic.severity.ERROR },
        -- Glyphs come from lua/config/icons.lua — shared with lualine and
        -- bufferline so all three surfaces always agree.
        signs = { text = require("config.icons").diagnostic_signs() },
        virtual_text = {
          spacing = 4,
          source = "if_many",
          prefix = "●",
        },
      })

      -- ---------------------------------------------------------------------
      -- Per-buffer keymaps + features when an LSP attaches.
      -- ---------------------------------------------------------------------
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
        callback = function(ev)
          local buf = ev.buf
          -- Virtual buffers (diffview://, fugitive://, oil://, …) carry a
          -- real filetype, so vim.lsp.enable attaches servers to them — but
          -- servers only understand file:// URIs. Opening a C++ diff made
          -- clangd reject every request ("clangd only supports 'file' URI
          -- scheme"), shown as an error per request. Big files
          -- (autocmds/bigfile.lua) are detached too: every server would
          -- receive and analyse the whole text. Detach (scheduled: not
          -- allowed from inside LspAttach) and skip the setup below.
          if
            vim.b[buf].big_file
            or vim.bo[buf].buftype ~= ""
            or (
              vim.api.nvim_buf_get_name(buf) ~= ""
              and not require("config.util").is_file_buffer(buf)
            )
          then
            vim.schedule(function()
              pcall(vim.lsp.buf_detach_client, buf, ev.data.client_id)
            end)
            return
          end
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          local function k(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = "LSP: " .. desc })
          end

          -- Python runs TWO servers on the same buffer: pyright (types +
          -- completion + hover) and ruff (lint diagnostics + import sorting).
          -- ruff also advertises a hover provider, but its hover is thin next
          -- to pyright's, and with two hover-capable clients `K` would open a
          -- multi-client picker or merge both. Silence ruff's hover so pyright
          -- is the single, authoritative hover source. (Guarded by name so this
          -- only touches ruff; every other server keeps its hover.)
          if client and client.name == "ruff" then
            client.server_capabilities.hoverProvider = false
          end

          -- stylua: ignore start
          k("n", "gd", vim.lsp.buf.definition,      "Definition")
          k("n", "gD", vim.lsp.buf.declaration,     "Declaration")
          -- stylua: ignore end
          -- `gr` opens references in the Trouble panel rather than dumping them
          -- into the quickfix list (what bare vim.lsp.buf.references does). The
          -- panel is navigable, previews inline, and shares the <leader>x list
          -- family's UX. `toggle` means a second `gr` closes it. `gd`/`gD`/`gI`/
          -- `gy` stay as DIRECT jumps on purpose — for a single destination,
          -- jumping straight there beats opening a list; `gr` is the one that
          -- is genuinely many-valued, so it's the one worth routing to Trouble.
          -- The <cmd>Trouble ...> form lazy-loads trouble.nvim on first use
          -- (its spec triggers on the Trouble command), so this stays cheap.
          -- <leader>xl (trouble.lua) remains the broader refs/defs/impl view.
          k("n", "gr", "<cmd>Trouble lsp_references toggle focus=true<cr>", "References (Trouble)")
          -- stylua: ignore start
          -- gI, not gi: Vim's built-in `gi` (resume insert where you last
          -- left it) is too useful to shadow in every LSP buffer.
          k("n", "gI", vim.lsp.buf.implementation,  "Implementation")
          k("n", "gy", vim.lsp.buf.type_definition, "Type definition")
          -- stylua: ignore end
          -- NO `K` mapping here, deliberately. nvim-ufo (folding.lua)
          -- owns the global `K`: peek the fold under the cursor, fall
          -- through to vim.lsp.buf.hover() otherwise. A buffer-local
          -- `K` → hover here would shadow that global map in every
          -- LSP-attached buffer — i.e. exactly the buffers that have
          -- folds — making the peek feature unreachable.
          --
          -- Signature help on <leader>lk (normal mode), not <C-k>: <C-k> is
          -- the global window-up key (keymaps.lua) and a buffer-local one
          -- would shadow it in every LSP-attached buffer. Insert mode needs
          -- no binding: blink.cmp auto-shows the signature popup while you
          -- type arguments (signature = { enabled = true } in completion.lua).
          -- Insert <C-k> stays Vim's i_CTRL-K digraph key: completion.lua
          -- removes blink's preset <C-k>, and keymaps.lua's insert <C-s>
          -- replaces Neovim's default i_CTRL-S signature help.
          k("n", "<leader>lk", vim.lsp.buf.signature_help, "Signature help")
          k("n", "<leader>lr", vim.lsp.buf.rename, "Rename")
          -- "x", not "v": "v" also covers SELECT mode, where a <leader>
          -- (<Space>) map makes typing a space inside a snippet placeholder
          -- wait for timeoutlen. Same rule as keymaps.lua's visual maps.
          k({ "n", "x" }, "<leader>la", vim.lsp.buf.code_action, "Code action")
          k("n", "<leader>lf", function()
            require("config.lsp_format").format(buf)
          end, "Format")

          -- Inlay hints — Neovim 0.10+. Two subtle correctness points:
          --
          --  (1) The bufnr argument on is_enabled() and enable() is
          --      MANDATORY: without it, enable() flips the global state and
          --      pressing the keymap in buffer A would toggle hints in
          --      every other buffer too.
          --
          --  (2) We track the user's last toggle preference in
          --      vim.g.user_inlay_hints_enabled. Without this, every new
          --      buffer of a supporting language would unconditionally turn
          --      hints back on — so pressing <leader>lh to disable them
          --      would feel like nothing happened the next time the user
          --      opened a file. Default is `true` (hints on).
          --
          -- Both the keymap and the auto-enable are gated on the client
          -- actually supporting inlay hints; for non-supporting servers,
          -- there's no point binding the toggle.
          if client and client:supports_method("textDocument/inlayHint", buf) then
            if vim.g.user_inlay_hints_enabled == nil then vim.g.user_inlay_hints_enabled = true end
            vim.lsp.inlay_hint.enable(vim.g.user_inlay_hints_enabled, { bufnr = buf })
            k("n", "<leader>lh", function()
              local on = vim.lsp.inlay_hint.is_enabled({ bufnr = buf })
              vim.lsp.inlay_hint.enable(not on, { bufnr = buf })
              vim.g.user_inlay_hints_enabled = not on
            end, "Toggle inlay hints")
          end

          -- Linked editing: while you edit an HTML/XML/JSX opening tag, the
          -- server keeps the matching closing tag in sync. Only for servers
          -- that advertise it (html does). On by default; <leader>lt
          -- toggles it for the whole session (every client that supports
          -- it, and new ones attach in the chosen state — Neovim has no
          -- per-buffer switch for this, and no is_enabled(), hence
          -- vim.g.user_linked_editing).
          if client and client:supports_method("textDocument/linkedEditingRange", buf) then
            if vim.g.user_linked_editing == nil then vim.g.user_linked_editing = true end
            vim.lsp.linked_editing_range.enable(
              vim.g.user_linked_editing,
              { client_id = client.id }
            )
            k("n", "<leader>lt", function()
              local on = not vim.g.user_linked_editing
              vim.g.user_linked_editing = on
              for _, c in ipairs(vim.lsp.get_clients()) do
                -- A dynamic registration may match a different buffer
                -- from the one containing this keymap. Toggle each
                -- supporting client once using its own attached buffers.
                for attached_buf in pairs(c.attached_buffers) do
                  if c:supports_method("textDocument/linkedEditingRange", attached_buf) then
                    vim.lsp.linked_editing_range.enable(on, { client_id = c.id })
                    break
                  end
                end
              end
              vim.notify("Linked tag editing " .. (on and "ON" or "OFF"))
            end, "Toggle linked tag editing")
          end

          -- Document colors: servers such as cssls report color values and
          -- Neovim highlights them (on by default). <leader>lc toggles it
          -- for this buffer.
          if client and client:supports_method("textDocument/documentColor", buf) then
            k("n", "<leader>lc", function()
              local on = vim.lsp.document_color.is_enabled({ bufnr = buf })
              vim.lsp.document_color.enable(not on, { bufnr = buf })
            end, "Toggle color swatches")
          end

          -- Document highlight on CursorHold: subtly underlines other
          -- occurrences of the symbol under the cursor.
          if client and client:supports_method("textDocument/documentHighlight", buf) then
            local hl_group_name = "user_lsp_highlight_" .. buf
            local hl_group = vim.api.nvim_create_augroup(hl_group_name, { clear = true })
            vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
              group = hl_group,
              buffer = buf,
              callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
              group = hl_group,
              buffer = buf,
              callback = vim.lsp.buf.clear_references,
            })
            -- Tear the autocmds down when the server detaches (:LspStop,
            -- server crash, scoper's clangd restart, …). Without this,
            -- CursorHold keeps calling document_highlight into a buffer
            -- with no capable client — at best a no-op, at worst a
            -- "method not supported" notification on every hold.
            vim.api.nvim_create_autocmd("LspDetach", {
              group = vim.api.nvim_create_augroup(
                "user_lsp_highlight_detach_" .. buf,
                { clear = true }
              ),
              buffer = buf,
              callback = function(dev)
                -- If ANOTHER attached client still supports the method
                -- (e.g. two servers on one buffer), keep the autocmds.
                for _, c in ipairs(vim.lsp.get_clients({ bufnr = dev.buf })) do
                  if
                    c.id ~= dev.data.client_id
                    and c:supports_method("textDocument/documentHighlight", dev.buf)
                  then
                    return
                  end
                end
                -- util.buf_clear_references takes the buffer explicitly;
                -- vim.lsp.buf.clear_references() acts on the CURRENT
                -- buffer, which is the wrong one whenever the detach is
                -- for a background buffer (e.g. scoper restarting clangd
                -- with many C++ buffers attached).
                vim.lsp.util.buf_clear_references(dev.buf)
                pcall(vim.api.nvim_del_augroup_by_name, hl_group_name)
              end,
            })
          end
        end,
      })

      -- ---------------------------------------------------------------------
      -- Per-server overrides via the vim.lsp.config API.
      -- The defaults are good; tweak only servers that need it.
      -- Completion capabilities need no line here: blink.cmp's plugin file
      -- calls vim.lsp.config("*", …) itself (hence the blink dependency).
      -- ---------------------------------------------------------------------

      -- -----------------------------------------------------------------
      -- Trim compound "dotted" filetypes from three servers' declared
      -- lists. nvim-lspconfig's stock configs declare filetypes like
      -- c.doxygen / cpp.doxygen (clangd), markdown.mdx (marksman), and
      -- yaml.docker-compose / yaml.gitlab / yaml.helm-values (yamlls).
      -- Those are Vim compound filetypes: valid to :setlocal, but NOTHING
      -- in stock Neovim's filetype detection (or this config) ever
      -- produces them — lspconfig lists them only so the server would
      -- still attach if some other plugin set one. Since nothing here
      -- does, they're dead entries whose only observable effect is a
      -- string of warnings in :checkhealth vim.lsp ("Unknown filetype
      -- 'c.doxygen' (Hint: filename extension != filetype)"), because the
      -- health check validates every ENABLED config's filetypes against
      -- vim.filetype's known set.
      --
      -- vim.lsp.config() replaces list-valued keys wholesale (verified,
      -- not merged element-wise), so these overrides are exact. If you
      -- later add filetype detection that emits one of the compound
      -- names (e.g. vim.filetype.add mapping docker-compose*.yml →
      -- "yaml.docker-compose"), re-add it here — and also
      -- vim.treesitter.language.register the base language for it, or
      -- the FileType handler in treesitter.lua won't find a parser and
      -- the file loses highlighting.
      vim.lsp.config("clangd", {
        filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
      })
      vim.lsp.config("marksman", {
        filetypes = { "markdown" },
      })
      -- yamlls also gets its settings tweak below; separate calls merge
      -- fine (only same-key lists replace).
      vim.lsp.config("yamlls", {
        filetypes = { "yaml" },
      })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
            -- Recognize the `vim` global so we don't get spammed with
            -- "undefined global" warnings while editing this config.
            diagnostics = { globals = { "vim" } },
            hint = { enable = true }, -- inlay hints
            completion = { callSnippet = "Replace" },
          },
        },
      })

      vim.lsp.config("yamlls", {
        settings = {
          yaml = {
            keyOrdering = false,
            schemas = {
              ["https://json.schemastore.org/github-workflow.json"] = ".github/workflows/*",
            },
          },
        },
      })

      -- -----------------------------------------------------------------
      -- Python: pyright + ruff, with responsibilities split so they don't
      -- double up. Before ruff was added, pyright ran alone and ruff's lint
      -- rules (unused imports, undefined names, pyflakes/pycodestyle/…) never
      -- surfaced as diagnostics — pyright does TYPE checking, not linting, so
      -- a whole class of warnings was silently absent. Now:
      --
      --   * ruff    → lint diagnostics + organize-imports (its strengths)
      --   * pyright → type checking + completion + hover (its strengths)
      --
      -- The split avoids overlap: pyright's own import organizer is turned off
      -- (ruff owns import sorting, and two organizers fighting over the same
      -- edit is how you get flip-flopping on save), and ruff's hover is
      -- silenced in the LspAttach handler above (pyright's hover wins). ruff
      -- the LSP shares the SAME binary conform calls for ruff_format /
      -- ruff_organize_imports — installing it once (ensure_installed above)
      -- covers both roles.
      vim.lsp.config("pyright", {
        settings = {
          pyright = {
            -- Let ruff be the single source of truth for import order.
            disableOrganizeImports = true,
          },
          python = {
            analysis = {
              -- "basic" is the sane default: real type errors without the
              -- flood "strict" produces on most untyped code. Bump to
              -- "strict" per-project via a `.nvim.lua` (exrc, see options.lua)
              -- or a pyrightconfig.json at the project root.
              typeCheckingMode = "basic",
            },
          },
        },
      })

      vim.lsp.config("ruff", {
        -- init_options.settings is ruff's native config channel; anything you
        -- can put in a project pyproject.toml `[tool.ruff]` can be forced here
        -- as a fallback. Left empty so a project's own pyproject.toml /
        -- ruff.toml wins — ruff discovers those by walking up from the file,
        -- exactly like clangd finds .clang-tidy. Add lint.select / lint.ignore
        -- here only if you want a global baseline for projects with no config.
        init_options = {
          settings = {},
        },
      })
    end,
  },
}
