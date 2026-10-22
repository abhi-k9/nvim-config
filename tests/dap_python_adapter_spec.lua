describe("Python debugger transport", function()
  local dap

  before_each(function()
    require("lazy.core.loader").load("nvim-dap", { cmd = "spec" })
    dap = require("dap")
  end)

  local function resolve(config)
    local resolved, calls
    calls = 0
    dap.adapters.python(function(adapter)
      calls = calls + 1
      resolved = adapter
    end, config)
    assert.equals(1, calls)
    return resolved
  end

  it("connects socket attach to the adapter already owned by the target", function()
    local config = {
      request = "attach",
      connect = { host = "192.0.2.1", port = 5678 },
    }
    local before = vim.deepcopy(config)
    assert.same({ type = "server", host = "192.0.2.1", port = 5678 }, resolve(config))
    assert.same(before, config)
  end)

  it("accepts a legacy attach port and defaults to loopback", function()
    assert.same(
      { type = "server", host = "127.0.0.1", port = 5678 },
      resolve({
        request = "attach",
        port = 5678,
      })
    )
  end)

  it("launches the Mason stdio adapter for new debuggees", function()
    local adapter = resolve({ request = "launch", program = "program.py" })
    assert.equals("executable", adapter.type)
    assert.equals(
      vim.fn.has("win32") == 1 and "debugpy-adapter.cmd" or "debugpy-adapter",
      vim.fs.basename(adapter.command)
    )
  end)

  it("retains stdio for PID attach and reverse connections", function()
    for _, config in ipairs({
      { request = "attach", processId = 1234 },
      { request = "attach", listen = { host = "127.0.0.1", port = 5678 } },
    }) do
      local adapter = resolve(config)
      assert.equals("executable", adapter.type)
      assert.is_string(adapter.command)
    end
  end)
end)
