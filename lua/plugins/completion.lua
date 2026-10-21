-- lua/plugins/completion.lua
--
-- blink.cmp — the completion engine. It's the modern (2024+) successor to
-- nvim-cmp: significantly faster (Rust fuzzy matcher), smaller config
-- surface, and ships with snippet support out of the box.
--
-- Neovim 0.12 can complete as you type on its own ('autocomplete' and
-- vim.lsp.completion.enable()); blink.cmp adds the fuzzy matcher, snippet,
-- path, buffer and lazydev sources in one menu, documentation and
-- signature popups, and cmdline completion. If you ever want to swap it
-- out, the spec for nvim-cmp is similar in shape but verbose.

return {
  {
    "saghen/blink.cmp",
    version = "*", -- pin to releases; blink ships pre-built binaries per tag
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = {
      -- LuaSnip is optional but lets you use the rich vscode-snippet
      -- ecosystem via friendly-snippets.
      --
      -- We deliberately do NOT add `build = "make install_jsregexp"` here.
      -- jsregexp is an optional native extension used only for advanced
      -- regex transforms inside snippet bodies; it fails to link on
      -- Windows + LuaJIT (Neovim ships LuaJIT, but the makefile expects
      -- a full Lua 5.1 static lib, so every `lua_*` symbol comes up
      -- "undefined"). Skipping it gives you ~99% of LuaSnip's features
      -- with zero build step. If you ever need transforms, install
      -- jsregexp via `luarocks --lua-version=5.1 install jsregexp`.
      {
        "L3MON4D3/LuaSnip",
        version = "v2.*",
        -- friendly-snippets must be on 'runtimepath' BEFORE the lazy_load()
        -- below runs, so it is LuaSnip's dependency (as a sibling under
        -- blink it was added after this config, and lazy_load found none).
        dependencies = { "rafamadriz/friendly-snippets" },
        config = function()
          -- Auto-exit a snippet session when the cursor leaves its region.
          -- Without this, LuaSnip keeps the session "jumpable" after you've
          -- moved away, and blink's default <Tab> = { 'snippet_forward',
          -- 'fallback' } then jumps back into that stale snippet (often a few
          -- lines UP) instead of indenting. It's intermittent because it only
          -- happens while a leftover session lingers — once it resolves, <Tab>
          -- falls back to inserting spaces again. CursorMoved/CursorMovedI exit
          -- the session the moment the cursor moves outside the snippet bounds
          -- (jumping between placeholders stays in-region, so that's unaffected);
          -- delete_check_events exits if the snippet text is deleted. The
          -- ModeChanged unlink autocmd in autocmds/glue.lua is a backstop for the
          -- leave-insert/select-mode case.
          require("luasnip").setup({
            region_check_events = "CursorMoved,CursorMovedI",
            delete_check_events = "TextChanged,InsertLeave",
          })
          -- Load friendly-snippets (VS Code format) into LuaSnip. With
          -- blink's `snippets.preset = "luasnip"`, blink only offers what
          -- LuaSnip holds, and nothing loaded friendly-snippets: LuaSnip had
          -- 0 snippets for every filetype, so the only "snippets" in the
          -- menu were the language servers' own. lazy_load() reads each
          -- filetype's file the first time a buffer of it is seen (and
          -- for the buffers already open).
          require("luasnip.loaders.from_vscode").lazy_load()
        end,
      },
    },
    opts = {
      -- ----------------------------------------------------------------
      -- Keymap preset. "default" = <C-Space> trigger, <C-n>/<C-p> (or
      -- <Up>/<Down>) to select, <C-y> accept, <C-e> cancel/dismiss,
      -- <Tab> snippet jump. Other presets: "super-tab" (Tab accepts the
      -- highlighted item), "enter" (Enter accepts; no Tab binding).
      --
      -- <C-Space> is kept (it still works on terminals that speak the kitty
      -- keyboard protocol), but it is unreliable elsewhere: legacy terminals
      -- — the Windows console, plus multiplexers not negotiating the protocol
      -- (zellij/tmux over such a terminal) — cannot distinguish Ctrl+Space
      -- from a bare <Space>. Since <leader> is <Space>, the keypress collapses
      -- to <leader> and pops which-key instead of opening the completion menu.
      --
      -- So we ALSO make <C-n>/<C-p> open the menu, not merely navigate it:
      -- those keys are transmitted cleanly by every terminal. Putting "show"
      -- first means a closed menu opens on the first press (nothing is
      -- inserted — the highlighted item only previews via ghost_text until you
      -- <C-y>); once the menu is open "show" is a no-op so the press falls to
      -- select_next/prev and moves the selection. (The default preset's
      -- <C-n> = { select_next, fallback_to_mappings } does nothing on a
      -- closed menu.) One of the two always handles the key, so native
      -- i_CTRL-N / i_CTRL-P keyword completion is only reached where blink
      -- is disabled.
      --
      -- <C-k> = false drops the preset's insert-mode signature toggle, so
      -- <C-k> stays Vim's digraph key (the signature popup opens by itself).
      -- ----------------------------------------------------------------
      keymap = {
        preset = "default",
        ["<C-n>"] = { "show", "select_next" },
        ["<C-p>"] = { "show", "select_prev" },
        ["<C-k>"] = false,
      },

      appearance = {
        nerd_font_variant = "mono", -- pick "normal" if your icons look squashed
      },

      completion = {
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
        },
        menu = {
          draw = {
            treesitter = { "lsp" }, -- syntax-highlight item kinds via treesitter
          },
        },
        ghost_text = { enabled = true }, -- inline preview of the highlighted completion
      },

      signature = { enabled = true }, -- function signature popup while typing args

      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        -- Lua buffers add lazydev to the defaults. Listed per filetype, not
        -- in `default`: blink requires every listed source's module when
        -- sources are set up, which would load lazydev in every filetype.
        per_filetype = { lua = { inherit_defaults = true, "lazydev" } },
        providers = {
          -- lazydev.nvim's blink source (the plugin spec itself lives in
          -- lua/plugins/lazydev.lua). It surfaces module-path completions for
          -- `require("…")` and the `vim.*` API in Lua config buffers. The high
          -- score_offset floats these above the buffer/LSP items when they
          -- apply.
          lazydev = {
            name = "LazyDev",
            module = "lazydev.integrations.blink",
            score_offset = 100,
          },
        },
      },

      snippets = { preset = "luasnip" },

      -- Command-line completion. Mirrors blink's default source routing, but
      -- SKIPS completion for shell/filter commands (:!cmd, :%!cmd, :3,7!cmd,
      -- :'<,'>!cmd). Those use Neovim's "shellcmd" completion, which
      -- enumerates every executable on $PATH — a multi-second, UI-blocking
      -- scan on Windows' large PATH, and blink fires it the instant you type
      -- "!" (which it lists as a cmdline trigger char). Result was a hang
      -- right after ":!". Native wildmenu (<Tab>) still completes shell
      -- commands on demand if you ever want it.
      cmdline = {
        sources = function()
          local ctype = vim.fn.getcmdtype()
          if ctype == "/" or ctype == "?" then return { "buffer" } end
          if ctype == ":" or ctype == "@" then
            -- getcmdcompltype() returns "shellcmd" for every form — :!, :%!,
            -- :3,7!, :'<,'>!, :'a,'b!, :/re/!, :sil ! — including a bare
            -- "!". The pattern is only a cheap second guard for the simple
            -- numeric-range forms.
            if
              vim.fn.getcmdcompltype() == "shellcmd"
              or vim.fn.getcmdline():match("^%s*[%%%d,%.%$;]*!")
            then
              return {}
            end
            return { "cmdline" }
          end
          return {}
        end,

        -- blink's default cmdline <Tab>/<S-Tab> have no 'fallback', so with
        -- our empty sources for shell commands they would just swallow the
        -- key. Adding 'fallback' lets <Tab> pass through to Neovim's native
        -- wildmenu there — so you CAN still Tab-complete an executable inside
        -- :! on demand (that's the slow $PATH scan, but only when you ask for
        -- it). For normal commands blink still handles <Tab> first; fallback
        -- is only reached when blink has nothing to offer.
        keymap = {
          preset = "cmdline",
          ["<Tab>"] = { "show_and_insert_or_accept_single", "select_next", "fallback" },
          ["<S-Tab>"] = {
            function(cmp)
              return cmp.show_and_insert_or_accept_single({ initial_selected_item_idx = -1 })
            end,
            "select_prev",
            "fallback",
          },
        },
      },

      -- Fuzzy matcher: blink ships a Rust implementation that is much
      -- faster than the Lua fallback. The binary is downloaded by
      -- `version = "*"`; if you're offline, set `implementation = "lua"`.
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
    -- Lets another spec fragment for blink.cmp APPEND to sources.default
    -- instead of replacing it (lazy.nvim list-merge).
    opts_extend = { "sources.default" },
  },
}
