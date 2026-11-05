describe("in-editor workflow references", function()
  local views, select, notify, current, filetypes, group
  before_each(function()
    views, filetypes = {}, 0
    current, select, notify = vim.api.nvim_get_current_win(), vim.ui.select, vim.notify
    group = vim.api.nvim_create_augroup("test_reference_filetypes", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      callback = function()
        filetypes = filetypes + 1
      end,
    })
  end)
  after_each(function()
    vim.api.nvim_del_augroup_by_id(group)
    vim.ui.select = select
    vim.notify = notify
    for _, view in ipairs(views) do
      view.close()
    end
    if vim.api.nvim_win_is_valid(current) then vim.api.nvim_set_current_win(current) end
  end)
  it(
    "reads the existing guide without editing its file or triggering filetype installers",
    function()
      local view = require("config.guides").show("quickstart")
      views[#views + 1] = view
      assert.same(
        vim.fn.readfile("docs/quick-start.md"),
        vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)
      )
      assert.is_false(vim.bo[view.buf].modifiable)
      assert.equals(0, filetypes)
      assert.is_truthy(
        vim.inspect(vim.api.nvim_win_get_config(view.win).footer):find("q / Esc", 1, true)
      )
      view.close()
      view.close()
      assert.is_true(vim.api.nvim_win_is_valid(current))
    end
  )
  it("opens the intended sections and provides native topic selection and completion", function()
    for _, name in ipairs({ "navigation", "buffers", "workspace" }) do
      local view = require("config.guides").show(name)
      views[#views + 1] = view
      local line = vim.api.nvim_win_get_cursor(view.win)[1]
      assert.is_true(line > 1, name)
      assert.is_truthy(vim.api.nvim_buf_get_lines(view.buf, line - 1, line, false)[1]:match("^## "))
      view.close()
    end
    assert.same({ "debugging" }, require("config.guides").complete("deb"))
    vim.ui.select = function(items, opts, callback)
      assert.is_truthy(opts.format_item(items[1]):find("workflows", 1, true))
      callback(nil)
    end
    require("config.guides").show()
  end)
  it("never closes a window that has been repurposed for another buffer", function()
    local view = require("config.readonly").open({ "Report" })
    local replacement = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(view.win, replacement)
    view.close()
    assert.is_true(vim.api.nvim_win_is_valid(view.win))
    vim.api.nvim_win_close(view.win, true)
  end)
  it("opens a direct guide if a selector integration fails", function()
    local warning
    vim.ui.select = function()
      error("selector unavailable")
    end
    vim.notify = function(message)
      warning = message
    end
    local view = require("config.guides").show()
    views[#views + 1] = view
    assert.same(
      vim.fn.readfile("docs/quick-start.md"),
      vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)
    )
    assert.is_truthy(warning:find(":ConfigHelp with Tab completion", 1, true))
  end)
  it("keeps both commands usable in a bare editor without optional plugins", function()
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({
      ("vim.opt.rtp:prepend(%q)"):format(vim.fn.getcwd()),
      "require('config.commands')",
      "vim.cmd.WorkspaceInfo(); vim.api.nvim_win_close(0, true)",
      "vim.cmd.ConfigHelp('quickstart'); vim.api.nvim_win_close(0, true)",
      "assert(not package.loaded.dap and not package.loaded['neo-tree.command'] and not package.loaded.scoper)",
      "print('bare references passed')",
    }, path)
    local result = vim
      .system({ vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", path }, { text = true })
      :wait(5000)
    vim.fn.delete(path)
    assert.equals(0, result.code, result.stderr)
    assert.is_truthy((result.stdout .. result.stderr):find("bare references passed", 1, true))
  end)
end)
