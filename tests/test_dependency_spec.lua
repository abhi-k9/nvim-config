-- Exercise both suites' shared bootstrap with real files and controlled Git.
local helper = vim.fn.getcwd() .. "/scoper.nvim/tests/bootstrap.lua"
local dirs = {}

local function bootstrap(options)
  local dir = vim.fn.tempname()
  dirs[#dirs + 1] = dir
  vim.fn.mkdir(dir, "p")
  local script = ([=[
local options = vim.json.decode(%q)
local install = vim.fn.stdpath('cache') .. '/test-deps/plenary.nvim'
vim.fn.writefile({ vim.json.encode(install) }, %q)
local calls = {}
local function ready(path, owner)
  vim.fn.mkdir(path .. '/lua/plenary', 'p')
  vim.fn.mkdir(path .. '/plugin', 'p')
  vim.fn.writefile({ '-- fixture' }, path .. '/lua/plenary/busted.lua')
  vim.fn.writefile({ '" fixture' }, path .. '/plugin/plenary.vim')
  vim.fn.writefile({ owner }, path .. '/owner')
end
if options.existing then ready(install, 'existing') end
if options.incomplete then vim.fn.mkdir(install, 'p') end
if options.missing_runtime then
  ready(install, 'existing')
  vim.fn.delete(install .. '/plugin/plenary.vim')
end
if options.publish_fails then
  vim.uv.fs_rename = function() return nil, 'permission denied' end
elseif options.winner_at_publish then
  local rename = vim.uv.fs_rename
  vim.uv.fs_rename = function(from, to)
    ready(to, 'winner')
    return rename(from, to)
  end
end
vim.v = setmetatable({ shell_error = 0 }, { __index = vim.v })
vim.fn.system = function(args)
  calls[#calls + 1] = args
  vim.fn.writefile({ vim.json.encode(calls) }, %q)
  if options.clone_incomplete then
    vim.fn.mkdir(args[#args], 'p')
  else
    ready(args[#args], 'ours')
  end
  if options.winner_during_clone then ready(install, 'winner') end
  if options.empty_target_during_clone then vim.fn.mkdir(install, 'p') end
  vim.v.shell_error = options.clone_fails and 1 or 0
  return options.clone_fails and 'clone failed' or ''
end
dofile(%q)()
]=]):format(vim.json.encode(options or {}), dir .. "/install.json", dir .. "/calls.json", helper)
  vim.fn.writefile(vim.split(script, "\n", { plain = true }), dir .. "/run.lua")
  local result = vim
    .system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", dir .. "/run.lua" }, {
      text = true,
      env = {
        XDG_CONFIG_HOME = dir .. "/config",
        XDG_DATA_HOME = dir .. "/data",
        XDG_STATE_HOME = dir .. "/state",
        XDG_CACHE_HOME = dir .. "/cache",
        NVIM_LOG_FILE = dir .. "/nvim.log",
        NVIM_APPNAME = options and options.app_name or "nvim",
      },
    })
    :wait(10000)
  local install = vim.json.decode(vim.fn.readfile(dir .. "/install.json")[1])
  local owner = install .. "/owner"
  return {
    code = result.code,
    stderr = result.stderr,
    owner = vim.fn.filereadable(owner) == 1 and vim.fn.readfile(owner)[1] or "",
    exists = vim.fn.isdirectory(install) == 1,
    partials = vim.fn.glob(install .. ".tmp-*", false, true),
    calls = vim.fn.filereadable(dir .. "/calls.json") == 1 and vim.json.decode(
      vim.fn.readfile(dir .. "/calls.json")[1]
    ) or {},
  }
end

describe("test dependency publication", function()
  after_each(function()
    for _, dir in ipairs(dirs) do
      vim.fn.delete(dir, "rf")
    end
    dirs = {}
  end)

  it("reuses a complete cached dependency without Git", function()
    local result = bootstrap({ existing = true })
    assert.equals(0, result.code, result.stderr)
    assert.equals("existing", result.owner)
    assert.equals(0, #result.calls)
  end)

  it("publishes a complete clone and cleans its staging path", function()
    local result = bootstrap()
    assert.equals(0, result.code, result.stderr)
    assert.equals("ours", result.owner)
    assert.equals(1, #result.calls)
    assert.same({}, result.partials)
  end)

  it("uses the child editor's application-specific cache path", function()
    local result = bootstrap({ app_name = "audit-other-config" })
    assert.equals(0, result.code, result.stderr)
    assert.equals("ours", result.owner)
    assert.equals(1, #result.calls)
    assert.same({}, result.partials)
  end)

  it("exits promptly and preserves an incomplete pre-existing cache", function()
    local result = bootstrap({ incomplete = true })
    assert.equals(1, result.code)
    assert.matches("incomplete Plenary cache", result.stderr)
    assert.is_true(result.exists)
    assert.equals(0, #result.calls)
  end)

  it("cleans only its failed clone", function()
    local result = bootstrap({ clone_fails = true })
    assert.equals(1, result.code)
    assert.is_false(result.exists)
    assert.same({}, result.partials)
  end)

  it("rejects a cache missing the runtime command definition", function()
    local result = bootstrap({ missing_runtime = true })
    assert.equals(1, result.code)
    assert.matches("incomplete Plenary cache", result.stderr)
    assert.equals("existing", result.owner)
    assert.equals(0, #result.calls)
  end)

  it("reuses another runner's completed clone after its own Git failure", function()
    local result = bootstrap({ clone_fails = true, winner_during_clone = true })
    assert.equals(0, result.code, result.stderr)
    assert.equals("winner", result.owner)
    assert.same({}, result.partials)
  end)

  it("rejects a successful but incomplete clone", function()
    local result = bootstrap({ clone_incomplete = true })
    assert.equals(1, result.code)
    assert.is_false(result.exists)
    assert.same({}, result.partials)
  end)

  it("keeps a winner published between checking and renaming", function()
    local result = bootstrap({ winner_at_publish = true })
    assert.equals(0, result.code, result.stderr)
    assert.equals("winner", result.owner)
    assert.same({}, result.partials)
  end)

  it("preserves a concurrently created incomplete target", function()
    local result = bootstrap({ empty_target_during_clone = true })
    assert.equals(1, result.code)
    assert.is_true(result.exists)
    assert.equals("", result.owner)
    assert.same({}, result.partials)
  end)

  it("fails clearly and cleans staging if publication is denied", function()
    local result = bootstrap({ publish_fails = true })
    assert.equals(1, result.code)
    assert.matches("permission denied", result.stderr)
    assert.is_false(result.exists)
    assert.same({}, result.partials)
  end)
end)
