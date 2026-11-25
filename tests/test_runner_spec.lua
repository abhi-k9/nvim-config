local runner = vim.fn.getcwd() .. "/scoper.nvim/tests/run.lua"

describe("headless test runner failures", function()
  local dir
  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/tests", "p")
    vim.fn.writefile({}, dir .. "/tests/example_spec.lua")
  end)
  after_each(function()
    vim.fn.delete(dir, "rf")
  end)

  local function run(init, target)
    vim.fn.writefile(init, dir .. "/tests/minimal_init.lua")
    local command = { vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", runner }
    if target then command[#command + 1] = target end
    return vim.system(command, { cwd = dir, text = true }):wait(3000)
  end

  it("exits promptly when the test initialization fails", function()
    local result = run({ 'error("injected init failure")' })
    assert.equals(1, result.code, result.stderr)
    assert.matches("injected init failure", result.stderr)
  end)

  it("exits promptly when starting the test harness fails", function()
    local result = run({
      'package.preload["plenary.test_harness"] = function() error("injected harness failure") end',
    })
    assert.equals(1, result.code, result.stderr)
    assert.matches("injected harness failure", result.stderr)
  end)

  it("rejects missing targets and directories without specs", function()
    vim.fn.mkdir(dir .. "/empty", "p")
    for _, target in ipairs({ "missing", "empty" }) do
      local result = run({}, target)
      assert.equals(1, result.code)
      assert.is_truthy(result.stderr:find(target, 1, true))
    end
  end)

  it("runs a selected file with the child initializer and propagates failure", function()
    local target = "tests/selected % spec_spec.lua"
    vim.fn.writefile({}, dir .. "/" .. target)
    local result = run({
      'package.preload["plenary.busted"] = function() return { run = function(path)',
      'assert(vim.fs.basename(path) == "selected % spec_spec.lua")',
      'io.stderr:write("selected fixture failed\\n")',
      'vim.cmd("cquit 1")',
      "end } end",
    }, target)
    assert.equals(1, result.code)
    assert.matches("selected fixture failed", result.stderr)
  end)

  it("forwards a test directory as data and selects the cwd's initializer", function()
    vim.fn.mkdir(dir .. "/specs with spaces", "p")
    vim.fn.writefile({}, dir .. "/specs with spaces/example_spec.lua")
    local result = run({
      'package.preload["plenary.test_harness"] = function() return { test_directory = function(target, opts)',
      'assert(target == "specs with spaces")',
      'assert(opts.minimal_init == "tests/minimal_init.lua")',
      "assert(opts.sequential == true)",
      'assert(vim.fs.normalize(vim.fn.stdpath("data")):find("/config-tests/data/", 1, true))',
      'io.stdout:write("correct runner target\\n")',
      "end } end",
    }, "specs with spaces")
    assert.equals(0, result.code, result.stderr)
    assert.matches("correct runner target", result.stdout)
  end)
end)
