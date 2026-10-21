-- First-boot tests run in clean child editors with fake Git and lazy.nvim.
-- No network, plugin installation, or shared Neovim data is used.
local source = vim.fn.readfile("lua/config/lazy.lua")
local commit = string.rep("a", 40)
local dirs = {}

local function bootstrap(lock, checkout_fails)
  local dir = vim.fn.tempname()
  dirs[#dirs + 1] = dir
  local config = dir .. "/checkout"
  vim.fn.mkdir(config .. "/lua/config", "p")
  vim.fn.writefile(source, config .. "/lua/config/lazy.lua")
  if lock then vim.fn.writefile({ lock }, config .. "/lazy-lock.json") end
  local script = ([=[
local calls = {}
vim.v = setmetatable({ shell_error = 0 }, { __index = vim.v })
package.preload.lazy = function()
  return { setup = function(opts)
    calls[#calls + 1] = { setup = true, lockfile = opts.lockfile }
  end }
end
vim.fn.system = function(args)
  calls[#calls + 1] = args
  vim.v.shell_error = 0
  if args[2] == 'clone' then vim.fn.mkdir(args[#args], 'p') end
  if args[4] == 'checkout' and %s then
    vim.v.shell_error = 1
    return 'checkout failed'
  end
  return ''
end
dofile(%q)
vim.fn.writefile({ vim.json.encode({
  calls = calls,
  directory_exists = vim.fn.isdirectory(vim.fn.stdpath('data') .. '/lazy/lazy.nvim') == 1,
}) }, %q)
]=]):format(
    tostring(checkout_fails or false),
    config .. "/lua/config/lazy.lua",
    dir .. "/result.json"
  )
  vim.fn.writefile(vim.split(script, "\n", { plain = true }), dir .. "/run.lua")
  local result = vim
    .system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", dir .. "/run.lua" }, {
      text = true,
      env = {
        XDG_CONFIG_HOME = dir .. "/unrelated-config",
        XDG_DATA_HOME = dir .. "/data",
        XDG_STATE_HOME = dir .. "/state",
        XDG_CACHE_HOME = dir .. "/cache",
        NVIM_LOG_FILE = dir .. "/nvim.log",
      },
    })
    :wait()
  assert.equals(0, result.code, result.stderr)
  return vim.json.decode(table.concat(vim.fn.readfile(dir .. "/result.json"), "\n")), config
end

describe("locked first-boot plugin manager", function()
  after_each(function()
    for _, dir in ipairs(dirs) do
      vim.fn.delete(dir, "rf")
    end
    dirs = {}
  end)

  it("checks out the locked manager before loading it and uses the checkout lockfile", function()
    local result, config = bootstrap(vim.json.encode({ ["lazy.nvim"] = { commit = commit } }))
    assert.equals("clone", result.calls[1][2])
    assert.equals("checkout", result.calls[2][4])
    assert.equals("--detach", result.calls[2][5])
    assert.equals(commit, result.calls[2][6])
    assert.is_true(result.calls[3].setup)
    assert.equals(config .. "/lazy-lock.json", result.calls[3].lockfile)
  end)

  it("does not load an unpinned manager when the lockfile is malformed", function()
    local result = bootstrap("{not json")
    assert.equals(0, #result.calls)
    assert.is_false(result.directory_exists)
  end)

  it("refuses non-SHA revisions in the manager pin", function()
    local result = bootstrap(vim.json.encode({ ["lazy.nvim"] = { commit = "--help" } }))
    assert.equals(0, #result.calls)
    assert.is_false(result.directory_exists)
  end)

  it("removes a failed checkout and never loads the wrong manager", function()
    local result = bootstrap(vim.json.encode({ ["lazy.nvim"] = { commit = commit } }), true)
    assert.equals(2, #result.calls)
    assert.is_false(result.directory_exists)
  end)

  it("can bootstrap a new configuration without a lockfile", function()
    local result, config = bootstrap()
    assert.equals(2, #result.calls)
    assert.equals("clone", result.calls[1][2])
    assert.is_true(result.calls[2].setup)
    assert.equals(config .. "/lazy-lock.json", result.calls[2].lockfile)
  end)
end)
