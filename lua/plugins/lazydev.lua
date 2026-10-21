-- lua/plugins/lazydev.lua
--
-- lazydev.nvim — makes editing THIS config (and any Neovim-plugin Lua) far
-- nicer by feeding lua_ls the right libraries on demand.
--
-- lua_ls knows nothing about `vim.*` or required plugin modules on its own;
-- lazydev feeds it the matching libraries as your `require(...)` calls
-- reference them, giving real completion and hover — only in Lua that
-- looks like Neovim config. (lsp.lua's `diagnostics.globals = { "vim" }`
-- stays as a fallback for the moment before lazydev attaches.) The
-- blink.cmp source for lazydev is registered in completion.lua, for Lua
-- buffers only: a source listed for every filetype would load lazydev in
-- all of them.

return {
  {
    "folke/lazydev.nvim",
    -- Only load for Lua buffers; there's nothing to do elsewhere. `ft` keeps
    -- it fully lazy — no startup cost until you open a .lua file.
    ft = "lua",
    opts = {
      library = {
        -- Load the luv (vim.uv) type definitions, but only when a file
        -- actually references `vim.uv` — the `words` gate keeps the library
        -- out of Lua that never touches it. This config uses vim.uv heavily
        -- (fs_stat, timers, fs_rename in autocmds/, util.lua, scoper), so
        -- these definitions get real use here.
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
        -- Add more on demand, e.g. a plugin whose types you want while
        -- editing its config:
        --   "lazy.nvim",
        --   { path = "wezterm-types", mods = { "wezterm" } },
      },
    },
  },
}
