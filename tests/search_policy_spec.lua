local Settings = require("config.settings")
local Search = require("config.search")

describe("search and session policies", function()
  local root, previous, old_select, old_notify

  before_each(function()
    Settings.reset()
    previous, root = vim.fn.getcwd(), vim.fn.tempname()
    old_select, old_notify = vim.ui.select, vim.notify
    vim.fn.mkdir(root .. "/project/src", "p")
    vim.fn.mkdir(root .. "/other", "p")
    vim.cmd.cd(vim.fn.fnameescape(root .. "/project"))
  end)

  after_each(function()
    Settings.reset()
    vim.ui.select, vim.notify = old_select, old_notify
    vim.cmd("silent! %bwipeout!")
    vim.cmd.cd(vim.fn.fnameescape(previous))
    vim.fn.delete(root, "rf")
  end)

  it("matches whole literal directory components without hiding similar names", function()
    local patterns = Search.component_patterns({ ".git", "node_modules", "[vendor]" })
    local function hidden(path)
      return vim.iter(patterns):any(function(pattern)
        return path:find(pattern) ~= nil
      end)
    end
    for _, path in ipairs({ ".git/config", "src/node_modules/a.js", "src\\[vendor]\\a.c" }) do
      assert.is_true(hidden(path), path)
    end
    for _, path in ipairs({ "vendor.git/config", "src/my_node_modules/a.js", "vendor/a.c" }) do
      assert.is_false(hidden(path), path)
    end
  end)

  it("keeps backend defaults while honoring false and empty overrides", function()
    assert.same({ ".git", "node_modules" }, Search.visibility("telescope", "find").exclude_dirs)
    assert.same({ ".git", ".jj" }, Search.visibility("fzf", "find").exclude_dirs)
    Settings.configure({
      search = { hidden = false, exclude_dirs = {}, explorer = { hidden = true } },
    })
    assert.is_false(Search.visibility("telescope", "find").hidden)
    assert.is_true(Search.visibility("explorer", "find").hidden)
    assert.same({}, Search.visibility("fzf", "find").exclude_dirs)
  end)

  it("resolves command roots on invocation under a window-local cwd", function()
    local project = root .. "/project"
    vim.cmd.edit(vim.fn.fnameescape(project .. "/src/a.c"))
    Settings.configure({
      project = { root = project },
      search = { find_root = "project", grep_root = "file" },
    })
    vim.cmd.lcd(vim.fn.fnameescape(root .. "/other"))
    assert.equals(vim.fs.normalize(project), Search.telescope_options("find").cwd)
    assert.equals(vim.fs.normalize(project .. "/src"), Search.telescope_options("grep").cwd)
    Settings.configure({ search = { find_root = "cwd" } })
    assert.equals(vim.fs.normalize(root .. "/other"), vim.fs.normalize(Search.root("find")))
  end)

  it("applies visibility in the real ripgrep file command", function()
    assert.equals(1, vim.fn.executable("rg"), "ripgrep is required")
    local project = root .. "/project"
    for _, dir in ipairs({ ".git", "node_modules", "my_node_modules", "vendor.git", "[vendor]" }) do
      vim.fn.mkdir(project .. "/" .. dir, "p")
      vim.fn.writefile({ "x" }, project .. "/" .. dir .. "/a.c")
    end
    vim.fn.writefile({ "ignored.c" }, project .. "/.gitignore")
    vim.fn.writefile({ "x" }, project .. "/ignored.c")
    vim.fn.writefile({ "x" }, project .. "/.hidden.c")
    Settings.configure({ search = { exclude_dirs = { ".git", "node_modules", "[vendor]" } } })
    local result = vim
      .system(Search.find_command(Search.visibility("telescope", "find")), {
        cwd = project,
        text = true,
      })
      :wait()
    assert.equals(0, result.code, result.stderr)
    local files = vim.split(result.stdout:gsub("\\", "/"), "\n", { trimempty = true })
    table.sort(files)
    assert.same({ ".gitignore", ".hidden.c", "my_node_modules/a.c", "vendor.git/a.c" }, files)
  end)

  it("keeps grep query option termination while exposing hidden and ignore policy", function()
    Settings.configure({
      search = { hidden = true, respect_gitignore = false, follow_links = true },
    })
    local args = Search.telescope_options("grep").additional_args()
    assert.is_true(vim.tbl_contains(args, "--hidden"))
    assert.is_true(vim.tbl_contains(args, "--no-ignore"))
    local opts = Search.fzf_options("grep")
    assert.matches("%-%-follow", opts.rg_opts)
    assert.matches(" %-e$", opts.rg_opts)
  end)

  it("keeps same-named files when fd excludes literal directories", function()
    local actual_executable = vim.fn.executable
    if actual_executable("fd") ~= 1 then
      pending("fd is required for this backend check")
      return
    end
    local project = root .. "/project"
    vim.fn.mkdir(project .. "/nested/node_modules", "p")
    vim.fn.writefile({ "x" }, project .. "/nested/node_modules/a.c")
    vim.fn.writefile({ "x" }, project .. "/node_modules")
    Settings.configure({ search = { exclude_dirs = { "node_modules" } } })
    vim.fn.executable = function(name)
      return name == "rg" and 0 or actual_executable(name)
    end
    local ok, command = pcall(Search.find_command, Search.visibility("telescope", "find"))
    vim.fn.executable = actual_executable
    assert.is_true(ok, command)
    assert.equals("fd", command[1])
    local result = vim.system(command, { cwd = project, text = true }):wait()
    assert.equals(0, result.code, result.stderr)
    assert.equals("node_modules", result.stdout:gsub("[\r\n]+$", ""))
  end)

  it("refuses non-current replacement roots instead of silently changing cwd", function()
    local messages = {}
    vim.notify = function(message)
      messages[#messages + 1] = message
    end
    Settings.configure({ search = { replace_root = root .. "/other" } })
    assert.is_nil(Search.replace_options())
    assert.matches("cannot preserve a different root", messages[1])
    Settings.configure({ search = { replace_root = "cwd" } })
    assert.same({ prefills = { search = "needle" } }, Search.replace_options({ search = "needle" }))
  end)

  it("leaves the selector alone for native or disabled ownership", function()
    local spec = dofile(previous .. "/lua/plugins/finder.lua")[1]
    for _, provider in ipairs({ "native", false }) do
      Settings.configure({ selector = { provider = provider } })
      spec.init()
      assert.equals(old_select, vim.ui.select)
    end
  end)

  it("clears directory-open hooks when explorer automation is disabled", function()
    Settings.configure({ explorer = { auto_open = false } })
    local spec = dofile(previous .. "/lua/plugins/explorer.lua")
    spec.init()
    assert.same({}, vim.api.nvim_get_autocmds({ group = "user_neotree_dir" }))
  end)

  it("supports manual sessions, empty suppression and independent save thresholds", function()
    Settings.configure({
      sessions = {
        auto_save = false,
        auto_restore = false,
        suppressed_dirs = {},
        min_tabs = false,
        min_files = 1,
      },
    })
    local opts = dofile(previous .. "/lua/plugins/session.lua").opts
    assert.is_false(opts.auto_save)
    assert.is_false(opts.auto_restore)
    assert.same({}, opts.suppressed_dirs)
    vim.cmd.edit(vim.fn.fnameescape(root .. "/project/a.c"))
    assert.is_true(opts.args_allow_files_auto_save())
    Settings.configure({ sessions = { min_files = false } })
    assert.is_false(opts.args_allow_files_auto_save())
  end)

  it("makes scope serialization and restoration no-ops for global buffers", function()
    Settings.configure({ sessions = { global_buffers = true } })
    local opts = dofile(previous .. "/lua/plugins/session.lua").opts
    vim.g.ScopeState = "old tab map"
    opts.pre_save_cmds[3]()
    assert.is_nil(vim.g.ScopeState)
    vim.g.ScopeState = "a session from tab-scoped mode"
    opts.post_restore_cmds[1]()
    opts.post_restore_cmds[2]()
    assert.equals("a session from tab-scoped mode", vim.g.ScopeState)
    vim.g.ScopeState = nil
  end)

  it("exposes automatic suppression hooks with explicit context", function()
    local contexts = {}
    Settings.configure({
      sessions = {
        suppress = function(ctx)
          contexts[#contexts + 1] = ctx
          return true
        end,
      },
    })
    local opts = dofile(previous .. "/lua/plugins/session.lua").opts
    assert.is_false(opts.pre_restore_cmds[1]("sample"))
    assert.is_true(require("config.session").suppressed("sample"))
    assert.equals("sample", contexts[1].session_name)
    assert.equals(vim.fn.getcwd(), contexts[1].cwd)
  end)

  it("vetoes automatic saves before cleanup and preserves manual save calls", function()
    local policy = require("config.session")
    local calls = 0
    local original = function(name, opts)
      calls = calls + 1
      assert.equals("sample", name)
      return opts.is_autosave ~= true
    end
    local session = { save_session = original }
    Settings.configure({
      sessions = {
        suppress = function()
          return true
        end,
      },
    })
    assert.is_true(policy.attach(session))
    local wrapper = session.save_session
    assert.is_true(policy.attach(session))
    assert.equals(wrapper, session.save_session)
    assert.is_false(session.save_session("sample", { is_autosave = true }))
    assert.equals(0, calls)
    assert.is_true(session.save_session("sample", {}))
    assert.equals(1, calls)
    policy.detach(session)
    assert.equals(original, session.save_session)
  end)

  it("leaves later user save overrides intact when detaching the policy", function()
    local policy = require("config.session")
    local session = { save_session = function() end }
    policy.attach(session)
    local custom = function()
      return "custom"
    end
    session.save_session = custom
    policy.detach(session)
    assert.equals(custom, session.save_session)
  end)

  it("keeps manual scope serialization safe when automatic saves are suppressed", function()
    Settings.configure({
      sessions = {
        suppress = function()
          return true
        end,
      },
    })
    local opts = dofile(previous .. "/lua/plugins/session.lua").opts
    vim.g.ScopeState = nil
    opts.pre_save_cmds[3]()
    assert.equals("table", type(vim.json.decode(vim.g.ScopeState)))
    vim.g.ScopeState = nil
  end)
end)
