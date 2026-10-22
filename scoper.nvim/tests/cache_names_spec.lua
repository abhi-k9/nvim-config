local State = require("scoper.state")
local LSP = require("scoper.lsp")

describe("portable scope cache components", function()
  local root, previous, env
  before_each(function()
    root, previous = vim.fn.tempname(), vim.fn.getcwd()
    env = { vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME }
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = root .. "/data", root .. "/cache"
    vim.fn.mkdir(root .. "/src", "p")
    vim.fn.writefile(
      { vim.json.encode({ { directory = root, file = "src/a.c", command = "cc -c src/a.c" } }) },
      root .. "/compile_commands.json"
    )
    vim.cmd.cd(root)
    State.load({ quiet = true })
  end)

  after_each(function()
    vim.cmd.cd(previous)
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = env[1], env[2]
    vim.fn.delete(root, "rf")
  end)

  local function cache_for(name)
    assert.is_true(State.new_scope(name))
    State.add_paths("src")
    State.set_enabled(true)
    local directory, info = LSP.write_filtered_compile_commands()
    assert.is_not_nil(directory, info)
    return vim.fs.basename(vim.fs.dirname(directory)), directory
  end

  it("encodes Windows device names and their extension forms without renaming scopes", function()
    local seen = {}
    for _, name in ipairs({
      "CON",
      "con",
      "AUX.txt",
      "NUL",
      "PRN",
      "COM1",
      "com9.db",
      "LPT1",
      "LPT9.c",
    }) do
      local component, directory = cache_for(name)
      assert.matches("^scope%-[0-9a-f]+$", component)
      assert.is_nil(seen[component])
      seen[component] = true
      assert.equals(name, State.active_name())
      assert.equals(1, vim.fn.filereadable(directory .. "/compile_commands.json"))
    end
    State.load({ quiet = true })
    assert.is_not_nil(State.scope("CON"))
    assert.is_not_nil(State.scope("AUX.txt"))
  end)

  it("encodes trailing dots without dropping the saved logical name", function()
    local component = cache_for("frontend.")
    assert.matches("^scope%-", component)
    State.load({ quiet = true })
    assert.equals("frontend.", State.active_name())
  end)

  it("can filter a scope whose logical name exceeds the filesystem component limit", function()
    local name = string.rep("a", 300)
    local component = cache_for(name)
    assert.is_true(#component <= 255)
    State.load({ quiet = true })
    assert.equals(name, State.active_name())
  end)

  it("retains existing cache components for ordinary names and near-device names", function()
    for _, name in ipairs({ "frontend", "CONSOLE", "COM10", "LPT0", ".hidden" }) do
      local component = cache_for(name)
      assert.equals(name, component)
    end
  end)
end)
