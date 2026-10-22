-- Exercise the real lazy loader without starting installers or language
-- servers. Mason's automatic enable runs inside setup(); observe the config
-- available at that exact boundary, before any later FileType replay.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
local observed
package.loaded["mason"] = { setup = function() end }
package.loaded["mason-lspconfig"] = {
  setup = function()
    observed = {
      settings = vim.deepcopy((vim.lsp.config.lua_ls or {}).settings or {}),
      capabilities = vim.deepcopy((vim.lsp.config["*"] or {}).capabilities or {}),
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
io.stdout:write("LSP initialization boundary: settings and capabilities ready\n")
