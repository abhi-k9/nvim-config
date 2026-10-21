-- tests/minimal_init.lua
--
-- Headless init used by `make test`. Adds two things to the runtimepath:
-- this plugin (so `require("scoper.*")` resolves), and plenary.nvim, cloned
-- into stdpath("cache")/test-deps on first run (`make clean` deletes it).
--
-- We DO NOT load the user's full Neovim config — tests should run against
-- a clean environment so a bug in someone's keymap doesn't fail
-- scoper's tests.

local function bootstrap_plenary()
  -- If plenary is already on rtp (running inside a user's full config),
  -- nothing to do.
  if pcall(require, "plenary.busted") then return end

  -- Under stdpath("cache"), added to 'runtimepath' explicitly — NOT a
  -- site/pack/*/start directory: that is your everyday Neovim's package
  -- path, where a test-only plenary would be auto-loaded (or, with lazy.nvim,
  -- flagged by :checkhealth lazy as "found existing packages").
  local install_dir = vim.fn.stdpath("cache") .. "/test-deps/plenary.nvim"
  -- Checked by a file, not the directory: an interrupted clone leaves the
  -- directory behind without the plugin in it.
  if vim.fn.filereadable(install_dir .. "/lua/plenary/busted.lua") == 0 then
    vim.fn.delete(install_dir, "rf")
    local out = vim.fn.system({
      "git",
      "clone",
      "--depth=1",
      "https://github.com/nvim-lua/plenary.nvim",
      install_dir,
    })
    if vim.v.shell_error ~= 0 then
      vim.fn.delete(install_dir, "rf")
      io.stderr:write("scoper tests: cloning plenary.nvim failed:\n" .. out .. "\n")
      -- Exit with an error: the suite can't run, and headless Neovim would
      -- otherwise stay open after the missing :PlenaryBustedDirectory.
      vim.cmd("cquit 1")
    end
  end
  vim.opt.rtp:append(install_dir)
end

-- Add this plugin's root to rtp. The test runner is invoked from the
-- plugin root, so cwd resolves correctly.
vim.opt.rtp:prepend(vim.fn.getcwd())

bootstrap_plenary()

vim.cmd("runtime plugin/plenary.vim")
