-- Opt-in only: scripts/portable-smoke.py supplies a disposable config/state
-- and bounds this process externally. No test harness or language tools needed.
local phase = assert(arg[1], "use scripts/portable-smoke.py")
assert(phase == "prepare" or phase == "smoke" or phase == "stress", "unknown check phase")
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.go.loadplugins = true
local errors, notify = {}, vim.notify
-- luacheck: ignore 122
vim.notify = function(message, level, opts)
  if level == vim.log.levels.ERROR then errors[#errors + 1] = tostring(message) end
  return notify(message, level, opts)
end
dofile("init.lua")
assert(package.loaded.lazy, "plugin bootstrap did not finish")
local lazy = require("lazy")
local config = require("lazy.core.config")
config.options.checker.enabled = false
if phase == "prepare" then
  -- Restore in the disposable checkout; a test cache may have older revisions.
  local lock = vim.json.decode(table.concat(vim.fn.readfile("lazy-lock.json"), "\n"))
  for name, plugin in pairs(config.plugins) do
    local installed = lock[name] and require("lazy.manage.git").info(plugin.dir)
    if lock[name] and (not installed or installed.commit ~= lock[name].commit) then
      lazy.restore({ wait = true, show = false })
      break
    end
  end
  assert(#errors == 0, table.concat(errors, "\n"))
  print("Locked plugins prepared; language-tool and native-sorter builds disabled")
  return
end

assert(#vim.api.nvim_list_uis() > 0, "smoke workflows require the runner UI")
lazy.load({
  plugins = {
    "mason-lspconfig.nvim",
    "telescope.nvim",
    "neo-tree.nvim",
    "nvim-dap-ui",
    "trouble.nvim",
    "conform.nvim",
    "gitsigns.nvim",
    "toggleterm.nvim",
  },
})
local path = vim.fn.getcwd() .. "/sample % # [x].txt"
vim.fn.writefile({ "portable smoke", "second line" }, path)
vim.cmd.edit({ args = { path }, magic = { file = false } })
local source, source_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
assert(vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == "portable smoke")
assert(vim.fn.exists(":WorkspaceInfo") == 2 and vim.fn.exists(":ScoperToggle") == 2)
assert(require("config.workspace").snapshot().launch_file, "workspace inspection failed")
local session = require("config.session")
session.save_scopes()
assert(session.restore_scopes(), "real scope.nvim session bridge failed")

-- Open the real picker and enter a query, without requiring fd/rg or a native
-- sorter. Terminal keystroke encoding and visual rendering remain manual checks.
require("telescope.builtin").buffers({ previewer = false })
local prompt = vim.api.nvim_get_current_buf()
local picker = require("telescope.actions.state").get_current_picker(prompt)
assert(
  vim.wait(1500, function()
    return picker.manager and picker.manager:num_results() > 0
  end, 10),
  "buffer picker did not produce results"
)
picker:set_prompt("sample")
vim.wait(100, function()
  return false
end, 10)
require("telescope.actions").close(prompt)
vim.wait(100, function()
  return false
end, 10)
vim.api.nvim_set_current_win(source_win)

local explorer = require("neo-tree.command")
explorer.execute({
  action = "show",
  source = "filesystem",
  position = "left",
  dir = vim.fn.getcwd(),
})
explorer.execute({ action = "show", source = "buffers", position = "left" })
explorer.execute({ action = "show", source = "filesystem", position = "left" })
local side
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then side = win end
end
assert(side and vim.wo[side].winfixwidth, "explorer fixed-width sidebar missing")
vim.api.nvim_set_current_win(source_win)
local width = vim.api.nvim_win_get_width(side)
local ui, summaries = require("dapui"), require("bufferline.diagnostics")
local namespace = vim.api.nvim_create_namespace("portable-smoke")
vim.diagnostic.config({ virtual_text = false, signs = false, underline = false })
local function drain()
  local finished = false
  vim.defer_fn(function()
    finished = true
  end, 50)
  assert(
    vim.wait(1000, function()
      return finished
    end, 10),
    "event queue did not drain"
  )
end
local function control_buffer()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    -- The disposable config uses DAP UI's default controls.element = "repl".
    if vim.bo[buf].filetype == "dap-repl" then
      assert(vim.wo[win].winbar:find("v:lua._dapui.play", 1, true), "DAP toolbar disappeared")
      return buf
    end
  end
  error("DAP control window missing")
end
local function cycle()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buffer, vim.fn.getcwd() .. "/cycle.txt")
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "cycle" })
  local diagnostics = {}
  for index = 1, 200 do
    diagnostics[index] = { lnum = 0, col = 0, message = "check " .. index, severity = 2 }
  end
  vim.diagnostic.set(namespace, buffer, diagnostics)
  assert(summaries.get({ diagnostics = "nvim_lsp" })[buffer].count == 200)
  for _ = 1, 20 do
    assert(summaries.get({ diagnostics = "nvim_lsp" })[buffer].count == 200)
  end
  ui.open()
  drain()
  control_buffer()
  ui.close()
  drain()
  assert(vim.api.nvim_win_get_width(side) == width, "sidebar width drift")
  session.save_scopes()
  assert(session.restore_scopes())
  vim.api.nvim_buf_delete(buffer, { force = true })
  assert(summaries.get({ diagnostics = "nvim_lsp" })[buffer].count == 0, "stale diagnostic count")
end
-- Warm lazy resources before comparing lifecycle counts, including async UI work.
cycle()
drain()
cycle()
drain()
-- A wiped control buffer must regain its toolbar without accumulating handlers.
-- Exercise the plugin's actual buffer factories and deferred rebinding.
ui.open()
drain()
local old_control = control_buffer()
ui.close()
vim.api.nvim_buf_delete(old_control, { force = true })
-- Native DAP UI rebinds in a scheduled BufWipeout callback. Wait for ownership
-- to move before reopening, rather than rely on the retired adapter's timing.
assert(
  vim.wait(1000, function()
    local commands = vim.api.nvim_get_autocmds({ group = "DAPUIControls" })
    if #commands == 0 then return false end
    for _, command in ipairs(commands) do
      if
        not command.buffer
        or command.buffer == old_control
        or not vim.api.nvim_buf_is_valid(command.buffer)
      then
        return false
      end
    end
    return true
  end, 10),
  "DAP control handlers did not rebind after buffer wipe"
)
ui.open()
drain()
assert(control_buffer() ~= old_control, "DAP control buffer was not recreated")
ui.close()
drain()
local function resources()
  collectgarbage("collect")
  local groups = {}
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
    local name = autocmd.group_name or "ungrouped"
    groups[name] = (groups[name] or 0) + 1
  end
  return {
    buffers = #vim.api.nvim_list_bufs(),
    windows = #vim.api.nvim_list_wins(),
    autocmds = #vim.api.nvim_get_autocmds({}),
    lua_kib = math.floor(collectgarbage("count")),
    groups = groups,
  }
end
local function control_handlers(snapshot)
  return snapshot.groups.DAPUIControls or 0
end
local before = resources()
assert(control_handlers(before) > 0, "DAP control lifecycle was not exercised")
local cycles, started = phase == "stress" and 25 or 1, vim.uv.hrtime()
for _ = 1, cycles do
  assert((vim.uv.hrtime() - started) / 1e9 < 15, "lifecycle cycle budget exceeded")
  cycle()
end
drain()
local after = resources()
assert(control_handlers(after) == control_handlers(before), "DAP control handlers accumulated")
assert(after.buffers <= before.buffers, "buffers accumulated: " .. vim.inspect({ before, after }))
assert(after.windows == before.windows, "windows accumulated")
local growth = {}
for group, count in pairs(after.groups) do
  if count > (before.groups[group] or 0) then
    growth[#growth + 1] = group .. ": " .. (before.groups[group] or 0) .. " -> " .. count
    assert(not group:match("^user_"), "config autocommands accumulated: " .. group)
  end
end
-- Plugins and Neovim can register lazily, so total registry growth is reported
-- separately from config-owned groups. Known upstream growth is documented;
-- a passing smoke check must not be read as an absence-of-leaks claim.
table.sort(growth)
before.control_handlers, after.control_handlers = control_handlers(before), control_handlers(after)
before.groups, after.groups = nil, nil
assert(#errors == 0, table.concat(errors, "\n"))
assert(#vim.lsp.get_clients() == 0, "smoke unexpectedly started a language server")
return {
  phase = phase,
  cycles = cycles,
  seconds = (vim.uv.hrtime() - started) / 1e9,
  before = before,
  after = after,
  observed_autocmd_growth = growth,
}
