local diagnostics = require("config.diagnostics")

describe("diagnostic dump log I/O", function()
  local dir, log_path, log_name, notify, stdpath, messages
  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    log_path = dir .. "/lsp.log"
    log_name, notify, stdpath = vim.lsp.log.get_filename, vim.notify, vim.fn.stdpath
    vim.lsp.log.get_filename = function()
      return log_path
    end
    messages = {}
    vim.notify = function(message, level)
      messages[#messages + 1] = { message, level }
    end
    vim.fn.stdpath = function(kind)
      if kind == "log" then return dir .. "/dumps" end
      return stdpath(kind)
    end
  end)
  after_each(function()
    vim.lsp.log.get_filename, vim.notify, vim.fn.stdpath = log_name, notify, stdpath
    vim.fn.delete(dir, "rf")
  end)

  it("retains a bounded tail when a log line exceeds the tail limit", function()
    vim.fn.writefile({ string.rep("A", 128 * 1024) }, log_path, "b")
    local dump = diagnostics.dump()
    local contents = table.concat(vim.fn.readfile(dump), "\n")
    local body = contents:match("showing last 64 KiB of 128 KiB%)\n\n(A+)")
    assert.is_not_nil(body)
    assert.are.equal(64 * 1024, #body)
  end)

  it("skips nonregular log paths without blocking", function()
    if vim.fn.has("win32") == 1 or vim.fn.executable("mkfifo") == 0 then return end
    vim.fn.system({ "mkfifo", log_path })
    assert.are.equal(0, vim.v.shell_error)
    local source = debug.getinfo(diagnostics.dump, "S").source:sub(2)
    local script = dir .. "/fifo.lua"
    vim.fn.writefile({
      "vim.opt.rtp:prepend(" .. vim.inspect(vim.fn.getcwd()) .. ")",
      "vim.lsp.log.get_filename = function() return " .. vim.inspect(log_path) .. " end",
      "assert(loadfile(" .. vim.inspect(source) .. "))().dump()",
    }, script)
    -- wait(timeout) sends SIGKILL on expiration, so a regression fails
    -- without leaving a child stuck in the FIFO's blocking open().
    local result = vim
      .system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", script }, { text = true })
      :wait(1000)
    assert.are.equal(0, result.code, result.stderr)
  end)

  it("reports an actual directory-creation failure instead of throwing", function()
    vim.fn.writefile({ "blocking file" }, dir .. "/dumps")
    local ok, result = pcall(diagnostics.dump)
    assert.is_true(ok)
    assert.is_nil(result)
    assert.are.equal(vim.log.levels.ERROR, messages[#messages][2])
    assert.is_truthy(messages[#messages][1]:find("FAILED", 1, true))
  end)

  it("reports a write exception instead of throwing", function()
    local writefile = vim.fn.writefile
    vim.fn.writefile = function()
      error("E482: injected disk failure")
    end
    local ok, result = pcall(diagnostics.dump)
    vim.fn.writefile = writefile
    assert.is_true(ok)
    assert.is_nil(result)
    assert.are.equal(vim.log.levels.ERROR, messages[#messages][2])
    assert.is_truthy(messages[#messages][1]:find("FAILED", 1, true))
  end)

  it("uses copied public Scoper status without reading private integration fields", function()
    local scoper, integration = package.loaded.scoper, package.loaded["scoper.lsp"]
    package.loaded.scoper = {
      snapshot = function()
        return {
          root = "/public/project",
          scope = "headers",
          enabled = true,
          definition = { include = { "include" }, exclude = {} },
        }
      end,
    }
    package.loaded["scoper.lsp"] = setmetatable({
      status = function()
        return { mode = "selected", selection = { path = "/external/compile_commands.json" } }
      end,
    }, {
      __index = function(_, name)
        error("Private field accessed: " .. name)
      end,
    })
    local ok, result = pcall(function()
      local dump = diagnostics.dump()
      local contents = table.concat(vim.fn.readfile(dump), "\n")
      assert.is_truthy(contents:find("/public/project", 1, true))
      assert.is_truthy(contents:find("/external/compile_commands.json", 1, true))
      assert.is_truthy(contents:find('mode = "selected"', 1, true))
      assert.is_nil(contents:find("Private field accessed", 1, true))
    end)
    package.loaded.scoper, package.loaded["scoper.lsp"] = scoper, integration
    assert.is_true(ok, tostring(result))
  end)
end)
