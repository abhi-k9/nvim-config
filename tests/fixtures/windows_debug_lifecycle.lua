-- The manual Windows job builds smoke.exe and its PDB in this temporary project.
local root, repo = vim.env.NATIVE_ROOT, vim.env.NATIVE_REPO
assert(root and repo and vim.fn.has("win32") == 1)
vim.opt.rtp:prepend(repo)
vim.opt.rtp:prepend(repo .. "/scoper.nvim")
vim.opt.rtp:prepend(root .. "/dap")
vim.cmd("runtime plugin/scoper.lua")
vim.cmd("filetype on")

local source = vim.fs.joinpath(root, "smoke.cpp")
local database = { { directory = root, file = source, arguments = { "clang++", "-c", source } } }
assert(vim.fn.writefile({ vim.json.encode(database) }, "compile_commands.json") == 0)
vim.lsp.config("clangd", { cmd = { "clangd" }, filetypes = { "cpp" }, root_dir = root })
require("scoper").setup({ lsp = { mode = "filtered", watch = false } })
vim.cmd.ScoperAdd("smoke.cpp")
if not require("scoper.state").is_enabled() then vim.cmd.ScoperToggle() end
vim.lsp.enable("clangd")
vim.cmd.edit("smoke.cpp")
local buf = vim.api.nvim_get_current_buf()
local function wait_for_client(previous)
  local id
  assert(
    vim.wait(20000, function()
      local clients = vim.lsp.get_clients({ name = "clangd" })
      local c = clients[1]
      if #clients == 1 and c.initialized and c.id ~= previous and c.attached_buffers[buf] then
        id = c.id
        return true
      end
    end, 20),
    "clangd did not attach one initialized replacement"
  )
  return id
end
local id = wait_for_client(nil)
for _ = 1, 2 do
  vim.cmd.ScoperLspReload()
  id = wait_for_client(id)
end
vim.lsp.enable("clangd", false)

require("config.settings").configure({ debug = { mason_root = root .. "/mason" } })
require("config.dap").setup()
local dap = require("dap")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
dap.toggle_breakpoint()
for cycle = 1, 2 do
  local exit_code
  dap.listeners.after.event_exited.native_smoke = function(_, event)
    exit_code = event.exitCode
  end
  dap.run({
    name = "PDB smoke",
    type = "codelldb",
    request = "launch",
    program = root .. "/smoke.exe",
    cwd = root,
    terminal = "console",
  })
  assert(
    vim.wait(30000, function()
      local session = dap.session()
      local frame = session and session.current_frame
      return frame
        and frame.line == 2
        and frame.source
        and vim.fs.basename(frame.source.path or ""):lower() == "smoke.cpp"
    end, 20),
    "PDB source breakpoint missed on launch " .. cycle
  )
  dap.continue()
  assert(
    vim.wait(15000, function()
      return exit_code == 0 and not dap.session()
    end, 20),
    "debuggee did not exit cleanly on launch " .. cycle
  )
end
print("Two clangd reloads and two CodeLLDB/PDB source breakpoint launches passed")
