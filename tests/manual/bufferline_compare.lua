-- Manual comparison only: run in a disposable Neovim process with an attached UI.
-- arg[1]: native/cached/barbar/cokeline/mini; arg[2]: candidate checkout path.
-- See docs/bufferline-audit-2026-11-08.md for the bounded runner.
assert(#vim.api.nvim_list_uis() > 0, "this probe requires an attached UI")
local kind, path = arg[1], arg[2]
vim.opt.rtp = { vim.env.VIMRUNTIME, path, vim.fn.getcwd() }
vim.o.termguicolors = true
vim.o.swapfile = false
local started = vim.uv.hrtime()
local redraw
if kind == "barbar" then
  vim.g.barbar_auto_setup = false
  require("barbar").setup({
    animation = false,
    icons = {
      filetype = { enabled = false },
      diagnostics = {
        { enabled = true },
        { enabled = true },
        { enabled = true },
        { enabled = true },
      },
    },
  })
  redraw = function()
    require("barbar.ui.render").update(true)
    return vim.o.tabline
  end
elseif kind == "cokeline" then
  require("cokeline").setup({
    components = {
      {
        text = function(b)
          return b.filename
            .. " "
            .. b.diagnostics.errors
            .. "/"
            .. b.diagnostics.warnings
            .. "/"
            .. b.diagnostics.infos
            .. "/"
            .. b.diagnostics.hints
            .. " "
        end,
      },
    },
  })
  redraw = _G.cokeline.tabline
elseif kind == "mini" then
  require("mini.tabline").setup({ show_icons = false })
  redraw = require("mini.tabline").make_tabline_string
else
  require("bufferline").setup({
    options = {
      show_buffer_icons = false,
      diagnostics = "nvim_lsp",
      diagnostics_cache = kind == "cached",
    },
  })
  redraw = _G.nvim_bufferline
end
local setup_ms = (vim.uv.hrtime() - started) / 1e6
local buffers = {}
local root = vim.fn.tempname()
for i = 1, 100 do
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, root .. "/file_" .. i .. ".txt")
  buffers[#buffers + 1] = b
end
vim.api.nvim_set_current_buf(buffers[50])
local ns = vim.api.nvim_create_namespace("audit")
vim.diagnostic.config({ virtual_text = false, signs = false, underline = false })
local diags = {}
for i = 1, 100 do
  diags[i] = { lnum = 0, col = 0, message = "d", severity = (i % 4) + 1 }
end
for _, b in ipairs(buffers) do
  vim.diagnostic.set(ns, b, diags)
end
vim.wait(25, function()
  return false
end, 5)
for _ = 1, 3 do
  redraw()
end
local times = {}
for i = 1, 25 do
  local t = vim.uv.hrtime()
  redraw()
  times[i] = (vim.uv.hrtime() - t) / 1e6
end
table.sort(times)
local report = {
  kind = kind,
  setup_ms = setup_ms,
  median_ms = times[13],
  p95_ms = times[24],
  buffers = 100,
  diagnostics = 10000,
  samples = 25,
}
if kind == "native" then
  local g = require("bufferline.groups")
  local a, b = buffers[1], buffers[2]
  vim.api.nvim_buf_set_name(a, root .. "/comma,name.txt")
  local decoy = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(decoy, root .. "/comma")
  local suffix = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(suffix, root .. "/other/name.txt")
  g.add_element("pinned", { id = a })
  local saved = vim.g.BufferlinePinnedBuffers
  g.remove_element("pinned", { id = a })
  vim.g.BufferlinePinnedBuffers = saved
  vim.api.nvim_exec_autocmds("SessionLoadPost", {})
  report.comma_pin_restored = require("bufferline").is_pinned(a)
  report.unrelated_prefix_pinned = require("bufferline").is_pinned(decoy)
  vim.g.BufferlinePinnedBuffers = vim.api.nvim_buf_get_name(b)
  vim.api.nvim_exec_autocmds("SessionLoadPost", {})
  report.second_session_pin_restored = require("bufferline").is_pinned(b)
end
return report
