describe("Bufferline's supported diagnostic cache", function()
  local line, diagnostics, settings, plugin, original_get, buffer, namespace, original_config
  before_each(function()
    line = require("bufferline")
    diagnostics = require("bufferline.diagnostics")
    settings = require("config.settings")
    settings.reset()
    for _, spec in ipairs(dofile("lua/plugins/ui.lua")) do
      if spec[1] == "abhi-k9/bufferline.nvim" then plugin = spec end
    end
    original_get = diagnostics.get
    original_config = vim.diagnostic.config()
    vim.diagnostic.config({ virtual_text = false, signs = false, underline = false })
    buffer = vim.api.nvim_create_buf(true, false)
    namespace = vim.api.nvim_create_namespace("fork-config-cache")
  end)
  after_each(function()
    settings.reset()
    vim.diagnostic.reset(namespace)
    vim.api.nvim_buf_delete(buffer, { force = true })
    vim.diagnostic.config(original_config)
    line.setup({})
  end)

  it("uses the native cache without replacing the plugin getter", function()
    local opts = plugin.opts()
    assert.is_true(opts.options.diagnostics_cache)
    assert.is_nil(plugin.config) -- Lazy's standard setup(opts) path
    line.setup(opts)
    local items = {}
    for severity = 1, 4 do
      items[#items + 1] = { lnum = 0, col = 0, message = "probe", severity = severity }
    end
    vim.diagnostic.set(namespace, buffer, items)
    local summary = diagnostics.get(opts.options)[buffer]
    assert.same({ error = 1, warning = 1, info = 1, hint = 1 }, summary.errors)
    assert.equals(4, summary.count)
    assert.equals(original_get, diagnostics.get)
    assert.is_nil(package.loaded["config.bufferline_diagnostics"])
  end)

  it("keeps the existing cache opt-out setting and cleans up on repeated setup", function()
    line.setup(plugin.opts())
    diagnostics.get(plugin.opts().options)
    assert.equals(2, #vim.api.nvim_get_autocmds({ group = "BufferlineDiagnosticCache" }))
    settings.configure({ ui = { bufferline_diagnostic_cache = false } })
    local opts = plugin.opts()
    assert.is_false(opts.options.diagnostics_cache)
    line.setup(opts)
    assert.equals(0, vim.fn.exists("#BufferlineDiagnosticCache"))
    settings.configure({ ui = { bufferline_diagnostic_cache = true } })
    line.setup(plugin.opts())
    diagnostics.get(plugin.opts().options)
    assert.equals(2, #vim.api.nvim_get_autocmds({ group = "BufferlineDiagnosticCache" }))
    assert.equals(original_get, diagnostics.get)
  end)
end)
