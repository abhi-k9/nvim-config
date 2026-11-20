-- lua/scoper/cdb_worker.lua
--
-- Background entry point for scoper.cdb, started by pipeline.lua as
--   nvim --clean --headless -l cdb_worker.lua <job.json> <result.json>
-- Writes the result of cdb.run as JSON to <result.json> (stdout may carry
-- messages). Not meant to be required.

local here = debug.getinfo(1, "S").source:sub(2)
local directory = vim.fs.dirname(here)
-- Resolve sibling modules literally. package.path treats ";" and "?" in the
-- installation directory as search syntax, even when the script argv is exact.
table.insert(package.loaders, 2, function(module)
  local name = module:match("^scoper%.([%w_]+)$")
  if name then return assert(loadfile(directory .. "/" .. name .. ".lua")) end
end)

local job = vim.json.decode(table.concat(vim.fn.readfile(arg[1]), "\n"))
local result = require("scoper.cdb").run(job)
assert(vim.fn.writefile({ vim.json.encode(result) }, arg[2]) == 0, "can't write " .. arg[2])
