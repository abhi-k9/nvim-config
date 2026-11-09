local settings = require("config.settings")

local function plugin(specs, name)
  for _, spec in ipairs(specs) do
    if spec[1] == name then return spec end
  end
  error("Missing fixture plugin: " .. name)
end

describe("portable UI policies", function()
  local icons, colors
  before_each(function()
    settings.reset()
    icons = package.loaded["config.icons"]
    colors = vim.g.colors_name
  end)
  after_each(function()
    settings.reset()
    package.loaded["config.icons"] = icons
    if colors then vim.cmd.colorscheme(colors) end
  end)

  it("renders shared information and chrome without Nerd Font icons", function()
    settings.configure({ ui = { icons = false } })
    package.loaded["config.icons"] = nil
    local ascii = require("config.icons")
    assert.are.equal("E ", ascii.diagnostics.error)
    assert.are.equal("+", ascii.misc.fold)
    local ui = dofile("lua/plugins/ui.lua")
    assert.is_false(plugin(ui, "nvim-lualine/lualine.nvim").opts().options.icons_enabled)
    assert.is_false(plugin(ui, "abhi-k9/bufferline.nvim").opts().options.show_buffer_icons)
    local which_key = dofile("lua/plugins/which-key.lua")
    assert.is_false(which_key.opts.icons.mappings)
    assert.are.equal("CR ", which_key.opts.icons.keys.CR)
  end)

  it("uses a stock colorscheme without requiring Catppuccin highlights", function()
    settings.configure({ ui = { colorscheme = "habamax" } })
    local color = dofile("lua/plugins/colorscheme.lua")
    assert.is_false(color[1].enabled)
    assert.are.equal("habamax", vim.g.colors_name)
    local ui = dofile("lua/plugins/ui.lua")
    local bufferline = plugin(ui, "abhi-k9/bufferline.nvim")
    assert.are.same({}, bufferline.opts().highlights)
    assert.is_false(vim.tbl_contains(bufferline.dependencies, "catppuccin/nvim"))
  end)

  it("disables both animation plugins and uses static progress in reduced motion", function()
    settings.configure({ ui = { reduced_motion = true } })
    local editor = dofile("lua/plugins/editor.lua")
    assert.is_false(plugin(editor, "karb94/neoscroll.nvim").cond())
    assert.is_false(plugin(editor, "sphamba/smear-cursor.nvim").cond())
    local ui = dofile("lua/plugins/ui.lua")
    assert.are.equal(".", plugin(ui, "j-hui/fidget.nvim").opts.progress.display.progress_icon)
  end)

  it("keeps Telescope typing on the real cursor while retaining code-window animation", function()
    local dir, checkout = vim.fn.tempname(), vim.fn.getcwd()
    vim.fn.mkdir(dir, "p")
    local smear_dir = assert(require("lazy.core.config").plugins["smear-cursor.nvim"]).dir
    local script = ([=[
vim.opt.rtp:prepend(%q)
vim.opt.rtp:append(%q)
local specs = dofile(%q)
local opts
for _, spec in ipairs(specs) do
  if spec[1] == "sphamba/smear-cursor.nvim" then opts = spec.opts end
end
assert(opts, "Missing smear-cursor configuration")
local smear = require("smear_cursor")
smear.setup(opts)
-- Drain setup work before observing this operation's event gate. This does
-- not assert that an animation already in flight disappears on a transition.
vim.wait(50, function() return false end, 5)
local animation = require("smear_cursor.animation")
local events = require("smear_cursor.events")
local replacements, scheduled = 0, 0
local original_replace, original_defer = animation.replace_real_cursor, vim.defer_fn
animation.replace_real_cursor = function() replacements = replacements + 1 end
vim.defer_fn = function() scheduled = scheduled + 1 end
vim.bo.filetype = "lua"
events.move_cursor()
assert(replacements == 1 and scheduled == 1, "Code windows lost cursor animation")
replacements, scheduled = 0, 0
vim.bo.filetype = "TelescopePrompt"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "sprin" })
for _ = 1, 20 do events.move_cursor() end
assert(replacements == 0, "Prompt typing replaced the real cursor")
assert(scheduled == 0, "Prompt typing scheduled cursor animation")
assert(vim.api.nvim_get_current_line() == "sprin", "Cursor handling changed prompt text")
animation.replace_real_cursor, vim.defer_fn = original_replace, original_defer
smear.enabled = false
io.stdout:write("Prompt cursor stays native\n")
]=]):format(checkout, smear_dir, checkout .. "/lua/plugins/editor.lua")
    vim.fn.writefile(vim.split(script, "\n", { plain = true }), dir .. "/cursor.lua")
    local result = vim
      .system({ vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", dir .. "/cursor.lua" }, {
        text = true,
        env = {
          XDG_CONFIG_HOME = dir .. "/config",
          XDG_DATA_HOME = dir .. "/data",
          XDG_STATE_HOME = dir .. "/state",
          XDG_CACHE_HOME = dir .. "/cache",
          NVIM_LOG_FILE = dir .. "/nvim.log",
        },
      })
      :wait(10000)
    vim.fn.delete(dir, "rf")
    assert.equals(0, result.code, (result.stderr or "") .. (result.stdout or ""))
    assert.is_truthy(result.stdout:find("Prompt cursor stays native", 1, true))
  end)

  it("allows global buffers without enabling the tab ownership plugin", function()
    settings.configure({ sessions = { global_buffers = true } })
    assert.is_false(plugin(dofile("lua/plugins/ui.lua"), "tiagovla/scope.nvim").cond())
  end)

  it("starts the full config with the portable UI profile before deferred events", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local checkout = vim.fn.getcwd()
    local local_file = dir .. "/local.lua"
    vim.fn.writefile({
      'return { ui = { colorscheme = "habamax", icons = false, reduced_motion = true },',
      "sessions = { global_buffers = true, auto_restore = false, auto_save = false },",
      "tools = { servers = {}, packages = {}, parsers = {} } }",
    }, local_file)
    local script = ([=[
vim.opt.rtp:prepend(%q)
vim.g.config_local_file = %q
vim.g.treesitter_auto_install = false
vim.go.loadplugins = true
local errors = {}
vim.notify = function(message, level)
  if level == vim.log.levels.ERROR then errors[#errors + 1] = tostring(message) end
end
dofile(%q)
local installer = package.loaded["mason-tool-installer"]
if installer then installer.setup({ run_on_start = false }) end
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
local loader = require("lazy.core.loader")
for _, name in ipairs({ "lualine.nvim", "bufferline.nvim", "incline.nvim", "fidget.nvim", "which-key.nvim", "render-markdown.nvim" }) do
  loader.load(name, { cmd = "portable UI profile" })
end
vim.wait(200, function() return false end, 20)
assert(vim.g.colors_name == "habamax", "stock scheme was overwritten")
assert(not package.loaded["catppuccin"], "stock theme loaded Catppuccin")
assert(not package.loaded["scope"], "global buffers loaded scope.nvim")
assert(not package.loaded["neoscroll"], "reduced motion loaded neoscroll")
assert(not package.loaded["smear_cursor"], "reduced motion loaded smear-cursor")
assert(require("config.icons").diagnostics.error == "E ", "shared icons are not ASCII")
assert(#errors == 0, table.concat(errors, "\n"))
io.stdout:write("portable UI profile passed\n")
]=]):format(checkout, local_file, checkout .. "/init.lua")
    vim.fn.writefile(vim.split(script, "\n", { plain = true }), dir .. "/profile.lua")
    local result = vim
      .system({ vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", dir .. "/profile.lua" }, {
        text = true,
        env = {
          XDG_STATE_HOME = dir .. "/state",
          XDG_CACHE_HOME = dir .. "/cache",
          NVIM_LOG_FILE = dir .. "/nvim.log",
        },
      })
      :wait(15000)
    vim.fn.delete(dir, "rf")
    assert.are.equal(0, result.code, (result.stderr or "") .. (result.stdout or ""))
    assert.is_truthy((result.stdout or ""):find("portable UI profile passed", 1, true))
  end)
end)
