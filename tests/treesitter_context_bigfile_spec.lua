describe("Treesitter context large-file policy", function()
  local context, original_options, original_get_parser, original_buf, buf, requests

  before_each(function()
    context = require("treesitter-context")
    original_options = vim.deepcopy(context.config)
    context.disable()
    original_buf = vim.api.nvim_get_current_buf()
    buf = vim.api.nvim_create_buf(true, false)
    local lines = { "local function example()" }
    for _ = 1, 40 do
      lines[#lines + 1] = "  local value = 1"
    end
    lines[#lines + 1] = "end"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    vim.cmd("noautocmd setlocal filetype=lua")
    vim.api.nvim_win_set_cursor(0, { 30, 0 })
    requests = 0
    original_get_parser = vim.treesitter.get_parser
    vim.treesitter.get_parser = function(target, ...)
      if target == buf and debug.traceback():find("treesitter-context/context.lua", 1, true) then
        requests = requests + 1
      end
      return original_get_parser(target, ...)
    end
  end)

  after_each(function()
    vim.treesitter.get_parser = original_get_parser
    context.disable()
    vim.api.nvim_set_current_buf(original_buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    context.setup(original_options)
  end)

  local function update()
    local specs = dofile(vim.fn.getcwd() .. "/lua/plugins/treesitter.lua")
    context.setup(specs[3].opts)
    vim.api.nvim_exec_autocmds("CursorMoved", { group = "treesitter_context_update" })
    vim.wait(200, function()
      return false
    end)
  end

  it("keeps sticky context functional for ordinary source files", function()
    update()
    assert.is_true(requests > 0)
  end)

  it("does not parse buffers that large-file mode excludes from Treesitter", function()
    vim.b[buf].big_file = true
    vim.treesitter.stop(buf)
    update()
    assert.equals(0, requests)
  end)

  it("rechecks large-file state when an existing buffer is read again", function()
    update()
    assert.is_true(requests > 0)
    vim.b[buf].big_file = true
    requests = 0
    vim.api.nvim_exec_autocmds("BufReadPost", {
      buffer = buf,
      group = "treesitter_context_update",
    })
    vim.api.nvim_exec_autocmds("CursorMoved", { group = "treesitter_context_update" })
    vim.wait(200, function()
      return false
    end)
    assert.equals(0, requests)

    vim.b[buf].big_file = nil
    vim.api.nvim_exec_autocmds("BufReadPost", {
      buffer = buf,
      group = "treesitter_context_update",
    })
    vim.api.nvim_exec_autocmds("CursorMoved", { group = "treesitter_context_update" })
    vim.wait(200, function()
      return false
    end)
    assert.is_true(requests > 0)
  end)
end)
