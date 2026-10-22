-- tests/minimal_init.lua
--
-- Headless init used by `make test`. Adds two things to the runtimepath:
-- this plugin (so `require("scoper.*")` resolves), and plenary.nvim, cloned
-- into stdpath("cache")/test-deps on first run (`make clean` deletes it).
--
-- We DO NOT load the user's full Neovim config — tests should run against
-- a clean environment so a bug in someone's keymap doesn't fail
-- scoper's tests.

local bootstrap_plenary = dofile(vim.fn.getcwd() .. "/tests/bootstrap.lua")

-- Add this plugin's root to rtp. The test runner is invoked from the
-- plugin root, so cwd resolves correctly.
vim.opt.rtp:prepend(vim.fn.getcwd())

bootstrap_plenary()

vim.cmd("runtime plugin/plenary.vim")
