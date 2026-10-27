-- Real init, private override file and first plugin-spec resolution.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.go.loadplugins = true
local path = vim.fn.tempname() .. ".lua"
vim.fn.writefile(
  vim.split(
    [[return {
  globals = { mapleader = ",", maplocalleader = ";", treesitter_auto_install = false },
  options = { exrc = false, shiftwidth = 6 },
  tools = { servers = {}, packages = {}, parsers = {} },
  plugins = {
    { "nvim-lualine/lualine.nvim", opts = { options = { globalstatus = false } } },
  },
}]],
    "\n",
    { plain = true }
  ),
  path
)
vim.g.config_local_file = path
local ok, err = pcall(dofile, "init.lua")
vim.fn.delete(path)
assert(ok, err)
assert(vim.g.mapleader == "," and vim.g.maplocalleader == ";", "leaders loaded too late")
assert(vim.o.exrc == false and vim.o.shiftwidth == 6, "option policy was overwritten")
assert(vim.fn.maparg(",W", "n") ~= "", "core maps did not use the selected leader")
local config, plugin = require("lazy.core.config"), require("lazy.core.plugin")
local opts = plugin.values(config.plugins["lualine.nvim"], "opts", false)
assert(opts.options.globalstatus == false, "local plugin specs did not override shipped opts")
local servers = plugin.values(config.plugins["mason-lspconfig.nvim"], "opts", false)
assert(#servers.ensure_installed == 0, "empty tool list was lost before plugin activation")
io.stdout:write("local settings ready before maps and plugins\n")
