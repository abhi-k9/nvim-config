-- -l exits with a nonzero status on Lua errors. An error in a -u init or
-- :PlenaryBustedDirectory Ex command can instead leave a headless editor open.
-- Resolve from cwd so the same entrypoint serves standalone Scoper and host.
dofile(vim.fn.getcwd() .. "/tests/minimal_init.lua")
require("plenary.test_harness").test_directory(arg[1] or "tests/", {
  minimal_init = "tests/minimal_init.lua",
  -- Every spec boots the real config. Parallel first starts contend for
  -- shared plugin caches and can starve short asynchronous UI assertions.
  sequential = true,
  timeout = 60000,
})
