local health = require("config.health")

describe("health state directory validation", function()
  local dir, directory, undodir, undofile, executable, handlers, results
  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    directory, undodir, undofile = vim.o.directory, vim.o.undodir, vim.o.undofile
    executable = vim.fn.executable
    vim.fn.executable = function()
      return 0
    end
    vim.o.undofile = false
    results, handlers = {}, {}
    for _, level in ipairs({ "start", "info", "ok", "warn", "error" }) do
      handlers[level] = vim.health[level]
      vim.health[level] = function(message)
        if message:find("Swap directory", 1, true) then
          results[#results + 1] = { level = level, message = message }
        end
      end
    end
  end)
  after_each(function()
    vim.o.directory, vim.o.undodir, vim.o.undofile = directory, undodir, undofile
    vim.fn.executable = executable
    for level, handler in pairs(handlers) do
      vim.health[level] = handler
    end
    vim.fn.delete(dir, "rf")
  end)

  local function check_path(path)
    vim.o.directory = path
    health.check()
    assert.are.equal(1, #results)
    return results[1]
  end

  it("rejects an existing regular file", function()
    vim.fn.writefile({ "blocking file" }, dir .. "/file")
    assert.are.equal("error", check_path(dir .. "/file").level)
  end)

  it("rejects a missing directory below a regular file", function()
    vim.fn.writefile({ "blocking file" }, dir .. "/file")
    assert.are.equal("error", check_path(dir .. "/file/child").level)
  end)

  it("recognizes a filesystem root as an existing directory", function()
    local root = vim.fs.root(dir, function()
      return false
    end) or (vim.fn.has("win32") == 1 and dir:match("^%a:[/\\]") or "/")
    local result = check_path(root)
    assert.is_nil(result.message:find("not set", 1, true))
    assert.is_nil(result.message:find("not created yet", 1, true))
  end)

  it("decodes escaped commas in native path options", function()
    local path = dir .. "/comma,dir"
    vim.fn.mkdir(path, "p")
    local result = check_path(path:gsub(",", "\\,") .. "//")
    assert.are.equal("ok", result.level)
    assert.is_truthy(result.message:find("writable (" .. path .. ")", 1, true))
  end)

  it("accepts missing directories below a writable directory", function()
    local result = check_path(dir .. "/future/deeper//")
    assert.are.equal("ok", result.level)
    assert.is_truthy(result.message:find("not created yet", 1, true))
  end)
end)
