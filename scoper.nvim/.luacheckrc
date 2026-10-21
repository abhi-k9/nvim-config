-- .luacheckrc
--
-- Static analysis config for scoper.nvim.
--
-- Goal: catch real bugs (typos in vim.* names, unused locals that hide
-- shadowing, accidentally global variables) without spamming us about
-- legitimate Lua-in-Neovim idioms (long lines in comments, the busted
-- spec DSL, …).

std = "luajit"

-- Recognise the globals injected by:
--   * Neovim runtime — `vim`, read-only apart from the option and variable
--     tables meant to be assigned to (`vim.g.x = …`)
--   * plenary's busted runner — `describe`, `it`, `before_each`, etc.
read_globals = {
  "vim",
  "describe", "it", "before_each", "after_each", "setup", "teardown",
  "pending", "finally", "assert", "spy", "stub", "mock",
}

globals = {
  "vim.g", "vim.b", "vim.w", "vim.t", "vim.o", "vim.go", "vim.bo", "vim.wo", "vim.env",
}

-- These warnings are noisy and not worth fixing case-by-case.
ignore = {
  "212/_.*",   -- unused argument starting with _ (idiomatic ignore marker)
  "631",       -- line too long (we allow long URLs / comments)
}

-- Per-path tweaks: test specs use a DSL that defines a lot of upvalues
-- inside `describe` blocks. Don't warn about shadowing inside them.
files["tests/"] = {
  ignore = {
    "423",  -- shadowing a local while defining a new one
    "122",  -- setting a field of `vim`: specs stub vim.* functions
  },
}
