local Scoper = require("scoper")
local State = require("scoper.state")
local LSP = require("scoper.lsp")
local Path = require("scoper.path")

describe("Scoper compilation integration policy", function()
  local root, data, cache, previous, env, config, lsp_config, saved, notes
  before_each(function()
    root, data, cache = Path.normalize(vim.fn.tempname()), vim.fn.tempname(), vim.fn.tempname()
    previous, env = vim.fn.getcwd(), { vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME }
    vim.fn.mkdir(root .. "/src", "p")
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = data, cache
    vim.fn.chdir(root)
    config = vim.deepcopy(Scoper.config)
    LSP.dispose()
    lsp_config = vim.deepcopy(vim.lsp.config.clangd or {})
    saved = {
      executable = vim.fn.executable,
      start = vim.lsp.rpc.start,
      clients = vim.lsp.get_clients,
      notify = vim.notify,
      filter = LSP._filter_async,
      reload = LSP.reload_clangd,
      reattach = LSP._reattach,
      worker_cmd = LSP._worker_cmd,
      run = require("scoper.cdb").run,
      system = vim.system,
      client = vim.lsp.get_client_by_id,
      timing = LSP._timing,
    }
    vim.fn.executable = function()
      return 1
    end
    vim.lsp.get_clients = function()
      return {}
    end
    LSP._reattach = function() end
    notes = {}
    vim.notify = function(msg)
      notes[#notes + 1] = msg
    end
    vim.lsp.config.clangd = {
      cmd = { "custom-clangd", "--background-index", "--log=error" },
      cmd_env = { CUSTOM = "kept" },
    }
    vim.fn.writefile({
      vim.json.encode({
        { file = root .. "/src/a.c", directory = root, arguments = { "cc", "-c", "src/a.c" } },
        { file = root .. "/other.c", directory = root, command = "cc -c other.c" },
      }),
    }, root .. "/compile_commands.json")
    Scoper.setup({ lsp = { clangd = false } })
  end)
  after_each(function()
    LSP.dispose()
    LSP._filter_async, LSP.reload_clangd, LSP._reattach = saved.filter, saved.reload, saved.reattach
    vim.fn.executable, vim.lsp.rpc.start = saved.executable, saved.start
    vim.lsp.get_clients, vim.notify = saved.clients, saved.notify
    LSP._worker_cmd, require("scoper.cdb").run = saved.worker_cmd, saved.run
    vim.system = saved.system
    vim.lsp.get_client_by_id, LSP._timing = saved.client, saved.timing
    vim.lsp.config.clangd = lsp_config
    Scoper.config = config
    pcall(vim.api.nvim_del_augroup_by_name, "scoper_dir")
    vim.fn.chdir(previous)
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = env[1], env[2]
    for _, path in ipairs({ root, data, cache }) do
      vim.fn.delete(path, "rf")
    end
  end)
  local function mode(name, extra)
    local opts = extra or {}
    opts.lsp = opts.lsp or {}
    opts.lsp.mode = name
    Scoper.setup(opts)
  end
  it("leaves native and disabled clangd command ownership untouched", function()
    local command = function() end
    local resolved = 0
    vim.lsp.config("clangd", { cmd = command })
    mode("native", {
      compilation_database = {
        resolver = function()
          resolved = resolved + 1
          return false
        end,
      },
    })
    assert.equals(command, vim.lsp.config.clangd.cmd)
    assert.equals(0, resolved)
    mode("disabled")
    LSP.reload_clangd()
    assert.equals(command, vim.lsp.config.clangd.cmd)
  end)
  it(
    "preserves the inherited command flags and environment without automatic compiler trust",
    function()
      mode("selected")
      assert.equals("custom-clangd", LSP._cmd[1])
      assert.is_true(vim.tbl_contains(LSP._cmd, "--log=error"))
      for _, arg in ipairs(LSP._cmd) do
        assert.is_nil(arg:find("--query-driver", 1, true))
      end
      local result
      vim.lsp.rpc.start = function(cmd, _, opts)
        result = { cmd = cmd, opts = opts }
        return {}
      end
      vim.lsp.config.clangd.cmd({}, { root_dir = root, cmd_env = { CUSTOM = "kept" } })
      assert.are.same({ CUSTOM = "kept" }, result.opts.env)
    end
  )
  it("selects an entire database independently of the active search scope", function()
    State.add_paths("src")
    State.set_enabled(true)
    mode("selected")
    assert.equals("--compile-commands-dir=" .. root, LSP._cmd[2])
    assert.is_nil(LSP.write_filtered_compile_commands())
  end)
  it("preserves arbitrary external database names through an immutable full copy", function()
    local external = root .. "/custom.json"
    vim.fn.writefile(vim.fn.readfile(root .. "/compile_commands.json"), external)
    mode("selected", { compilation_database = { path = external } })
    local dir = LSP.write_filtered_compile_commands()
    assert.are.same(
      vim.json.decode(table.concat(vim.fn.readfile(external), "\n")),
      vim.json.decode(table.concat(vim.fn.readfile(dir .. "/compile_commands.json"), "\n"))
    )
    assert.equals(external, LSP.status().selection.path)
  end)
  it("restores its command on disposal while retaining later user replacements", function()
    local original = vim.deepcopy(vim.lsp.config.clangd.cmd)
    mode("selected")
    mode("disabled")
    assert.are.same(original, vim.lsp.config.clangd.cmd)
    mode("selected")
    local replacement = { "user-clangd", "--new" }
    vim.lsp.config("clangd", { cmd = replacement })
    mode("disabled")
    assert.are.same(replacement, vim.lsp.config.clangd.cmd)
  end)
  it("refreshes source-only changes through the focus fallback and disposes its watcher", function()
    mode("selected", { lsp = { debounce_ms = 1 } })
    local watcher = LSP._watcher
    assert.is_not_nil(watcher)
    local count = 0
    LSP.reload_clangd = function()
      count = count + 1
    end
    local path = root .. "/compile_commands.json"
    vim.fn.writefile({ "[ ]" }, path .. ".new")
    assert(vim.uv.fs_rename(path .. ".new", path))
    vim.api.nvim_exec_autocmds("FocusGained", {})
    assert.is_true(vim.wait(200, function()
      return count == 1
    end, 1))
    mode("disabled")
    assert.is_true(watcher:is_closing())
    assert.is_nil(LSP._watcher)
  end)
  it("gates first attachment on asynchronous filtered preparation", function()
    State.add_paths("src")
    State.set_enabled(true)
    local pending
    LSP._filter_async = function(cb)
      pending = cb
    end
    mode("filtered", { lsp = { startup = "prepare", prepare_timeout_ms = 100 } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/src/a.c")
    local attached = false
    vim.lsp.config.clangd.root_dir(buf, function()
      attached = true
    end)
    assert.is_false(attached)
    assert.equals("preparing", LSP.status().startup.state)
    pending(root .. "/filtered", "ready", true)
    assert.is_true(attached)
    assert.equals("--compile-commands-dir=" .. root .. "/filtered", LSP._cmd[2])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  it("accepts full database preparation when filtering is off or its includes are empty", function()
    for _, enabled in ipairs({ false, true }) do
      State.clear_active()
      State.set_enabled(enabled)
      mode("filtered", { lsp = { startup = "prepare" } })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, root .. "/src/a.c")
      local attached = false
      vim.lsp.config.clangd.root_dir(buf, function()
        attached = true
      end)
      assert.is_true(attached)
      assert.equals("ready", LSP.status().startup.state)
      assert.equals("--compile-commands-dir=" .. root, LSP._cmd[2])
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("bounds strict preparation without starting on an unfiltered database", function()
    LSP._filter_async = function() end
    mode("filtered", { lsp = { startup = "prepare", prepare_timeout_ms = 1 } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/src/a.c")
    local attached = false
    vim.lsp.config.clangd.root_dir(buf, function()
      attached = true
    end)
    assert.is_true(vim.wait(100, function()
      return LSP.status().startup.state == "timed_out"
    end, 1))
    assert.is_false(attached)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  it(
    "retries strict preparation after the scope changes without stranding the waiting buffer",
    function()
      State.add_paths("src")
      State.set_enabled(true)
      local pending = {}
      LSP._filter_async = function(cb)
        pending[#pending + 1] = cb
      end
      mode("filtered", { lsp = { startup = "prepare", prepare_timeout_ms = 1000 } })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, root .. "/src/a.c")
      local attached = 0
      vim.lsp.config.clangd.root_dir(buf, function()
        attached = attached + 1
      end)
      State.add_paths("other")
      pending[1](nil, "changed", false, true, true)
      assert.is_true(vim.wait(100, function()
        return #pending == 2
      end, 1))
      pending[2](root .. "/current", "ready", true)
      assert.equals(1, attached)
      assert.equals("ready", LSP.status().startup.state)
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  )
  it("prepares a cold named-source copy before selected-mode attachment", function()
    local external = root .. "/custom.json"
    vim.fn.writefile(vim.fn.readfile(root .. "/compile_commands.json"), external)
    mode("selected", { lsp = { startup = "prepare" }, compilation_database = { path = external } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/src/a.c")
    local attached = false
    vim.lsp.config.clangd.root_dir(buf, function()
      attached = true
    end)
    assert.is_true(vim.wait(3000, function()
      return attached
    end, 1))
    local dir = LSP._cmd[2]:gsub("^%-%-compile%-commands%-dir=", "")
    assert.are.same(
      vim.json.decode(table.concat(vim.fn.readfile(external), "\n")),
      vim.json.decode(table.concat(vim.fn.readfile(dir .. "/compile_commands.json"), "\n"))
    )
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  it(
    "does not claim an unmaterialized named source is available in its parent directory",
    function()
      local external = root .. "/custom.json"
      vim.fn.writefile(vim.fn.readfile(root .. "/compile_commands.json"), external)
      LSP.reload_clangd = function() end
      mode("selected", { compilation_database = { path = external } })
      for _, arg in ipairs(LSP._cmd) do
        assert.is_nil(arg:find("--compile-commands-dir", 1, true))
      end
    end
  )
  it("returns independent public status snapshots", function()
    mode("selected")
    local status = LSP.status()
    status.selection.path = "changed"
    assert.equals(root .. "/compile_commands.json", LSP.status().selection.path)
  end)
  it("coalesces preparation for simultaneous buffers", function()
    local pending, runs, delivered = nil, 0, 0
    LSP._filter_async = function(cb)
      pending, runs = cb, runs + 1
    end
    local function done()
      delivered = delivered + 1
    end
    LSP.prepare(done)
    LSP.prepare(done)
    assert.equals(1, runs)
    pending(root .. "/filtered", "ready", true)
    assert.equals(2, delivered)
  end)
  it("does not synchronously filter when strict preparation cannot start its worker", function()
    State.add_paths("src")
    State.set_enabled(true)
    mode("filtered", { lsp = { startup = "prepare" } })
    local runs, result = 0, nil
    require("scoper.cdb").run = function()
      runs = runs + 1
      error("must not filter in editor")
    end
    LSP._worker_cmd = function()
      return { "scoper-nonexistent-worker" }
    end
    LSP.prepare(function(dir, info)
      result = { dir = dir, info = info }
    end)
    assert.is_true(vim.wait(1000, function()
      return result ~= nil
    end, 1))
    assert.is_nil(result.dir)
    assert.matches("background preparation failed", result.info)
    assert.equals(0, runs)
  end)
  it("drops a worker result captured before a build selection change", function()
    State.add_paths("src")
    State.set_enabled(true)
    local other = root .. "/other-build.json"
    vim.fn.writefile(vim.fn.readfile(root .. "/compile_commands.json"), other)
    local result
    vim.system = function(cmd, _, callback)
      local job = vim.json.decode(table.concat(vim.fn.readfile(cmd[#cmd - 1]), "\n"))
      local output = require("scoper.cdb").run(job)
      State.set_database(other)
      vim.fn.writefile({ vim.json.encode(output) }, cmd[#cmd])
      callback({ code = 0 })
    end
    LSP._filter_async(function(dir, _, _, _, obsolete)
      result = { dir = dir, obsolete = obsolete }
    end)
    assert.is_true(vim.wait(1000, function()
      return result ~= nil
    end, 1))
    assert.is_nil(result.dir)
    assert.is_true(result.obsolete)
  end)
  it("restores an owned fallback argv when clangd was unavailable", function()
    vim.fn.executable = function()
      return 0
    end
    local original = vim.deepcopy(vim.lsp.config.clangd.cmd)
    mode("selected")
    assert.is_table(vim.lsp.config.clangd.cmd)
    mode("disabled")
    assert.are.same(original, vim.lsp.config.clangd.cmd)
  end)
  it("requires explicit argv before replacing a custom transport function", function()
    local command = function() end
    vim.lsp.config("clangd", { cmd = command })
    mode("selected")
    assert.equals(command, vim.lsp.config.clangd.cmd)
    assert.matches("requires explicit lsp.cmd argv", notes[#notes])
  end)
  it("reconciles final server overrides before activation without reloading scope state", function()
    mode("selected")
    State.add_paths("src")
    local revision = State.context().revision
    local command = { "late-clangd", "--log=verbose" }
    local provider = function(_, callback)
      callback(root)
    end
    vim.lsp.config("clangd", { cmd = command, root_dir = provider })
    LSP.reconfigure()
    assert.equals("late-clangd", LSP._cmd[1])
    assert.is_true(vim.tbl_contains(LSP._cmd, "--log=verbose"))
    assert.equals(revision, State.context().revision)
    mode("disabled")
    assert.are.same(command, vim.lsp.config.clangd.cmd)
    assert.equals(provider, vim.lsp.config.clangd.root_dir)
  end)
  it("replays a project switch during restart polling before reattaching any buffers", function()
    mode("selected", { lsp = { debounce_ms = 1000 } })
    local other = Path.normalize(vim.fn.tempname())
    vim.fn.mkdir(other .. "/src", "p")
    local old_buf, new_buf =
      vim.api.nvim_create_buf(true, false), vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(old_buf, root .. "/src/a.c")
    vim.api.nvim_buf_set_name(new_buf, other .. "/src/b.c")
    vim.bo[old_buf].filetype, vim.bo[new_buf].filetype = "c", "c"
    local alive = true
    local client = { id = 42, root_dir = root, attached_buffers = { [old_buf] = true } }
    client.is_stopped = function()
      return false
    end
    client.stop = function()
      alive = false
    end
    vim.lsp.get_clients = function(filter)
      if filter and filter.bufnr then return {} end
      return alive and { client } or {}
    end
    vim.lsp.get_client_by_id = function()
      return alive and client or nil
    end
    LSP._timing = { poll = 1, grace = 2, kill = 2 }
    LSP._filter_async = function(cb)
      cb(State.root() .. "/object", "ready", true)
    end
    local targets
    LSP._reattach = function(bufs)
      targets = bufs
    end
    LSP.reload_clangd()
    vim.fn.chdir(other)
    assert.is_true(vim.wait(200, function()
      return targets ~= nil
    end, 1))
    assert.are.same({ new_buf }, targets)
    assert.equals("--compile-commands-dir=" .. other .. "/object", LSP._cmd[2])
    vim.api.nvim_buf_delete(old_buf, { force = true })
    vim.api.nvim_buf_delete(new_buf, { force = true })
    vim.fn.chdir(root)
    vim.fn.delete(other, "rf")
  end)
  it(
    "replaces both joined and separate database flags without dropping unrelated arguments",
    function()
      mode("selected", {
        lsp = {
          cmd = {
            "custom-clangd",
            "--compile-commands-dir",
            "/old",
            "--log=error",
            "--compile-commands-dir=/other",
          },
        },
      })
      local flags = vim.tbl_filter(function(arg)
        return arg:match("^%-%-compile%-commands%-dir")
      end, LSP._cmd)
      assert.are.same({ "--compile-commands-dir=" .. root }, flags)
      assert.is_false(vim.tbl_contains(LSP._cmd, "/old"))
      assert.is_true(vim.tbl_contains(LSP._cmd, "--log=error"))
    end
  )
end)
