describe("DAP UI session ownership", function()
  local saved_dap, saved_ui, saved_preference, spec, dap, roots, current, closed, completion

  before_each(function()
    saved_dap, saved_ui = package.loaded.dap, package.loaded.dapui
    saved_preference = vim.g.dap_autoclose_ui
    roots, current, closed, completion = {}, nil, 0, nil
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
      open = function() end,
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
  end)

  local function terminate_key()
    for _, key in ipairs(spec[1].keys) do
      if key[1] == "<leader>dt" then return key[2]() end
    end
    error("terminate mapping not found")
  end

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

  it("does not hide another session after a failed launch or attach", function()
    local active, failed = {}, {}
    roots = { active }
    dap.listeners.after.launch.dapui_config(failed, { message = "launch failed" })
    dap.listeners.after.attach.dapui_config(failed, { message = "attach failed" })
    assert.equals(0, closed)
    roots = {}
    dap.listeners.after.launch.dapui_config(failed, { message = "launch failed" })
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
