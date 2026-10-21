-- .luacheckrc
--
-- Static analysis for init.lua, lua/ and tests/. `vim` is read-only, so a
-- stray `vim.foo = …` that replaces part of the API is reported (warning
-- 122); only the option and variable tables below may be written. Busted's
-- globals are read-only too. scoper.nvim/ has its own .luacheckrc.

std = "luajit"

read_globals = {
  "vim",
  "describe", "it", "before_each", "after_each", "setup", "teardown",
  "pending", "finally", "assert", "spy", "stub", "mock",
}

globals = {
  "vim.g", "vim.b", "vim.w", "vim.t", "vim.v", "vim.env",
  "vim.o", "vim.go", "vim.bo", "vim.wo",
  "vim.opt", "vim.opt_local", "vim.opt_global",
}

-- (No whitespace-only ignores: stylua, enforced by `make check`, already
-- guarantees clean whitespace, so 611/612 would only hide real slips.)
ignore = {
  "212/_.*",   -- unused argument starting with _
  "631",       -- line too long
}

-- The specs stub vim.notify, vim.fn.input and vim.api.nvim_set_keymap, then
-- restore them.
files["tests/*.lua"] = {
  ignore = { "122" },
}

-- These documented adapters intentionally replace exactly one public API.
-- Keep the rest of vim read-only so unrelated accidental writes still fail.
files["lua/plugins/editor.lua"] = {
  globals = { "vim.filetype.get_option" },
}
files["lua/plugins/finder.lua"] = {
  globals = { "vim.ui.select" },
}

-- The `scoper.nvim/` subtree has its own .luacheckrc; don't double-check.
exclude_files = {
  "scoper.nvim/",
  ".luarocks/",
}
