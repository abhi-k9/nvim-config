-- lua/plugins/colorscheme.lua
--
-- Colorscheme. `catppuccin` is loaded eagerly with priority = 1000 so
-- it's ready before any other plugin draws its UI. To change palette,
-- swap the `flavour` field below (or run `:colorscheme catppuccin-latte`
-- etc. ad-hoc). To replace the scheme entirely, add another plugin spec
-- and activate it in that spec. `ui.colorscheme` also accepts stock schemes.

local selected = require("config.settings").get("ui.colorscheme", "catppuccin")
local catppuccin = type(selected) == "string" and selected:match("^catppuccin") ~= nil
if not catppuccin then
  -- Built-in schemes need no plugin. Run before the UI specs draw anything;
  -- a separate third-party theme spec can perform its own activation later.
  local ok, err = pcall(vim.cmd.colorscheme, selected)
  if not ok then
    vim.notify("Could not load ui.colorscheme: " .. tostring(err), vim.log.levels.WARN)
  end
end

return {
  -- -------------------------------------------------------------------------
  -- Catppuccin — main colorscheme.
  -- Four flavors: latte (light), frappe, macchiato, mocha (darkest).
  -- -------------------------------------------------------------------------
  {
    "catppuccin/nvim",
    name = "catppuccin",
    enabled = catppuccin,
    lazy = false, -- must load on startup, not on demand
    priority = 1000, -- load before any plugin that paints itself
    opts = {
      flavour = "mocha", -- latte | frappe | macchiato | mocha
      background = { light = "latte", dark = "mocha" },
      transparent_background = false,
      term_colors = true, -- recolor the :terminal palette
      dim_inactive = {
        enabled = false, -- set true if you want inactive splits dimmer
        shade = "dark",
        percentage = 0.15,
      },
      styles = {
        -- stylua: ignore start
        comments     = { "italic" },
        conditionals = { "italic" },
        -- stylua: ignore end
      },
      -- Integrations let catppuccin theme third-party plugins. Disable any
      -- you don't use to shave a millisecond off startup.
      -- Integrations are listed explicitly and auto-detection is OFF. The
      -- detector calls vim.pack.get() on Neovim 0.12, which creates
      -- stdpath("data")/site/pack/core as a side effect — then
      -- :checkhealth lazy warns "found existing packages" and
      -- :checkhealth vim.pack about a missing lockfile — and it adds
      -- integrations implicitly. The list below covers this plugin set
      -- (blink_indent and mini included). Treesitter and LSP highlights
      -- need no entry (diagnostic styles are the `lsp_styles` option,
      -- defaults kept), and bufferline is themed from its own spec in
      -- ui.lua (catppuccin.special.bufferline).
      auto_integrations = false,
      integrations = {
        blink_indent = true,
        mini = { enabled = true },
        gitsigns = true,
        treesitter_context = true,
        telescope = { enabled = true },
        which_key = true,
        mason = true,
        lsp_trouble = true,
        dap = true,
        dap_ui = true,
        fidget = true,
        flash = true,
        fzf = true,
        ufo = true,
        diffview = true,
        grug_far = true,
        neotree = true,
        render_markdown = true,
        blink_cmp = true,
      },
    },
    -- Activate the colorscheme once setup is done.
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme(selected)
    end,
  },
}
