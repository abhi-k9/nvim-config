-- A real second editor, with a barrier after sync but before persistence.
vim.opt.rtp:prepend(vim.fn.getcwd())
local State = require("scoper.state")
State.load({ quiet = true })
local mode, ready, start, entry = arg[1], arg[2], arg[3], arg[4]
if mode == "crash" then
  require("scoper.util").atomic_write = function()
    os.exit(42)
  end
  State.add_paths("interrupted")
  error("crash fixture did not reach the write")
end
local save, saved = State.save, nil
State.save = function()
  vim.fn.writefile({ "ready" }, ready)
  assert(
    vim.wait(15000, function()
      return vim.uv.fs_stat(start) ~= nil
    end, 10),
    "barrier timed out"
  )
  saved = save()
  return saved
end
State.add_paths(entry)
io.stdout:write(vim.json.encode({ saved = saved, include = State.active_scope().include }) .. "\n")
