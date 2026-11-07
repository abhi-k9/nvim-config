-- Standalone smoke fixture: run from the checkout root on Linux/Windows/macOS.
-- Observe the opener argv without starting a desktop program in CI.
-- Like the specs, this isolated fixture intentionally stubs vim APIs.
-- luacheck: ignore 122
vim.opt.rtp:prepend(vim.fn.getcwd())
require("config.commands")
local settings = require("config.settings")
settings.configure({ images = { enabled = true, fallback = "notify" } })
local root = vim.fs.normalize(vim.fn.tempname())
vim.fn.mkdir(root, "p")
local file = root .. "/literal $image & (name) %#.png"
vim.fn.writefile({ "fixture" }, file)
local notes, argv = {}, nil
vim.notify = function(message)
  notes[#notes + 1] = message
end
vim.fn.executable = function(command)
  return vim.tbl_contains({ "convert", "identify", "rundll32.exe", "open", "xdg-open" }, command)
      and 1
    or 0
end
vim.system = function(command)
  argv = command
  return {}
end
local images = require("config.images")
vim.cmd("ImageOpen " .. vim.fn.fnameescape(file))
assert(#notes == 1 and notes[1]:find("no supported terminal UI", 1, true))
assert(not package.loaded["snacks.image"] and not argv)
vim.cmd("ImageOpen! " .. vim.fn.fnameescape(file))
assert(argv[#argv] == file, vim.inspect(argv))
if vim.fn.has("win32") == 1 then
  assert(argv[1] == "rundll32.exe" and argv[2] == "url.dll,FileProtocolHandler")
  assert(not images.status().converter, "Windows convert.exe is not ImageMagick")
  images.open("C:relative.png", true)
  assert(notes[#notes]:find("drive-relative", 1, true))
elseif vim.fn.has("mac") == 1 then
  assert(argv[1] == "open")
else
  assert(argv[1] == "xdg-open")
end
if vim.fn.has("win32") == 0 then
  local name = "diagram:local.png"
  vim.fn.writefile({ "fixture" }, root .. "/" .. name)
  vim.cmd.lcd(root)
  vim.cmd("ImageOpen! " .. vim.fn.fnameescape(name))
  assert(argv[#argv] == root .. "/" .. name, vim.inspect(argv))
end
vim.fn.delete(root, "rf")
print("Portable image command fixture passed")
