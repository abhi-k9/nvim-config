describe("persistent breakpoint lifecycle", function()
  local dap = require("dap")
  local Store = require("persistent-breakpoints.store")
  local api, root, cwd, buffers, notices, notify, input
  local function buffer(name)
    local buf = vim.api.nvim_create_buf(true, false)
    buffers[#buffers + 1] = buf
    vim.api.nvim_buf_set_name(buf, root .. "/" .. name)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c", "d", "e" })
    vim.api.nvim_set_current_buf(buf)
    return buf
  end
  local function reset()
    pcall(vim.api.nvim_del_augroup_by_name, "persistent_breakpoints")
    package.loaded["persistent-breakpoints.core"] = nil
    api = require("persistent-breakpoints.core")
    package.loaded["persistent-breakpoints.api"] = nil
  end
  before_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "persistent_breakpoints")
    cwd, root = vim.fn.getcwd(), vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.api.nvim_set_current_dir(root)
    buffers, notices = {}, {}
    notify = vim.notify
    input = vim.fn.input
    vim.notify = function(msg)
      notices[#notices + 1] = msg
    end
    dap.clear_breakpoints()
    reset()
    api.setup({ directory = root .. "/store" })
  end)
  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "persistent_breakpoints")
    dap.sessions()[98765] = nil
    for _, event in ipairs({ "event_terminated", "event_exited", "disconnect" }) do
      dap.listeners.after[event].persistent_breakpoints = nil
    end
    dap.clear_breakpoints()
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    vim.api.nvim_set_current_dir(cwd)
    vim.notify = notify
    vim.fn.input = input
    vim.fn.delete(root, "rf")
  end)
  local function points(buf)
    return require("dap.breakpoints").get()[buf] or {}
  end
  local function restart()
    dap.clear_breakpoints()
    reset()
    api.setup({ directory = root .. "/store" })
  end
  it("keeps mapped prompts, cancel semantics, F9 and clear behavior", function()
    local keys = {}
    for _, key in ipairs(dofile(cwd .. "/lua/plugins/dap.lua")[1].keys) do
      keys[key[1]] = key[2]
    end
    local buf = buffer("mapped.cpp")
    local answers = { "", "" }
    vim.fn.input = function()
      return table.remove(answers, 1)
    end
    keys["<leader>dB"]()
    assert.equals(0, #points(buf))
    answers = { "x>0", ">=5" }
    keys["<leader>dB"]()
    assert.equals(">=5", points(buf)[1].hitCondition)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    answers = { "x={x}" }
    keys["<leader>dP"]()
    assert.equals("x={x}", points(buf)[2].logMessage)
    keys["<F9>"]()
    assert.equals(1, #points(buf))
    keys["<leader>db"]()
    assert.equals(2, #points(buf))
    keys["<leader>dX"]()
    restart()
    assert.equals(0, #points(buf))
  end)
  it("restores files loaded after setup without duplicating session restoration", function()
    local path = root .. "/late.cpp"
    local disk = Store.new(root .. "/store", root)
    disk.load()
    assert.is_true(disk.save({ [path] = { { line = 2, hitCondition = "3" } } }))
    restart()
    vim.fn.writefile({ "a", "b" }, path)
    vim.cmd.edit({ args = { path }, magic = { file = false } })
    local buf = vim.api.nvim_get_current_buf()
    buffers[#buffers + 1] = buf
    assert.equals(2, points(buf)[1].line)
    vim.api.nvim_exec_autocmds("SessionLoadPost", {})
    assert.equals(1, #points(buf))
  end)
end)
