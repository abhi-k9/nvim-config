-- ~/.config/nvim/init.lua
--
-- Neovim configuration entry point. The hard MINIMUM Neovim version is
-- enforced by the guard below; :checkhealth config reads it from
-- vim.g.config_min_nvim. README.md and the CI matrix repeat the number, so
-- change all three together.
--
-- Loading order matters:
--   0. version guard – abort early (before any require) if Neovim is too old,
--                     so a missing 0.12 API surfaces as one clear message
--                     instead of a confusing mid-load stack trace.
--   1. options      – set globals BEFORE plugins load (e.g. mapleader must be
--                     set before lazy.nvim reads your plugin specs).
--   2. keymaps      – global, non-plugin keymaps.
--   3. autocmds     – autocommands (e.g. highlight on yank).
--   4. diagnostics  – registers the :DiagnosticDump command. The command
--                     body queries dap/lazy via pcall when invoked, but
--                     registration itself is just nvim_create_user_command
--                     and doesn't need any plugin loaded.
--   5. lazy         – bootstraps lazy.nvim and imports `lua/plugins/*.lua`.
--   6. health reminder – periodic, persisted prompt to review optional tools.
--
-- Each file under lua/config/ and lua/plugins/ is heavily commented; start
-- there if you want to tweak something.

-- ---------------------------------------------------------------------------
-- Minimum Neovim version.
--
-- 0.12.0 is the floor because nvim-treesitter's `main` branch requires it,
-- and the config relies on 0.12 APIs (vim.diagnostic `jump.on_jump`,
-- vim.lsp.linked_editing_range / document_color, :restart).
--
-- The failure branch deliberately uses only ancient-safe APIs (plain
-- nvim_echo, no vim.version()) — it runs precisely because the user is on an
-- old build, so it can't assume any recent function exists — and `return`s
-- out of init.lua before a single plugin spec is read.
-- ---------------------------------------------------------------------------
local MIN_NVIM = "0.12.0"
if vim.fn.has("nvim-" .. MIN_NVIM) == 0 then
  vim.api.nvim_echo({
    { ("This Neovim config requires Neovim >= %s.\n"):format(MIN_NVIM), "ErrorMsg" },
    { "Your version is older; startup aborted so nothing breaks confusingly.", "WarningMsg" },
  }, true, {})
  return
end
-- Published (read-only by convention) so :checkhealth config reports the
-- SAME floor instead of restating the number.
vim.g.config_min_nvim = MIN_NVIM

local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local settings = require("config.settings")
settings.bootstrap(config_root)
require("config.options")
settings.apply_options()
require("config.keymaps")
require("config.autocmds")
require("config.diagnostics")
require("config.lazy")
require("config.health_reminder").setup()
