-- Native Windows regression for nvim-dap's uv.spawn contract. No plugins or
-- downloaded adapters are needed. Native executable fixtures exercise the two
-- C++ adapter paths; actual Python/Node run stub adapter modules with literal argv.
assert(vim.fn.has("win32") == 1, "This regression requires native Windows")
vim.opt.rtp:prepend(vim.fn.getcwd())

local uv = vim.uv
local base = vim.fn.tempname() .. " DAP space & 100% é"
local mason = vim.fs.joinpath(base, "custom Mason")
local packages = vim.fs.joinpath(mason, "packages")
vim.fn.mkdir(packages, "p")

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines, path) == 0, "Cannot write " .. path)
end

local function spawn(command, args)
  local finished, code, handle
  local err
  handle, err = uv.spawn(command, { args = args, detached = false }, function(exit)
    code, finished = exit, true
    if not handle:is_closing() then handle:close() end
  end)
  assert(handle, ("uv.spawn(%s) failed: %s"):format(command, tostring(err)))
  if not vim.wait(15000, function()
    return finished
  end, 10) then
    handle:kill("sigkill")
    vim.wait(2000, function()
      return finished
    end, 10)
    error("Timed out spawning " .. command)
  end
  return code
end

local function append(prefix, suffix)
  local result = vim.deepcopy(prefix)
  vim.list_extend(result, suffix)
  return result
end

local ok, err = xpcall(function()
  -- A valid .cmd shim must never be sent directly to uv.spawn. Place one at
  -- each old entrypoint so the old configuration fails for the actual reason.
  for _, name in ipairs({ "OpenDebugAD7", "codelldb", "debugpy-adapter", "bash-debug-adapter" }) do
    write(vim.fs.joinpath(mason, "bin", name .. ".cmd"), { "@echo off", "exit /b 17" })
  end
  local native = (vim.env.SystemRoot or "C:\\Windows") .. "\\System32\\cmd.exe"
  for _, relative in ipairs({
    { "cpptools", "extension", "debugAdapters", "bin", "OpenDebugAD7.exe" },
    { "codelldb", "extension", "adapter", "codelldb.exe" },
  }) do
    local destination = vim.fs.joinpath(packages, unpack(relative))
    vim.fn.mkdir(vim.fs.dirname(destination), "p")
    assert(uv.fs_copyfile(native, destination))
  end

  local python = vim.fn.exepath("python.exe")
  assert(python ~= "", "Native Python with venv is required for this regression")
  local venv = vim.fs.joinpath(packages, "debugpy", "venv")
  local result = vim
    .system({ python, "-m", "venv", "--without-pip", venv }, { text = true })
    :wait(30000)
  assert(result.code == 0, "Cannot prepare Python venv: " .. (result.stderr or ""))
  local module = vim.fs.joinpath(venv, "Lib", "site-packages", "debugpy")
  write(vim.fs.joinpath(module, "__init__.py"), {})
  write(vim.fs.joinpath(module, "adapter", "__main__.py"), {
    "import json, os, sys",
    "with open(os.environ['NVIM_DAP_SPAWN_RESULT'], 'w', encoding='utf-8') as stream:",
    "    json.dump(sys.argv[1:], stream)",
  })
  write(vim.fs.joinpath(packages, "bash-debug-adapter", "extension", "out", "bashDebug.js"), {
    "require('fs').writeFileSync(process.env.NVIM_DAP_SPAWN_RESULT, JSON.stringify(process.argv.slice(2)));",
  })

  local dap = { adapters = {}, configurations = {}, ABORT = {}, pause = function() end }
  package.loaded.dap = dap
  package.loaded["dap.utils"] = { pick_process = function() end }
  package.loaded["mason.settings"] = { current = { install_root_dir = mason } }
  require("config.dap").setup()

  -- These are direct native-image launches, without cmd /c around the adapter.
  assert(spawn(dap.adapters.cppdbg.command, { "/d", "/c", "exit", "17" }) == 17)
  assert(spawn(dap.adapters.codelldb.executable.command, { "/d", "/c", "exit", "17" }) == 17)

  local literal =
    { "with spaces", "literal&argument", "%DO_NOT_EXPAND%", 'a"quoted"argument', "é漢字" }
  local target = vim.fs.joinpath(base, "argv.json")
  vim.env.NVIM_DAP_SPAWN_RESULT = target
  local adapter
  dap.adapters.python(function(value)
    adapter = value
  end, { request = "launch" })
  assert(spawn(adapter.command, append(adapter.args, literal)) == 0)
  assert(
    vim.deep_equal(literal, vim.json.decode(table.concat(vim.fn.readfile(target), "\n"))),
    "Python argv changed"
  )
  assert(vim.fn.exepath("node.exe") ~= "", "Native Node.js is required for this regression")
  assert(spawn(dap.adapters.bashdb.command, append(dap.adapters.bashdb.args, literal)) == 0)
  assert(
    vim.deep_equal(literal, vim.json.decode(table.concat(vim.fn.readfile(target), "\n"))),
    "Node argv changed"
  )
end, debug.traceback)

vim.fn.delete(base, "rf")
assert(ok, err)
io.stdout:write(
  "Windows DAP native spawning passed: cppdbg, codelldb, debugpy, bashdb; literal argv preserved\n"
)
