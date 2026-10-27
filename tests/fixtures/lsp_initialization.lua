-- Exercise the real lazy loader without starting installers or language
-- servers. Mason's automatic enable runs inside setup(); observe the config
-- available at that exact boundary, before any later FileType replay.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/scoper.nvim")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "[]" }, root .. "/compile_commands.json")
require("scoper").setup({ project = { root = root }, lsp = { mode = "selected" } })
local revision = require("scoper").snapshot().revision
local observed
require("config.settings").configure({
  tools = { servers = { "lua_ls" } },
  lsp = {
    servers = {
      lua_ls = { settings = { Lua = { diagnostics = { globals = { "custom_global" } } } } },
      clangd = { cmd = { vim.v.progpath, "--log=error" }, cmd_env = { FINAL_POLICY = "kept" } },
    },
  },
})
package.loaded["mason"] = { setup = function() end }
package.loaded["mason-lspconfig"] = {
  setup = function()
    observed = {
      settings = vim.deepcopy((vim.lsp.config.lua_ls or {}).settings or {}),
      capabilities = vim.deepcopy((vim.lsp.config["*"] or {}).capabilities or {}),
      clangd = require("scoper.lsp").status(),
      environment = vim.deepcopy(vim.lsp.config.clangd.cmd_env),
      revision = require("scoper").snapshot().revision,
    }
  end,
}
vim.go.loadplugins = true
require("lazy").setup({
  spec = dofile("lua/plugins/lsp.lua"),
  root = vim.fn.stdpath("data") .. "/lazy",
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  rocks = { enabled = false },
  performance = { rtp = { reset = false } },
})
require("lazy.core.loader").load("mason-lspconfig.nvim", { cmd = "spec" })
assert(observed, "Mason's LSP setup did not run")
assert(
  vim.tbl_get(observed.settings, "Lua", "telemetry", "enable") == false,
  "LuaLS started before telemetry settings"
)
assert(
  vim.tbl_get(observed.settings, "Lua", "workspace", "checkThirdParty") == false,
  "LuaLS started before workspace settings"
)
assert(
  vim.tbl_get(observed.settings, "Lua", "completion", "callSnippet") == "Replace",
  "LuaLS started before completion settings"
)
assert(
  observed.capabilities.textDocument.completion.completionItem.snippetSupport,
  "LSP started before completion capabilities"
)
assert(
  vim.tbl_contains(observed.settings.Lua.diagnostics.globals, "custom_global"),
  "LSP started before the user's server override"
)
assert(observed.clangd.effective[1] == vim.v.progpath, "Scoper lost the final clangd executable")
assert(vim.tbl_contains(observed.clangd.effective, "--log=error"), "Scoper lost final clangd flags")
assert(type(vim.lsp.config.clangd.cmd) == "function", "Final server opts removed Scoper's provider")
assert(observed.environment.FINAL_POLICY == "kept", "Scoper lost final clangd environment")
assert(revision == observed.revision, "Final LSP options reloaded scope state")
require("scoper.lsp").dispose()
vim.fn.delete(root, "rf")
io.stdout:write("LSP initialization boundary: settings and capabilities ready\n")
