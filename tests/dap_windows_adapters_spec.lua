describe("Windows debugger executable selection", function()
  local original_dap, original_utils, original_settings, has, stdpath, exepath
  local root, dap, windows

  before_each(function()
    original_dap, original_utils, original_settings =
      package.loaded.dap, package.loaded["dap.utils"], package.loaded["mason.settings"]
    has, stdpath, exepath = vim.fn.has, vim.fn.stdpath, vim.fn.exepath
    root, windows = vim.fn.tempname() .. " DAP space & 100%", true
    vim.fn.has = function(feature)
      if feature == "win32" then return windows and 1 or 0 end
      return has(feature)
    end
    vim.fn.stdpath = function(kind)
      return kind == "data" and root or stdpath(kind)
    end
    vim.fn.exepath = function(bin)
      return (bin == "node" or bin == "node.exe") and "C:/Program Files/Node/node.exe"
        or exepath(bin)
    end
    dap = { adapters = {}, configurations = {}, ABORT = {}, pause = function() end }
    package.loaded.dap = dap
    package.loaded["dap.utils"] = { pick_process = function() end }
    package.loaded["mason.settings"] = nil
  end)

  after_each(function()
    package.loaded.dap, package.loaded["dap.utils"], package.loaded["mason.settings"] =
      original_dap, original_utils, original_settings
    vim.fn.has, vim.fn.stdpath, vim.fn.exepath = has, stdpath, exepath
  end)

  local function setup()
    require("config.dap").setup()
    return vim.fs.joinpath(root, "mason", "packages")
  end

  it("spawns native C++ adapter images without a command interpreter", function()
    local packages = setup()
    assert.equals(
      vim.fs.joinpath(packages, "cpptools", "extension", "debugAdapters", "bin", "OpenDebugAD7.exe"),
      dap.adapters.cppdbg.command
    )
    assert.equals(
      vim.fs.joinpath(packages, "codelldb", "extension", "adapter", "codelldb.exe"),
      dap.adapters.codelldb.executable.command
    )
    assert.is_false(dap.adapters.cppdbg.options.detached)
    assert.is_false(dap.adapters.codelldb.executable.detached)
    assert.same({ "--port", "${port}" }, dap.adapters.codelldb.executable.args)
  end)

  it("runs debugpy with its own environment interpreter", function()
    local packages = setup()
    local resolved
    dap.adapters.python(function(adapter)
      resolved = adapter
    end, { request = "launch" })
    assert.equals(
      vim.fs.joinpath(packages, "debugpy", "venv", "Scripts", "python.exe"),
      resolved.command
    )
    assert.same({ "-m", "debugpy.adapter" }, resolved.args)
  end)

  it("passes the Bash adapter's literal script path as a Node argument", function()
    local packages = setup()
    assert.equals("C:/Program Files/Node/node.exe", dap.adapters.bashdb.command)
    assert.same(
      { vim.fs.joinpath(packages, "bash-debug-adapter", "extension", "out", "bashDebug.js") },
      dap.adapters.bashdb.args
    )
  end)

  it("honors Mason's configured installation root", function()
    local custom = vim.fs.joinpath(root, "custom Mason")
    package.loaded["mason.settings"] = { current = { install_root_dir = custom } }
    setup()
    assert.equals(
      vim.fs.joinpath(custom, "packages", "codelldb", "extension", "adapter", "codelldb.exe"),
      dap.adapters.codelldb.executable.command
    )
  end)

  it("keeps Unix entrypoints unchanged", function()
    windows = false
    setup()
    assert.equals(
      vim.fs.joinpath(root, "mason", "bin", "OpenDebugAD7"),
      dap.adapters.cppdbg.command
    )
    assert.equals(
      vim.fs.joinpath(root, "mason", "bin", "codelldb"),
      dap.adapters.codelldb.executable.command
    )
    assert.equals(
      vim.fs.joinpath(root, "mason", "bin", "bash-debug-adapter"),
      dap.adapters.bashdb.command
    )
    assert.is_true(dap.adapters.cppdbg.options.detached)
  end)
end)
