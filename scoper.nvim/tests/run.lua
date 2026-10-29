-- -l exits with a nonzero status on Lua errors. An error in a -u init or
-- :PlenaryBustedDirectory Ex command can instead leave a headless editor open.
-- Resolve from cwd so the same entrypoint serves standalone Scoper and host.
dofile(vim.fn.getcwd() .. "/tests/minimal_init.lua")
require("plenary.test_harness").test_directory(arg[1] or "tests/", {
  minimal_init = "tests/minimal_init.lua",
  -- This entrypoint serves standalone Scoper and the full host config.
  -- Sequential children avoid shared-cache contention and UI timer starvation.
  sequential = true,
  timeout = 60000,
})
