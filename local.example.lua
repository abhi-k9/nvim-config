-- Copy this file to local.lua beside init.lua, then restart Neovim.
-- local.lua is ignored by Git and takes precedence over local.json.
-- Merge personal settings into this one returned table.
return {
  explorer = {
    scope_filter = false, -- Startup default; :ScoperFilterToggle switches at runtime.
    scope_markers = {
      enabled = false, -- Startup default; :ScoperMarkersToggle switches at runtime.
      marker = "-", -- Use "" for dimming without a symbol.
      dim = true, -- false preserves normal filename colours.
      highlight = "NeoTreeDimText", -- Highlight group supplied by the theme.
      show_scope = true, -- Show the active scope beside the tree root.
      debounce_ms = 100, -- Coalesce scope-change redraws.
    },
  },
}
