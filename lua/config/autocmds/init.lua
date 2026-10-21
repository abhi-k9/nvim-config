-- lua/config/autocmds/init.lua
--
-- Autocommands, one module per topic. Each group is created with
-- { clear = true } (util.augroup), so re-sourcing a module doesn't pile up
-- duplicate handlers. Order matters only where noted inside a module.
--
-- Load-order rule: init.lua loads these before lazy.nvim sources
-- filetype.lua, so their BufRead* handlers run BEFORE filetype detection.
-- A handler that needs the filetype must call vim.filetype.match() or
-- defer to a buffer-local FileType autocmd (see bigfile.lua, editing.lua).

require("config.autocmds.editing")
require("config.autocmds.bigfile")
require("config.autocmds.glue")
require("config.autocmds.folds")
require("config.autocmds.lsplog")
require("config.autocmds.swap")
