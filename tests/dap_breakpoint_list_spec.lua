describe("debugger breakpoint list", function()
  local exists, command, notify, win, buf, dap, show, trouble, messages

  before_each(function()
    require("lazy.core.loader").load("nvim-dap", { cmd = "spec" })
    dap = require("dap")
    dap.clear_breakpoints()
    win = vim.api.nvim_get_current_win()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".cpp")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int main() {}" })
    dap.set_breakpoint()
    local spec = dofile(vim.fn.getcwd() .. "/lua/plugins/dap.lua")
    for _, key in ipairs(spec[1].keys) do
      if key[1] == "<leader>dx" then show = key[2] end
    end
    assert.is_function(show)
    exists, command, notify = vim.fn.exists, vim.cmd, vim.notify
    trouble, messages = "missing", {}
    vim.fn.exists = function(name)
      if name == ":Trouble" then return trouble == "missing" and 0 or 2 end
      return exists(name)
    end
    vim.cmd = function(cmd)
      if cmd == "Trouble qflist open" then
        if trouble ~= "available" then error("Trouble unavailable") end
        trouble = "opened"
        return
      end
      return command(cmd)
    end
    vim.notify = function(message, level)
      messages[#messages + 1] = { message, level }
    end
  end)

  after_each(function()
    vim.fn.exists, vim.cmd, vim.notify = exists, command, notify
    vim.cmd("cclose")
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
    dap.clear_breakpoints()
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end)

  local function expect_quickfix()
    local list = vim.fn.getqflist({ items = 0, winid = 0 })
    assert.equals(1, #list.items)
    assert.equals(buf, list.items[1].bufnr)
    assert.equals(1, list.items[1].lnum)
    assert.is_true(list.winid > 0)
    assert.equals(list.winid, vim.api.nvim_get_current_win())
  end

  it("opens native quickfix with the real breakpoints when Trouble is missing", function()
    show()
    expect_quickfix()
    assert.same({}, messages)
  end)

  it("reports Trouble failures and still opens the real breakpoint list", function()
    trouble = "broken"
    show()
    expect_quickfix()
    assert.equals(1, #messages)
    assert.is_truthy(messages[1][1]:find("Trouble unavailable", 1, true))
    assert.equals(vim.log.levels.WARN, messages[1][2])
  end)

  it("keeps the preferred Trouble view when it is available", function()
    trouble = "available"
    show()
    assert.equals("opened", trouble)
    assert.equals(1, #vim.fn.getqflist())
    assert.equals(0, vim.fn.getqflist({ winid = 0 }).winid)
    assert.same({}, messages)
  end)

  it("reports an empty breakpoint list without opening another window", function()
    dap.clear_breakpoints()
    show()
    assert.equals(win, vim.api.nvim_get_current_win())
    assert.equals(0, vim.fn.getqflist({ winid = 0 }).winid)
    assert.equals(1, #messages)
    assert.is_truthy(messages[1][1]:find("No breakpoints", 1, true))
    assert.equals(vim.log.levels.INFO, messages[1][2])
  end)
end)
