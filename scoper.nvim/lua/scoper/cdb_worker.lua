-- lua/scoper/cdb_worker.lua
--
-- Background entry point for scoper.cdb, started by pipeline.lua as
--   nvim --clean --headless -l cdb_worker.lua <job.json> <result.json>
-- Writes the result of cdb.run as JSON to <result.json> (stdout may carry
-- messages). Not meant to be required.

local here = debug.getinfo(1, "S").source:sub(2)
local lua_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(here)))
package.path = lua_dir .. "/?.lua;" .. lua_dir .. "/?/init.lua;" .. package.path

local job = vim.json.decode(table.concat(vim.fn.readfile(arg[1]), "\n"))
local result = require("scoper.cdb").run(job)
assert(vim.fn.writefile({ vim.json.encode(result) }, arg[2]) == 0, "can't write " .. arg[2])
