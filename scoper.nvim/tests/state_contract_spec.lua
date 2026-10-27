local Path = require("scoper.path")
local Util = require("scoper.util")

describe("Scoper state contracts", function()
  local State, Scoper, root, data, previous, old_data, notify, atomic, group

  local function path()
    return vim.fn.stdpath("data") .. "/scoper/" .. Util.cwd_hash(Path.key(State.root())) .. ".json"
  end

  local function write(document)
    vim.fn.mkdir(vim.fn.fnamemodify(path(), ":h"), "p")
    vim.fn.writefile({ vim.json.encode(document) }, path())
  end

  before_each(function()
    root, data = Path.normalize(vim.fn.tempname()), vim.fn.tempname()
    previous, old_data = vim.fn.getcwd(), vim.env.XDG_DATA_HOME
    vim.fn.mkdir(root .. "/a/src", "p")
    vim.fn.mkdir(root .. "/b", "p")
    vim.env.XDG_DATA_HOME = data
    vim.cmd.cd(root .. "/a")
    package.loaded["scoper.state"], package.loaded["scoper"] = nil, nil
    State, Scoper = require("scoper.state"), require("scoper")
    State.load({ quiet = true })
    notify, atomic = vim.notify, Util.atomic_write
    vim.notify = function() end
    group = vim.api.nvim_create_augroup("scoper_contract_test", { clear = true })
  end)

  after_each(function()
    Util.atomic_write, vim.notify = atomic, notify
    pcall(vim.api.nvim_del_augroup_by_name, "scoper_dir")
    vim.api.nvim_del_augroup_by_id(group)
    vim.cmd.cd(previous)
    vim.env.XDG_DATA_HOME = old_data
    vim.fn.delete(root, "rf")
    vim.fn.delete(data, "rf")
  end)

  it("returns isolated snapshots and revisioned same-name edits", function()
    local before = State.context()
    State.add_paths("src")
    local current = State.snapshot()
    assert.equals(before.scope, current.scope)
    assert.is_true(current.revision > before.revision)
    current.definition.include[1] = "modified"
    current.result.reason = "modified"
    assert.same({ "src" }, State.active_scope().include)
    assert.equals("saved", State.last_result().reason)
  end)

  it("describes the exact accepted change and persistence in its existing event", function()
    local event
    vim.api.nvim_create_autocmd("User", {
      pattern = "ScoperChanged",
      group = group,
      callback = function(args)
        event = args.data
      end,
    })
    State.set_database("../build/compile_commands.json")
    local current = State.context()
    assert.equals(current.root, Path.key(event.root))
    assert.equals(current.scope, event.scope)
    assert.equals(current.revision, event.revision)
    assert.equals(current.database, event.database)
    assert.equals("database", event.reason)
    assert.same({ "database" }, event.changed)
    assert.is_true(event.persistence.applied)
    assert.is_true(event.persistence.persisted)
  end)

  it("keeps build selection independent of named scope changes", function()
    local database = root .. "/build/compile_commands.json"
    State.set_database(database)
    State.new_scope("other")
    State.clear_active()
    assert.equals(database, State.database())
    State.set_active("default")
    assert.equals(database, State.database())
    State.reload()
    assert.equals(database, State.database())
    State.set_database(nil)
    assert.is_nil(State.database())
  end)

  it("reports successful, unchanged and refused mutations without losing legacy returns", function()
    local count, _, accepted = State.add_paths("src")
    assert.equals(1, count)
    assert.same({ applied = true, persisted = true, reason = "saved" }, accepted)
    local _, _, unchanged = State.add_paths("src")
    assert.is_false(unchanged.applied)
    assert.equals("unchanged", unchanged.reason)
    local ok, err, refused = State.new_scope("../invalid")
    assert.is_false(ok)
    assert.is_string(err)
    assert.is_false(refused.applied)
    assert.equals("invalid", refused.reason)
  end)

  it(
    "retains failed publications, refuses an implicit discard and permits a forced reload",
    function()
      State.add_paths("saved")
      Util.atomic_write = function()
        return false, "disk full"
      end
      local _, _, changed = State.add_paths("local")
      assert.is_true(changed.applied)
      assert.is_false(changed.persisted)
      assert.equals("io_error", changed.reason)
      assert.is_true(State.snapshot().unsaved)
      assert.equals("unsaved", State.reload().reason)
      assert.same({ "saved", "local" }, State.active_scope().include)
      local opts = { force = true }
      assert.is_true(State.reload(opts).applied)
      assert.same({ force = true }, opts)
      assert.same({ "saved" }, State.active_scope().include)
      assert.is_false(State.snapshot().unsaved)
    end
  )

  it("does not replace failed local changes with later external data", function()
    State.add_paths("saved")
    Util.atomic_write = function()
      return false, "disk full"
    end
    State.add_paths("local")
    local external = vim.json.decode(table.concat(vim.fn.readfile(path()), "\n"))
    external.scopes.default.include = { "external" }
    write(external)
    State.context()
    assert.same({ "saved", "local" }, State.active_scope().include)
    Util.atomic_write = atomic
    local saved, outcome = State.save()
    assert.is_false(saved)
    assert.equals("conflict", outcome.reason)
    assert.same(
      { "external" },
      vim.json.decode(table.concat(vim.fn.readfile(path()), "\n")).scopes.default.include
    )
  end)

  it("retains unsaved sessions across project switches with monotonic revisions", function()
    State.add_paths("saved")
    Util.atomic_write = function()
      return false, "disk full"
    end
    State.add_paths("local")
    local revision = State.context().revision
    vim.cmd.cd(root .. "/b")
    State.follow_cwd()
    assert.same({}, State.active_scope().include)
    assert.is_true(State.context().revision > revision)
    revision = State.context().revision
    vim.cmd.cd(root .. "/a")
    State.follow_cwd()
    assert.same({ "saved", "local" }, State.active_scope().include)
    assert.is_true(State.context().revision > revision)
    assert.is_true(State.snapshot().unsaved)
    Util.atomic_write = atomic
    assert.is_true(State.save())
    assert.is_false(State.snapshot().unsaved)
  end)

  it("migrates legacy stores on publication without changing their scopes", function()
    write({
      active = "legacy",
      enabled = true,
      scopes = { legacy = { include = { "src" }, exclude = {} } },
    })
    State.reload()
    assert.equals("legacy", State.active_name())
    assert.same({ "src" }, State.active_scope().include)
    assert.is_true(State.save())
    local published = vim.json.decode(table.concat(vim.fn.readfile(path()), "\n"))
    assert.equals(1, published.schema_version)
  end)

  it("refuses destructive saves of a newer schema and recovers after an explicit reload", function()
    local newer = { schema_version = 2, private_future_data = { "precious" } }
    write(newer)
    local loaded = State.reload()
    assert.is_false(loaded.persisted)
    assert.equals("unsupported_schema", loaded.reason)
    local _, _, changed = State.add_paths("session-only")
    assert.is_true(changed.applied)
    assert.is_false(changed.persisted)
    assert.equals("unsupported_schema", changed.reason)
    assert.same(newer, vim.json.decode(table.concat(vim.fn.readfile(path()), "\n")))
    assert.equals("unsaved", State.reload().reason)
    write({ schema_version = 1, active = "default", scopes = {}, enabled = false })
    assert.is_true(State.reload({ force = true }).persisted)
    assert.is_true(State.save())
  end)

  it("resolves explicit project roots independently of local cwd changes", function()
    local seen
    State.configure_project(function(cwd)
      seen = cwd
      return root .. "/a"
    end)
    State.initialize()
    vim.cmd.cd(root .. "/b")
    State.follow_cwd()
    assert.equals(Path.key(root .. "/b"), Path.key(seen))
    assert.equals(Path.key(root .. "/a"), Path.key(State.root()))
  end)

  it("allows project root resolvers to decline with nil or false", function()
    for _, resolver in ipairs({
      function() end,
      function()
        return false
      end,
    }) do
      State.configure_project(resolver)
      assert.has_no.errors(State.initialize)
      assert.equals(Path.key(Path.cwd()), Path.key(State.root()))
    end
  end)

  it("reconfigures from stable defaults and preserves unsaved state at the same root", function()
    Scoper.setup({ default_excludes = { "**/generated/**" }, lsp = { extra_args = { "--x" } } })
    Util.atomic_write = function()
      return false, "disk full"
    end
    State.add_paths("local")
    Scoper.setup({ picker = "native" })
    assert.same({}, Scoper.config.default_excludes)
    assert.same({}, Scoper.config.lsp.extra_args)
    assert.same({ "local" }, State.active_scope().include)
    assert.is_true(State.snapshot().unsaved)
    assert.equals(1, #vim.api.nvim_get_autocmds({ group = "scoper_dir" }))
    Scoper.patch({ lsp = { extra_args = { "--patched" } } })
    assert.equals("native", Scoper.config.picker)
    assert.same({ "--patched" }, Scoper.config.lsp.extra_args)
  end)
end)
