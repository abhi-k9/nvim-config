describe("Trouble cursor lookup after window teardown", function()
  local View, Window, view, buf, win
  before_each(function()
    require("lazy").load({ plugins = { "trouble.nvim" } })
    View, Window = require("trouble.view"), require("trouble.view.window")
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "second" })
    vim.cmd("botright split")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    local window = Window.new({})
    window.buf, window.win = buf, win
    view = setmetatable({
      win = window,
      renderer = {
        at = function(_, row)
          return { row = row }
        end,
      },
    }, View)
  end)
  after_each(function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end)

  it("preserves live cursor and explicit-row lookups", function()
    vim.api.nvim_win_set_cursor(win, { 2, 0 })
    assert.same({ row = 2 }, view:at())
    assert.same({ row = 1 }, view:at({ 1, 0 }))
  end)

  it("ignores a queued lookup after window closure with a surviving buffer", function()
    local done, ok, result = false
    vim.schedule(function()
      ok, result = pcall(View.at, view)
      done = true
    end)
    -- Match Trouble Window:close: the window id is cleared, but the buffer
    -- may survive (e.g. it is still displayed elsewhere).
    view.win:close()
    assert.is_true(vim.api.nvim_buf_is_valid(buf))
    assert.is_true(vim.wait(1000, function()
      return done
    end))
    assert.is_true(ok, tostring(result))
    assert.same({}, result)
    assert.same({ row = 2 }, view:at({ 2, 0 }))
  end)

  it("ignores an invalid window id and a window repurposed for another buffer", function()
    vim.cmd("enew")
    assert.same({}, view:at())
    vim.api.nvim_win_close(win, true)
    assert.same({}, view:at())
  end)

  it("does not suppress renderer errors", function()
    view.renderer.at = function()
      error("renderer failure")
    end
    assert.has_error(function()
      view:at()
    end, "renderer failure")
  end)

  it("does not stack the guard on repeated configuration", function()
    local spec = require("plugins.trouble")
    spec.config(nil, spec.opts)
    local first = View.at
    spec.config(nil, spec.opts)
    assert.equals(first, View.at)
  end)
end)

describe("Trouble references reopening", function()
  local source, original, buf, panel, editor
  before_each(function()
    require("lazy").load({ plugins = { "trouble.nvim" } })
    source = require("trouble.sources.lsp")
    original = source.get.references
    vim.cmd("new")
    editor, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "reference" })
    source.get.references = function(cb)
      cb({ require("trouble.item").new({ source = "lsp.references", buf = buf, pos = { 1, 0 } }) })
    end
  end)
  after_each(function()
    if panel then panel:close() end
    source.get.references = original
    if vim.api.nvim_win_is_valid(editor) then vim.api.nvim_win_close(editor, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end)
  it("keeps one reference visible and reopens after its source window closes", function()
    local Trouble = require("trouble")
    panel = Trouble.open({ mode = "lsp_references", new = true })
    assert.is_true(vim.wait(2000, function()
      return panel:is_open() and panel:count() == 1
    end))
    assert.is_false(panel.opts.auto_jump)
    vim.api.nvim_win_close(editor, true)
    -- Leave enough time for queued updates caused by closing the editor.
    vim.wait(150, function()
      return false
    end)
    Trouble.close({ mode = "lsp_references" })
    assert.is_falsy(panel:is_open())
    vim.cmd("new")
    editor = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(editor, buf)
    panel = Trouble.open({ mode = "lsp_references" })
    assert.is_true(vim.wait(2000, function()
      return panel:is_open() and panel:count() == 1
    end))
    vim.wait(150, function()
      return false
    end)
    assert.is_true(panel:is_open())
  end)
end)
