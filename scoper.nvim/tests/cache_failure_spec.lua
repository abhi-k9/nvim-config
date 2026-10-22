local State = require("scoper.state")
local Lsp = require("scoper.lsp")
local Path = require("scoper.path")

describe("Scoper filter cache failures", function()
  local root, previous, env, notify, warnings
  before_each(function()
    -- clangd commands deliberately use normalized forward-slash paths on
    -- Windows too; tempname() uses the native separators and drive case.
    root, previous = Path.normalize(vim.fn.tempname()), vim.fn.getcwd()
    env = { vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME }
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = root .. "/data", root .. "/cache"
    vim.fn.mkdir(root .. "/src", "p")
    vim.fn.mkdir(vim.fn.stdpath("cache"), "p")
    vim.fn.writefile({ "blocking file" }, vim.fn.stdpath("cache") .. "/scoper")
    vim.fn.writefile({
      vim.json.encode({ { file = root .. "/src/a.c", directory = root, command = "cc -c a.c" } }),
    }, root .. "/compile_commands.json")
    vim.fn.chdir(root)
    State.load({ quiet = true })
    State.add_paths("src")
    State.toggle(true)
    notify, warnings = vim.notify, {}
    vim.notify = function(message)
      warnings[#warnings + 1] = message
    end
  end)

  after_each(function()
    vim.notify = notify
    vim.fn.chdir(previous)
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = env[1], env[2]
    vim.fn.delete(root, "rf")
  end)

  it("returns a usable unfiltered command when cache creation fails", function()
    local ok, cmd, info = pcall(Lsp.clangd_cmd)
    assert.is_true(ok, cmd)
    assert.equals("clangd", cmd[1])
    assert.equals("--compile-commands-dir=" .. root, cmd[2])
    assert.matches("cannot create filter cache", info)
    assert.equals("blocking file", vim.fn.readfile(vim.fn.stdpath("cache") .. "/scoper")[1])
  end)

  it("completes an asynchronous request once without spawning a doomed worker", function()
    local calls, result = 0
    local worker = Lsp._worker_cmd
    Lsp._worker_cmd = function()
      error("worker must not start when its cache directory is blocked")
    end
    local ok, err = pcall(Lsp._filter_async, function(dir, info)
      calls, result = calls + 1, { dir = dir, info = info }
    end)
    Lsp._worker_cmd = worker
    assert.is_true(ok, err)
    assert.equals(1, calls)
    assert.is_nil(result.dir)
    assert.matches("cannot create filter cache", result.info)
    assert.matches("cannot create filter cache", warnings[#warnings])
  end)
end)
