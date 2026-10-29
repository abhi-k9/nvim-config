-- lua/plugins/neogen.lua
--
-- Annotation generator: position the cursor inside a function (or on a
-- class / type / file), hit <leader>cd, and neogen reads the signature
-- via treesitter and writes a fully-templated doc-comment block above
-- it. <Tab>/<S-Tab> walk between the empty placeholders so you can fill
-- them in without leaving insert mode.
--
-- Shipped/locked annotation conventions (only C/C++ are overridden here):
--   C / C++        doxygen        /** @param x ... @return ... */
--   Lua            emmylua        --- @param x  @return
--   Python         google_docstrings (Args / Returns sections)
--   TypeScript     tsdoc          /** @param @returns */
--   Rust           rust_alternative (/// argument bullet list)
--   etc.
--
-- The C/C++ default IS already doxygen, so the explicit override in
-- `opts.languages` is documentation-as-code more than functional — it
-- makes the choice visible at the config level so a future reader
-- doesn't have to dig into neogen's defaults to understand what the
-- generator will emit.
--
-- C/C++ Doxygen tag highlighting uses the injected `doxygen` parser
-- (included in treesitter.lua's default PARSERS). Without that parser the
-- generated block still works, but its tags may remain plain comment text.

return {
  {
    "danymat/neogen",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    -- Lazy-load behind the command and the keymap; setup runs on first use.
    cmd = "Neogen",
    keys = {
      -- Auto-detects the nearest annotatable node (function by default).
      -- For explicit types use `:Neogen class`, `:Neogen type`,
      -- `:Neogen file`. Command tab-completion lists them.
      {
        "<leader>cd",
        function()
          require("neogen").generate()
        end,
        desc = "Generate doc comment",
      },
    },
    opts = {
      enabled = true,
      -- The generated block is expanded as a LuaSnip snippet (the engine
      -- blink.cmp uses, completion.lua), so blink's <Tab>/<S-Tab>
      -- (snippet_forward / snippet_backward) jump between the empty
      -- placeholders. Without an engine there is nothing to jump.
      snippet_engine = "luasnip",
      languages = {
        -- stylua: ignore start
        c   = { template = { annotation_convention = "doxygen" } },
        cpp = { template = { annotation_convention = "doxygen" } },
        -- stylua: ignore end
        -- Other languages keep neogen's defaults listed above. Available
        -- alternatives are documented in its README; override the language's
        -- template.annotation_convention to select one explicitly.
      },
    },
  },
}
