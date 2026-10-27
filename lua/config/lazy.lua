-- lua/config/lazy.lua
--
-- Bootstraps lazy.nvim (the plugin manager) and tells it to load every spec
-- file under `lua/plugins/`. Each plugin lives in its own file there so you
-- can add/remove plugins without churning a giant monolithic spec.

-- ---------------------------------------------------------------------------
-- Bootstrap: clone lazy.nvim into stdpath("data") on first run.
-- ---------------------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
-- Tests and `nvim -u /path/to/init.lua` can load this config outside
-- stdpath("config"). Keep the lock beside the source in those cases too.
local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local lockfile = config_root .. "/lazy-lock.json"

-- Bootstrap failure (no git, offline first start, proxy) must not take the
-- editor down with it. Options, keymaps and autocmds are already loaded by
-- the time we get here, so on failure: explain, skip the plugin layer, and
-- leave a working plain Neovim. The next start retries the clone.
local function bootstrap_failed(msg)
  vim.api.nvim_echo({
    { "lazy.nvim bootstrap failed — starting WITHOUT plugins.\n", "ErrorMsg" },
    { msg, "WarningMsg" },
    { "\nFix it (install git / check the network), then restart Neovim.", "Normal" },
  }, true, {})
end

local function manager_installed()
  return vim.fn.filereadable(lazypath .. "/lua/lazy/init.lua") == 1
end

if not vim.uv.fs_stat(lazypath) then
  if vim.fn.executable("git") == 0 then
    bootstrap_failed("git is not on PATH; it is needed to download lazy.nvim.")
    return
  end
  -- The manager itself runs before lazy.nvim can read its lockfile. Check
  -- out its locked commit before requiring it, so first boot cannot run a
  -- newer manager and then overwrite the pinned entry during installation.
  local commit
  if vim.fn.filereadable(lockfile) == 1 then
    local ok, lock = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
    end)
    if not ok or type(lock) ~= "table" then
      bootstrap_failed("Cannot read a valid plugin lockfile: " .. lockfile)
      return
    end
    local manager = lock["lazy.nvim"]
    if manager ~= nil then
      commit = type(manager) == "table" and manager.commit or nil
      if type(commit) ~= "string" or #commit ~= 40 or not commit:match("^%x+$") then
        bootstrap_failed("Invalid lazy.nvim commit in " .. lockfile)
        return
      end
    end
  end
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  -- Concurrent first starts must own separate partial clones. Only publish
  -- a fully checked-out manager, and never clean up another editor's path.
  local staging = lazypath .. ".tmp-" .. vim.fn.getpid() .. "-" .. vim.uv.hrtime()
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    lazyrepo,
    staging,
  })
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(staging, "rf")
    if not manager_installed() then
      bootstrap_failed("git clone " .. lazyrepo .. " failed:\n" .. out)
      return
    end
  else
    if commit then
      out = vim.fn.system({ "git", "-C", staging, "checkout", "--detach", commit })
      if vim.v.shell_error ~= 0 then
        vim.fn.delete(staging, "rf")
        bootstrap_failed("Cannot check out locked lazy.nvim commit " .. commit .. ":\n" .. out)
        return
      end
    end
    if vim.fn.filereadable(staging .. "/lua/lazy/init.lua") ~= 1 then
      vim.fn.delete(staging, "rf")
      bootstrap_failed("The cloned lazy.nvim checkout is incomplete")
      return
    end
    -- Do not replace even an empty pre-existing target. A concurrently
    -- published complete manager is nonempty, so rename cannot replace it;
    -- reuse that winner if it appeared after the existence check.
    local published, err
    if not vim.uv.fs_lstat(lazypath) then
      published, err = vim.uv.fs_rename(staging, lazypath)
    end
    vim.fn.delete(staging, "rf")
    if not published and not manager_installed() then
      bootstrap_failed(
        "Cannot publish lazy.nvim checkout: " .. (err or "destination already exists")
      )
      return
    end
  end
end
if not manager_installed() then
  bootstrap_failed("Existing lazy.nvim checkout is incomplete: " .. lazypath)
  return
end
vim.opt.rtp:prepend(lazypath)

-- ---------------------------------------------------------------------------
-- Lazy setup
-- ---------------------------------------------------------------------------
require("lazy").setup({
  lockfile = lockfile,
  -- No plugin here is distributed as a luarocks rock, so lazy.nvim's rocks
  -- support (a hererocks/luarocks toolchain it would try to set up) is off;
  -- with it on, :checkhealth lazy reported an ERROR for the missing luarocks.
  rocks = { enabled = false },
  spec = {
    -- Import every file under lua/plugins/ as a plugin spec.
    -- Order inside that folder doesn't matter; lazy.nvim resolves
    -- `dependencies` automatically.
    { import = "plugins" },
    -- Machine-local spec overrides are last, after shipped defaults.
    require("config.settings").plugin_specs(),
  },
  defaults = {
    -- Same as lazy.nvim's own default, spelled out because the specs rely
    -- on it: a spec without a trigger (`event`, `cmd`, `keys`, `ft`, …)
    -- loads eagerly at startup. Almost every plugin here DOES declare a
    -- trigger; the eager default only catches the handful that must be
    -- present at startup (colorscheme, session, scope, bufferline) plus
    -- dependency-only entries pulled in by another spec anyway.
    lazy = false,
    version = false, -- always use the latest commit; pin individual plugins if you want stability
  },
  install = {
    -- Pre-fetch the catppuccin colorscheme on first install so the install
    -- UI itself isn't ugly. Replace with another scheme if you change it.
    colorscheme = { "catppuccin", "habamax" },
  },
  checker = {
    -- stylua: ignore start
    enabled = true, -- periodically check for plugin updates
    notify  = false, -- ...but don't pop up about them
    -- stylua: ignore end
    frequency = 86400, -- once a day
  },
  change_detection = {
    -- stylua: ignore start
    enabled = true,
    notify  = false,
    -- stylua: ignore end
  },
  performance = {
    rtp = {
      -- lazy resets runtimepath to stdpath("config") on setup. A source
      -- checkout loaded with -u may live elsewhere; keep its specs visible
      -- when a cold install resets the module cache and reloads them.
      paths = { config_root },
      -- Disable some default rtp plugins we don't use; tiny startup win.
      -- We deliberately KEEP `matchparen` (highlights the bracket under the
      -- cursor — the thing you actually look at most of the time) and
      -- `matchit` (lets `%` jump between if/endif, html tags, etc.). The
      -- startup savings from disabling them aren't worth the loss in
      -- everyday editor feel.
      disabled_plugins = {
        "gzip",
        "netrwPlugin",
        "tarPlugin",
        "tutor",
        "zipPlugin",
      },
    },
  },
  ui = {
    border = "rounded", -- lazy.nvim doesn't inherit 'winborder'
  },
})

-- Convenience keymap to open the lazy.nvim UI.
vim.keymap.set("n", "<leader>L", "<cmd>Lazy<cr>", { desc = "Lazy.nvim UI" })
