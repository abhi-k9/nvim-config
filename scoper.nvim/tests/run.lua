-- -l exits with a nonzero status on Lua errors. An error in a -u init or
-- :PlenaryBustedDirectory Ex command can instead leave a headless editor open.
-- Resolve from cwd so the same entrypoint serves standalone Scoper and host.
local checkout = vim.fn.getcwd()
local cache = vim.fn.stdpath("cache") .. "/config-tests"
local run = vim.fn.tempname()
vim.o.shadafile = "NONE"
vim.env.NVIM = nil
vim.env.NVIM_APPNAME = "nvim"
vim.env.XDG_STATE_HOME = run .. "/state"
vim.env.XDG_CONFIG_HOME = run .. "/config"
vim.env.XDG_CONFIG_DIRS = run .. "/system-config"
vim.env.XDG_DATA_DIRS = run .. "/system-data"
vim.env.XDG_DATA_HOME = cache .. "/data"
vim.env.XDG_CACHE_HOME = cache .. "/cache"
vim.env.NVIM_LOG_FILE = run .. "/nvim.log"
assert(vim.fn.mkdir(run, "p") == 1)
-- The parent started before these environment changes. Discard its inherited
-- runtime search path too; Plenary children start with the isolated paths.
vim.opt.runtimepath = { vim.env.VIMRUNTIME }
vim.opt.packpath = { vim.env.VIMRUNTIME }

if vim.fn.filereadable(checkout .. "/lazy-lock.json") == 1 then
  local config = vim.fn.stdpath("config")
  vim.env.NVIM_TEST_CONFIG = config
  -- Lazy can rewrite the lock during installation. Run the checkout's current
  -- sources (including uncommitted edits) from a disposable config directory.
  local function copy(relative)
    local destination = config .. "/" .. relative
    vim.fn.mkdir(vim.fs.dirname(destination), "p")
    assert(vim.uv.fs_copyfile(checkout .. "/" .. relative, destination))
  end
  for _, file in ipairs({ "init.lua", "lazy-lock.json", "README.md", "CHANGES.md" }) do
    copy(file)
  end
  for _, tree in ipairs({ "lua", "docs", "scoper.nvim/lua", "scoper.nvim/plugin" }) do
    for name, kind in vim.fs.dir(checkout .. "/" .. tree, { depth = math.huge }) do
      if kind == "file" then copy(tree .. "/" .. name) end
    end
  end
end

local target = arg[1] or "tests/"
local stat = vim.uv.fs_stat(target)
assert(stat, "test target does not exist: " .. target)
if stat.type == "directory" then
  assert(
    vim.fs.find(function(name)
      return name:match("_spec%.lua$") ~= nil
    end, { path = target, type = "file" })[1],
    "no specs in " .. target
  )
else
  assert(stat.type == "file" and target:match("_spec%.lua$"), "expected a *_spec.lua file")
end

dofile(vim.fn.getcwd() .. "/tests/minimal_init.lua")
-- Plenary's Windows directory finder starts PowerShell with the target as
-- cwd. A single spec is a file, so invoke the same Busted entry point directly.
if stat.type == "file" then
  local result = vim
    .system({
      vim.v.progpath,
      "--headless",
      "--noplugin",
      "-u",
      "tests/minimal_init.lua",
      "-c",
      'lua require("plenary.busted").run(vim.env.NVIM_TEST_SPEC)',
    }, { env = { NVIM_TEST_SPEC = vim.fn.fnamemodify(target, ":p") }, text = true })
    :wait(60000)
  io.stdout:write(result.stdout or "")
  io.stderr:write(result.stderr or "")
  vim.cmd(("cquit %d"):format(result.code ~= 0 and 1 or 0))
  return
end
require("plenary.test_harness").test_directory(target, {
  minimal_init = "tests/minimal_init.lua",
  -- This entrypoint serves standalone Scoper and the full host config.
  -- Sequential children avoid shared-cache contention and UI timer starvation.
  sequential = true,
  timeout = 60000,
})
