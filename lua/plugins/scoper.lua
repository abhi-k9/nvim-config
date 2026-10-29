-- lua/plugins/scoper.lua
--
-- Local-plugin spec for scoper.nvim, which is bundled in this config under
-- `scoper.nvim/` (relative to this checkout). Resolve the path from this
-- spec's source so headless tests and `nvim -u /path/to/init.lua` also work
-- when stdpath("config") points at a different configuration.
--
-- Want to point at a clone of your own instead? Set `dir = "~/projects/scoper.nvim"`.
-- Want to use the published version once it's on GitHub? Replace the table
-- with `"<owner>/scoper.nvim"` (and drop `dir`).
--
-- Setup options:
--   lsp.mode          – disabled/native/selected/filtered integration policy
--   lsp.clangd        – legacy opt-in to automatic filtered-cache refresh
--   lsp.query_drivers – explicit trusted compiler paths (no auto-trust globs)
--   default_excludes  – seed every new scope, including a fresh project's default scope

local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

return {
  {
    dir = vim.fs.joinpath(config_root, "scoper.nvim"),
    -- Loaded eagerly so :Scoper* commands are registered up front. The
    -- heavy modules inside scoper itself are still lazy-required on demand.
    lazy = false,
    opts = function()
      local settings = require("config.settings")
      local opts = settings.get("scoper", {})
      opts.lsp = opts.lsp or {}
      -- Preserve the shipped automatic-filtering behavior. An explicit mode
      -- or the legacy boolean wins; compiler execution trust is opt-in.
      if opts.lsp.mode == nil and opts.lsp.clangd == nil then opts.lsp.clangd = true end
      if opts.default_excludes == nil then
        opts.default_excludes = { "**/node_modules/**", "**/.git/**", "**/target/**" }
      end
      opts.project = opts.project or {}
      if opts.project.root == nil then
        opts.project.root = function()
          return settings.project_root()
        end
      end
      return opts
    end,
    config = function(_, opts)
      require("scoper").setup(opts)
    end,
  },
}
