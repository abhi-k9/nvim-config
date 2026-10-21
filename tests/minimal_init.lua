-- tests/minimal_init.lua
--
-- Headless init used by the config smoke test.
--
-- We DO load the real config (init.lua) — the whole point of the smoke
-- test is to assert that loading the real config doesn't error. We just
-- need plenary on rtp first so its busted runner is available.

-- Make `require("config.*")` resolve regardless of where this checkout
-- lives. When the config sits at ~/.config/nvim, Neovim puts it on rtp
-- automatically (stdpath("config") is always added, even with -u), which
-- masks a missing entry: from any other checkout or in CI the config
-- fails with `module 'config.options' not found`. (scoper.nvim's
-- minimal_init does the same.)
vim.opt.rtp:prepend(vim.fn.getcwd())

local function bootstrap_plenary()
  if pcall(require, "plenary.busted") then return end
  -- Under stdpath("cache"), added to 'runtimepath' explicitly — NOT a
  -- site/pack/*/start directory: that is your everyday Neovim's package
  -- path, where a test-only plenary would be auto-loaded (or, with lazy.nvim,
  -- flagged by :checkhealth lazy as "found existing packages").
  local install_dir = vim.fn.stdpath("cache") .. "/test-deps/plenary.nvim"
  if vim.fn.isdirectory(install_dir) == 0 then
    local out = vim.fn.system({
      "git",
      "clone",
      "--depth=1",
      "https://github.com/nvim-lua/plenary.nvim",
      install_dir,
    })
    if vim.v.shell_error ~= 0 then
      -- A failed clone can leave a partial directory behind, which the
      -- isdirectory() check above would take for an install next run.
      vim.fn.delete(install_dir, "rf")
      error("git clone of plenary.nvim failed:\n" .. out)
    end
  end
  vim.opt.rtp:append(install_dir)
end

bootstrap_plenary()
vim.cmd("runtime plugin/plenary.vim")

-- Record the global keymaps registered DURING config load, so config_spec can
-- detect genuine duplicate <leader> maps. This cannot be read from the live
-- keymap table afterwards: Neovim keys it on (mode, lhs) and keeps only the
-- last rhs, so a second mapping of the same leader key silently overwrites the
-- first and the collision vanishes before any test could see it. We must
-- observe the registrations themselves.
--
-- Hook ONLY vim.api.nvim_set_keymap — the single low-level chokepoint. The
-- high-level vim.keymap.set (which the config's map()/k() helpers, lazy and
-- which-key all use) is implemented ON TOP of nvim_set_keymap, so hooking both
-- layers records every mapping twice and reports phantom duplicates. Global
-- maps funnel through nvim_set_keymap; buffer-local maps use
-- nvim_buf_set_keymap and are intentionally not captured (we only care about
-- global leader maps).
--
-- Capture only the SYNCHRONOUS load: install right before dofile, restore right
-- after. That window holds the config's own global maps. It deliberately
-- excludes everything deferred onto the event loop (lazy creating keys-spec
-- stubs and later swapping them for the real keymap when a plugin loads,
-- LspAttach buffer maps) — that is where benign re-registration lives, and
-- counting it would cause false positives.
_G.__config_keymap_registrations = {}
do
  local log = _G.__config_keymap_registrations
  -- lazy.nvim registers a `keys` entry twice by design (a stub, then the
  -- real map once the plugin loads). Those are tagged so the raw log check
  -- can skip them; duplicates BETWEEN lazy specs are checked separately
  -- from lazy's own spec table (config_spec.lua).
  local from_lazy = false
  local function record(mode, lhs)
    from_lazy = false
    for level = 3, 12 do
      local info = debug.getinfo(level, "S")
      if not info then break end
      if info.source:find("lazy/core/handler", 1, true) then
        from_lazy = true
        break
      end
    end
    -- At this layer mode is always a single string; guard anyway.
    local modes = type(mode) == "table" and mode or { mode }
    for _, m in ipairs(modes) do
      log[#log + 1] = { mode = m, lhs = lhs, lazy = from_lazy }
    end
  end
  local orig_api = vim.api.nvim_set_keymap
  vim.api.nvim_set_keymap = function(...)
    local a = { ... }
    pcall(record, a[1], a[2])
    return orig_api(...)
  end
  _G.__config_keymap_restore = function()
    vim.api.nvim_set_keymap = orig_api
  end
end

-- Now load the real config. If anything inside throws, the spec that
-- requires this init will fail with a useful traceback.
-- The runner starts Neovim with --noplugin (so the user's own packages
-- can't leak in), but lazy.nvim's setup() returns immediately when
-- 'loadplugins' is off, which would leave the suite with ZERO plugin
-- specs. Re-enable it just for lazy; everything lazy loads is sourced by
-- lazy itself.
vim.go.loadplugins = true
dofile(vim.fn.getcwd() .. "/init.lua")

-- Stop recording: from here on it's asynchronous plugin loading, not a
-- config-declared mapping.
_G.__config_keymap_restore()
