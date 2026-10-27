-- Isolate the actual window plugins from unrelated parsers/statusline timers.
-- No adapter, compiler, language server or debuggee is needed for this bug.
local function scenario(body, options)
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
ui.setup(%s)
require("config.dap_ui_layout").attach(ui)
local files = %q
local function open_side(position, size)
  vim.cmd((position == "right" and "botright " or "topleft ") .. size .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(false, true))
  vim.wo[win].winfixwidth = true
  return win
end
local function width(win, expected)
  local actual = vim.api.nvim_win_get_width(win)
  assert(actual == expected, ("Window %%d width changed: expected %%d, got %%d"):format(win, expected, actual))
end
local editor = vim.api.nvim_get_current_win()
local side = open_side("left", 32)
vim.api.nvim_set_current_win(editor)
width(side, 32)
%s
ui.close()
io.stdout:write("sidebar widths preserved\n")
]=]):format(
    repo,
    vim.inspect(dirs),
    vim.inspect(vim.tbl_extend("force", { controls = { enabled = false } }, options or {})),
    dir .. "/files",
    body
  )
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

describe("fixed columns across real debugger panel changes", function()
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
local second_side = open_side("left", 45)
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

  it("preserves both left and right columns without cumulative shrinkage", function()
    scenario([=[
local right = open_side("right", 45)
vim.api.nvim_set_current_win(editor)
for _ = 1, 4 do
  ui.open()
  width(side, 32)
  width(right, 45)
  ui.close()
  width(side, 32)
  width(right, 45)
end
]=])
  end)

  it("lets a horizontal fixed panel follow the width of its flexible editor column", function()
    scenario([=[
vim.cmd("belowright 10split")
local bottom = vim.api.nvim_get_current_win()
vim.wo[bottom].winfixwidth = true
vim.wo[bottom].winfixheight = true
local initial = vim.api.nvim_win_get_width(editor)
vim.api.nvim_set_current_win(editor)
for _ = 1, 3 do
  ui.open()
  width(side, 32)
  width(editor, initial - 41)
  width(bottom, initial - 41)
  ui.close()
  width(side, 32)
  width(editor, initial)
  width(bottom, initial)
end
]=])
  end)

  it("lets full-width horizontal panels regain the screen width", function()
    scenario([=[
vim.cmd("botright 10split")
local bottom = vim.api.nvim_get_current_win()
vim.wo[bottom].winfixwidth = true
vim.wo[bottom].winfixheight = true
local initial = vim.api.nvim_win_get_width(bottom)
vim.api.nvim_set_current_win(editor)
for _ = 1, 3 do
  ui.open()
  width(bottom, initial - 41)
  ui.close()
  width(bottom, initial)
  width(side, 32)
end
]=])
  end)

  it("leaves coupled grids of fixed windows to Neovim instead of fighting their widths", function()
    scenario([=[
local grid = {}
vim.api.nvim_set_current_win(side)
vim.cmd.split()
grid[1] = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
grid[2] = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(side)
vim.cmd.vsplit()
grid[3] = vim.api.nvim_get_current_win()
grid[4] = side
for _, win in ipairs(grid) do vim.wo[win].winfixwidth = true end
vim.api.nvim_set_current_win(editor)
-- DAP UI sizes its own panels through this API; the guard must not also
-- resize individual leaves of the coupled grid.
local set_width = vim.api.nvim_win_set_width
local grid_resizes = 0
vim.api.nvim_win_set_width = function(win, size)
  if vim.tbl_contains(grid, win) then grid_resizes = grid_resizes + 1 end
  return set_width(win, size)
end
for _ = 1, 3 do ui.open(); ui.close() end
vim.api.nvim_win_set_width = set_width
assert(grid_resizes == 0, "Guard tried to impose incompatible grid widths")
]=])
  end)

  it("protects stacked fixed windows and leaves flexible file splits free to resize", function()
    scenario([=[
vim.api.nvim_set_current_win(side)
vim.cmd.split()
local stacked = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(stacked, vim.api.nvim_create_buf(false, true))
vim.wo[stacked].winfixwidth = true
vim.api.nvim_set_current_win(editor)
vim.cmd.vsplit()
local other = vim.api.nvim_get_current_win()
vim.wo[other].winfixwidth = false
local initial = vim.api.nvim_win_get_width(editor) + vim.api.nvim_win_get_width(other)
for _ = 1, 3 do
  ui.open()
  width(side, 32)
  width(stacked, 32)
  assert(vim.api.nvim_win_get_width(editor) + vim.api.nvim_win_get_width(other) == initial - 41,
    "Flexible editors did not make room for DAP UI")
  ui.close()
  width(side, 32)
  width(stacked, 32)
end
]=])
  end)

  it("allows native clamping on a narrow screen without repeated width loss", function()
    scenario([=[
local right = open_side("right", 45)
vim.api.nvim_set_current_win(editor)
vim.o.columns = 100
ui.open()
local left_width, right_width = vim.api.nvim_win_get_width(side), vim.api.nvim_win_get_width(right)
assert(left_width > 0 and right_width > 0, "Fixed columns must remain usable")
ui.close()
for _ = 1, 3 do
  ui.open()
  ui.close()
  width(side, left_width)
  width(right, right_width)
end
]=])
  end)

  it(
    "supports custom layout positions and keeps DAP panel resizing under DAP UI control",
    function()
      scenario(
        [=[
for _ = 1, 3 do
  ui.open()
  width(side, 32)
  ui.close({ layout = 1 })
  width(side, 32)
  ui.close()
  width(side, 32)
end
ui.open({ layout = 1 })
local panel = require("dapui.windows").layouts[1].opened_wins[1]
vim.bo[vim.api.nvim_win_get_buf(panel)].filetype = "unrelated-custom-element"
vim.api.nvim_win_set_width(panel, 63)
ui.open({ reset = true })
width(panel, 40)
width(side, 32)
]=],
        {
          layouts = {
            { elements = { "scopes" }, position = "right", size = 40 },
            { elements = { "repl" }, position = "top", size = 10 },
          },
        }
      )
    end
  )

  it("protects actual Neo-tree through its native fixed-width option", function()
    scenario([=[
vim.api.nvim_win_close(side, true)
vim.cmd.edit(files .. "/one.txt")
require("neo-tree").setup(require("plugins.explorer").opts)
require("neo-tree.command").execute({
  action = "show", source = "filesystem", position = "left", dir = files,
})
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then side = win end
end
assert(vim.api.nvim_win_is_valid(side), "Neo-tree sidebar is missing")
assert(vim.wo[side].winfixwidth, "Neo-tree must advertise fixed width")
for _ = 1, 3 do
  ui.open()
  ui.close()
  width(side, 32)
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
    vim.wo[win].winfixwidth = true
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

  it("respects a fixed-width opt-out made during an operation", function()
    local ui = {
      close = function()
        vim.wo[win].winfixwidth = false
        vim.api.nvim_win_set_width(win, 60)
      end,
    }
    require("config.dap_ui_layout").attach(ui)
    ui.close()
    assert.equals(60, vim.api.nvim_win_get_width(win))
  end)

  it("does not resize a replacement buffer in the same window", function()
    local replacement = vim.api.nvim_create_buf(false, true)
    local ui = {
      close = function()
        vim.api.nvim_win_set_buf(win, replacement)
        vim.api.nvim_win_set_width(win, 60)
      end,
    }
    require("config.dap_ui_layout").attach(ui)
    ui.close()
    assert.equals(60, vim.api.nvim_win_get_width(win))
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_buf_delete(replacement, { force = true })
  end)

  it("ignores fixed-width floating windows", function()
    local float = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 20,
      height = 3,
    })
    vim.wo[float].winfixwidth = true
    local ui = {
      open = function()
        vim.api.nvim_win_set_width(float, 40)
      end,
    }
    require("config.dap_ui_layout").attach(ui)
    ui.open()
    assert.equals(40, vim.api.nvim_win_get_width(float))
    vim.api.nvim_win_close(float, true)
  end)
end)
