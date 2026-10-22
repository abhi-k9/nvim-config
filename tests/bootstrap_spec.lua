-- First-boot tests run in clean child editors with fake Git and lazy.nvim.
-- No network, plugin installation, or shared Neovim data is used.
local source = vim.fn.readfile("lua/config/lazy.lua")
local commit = string.rep("a", 40)
local dirs = {}

local function bootstrap(lock, options)
  local dir = vim.fn.tempname()
  dirs[#dirs + 1] = dir
  local config = dir .. "/checkout"
  vim.fn.mkdir(config .. "/lua/config", "p")
  vim.fn.writefile(source, config .. "/lua/config/lazy.lua")
  if lock then vim.fn.writefile({ lock }, config .. "/lazy-lock.json") end
  local script = ([=[
local calls = {}
local options = vim.json.decode(%q)
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
local function manager(path, owner)
  vim.fn.mkdir(path .. '/lua/lazy', 'p')
  vim.fn.writefile({ '-- fake manager' }, path .. '/lua/lazy/init.lua')
  if owner then vim.fn.writefile({ owner }, path .. '/owner') end
end
if options.existing_incomplete then vim.fn.mkdir(lazypath, 'p') end
if options.cleanup_fails then
  local delete = vim.fn.delete
  vim.fn.delete = function(path, flags)
    if path:sub(1, #lazypath + 5) == lazypath .. '.tmp-' then return -1 end
    return delete(path, flags)
  end
end
if options.publish_fails then
  vim.uv.fs_rename = function() return nil, 'permission denied' end
elseif options.winner_during_publish then
  local rename = vim.uv.fs_rename
  vim.uv.fs_rename = function(from, to)
    manager(to, 'winner')
    return rename(from, to)
  end
end
vim.v = setmetatable({ shell_error = 0 }, { __index = vim.v })
package.preload.lazy = function()
  return { setup = function(opts)
    calls[#calls + 1] = { setup = true, lockfile = opts.lockfile }
  end }
end
vim.fn.system = function(args)
  calls[#calls + 1] = args
  vim.v.shell_error = 0
  if args[2] == 'clone' then
    if options.incomplete_clone then
      vim.fn.mkdir(args[#args], 'p')
    else
      manager(args[#args], 'ours')
    end
    if options.winner_during_clone then manager(lazypath, 'winner') end
    if options.empty_target_during_clone then vim.fn.mkdir(lazypath, 'p') end
    if options.clone_fails then
      vim.v.shell_error = 1
      return 'clone failed'
    end
  end
  if args[4] == 'checkout' and options.checkout_fails then
    vim.v.shell_error = 1
    return 'checkout failed'
  end
  return ''
end
dofile(%q)
vim.fn.writefile({ vim.json.encode({
  calls = calls,
  directory_exists = vim.fn.isdirectory(lazypath) == 1,
  owner = vim.fn.filereadable(lazypath .. '/owner') == 1 and vim.fn.readfile(lazypath .. '/owner')[1] or '',
  partials = vim.fn.glob(lazypath .. '.tmp-*', false, true),
}) }, %q)
]=]):format(
    vim.json.encode(options or {}),
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
    local result =
      bootstrap(vim.json.encode({ ["lazy.nvim"] = { commit = commit } }), { checkout_fails = true })
    assert.equals(2, #result.calls)
    assert.is_false(result.directory_exists)
    assert.equals(0, #result.partials)
  end)

  it("can bootstrap a new configuration without a lockfile", function()
    local result, config = bootstrap()
    assert.equals(2, #result.calls)
    assert.equals("clone", result.calls[1][2])
    assert.is_true(result.calls[2].setup)
    assert.equals(config .. "/lazy-lock.json", result.calls[2].lockfile)
  end)

  it("never deletes another editor's checkout when its own clone fails", function()
    local result = bootstrap(nil, { clone_fails = true, winner_during_clone = true })
    assert.equals("winner", result.owner)
    assert.equals(0, #result.partials)
    assert.is_true(result.calls[2].setup)
  end)

  it("reuses a completed winner instead of replacing it with its staged clone", function()
    local result = bootstrap(nil, { winner_during_clone = true })
    assert.equals("winner", result.owner)
    assert.equals(0, #result.partials)
    assert.is_true(result.calls[2].setup)
  end)

  it("does not replace an empty target created while its clone was running", function()
    local result = bootstrap(nil, { empty_target_during_clone = true })
    assert.equals(1, #result.calls)
    assert.is_true(result.directory_exists)
    assert.equals("", result.owner)
    assert.equals(0, #result.partials)
  end)

  it("keeps the winner that publishes between the existence check and rename", function()
    local result = bootstrap(nil, { winner_during_publish = true })
    assert.equals("winner", result.owner)
    assert.equals(0, #result.partials)
    assert.is_true(result.calls[2].setup)
  end)

  it("cleans only its staging directory when publishing fails", function()
    local result = bootstrap(nil, { publish_fails = true })
    assert.equals(1, #result.calls)
    assert.is_false(result.directory_exists)
    assert.equals(0, #result.partials)
  end)

  it("leaves an existing incomplete checkout intact and reports bootstrap failure", function()
    local result = bootstrap(nil, { existing_incomplete = true })
    assert.equals(0, #result.calls)
    assert.is_true(result.directory_exists)
  end)

  it("cleans its partial clone after an ordinary Git failure", function()
    local result = bootstrap(nil, { clone_fails = true })
    assert.equals(1, #result.calls)
    assert.is_false(result.directory_exists)
    assert.equals(0, #result.partials)
  end)

  it("never publishes an incomplete clone even if Git reports success", function()
    local result = bootstrap(nil, { incomplete_clone = true })
    assert.equals(1, #result.calls)
    assert.is_false(result.directory_exists)
    assert.equals(0, #result.partials)
  end)

  it("never falls back to deleting the winner if staging cleanup fails", function()
    local result =
      bootstrap(nil, { clone_fails = true, winner_during_clone = true, cleanup_fails = true })
    assert.equals("winner", result.owner)
    assert.equals(1, #result.partials)
    assert.is_true(result.calls[2].setup)
  end)
end)
