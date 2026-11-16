describe("optional Scoper explorer decoration", function()
  local Adapter, scoper, manager, opts, enabled, captures, redraws, original, root, decorations
  local function node(kind, path, depth)
    return {
      type = kind,
      get_id = function()
        return path
      end,
      get_depth = function()
        return depth or 2
      end,
    }
  end
  local function render(kind, path, tree, depth)
    return opts.filesystem.components.name({}, node(kind, path, depth), { path = tree or root })
  end
  before_each(function()
    Adapter = require("config.scoper_explorer")
    scoper, manager = package.loaded.scoper, package.loaded["neo-tree.sources.manager"]
    root = vim.fs.normalize(vim.fn.getcwd())
    enabled, captures, redraws = true, 0, 0
    decorations = { text = "name", highlight = "GitColour", extra = "kept" }
    original = function()
      return decorations
    end
    opts = { filesystem = { components = { name = original } } }
    package.loaded.scoper = {
      snapshot = function()
        return { enabled = enabled, root = root, scope = "cpp" }
      end,
      matcher = function()
        captures = captures + 1
        return function(path)
          return path:match("%.cpp$") ~= nil
        end
      end,
    }
    package.loaded["neo-tree.sources.manager"] = {
      redraw = function(source)
        assert.equals("filesystem", source)
        redraws = redraws + 1
      end,
    }
    Adapter.setup(opts, { enabled = true, debounce_ms = 1 })
  end)
  after_each(function()
    Adapter.setup(opts, false)
    package.loaded.scoper, package.loaded["neo-tree.sources.manager"] = scoper, manager
  end)

  it("dims and marks only out-of-scope files without changing base components", function()
    local result = render("file", root .. "/main.h")
    assert.equals("- name", result.text)
    assert.equals("NeoTreeDimText", result.highlight)
    assert.equals("kept", result.extra)
    assert.equals("name", decorations.text)
    assert.equals(decorations, render("file", root .. "/main.cpp"))
    assert.equals(decorations, render("directory", root .. "/src"))
    assert.equals(1, captures)
    assert.equals("name [scope: cpp]", render("directory", root, root, 1).text)
  end)

  it("leaves unrelated roots alone, including matching path prefixes", function()
    assert.equals(decorations, render("file", root .. "-other/main.h", root .. "-other"))
    assert.equals("- name", render("file", root .. "/src/main.h", root .. "/src").text)
  end)

  it("invalidates disabled scope state and coalesces redraws", function()
    render("file", root .. "/main.h")
    enabled = false
    for _ = 1, 3 do
      vim.api.nvim_exec_autocmds(
        "User",
        { pattern = "ScoperChanged", group = "config_scoper_explorer" }
      )
    end
    assert.equals(decorations, render("file", root .. "/main.h"))
    assert.is_true(vim.wait(1000, function()
      return redraws == 1
    end))
    assert.equals(1, captures)
  end)

  it("does nothing when Scoper or its supported APIs are missing", function()
    for _, replacement in ipairs({
      false,
      {},
      {
        snapshot = function()
          error("unavailable")
        end,
        matcher = function()
          error("unavailable")
        end,
      },
    }) do
      package.loaded.scoper = replacement
      assert.equals(decorations, render("file", root .. "/main.h"))
    end
  end)

  it("does not load a missing explorer manager during scope changes", function()
    package.loaded["neo-tree.sources.manager"] = nil
    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "ScoperChanged", group = "config_scoper_explorer" }
    )
    vim.wait(20)
    assert.is_nil(package.loaded["neo-tree.sources.manager"])
    assert.equals(0, redraws)
  end)

  it("compares Windows roots with normalized separators and case", function()
    local has = vim.fn.has
    vim.fn.has = function(feature)
      return feature == "win32" and 1 or has(feature)
    end
    root = [[C:\Work\Project]]
    local ok, err = pcall(function()
      assert.equals("- name", render("file", "c:/work/project/src/a.h", "c:/work/project/src").text)
      assert.equals(decorations, render("file", "c:/work/project2/a.h", "c:/work/project2"))
    end)
    vim.fn.has = has
    assert.is_true(ok, err)
  end)

  it("does not interpret literal root characters as environment variables", function()
    local value = vim.env.NVIM_SCOPER_MARKER_TEST
    vim.env.NVIM_SCOPER_MARKER_TEST = "expanded"
    root = root .. "/$NVIM_SCOPER_MARKER_TEST"
    local ok, err = pcall(function()
      local other = root:gsub("%$NVIM_SCOPER_MARKER_TEST", "expanded")
      assert.equals(decorations, render("file", other .. "/a.h", other))
      assert.equals("- name", render("file", root .. "/a.h").text)
    end)
    vim.env.NVIM_SCOPER_MARKER_TEST = value
    assert.is_true(ok, err)
  end)

  it("supports custom or absent markers without overriding normal colours", function()
    Adapter.setup(opts, { enabled = true, marker = "", dim = false, show_scope = false })
    assert.same(decorations, render("file", root .. "/main.h"))
    assert.equals(decorations, render("directory", root, root, 1))
    Adapter.setup(opts, { enabled = true, marker = "out", highlight = "Comment" })
    local result = render("file", root .. "/main.h")
    assert.equals("out name", result.text)
    assert.equals("Comment", result.highlight)
  end)

  it("removes wrappers and pending redraws when disabled or reconfigured", function()
    Adapter.setup(opts, true)
    assert.equals("- name", render("file", root .. "/main.h").text)
    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "ScoperChanged", group = "config_scoper_explorer" }
    )
    Adapter.setup(opts, false)
    assert.equals(original, opts.filesystem.components.name)
    vim.wait(120)
    assert.equals(0, redraws)
  end)
end)
