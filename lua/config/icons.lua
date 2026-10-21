-- lua/config/icons.lua
--
-- Shared icon glyphs. The diagnostic set is used by vim.diagnostic sign
-- text (plugins/lsp.lua), lualine's diagnostics symbols and bufferline's
-- diagnostics_indicator (both in plugins/ui.lua); keeping it in one place
-- keeps the gutter, statusline and tabline in agreement. Edit here; every
-- consumer follows.
--
-- Nerd Font glyphs are private-use code points, which some editors and
-- archive tools silently drop. Write them only as \u{XXXX} escapes, never
-- as literal characters, and only from Nerd Fonts v3 (the old Material
-- Design range U+F500-U+FD46 is retired; it now lives at U+F0001 and up).
--
-- Values keep their trailing space where the consumer concatenates a
-- count or message directly after the glyph.

local M = {}

M.diagnostics = {
  -- stylua: ignore start
  error = "\u{F057} ", -- nf-fa-times_circle
  warn  = "\u{F071} ", -- nf-fa-warning
  info  = "\u{F05A} ", -- nf-fa-info_circle
  hint  = "\u{F0336} ", -- nf-md-lightbulb_outline
  -- stylua: ignore end
}

-- lualine `diff` symbols.
M.git = {
  -- stylua: ignore start
  added    = "\u{F0FE} ", -- nf-fa-plus_square
  modified = "\u{F14B} ", -- nf-fa-pencil_square
  removed  = "\u{F146} ", -- nf-fa-minus_square
  -- stylua: ignore end
}

M.misc = {
  -- stylua: ignore start
  git_delete = "\u{F0DA}", -- nf-fa-caret_right (gitsigns delete/topdelete)
  pl_left    = "\u{E0B0}", -- nf-pl-left_hard_divider (lualine)
  pl_right   = "\u{E0B2}", -- nf-pl-right_hard_divider (lualine)
  search     = "\u{F002}", -- nf-fa-search (telescope prompt)
  recording  = "\u{F111}", -- nf-fa-circle (lualine macro indicator)
  fold       = "\u{F0042}", -- nf-md-arrow_bottom_left (ufo fold suffix)
  -- stylua: ignore end
}

-- Keyed-by-severity variant for vim.diagnostic.config's signs.text,
-- derived from the same table so it can't drift.
function M.diagnostic_signs()
  return {
    -- stylua: ignore start
    [vim.diagnostic.severity.ERROR] = M.diagnostics.error,
    [vim.diagnostic.severity.WARN]  = M.diagnostics.warn,
    [vim.diagnostic.severity.HINT]  = M.diagnostics.hint,
    [vim.diagnostic.severity.INFO]  = M.diagnostics.info,
    -- stylua: ignore end
  }
end

return M
