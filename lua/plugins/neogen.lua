-- lua/plugins/neogen.lua
--
-- Annotation generator: position the cursor inside a function (or on a
-- class / type / file), hit <leader>cd, and neogen reads the signature
-- via treesitter and writes a fully-templated doc-comment block above
-- it. <Tab>/<S-Tab> walk between the empty placeholders so you can fill
-- them in without leaving insert mode.
--
-- Annotation conventions per language:
--   C / C++        doxygen        /** @param x ... @return ... */
--   Lua            ldoc / EmmyLua --- @param x  @return
--   Python         numpydoc        (Parameters / Returns sections)
--   TypeScript     jsdoc           /** @param @returns */
--   Rust           rustdoc         /// # Arguments / # Returns
--   etc.
--
-- The C/C++ default IS already doxygen, so the explicit override in
-- `opts.languages` is documentation-as-code more than functional — it
-- makes the choice visible at the config level so a future reader
-- doesn't have to dig into neogen's defaults to understand what the
-- generator will emit.
--
-- Highlighting of the generated tags depends on the `doxygen`
-- treesitter parser (added to PARSERS in treesitter.lua). Without it
-- the doc block still works, but `@param` etc. render as plain comment
-- text rather than as their own highlight group.

return {
  {
    "danymat/neogen",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    -- Lazy-load behind the command and the keymap. No startup cost; the
    -- plugin only loads the first time you actually invoke it.
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
        -- Other languages use their conventional style by default
        -- (luadoc / numpydoc / jsdoc / rustdoc / etc.) — listed in
        -- neogen's README. Override here if you want a non-default
        -- style for a particular language.
      },
    },
  },
}
