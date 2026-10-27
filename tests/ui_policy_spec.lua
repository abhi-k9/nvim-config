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
    assert.is_false(plugin(ui, "akinsho/bufferline.nvim").opts().options.show_buffer_icons)
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
    local bufferline = plugin(ui, "akinsho/bufferline.nvim")
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
