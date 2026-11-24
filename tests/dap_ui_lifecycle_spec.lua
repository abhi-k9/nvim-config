describe("DAP UI session ownership", function()
  local notify, notes
  local Settings = require("config.settings")
  local saved_dap, saved_ui, saved_preference, spec, dap, roots, current, opened, closed, completion

  before_each(function()
    saved_dap, saved_ui = package.loaded.dap, package.loaded.dapui
    notify, notes = vim.notify, {}
    vim.notify = function(message)
      notes[#notes + 1] = message
    end
    saved_preference = vim.g.dap_autoclose_ui
    Settings.reset()
    roots, current, opened, closed, completion = {}, nil, 0, 0, nil
    dap = {
      listeners = {
        before = { attach = {}, launch = {}, event_terminated = {}, event_exited = {} },
        after = { attach = {}, launch = {} },
      },
      session = function()
        return current
      end,
      sessions = function()
        return roots
      end,
      terminate = function(opts)
        completion = opts.on_done
      end,
    }
    package.loaded.dap = dap
    package.loaded.dapui = {
      setup = function() end,
      open = function()
        opened = opened + 1
      end,
      close = function()
        closed = closed + 1
      end,
    }
    vim.g.dap_autoclose_ui = true
    spec = dofile(vim.fn.getcwd() .. "/lua/plugins/dap.lua")
    spec[3].config(nil, {})
  end)

  after_each(function()
    package.loaded.dap, package.loaded.dapui = saved_dap, saved_ui
    vim.g.dap_autoclose_ui = saved_preference
    vim.notify = notify
    Settings.reset()
  end)

  local function terminate_key()
    for _, key in ipairs(spec[1].keys) do
      if key[1] == "<leader>dt" then return key[2]() end
    end
    error("terminate mapping not found")
  end

  it("honors auto-open policy on first launch and attach", function()
    Settings.configure({ debug = { auto_open_ui = false } })
    dap.listeners.before.launch.dapui_config({ on_close = {} })
    dap.listeners.before.attach.dapui_config({ on_close = {} })
    assert.equals(0, opened)
    Settings.configure({ debug = { auto_open_ui = true } })
    dap.listeners.before.launch.dapui_config({ on_close = {} })
    assert.equals(1, opened)
  end)

  it("keeps a panel error out of the DAP launch response handler", function()
    package.loaded.dapui.open = function()
      error("panel layout unavailable")
    end
    local session = { on_close = {} }
    dap.listeners.before.launch.dapui_config(session)
    assert.is_function(session.on_close.dapui_config)
    assert.is_truthy(notes[1]:find("panel layout unavailable", 1, true))
  end)

  it("keeps terminate independent of optional UI loading", function()
    local preload, loads = package.preload.dapui, 0
    package.loaded.dapui = nil
    package.preload.dapui = function()
      loads = loads + 1
      error("missing UI")
    end
    local ok, err = pcall(terminate_key)
    package.preload.dapui = preload
    assert.is_true(ok, tostring(err))
    assert.equals(0, loads)
  end)

  it("explains missing UI actions when invoked from a mapping", function()
    package.loaded.dapui = {}
    for _, key in ipairs(spec[3].keys) do
      if key[1] == "<leader>du" or key[1] == "<leader>de" then key[2]() end
    end
    assert.equals(2, #notes)
    assert.is_truthy(notes[1]:find(":Lazy", 1, true))
  end)

  it("seeds auto-close policy without overwriting an existing preference", function()
    Settings.configure({ debug = { auto_close_ui = false } })
    vim.g.dap_autoclose_ui = nil
    spec[3].config(nil, {})
    assert.is_false(vim.g.dap_autoclose_ui)
    vim.g.dap_autoclose_ui = true
    spec[3].config(nil, {})
    assert.is_true(vim.g.dap_autoclose_ui)
  end)

  it("preserves another root session's UI on exit and termination", function()
    local a, b = {}, {}
    roots = { a, b }
    dap.listeners.before.event_exited.dapui_config(b)
    dap.listeners.before.event_terminated.dapui_config(b)
    assert.equals(0, closed)
    b.closed, roots[2] = true, nil
    dap.listeners.before.event_terminated.dapui_config(a)
    assert.equals(1, closed)
  end)

  it("preserves parent and child controls when only one child ends", function()
    local child = {}
    local parent = { children = { child } }
    roots = { parent }
    dap.listeners.before.event_terminated.dapui_config(child)
    assert.equals(0, closed)
    dap.listeners.before.event_terminated.dapui_config(parent)
    assert.equals(0, closed)
  end)

  it("closes after an adapter crash without protocol exit events", function()
    local session = { on_close = {} }
    roots = { session }
    dap.listeners.before.launch.dapui_config(session)
    assert.is_function(session.on_close.dapui_config)
    session.closed, roots = true, {}
    session.on_close.dapui_config()
    assert.is_true(vim.wait(1000, function()
      return closed == 1
    end, 10))
  end)

  it("keeps another session's UI after an adapter crash", function()
    local active, failed = {}, { on_close = {} }
    roots = { active, failed }
    dap.listeners.before.attach.dapui_config(failed)
    failed.closed = true
    failed.on_close.dapui_config()
    vim.wait(20, function()
      return false
    end, 1)
    assert.equals(0, closed)
  end)

  it("checks new sessions and auto-close preferences after scheduling cleanup", function()
    local failed = { on_close = {} }
    dap.listeners.before.launch.dapui_config(failed)
    failed.closed = true
    failed.on_close.dapui_config()
    roots = { {} }
    vim.wait(20, function()
      return false
    end, 1)
    assert.equals(0, closed)
    roots = {}
    failed.on_close.dapui_config()
    vim.g.dap_autoclose_ui = false
    vim.wait(20, function()
      return false
    end, 1)
    assert.equals(0, closed)
  end)

  it("leaves manually opened panels alone on failed launch and attach replies", function()
    for _, request in ipairs({ "launch", "attach" }) do
      local failed, err = { on_close = {} }, { message = "failed" }
      dap.listeners.before[request].dapui_config(failed, err)
      local after = dap.listeners.after[request].dapui_config
      if after then after(failed, err) end
      dap.listeners.before.event_terminated.dapui_config(failed)
    end
    assert.equals(0, opened)
    assert.equals(0, closed)
  end)

  it("closes once across exit, termination, transport close and terminate completion", function()
    local session = { on_close = {} }
    current, roots = session, { session }
    dap.listeners.before.launch.dapui_config(session)
    terminate_key()
    dap.listeners.before.event_exited.dapui_config(session)
    assert.equals(1, closed)
    package.loaded.dapui.open() -- User reopened the panels to inspect output.
    dap.listeners.before.event_terminated.dapui_config(session)
    session.closed, current, roots = true, nil, {}
    session.on_close.dapui_config()
    completion()
    vim.wait(20, function()
      return false
    end, 1)
    assert.equals(1, closed)
  end)

  it("waits for terminate completion and leaves another session's UI alone", function()
    local a, b = {}, {}
    current, roots = b, { a, b }
    terminate_key()
    assert.equals(0, closed)
    assert.is_function(completion)
    b.closed, roots[2], current = true, nil, a
    completion()
    assert.equals(0, closed)
  end)

  it("closes after the last termination and respects the preference at completion", function()
    local a = {}
    current, roots = a, { a }
    terminate_key()
    assert.equals(0, closed)
    a.closed, current, roots = true, nil, {}
    completion()
    assert.equals(1, closed)
    vim.g.dap_autoclose_ui = false
    terminate_key()
    assert.equals(1, closed)
  end)

  it("does not close a newly started session when an earlier termination completes", function()
    local a = {}
    current, roots = a, { a }
    terminate_key()
    current, roots = {}, { {} }
    a.closed = true
    completion()
    assert.equals(0, closed)
  end)

  it("closes empty panels when terminate is invoked without sessions", function()
    terminate_key()
    assert.equals(1, closed)
  end)
end)
