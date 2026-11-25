-- lua/plugins/completion.lua
--
-- blink.cmp — the completion engine, with LSP/path/buffer/snippet sources
-- and optional Rust fuzzy matching. It is an alternative to nvim-cmp.
--
-- Neovim 0.12 can complete as you type on its own ('autocomplete' and
-- vim.lsp.completion.enable()); blink.cmp adds the fuzzy matcher, snippet,
-- path, buffer and lazydev sources in one menu, documentation and
-- signature popups, and cmdline completion. If you ever want to swap it
-- out, the spec for nvim-cmp is similar in shape but verbose.

local function cmdline_sources()
  local mode = vim.fn.getcmdtype()
  if mode == "/" or mode == "?" then return { "buffer" } end
  if mode == ":" or mode == "@" then
    if
      vim.fn.getcmdcompltype() ~= "shellcmd" and not vim.fn.getcmdline():match("^%s*[%%%d,%.%$;]*!")
    then
      return { "cmdline" }
    end
  end
  return {}
end

local function cmdline_tab(backward)
  return function(cmp)
    -- Blink claims a manual show immediately, even when there are no sources.
    -- Let the mapping reach native wildmenu before asking Blink to show.
    if #cmdline_sources() == 0 then
      local mode = vim.fn.getcmdtype()
      if mode ~= ":" and mode ~= "@" then return end
      -- A mapped Tab inserts a literal tab. CTRL-Z invokes wildmode from a mapping.
      local key = backward and vim.fn.wildmenumode() == 1 and "<C-p>" or "<C-z>"
      vim.api.nvim_feedkeys(vim.keycode(key), "in", false)
      return true
    end
    if
      cmp.show_and_insert_or_accept_single(backward and { initial_selected_item_idx = -1 } or nil)
    then
      return true
    end
    if backward then return cmp.select_prev() end
    return cmp.select_next()
  end
end

return {
  {
    "saghen/blink.cmp",
    version = "*", -- select release tags; lazy-lock.json records the exact revision
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = {
      -- LuaSnip is optional but lets you use the rich vscode-snippet
      -- ecosystem via friendly-snippets.
      --
      -- We deliberately do NOT add `build = "make install_jsregexp"` here.
      -- jsregexp is optional and needed for LSP-snippet regex transforms.
      -- Skipping it avoids a native build requirement on limited systems.
      -- If transforms are needed, follow LuaSnip's installation guidance for
      -- your compiler and Neovim LuaJIT runtime; Windows builds need matching
      -- tooling and can otherwise fail to link.
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
      -- highlighted item), "enter" (Enter accepts; Tab still jumps snippets).
      --
      -- <C-Space> is kept, but terminal/multiplexer or OS shortcuts may
      -- intercept it. Legacy terminals normally encode it as NUL (<C-@>),
      -- not bare Space; extended keyboard protocols can encode it explicitly.
      -- C-n/C-p provide an alternative when the key never reaches Neovim.
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
        list = { selection = { auto_insert = false } }, -- preview until explicitly accepted
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
        per_filetype = {
          lua = function()
            -- Its Lua FileType hook loads the optional provider when installed.
            if package.loaded.lazydev then return { inherit_defaults = true, "lazydev" } end
            return { inherit_defaults = true }
          end,
        },
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
        sources = cmdline_sources,
        keymap = {
          preset = "cmdline",
          ["<Tab>"] = { cmdline_tab(false), "fallback" },
          ["<S-Tab>"] = { cmdline_tab(true), "fallback" },
        },
      },

      -- Fuzzy matcher: blink ships a Rust implementation that is much
      -- faster than the Lua fallback. The binary is downloaded by
      -- `version = "*"`. Missing download/checksum tools select Lua quietly;
      -- failures with those tools present retain Blink's normal warnings.
      fuzzy = { implementation = require("config.tooling").blink_implementation() },
    },
    -- Lets another spec fragment for blink.cmp APPEND to sources.default
    -- instead of replacing it (lazy.nvim list-merge).
    opts_extend = { "sources.default" },
  },
}
