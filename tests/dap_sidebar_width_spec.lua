-- Isolate the actual window plugins from unrelated parsers/statusline timers.
-- No adapter, compiler, language server or debuggee is needed for this bug.
local function scenario(body)
  local dir, repo = vim.fn.tempname(), vim.fn.getcwd()
  vim.fn.mkdir(dir .. "/files", "p")
  vim.fn.writefile({ "plain text" }, dir .. "/files/one.txt")
  local dirs = {}
  for _, name in ipairs({
    "plenary.nvim",
    "nui.nvim",
    "nvim-nio",
    "nvim-dap",
    "nvim-dap-ui",
    "neo-tree.nvim",
    "nvim-web-devicons",
  }) do
    dirs[#dirs + 1] = assert(require("lazy.core.config").plugins[name], name).dir
  end
  local script = ([=[
vim.opt.rtp:prepend(%q)
for _, path in ipairs(%s) do vim.opt.rtp:append(path) end
vim.o.columns, vim.o.lines = 240, 70
-- Apply headless screen dimensions before establishing the initial layout.
vim.cmd.vsplit()
vim.cmd.close()
vim.fn.mkdir(vim.fn.stdpath("data"), "p")
local ui = require("dapui")
require("neo-tree").setup(require("plugins.explorer").opts)
ui.setup({ controls = { enabled = false } })
require("config.dap_ui_layout").attach(ui)
local files = %q
local function tree(tab)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab or 0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then return win end
  end
end
local function open_tree()
  vim.cmd.edit(files .. "/one.txt")
  require("neo-tree.command").execute({
    action = "show", source = "filesystem", position = "left", dir = files,
  })
  assert(vim.wait(1000, function() return tree() ~= nil end, 10), "Neo-tree sidebar is missing")
  return tree()
end
local function width(win, expected)
  local actual = vim.api.nvim_win_get_width(win)
  assert(actual == expected, ("Neo-tree width changed: expected %%d, got %%d"):format(expected, actual))
end
local side = open_tree()
width(side, 32)
%s
ui.close()
io.stdout:write("sidebar widths preserved\n")
]=]):format(repo, vim.inspect(dirs), dir .. "/files", body)
  vim.fn.writefile(vim.split(script, "\n", { plain = true }), dir .. "/probe.lua")
  local result = vim
    .system({ vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", dir .. "/probe.lua" }, {
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
  assert.is_truthy(result.stdout:find("sidebar widths preserved", 1, true))
end

describe("Neo-tree width across real debugger panel changes", function()
  it("does not accumulate the debugger sidebar width across repeated sessions", function()
    scenario([=[
for _ = 1, 4 do
  ui.open()
  width(side, 32)
  ui.close()
  width(side, 32)
end
]=])
  end)

  it("keeps a manual resize made while debugger panels are open", function()
    scenario([=[
ui.open()
vim.api.nvim_win_set_width(side, 57)
ui.close()
width(side, 57)
for _ = 1, 3 do
  ui.open()
  ui.close()
  width(side, 57)
end
]=])
  end)

  it("preserves width when only the debugger's vertical layout is closed", function()
    scenario([=[
local focused = vim.api.nvim_get_current_win()
for _ = 1, 4 do
  ui.open()
  ui.close({ layout = 1 })
  width(side, 32)
  assert(vim.api.nvim_get_current_win() == focused, "Panel close changed file-window focus")
  ui.close()
  width(side, 32)
end
]=])
  end)

  it("preserves sidebar widths when manually toggling the debugger panels", function()
    scenario([=[
for _ = 1, 4 do
  ui.toggle()
  width(side, 32)
  ui.toggle()
  width(side, 32)
end
]=])
  end)

  it("keeps independent widths and focus for debugger layouts in separate tabs", function()
    scenario([=[
local first = vim.api.nvim_get_current_tabpage()
ui.open({ layout = 1 })
vim.cmd.tabnew()
local second = vim.api.nvim_get_current_tabpage()
local second_side = open_tree()
vim.api.nvim_win_set_width(second_side, 45)
for _ = 1, 4 do
  vim.api.nvim_set_current_tabpage(first)
  ui.open({ layout = 1 })
  vim.api.nvim_set_current_tabpage(second)
  ui.open({ layout = 2 })
  ui.close()
  width(side, 32)
  width(second_side, 45)
  assert(vim.api.nvim_get_current_tabpage() == second, "Panel close changed tabs")
end
]=])
  end)
end)

describe("debugger layout guard public API", function()
  local win, buf

  before_each(function()
    vim.cmd.vsplit()
    win = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.bo[buf].filetype = "neo-tree"
    vim.b[buf].neo_tree_position = "left"
    vim.api.nvim_win_set_width(win, 32)
  end)

  after_each(function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end)

  it("preserves arguments and nil/false return slots", function()
    local ui = {
      open = function(...)
        assert.equals(3, select("#", ...))
        local first, middle, last = ...
        assert.equals("kept", first)
        assert.is_nil(middle)
        assert.is_false(last)
        vim.api.nvim_win_set_width(win, 60)
        return "returned", nil, false, nil
      end,
    }
    require("config.dap_ui_layout").attach(ui)
    local result = vim.F.pack_len(ui.open("kept", nil, false))
    assert.equals(4, result.n)
    assert.equals("returned", result[1])
    assert.is_nil(result[2])
    assert.is_false(result[3])
    assert.is_nil(result[4])
    assert.equals(32, vim.api.nvim_win_get_width(win))
  end)

  it("restores sidebar width without swallowing the upstream failure", function()
    local ui = {
      close = function()
        vim.api.nvim_win_set_width(win, 60)
        error("upstream layout failure", 0)
      end,
    }
    require("config.dap_ui_layout").attach(ui)
    local ok, err = pcall(ui.close)
    assert.is_false(ok)
    assert.equals("upstream layout failure", err)
    assert.equals(32, vim.api.nvim_win_get_width(win))
  end)

  it("attaches once and preserves a later owner's function replacement", function()
    local guard = require("config.dap_ui_layout")
    local ui = { close = function() end }
    guard.attach(ui)
    local wrapped = ui.close
    guard.attach(ui)
    assert.equals(wrapped, ui.close)
    local replacement = function()
      return "owner replacement"
    end
    ui.close = replacement
    guard.attach(ui)
    assert.equals(replacement, ui.close)
    assert.equals("owner replacement", ui.close())
  end)
end)
