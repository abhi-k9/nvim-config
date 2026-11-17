describe("optional Scoper explorer decoration", function()
  local Adapter, scoper, manager, opts, enabled, captures, redraws, original, root, decorations
  local previous_adapter, previous_renderer, renderer, refreshes
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
    previous_adapter = package.loaded["config.scoper_explorer"]
    package.loaded["config.scoper_explorer"] = nil
    Adapter = require("config.scoper_explorer")
    scoper, manager = package.loaded.scoper, package.loaded["neo-tree.sources.manager"]
    previous_renderer = package.loaded["neo-tree.ui.renderer"]
    renderer = {
      show_nodes = function(items)
        return items
      end,
    }
    package.loaded["neo-tree.ui.renderer"] = renderer
    refreshes = 0
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
      refresh = function(source)
        assert.equals("filesystem", source)
        refreshes = refreshes + 1
      end,
      redraw = function(source)
        assert.equals("filesystem", source)
        redraws = redraws + 1
      end,
    }
    Adapter.setup(opts, { enabled = true, debounce_ms = 1 })
  end)
  after_each(function()
    Adapter.setup(opts, false)
    package.loaded["config.scoper_explorer"] = previous_adapter
    package.loaded["neo-tree.ui.renderer"] = previous_renderer
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

  it("marks only directories proven excluded by the optional public predicate", function()
    package.loaded.scoper.excluded_directory_matcher = function()
      return function(path)
        return path == root .. "/vendor"
      end
    end
    assert.equals("- name", render("directory", root .. "/vendor").text)
    assert.equals(decorations, render("directory", root .. "/src"))
  end)

  it("keeps scope labels and exclusion markers together on a rerooted directory", function()
    package.loaded.scoper.excluded_directory_matcher = function()
      return function(path)
        return path == root .. "/vendor"
      end
    end
    local result = render("directory", root .. "/vendor", root .. "/vendor", 1)
    assert.equals("- name [scope: cpp]", result.text)
    assert.equals("NeoTreeDimText", result.highlight)
  end)

  it("reconfigures defaults until an explicit runtime toggle takes ownership", function()
    Adapter.configure(opts, false)
    assert.equals(decorations, render("file", root .. "/a.h"))
    Adapter.configure(opts, true)
    assert.equals("- name", render("file", root .. "/a.h").text)
    Adapter.toggle()
    Adapter.configure(opts, true)
    assert.equals(decorations, render("file", root .. "/a.h"))
  end)

  it("does not redraw disabled markers when a pending scope update arrives", function()
    Adapter.configure(opts, true)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "ScoperChanged",
      group = "config_scoper_explorer",
    })
    Adapter.toggle()
    local count = redraws
    vim.wait(150)
    assert.equals(count, redraws)
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
  local function items()
    return {
      {
        type = "directory",
        path = root,
        children = {
          { type = "file", path = root .. "/main.cpp" },
          { type = "file", path = root .. "/main.h" },
          { type = "directory", path = root .. "/src" },
          { type = "directory", path = root .. "/vendor" },
        },
      },
    }
  end
  local function filtered(source, path, entries)
    return renderer.show_nodes(
      entries or items(),
      { name = source or "filesystem", path = path or root }
    )
  end

  it("filters files and definite subtrees without mutating scan items", function()
    package.loaded.scoper.excluded_directory_matcher = function()
      return function(path)
        return path == root .. "/vendor"
      end
    end
    Adapter.configure(opts, false, true)
    local entries = items()
    local before = vim.deepcopy(entries)
    local result = filtered(nil, nil, entries)
    assert.equals(2, #result[1].children)
    assert.equals(root .. "/main.cpp", result[1].children[1].path)
    assert.equals(root .. "/src", result[1].children[2].path)
    assert.same(before, entries)
    assert.equals(decorations, render("file", root .. "/main.h"))
    assert.equals(1, captures)
  end)

  it("keeps the tree root and flattens included children of excluded nesting parents", function()
    package.loaded.scoper.excluded_directory_matcher = function()
      return function()
        return true
      end
    end
    Adapter.configure(opts, false, true)
    local entries = items()
    entries[1].children = {
      {
        type = "file",
        path = root .. "/main.h",
        children = {
          { type = "file", path = root .. "/main.cpp", is_nested = true },
        },
      },
    }
    local result = filtered(nil, nil, entries)
    assert.equals(root, result[1].path)
    assert.equals(root .. "/main.cpp", result[1].children[1].path)
    assert.is_false(result[1].children[1].is_nested)
    assert.is_true(entries[1].children[1].children[1].is_nested)
  end)

  it("leaves other sources, unrelated roots and missing or disabled Scoper unchanged", function()
    Adapter.configure(opts, false, true)
    assert.same(items(), filtered("buffers"))
    assert.same(items(), filtered(nil, root .. "-other"))
    enabled = false
    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "ScoperChanged", group = "config_scoper_explorer" }
    )
    assert.same(items(), filtered())
    package.loaded.scoper = nil
    assert.same(items(), filtered())
  end)

  it("fails open on predicate failures and retains folders without a directory API", function()
    Adapter.configure(opts, false, true)
    assert.equals(3, #filtered()[1].children)
    package.loaded.scoper = {
      snapshot = function()
        return { enabled = true, root = root }
      end,
      matcher = function()
        return function()
          error("unavailable")
        end
      end,
    }
    assert.same(items(), filtered())
  end)

  it("refreshes filters independently and honors a runtime toggle across configuration", function()
    Adapter.configure(opts, false, true)
    for _ = 1, 3 do
      vim.api.nvim_exec_autocmds(
        "User",
        { pattern = "ScoperChanged", group = "config_scoper_explorer" }
      )
    end
    assert.is_true(vim.wait(1000, function()
      return refreshes == 1
    end))
    assert.equals(0, redraws)
    Adapter.toggle_filter()
    assert.equals(2, refreshes)
    assert.same(items(), filtered())
    Adapter.configure(opts, false, true)
    assert.same(items(), filtered())
    Adapter.toggle_filter()
    assert.equals(3, #filtered()[1].children)
    enabled = false
    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "ScoperChanged", group = "config_scoper_explorer" }
    )
    assert.is_true(vim.wait(1000, function()
      return refreshes == 4
    end))
    assert.same(items(), filtered())
  end)

  it("does not stack renderer wrappers and restores the original on teardown", function()
    Adapter.setup(opts, false)
    local original_renderer = renderer.show_nodes
    Adapter.configure(opts, false, true)
    local first = renderer.show_nodes
    Adapter.configure(opts, false, true)
    assert.is_not.equals(first, renderer.show_nodes)
    Adapter.setup(opts, false)
    assert.equals(original_renderer, renderer.show_nodes)
    package.loaded["neo-tree.sources.manager"] = nil
    Adapter.toggle_filter()
    assert.is_nil(package.loaded["neo-tree.sources.manager"])
  end)
end)

describe("Scoper filtering with the pinned Neo-tree renderer", function()
  local adapter, previous_scoper, previous_adapter, root, opts, command
  after_each(function()
    if command then pcall(command.execute, { action = "close", source = "filesystem" }) end
    if adapter then adapter.setup(opts, false) end
    package.loaded.scoper = previous_scoper
    package.loaded["config.scoper_explorer"] = previous_adapter
    if root then vim.fn.delete(root, "rf") end
  end)

  it("restores scanned entries after toggling and disabling scope", function()
    previous_scoper = package.loaded.scoper
    previous_adapter = package.loaded["config.scoper_explorer"]
    -- Load BufEnter consumers before installing the deliberately minimal Scoper stub.
    require("lazy").load({ plugins = { "neo-tree.nvim", "nvim-lspconfig" } })
    command = require("neo-tree.command")
    root = vim.fn.tempname() .. " space-λ"
    vim.fn.mkdir(root .. "/vendor", "p")
    vim.fn.writefile({}, root .. "/keep.cpp")
    vim.fn.writefile({}, root .. "/hide.h")
    vim.fn.writefile({}, root .. "/.hidden.cpp")
    local active = true
    package.loaded.scoper = {
      snapshot = function()
        return { root = root, enabled = active }
      end,
      matcher = function()
        return function(path)
          return path:match("%.cpp$") ~= nil
        end
      end,
      excluded_directory_matcher = function()
        return function(path)
          return path == root .. "/vendor"
        end
      end,
    }
    package.loaded["config.scoper_explorer"] = nil
    adapter = require("config.scoper_explorer")
    opts = {}
    adapter.configure(opts, false, true)
    local state = require("neo-tree.sources.manager").get_state("filesystem")
    state.follow_current_file.enabled = false
    state.filtered_items.visible = false
    state.filtered_items.hide_dotfiles = true
    command.execute({ action = "show", source = "filesystem", dir = root })
    local function visible(path)
      return state.tree and state.tree:get_node(root .. "/" .. path) ~= nil
    end
    assert.is_true(vim.wait(3000, function()
      return visible("keep.cpp")
    end))
    assert.is_false(visible("hide.h"))
    assert.is_false(visible("vendor"))
    assert.is_false(visible(".hidden.cpp"))
    adapter.toggle_filter()
    assert.is_true(vim.wait(3000, function()
      return visible("hide.h") and visible("vendor")
    end))
    adapter.toggle_filter()
    assert.is_true(vim.wait(3000, function()
      return not visible("hide.h")
    end))
    active = false
    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "ScoperChanged", group = "config_scoper_explorer" }
    )
    assert.is_true(vim.wait(3000, function()
      return visible("hide.h") and visible("vendor")
    end))
    assert.is_false(visible(".hidden.cpp"))
  end)
end)
