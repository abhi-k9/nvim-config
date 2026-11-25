describe("fold view freshness", function()
  local dir, viewdir, buf, source, view, original_stat
  before_each(function()
    original_stat = vim.uv.fs_stat
    vim.cmd("enew")
    viewdir = vim.o.viewdir
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/views", "p")
    vim.o.viewdir = dir .. "/views"
    source = dir .. "/fold.txt"
    vim.fn.writefile({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }, source)
    vim.api.nvim_cmd({ cmd = "edit", args = { source } }, {})
    buf = vim.api.nvim_get_current_buf()
    vim.wo.foldmethod = "manual"
    vim.cmd("2,5fold")
    vim.cmd("mkview")
    view = vim.o.viewdir .. "/" .. vim.fn.readdir(vim.o.viewdir)[1]
    vim.cmd("normal! zE")
  end)
  after_each(function()
    vim.uv.fs_stat = original_stat
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.o.viewdir = viewdir
    vim.fn.delete(dir, "rf")
  end)

  it("does not probe the source on entry or idle when no saved view exists", function()
    assert.are.equal(0, vim.fn.delete(view))
    local source_stats = 0
    vim.uv.fs_stat = function(path, ...)
      if path == source then source_stats = source_stats + 1 end
      return original_stat(path, ...)
    end

    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf, group = "user_fold_persistence" })
    vim.api.nvim_exec_autocmds("CursorHold", { buffer = buf, group = "user_fold_persistence" })

    assert.are.equal(0, source_stats)
    assert.are.equal(-1, vim.fn.foldclosed(2))
  end)

  it("preserves an existing view while large-file folding is disabled", function()
    vim.b[buf].big_file = true
    local contents = vim.fn.readfile(view)
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf, group = "user_fold_persistence" })
    assert.equals(-1, vim.fn.foldclosed(2))
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, group = "user_fold_persistence" })
    assert.same(contents, vim.fn.readfile(view))
  end)

  it("reasserts saved folds independently in two windows showing the same file", function()
    local first = vim.api.nvim_get_current_win()
    vim.cmd("split")
    local second = vim.api.nvim_get_current_win()
    local ok, err = pcall(function()
      for _, win in ipairs({ first, second }) do
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf, group = "user_fold_persistence" })
        vim.cmd("normal! zE")
      end
      for _, win in ipairs({ first, second }) do
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_exec_autocmds("CursorHold", { buffer = buf, group = "user_fold_persistence" })
        assert.equals(2, vim.fn.foldclosed(2))
      end
    end)
    vim.api.nvim_win_close(second, true)
    assert.is_true(ok, tostring(err))
  end)

  it("ignores a view when the file changed later in the same second", function()
    assert(vim.uv.fs_utime(view, 1000.1, 1000.1))
    assert(vim.uv.fs_utime(source, 1000.9, 1000.9))
    assert.are.equal(vim.fn.getftime(view), vim.fn.getftime(source))
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
    assert.are.equal(-1, vim.fn.foldclosed(2))
  end)

  it("restores folds when the view is newer within the same second", function()
    assert(vim.uv.fs_utime(view, 1000.9, 1000.9))
    assert(vim.uv.fs_utime(source, 1000.1, 1000.1))
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
    assert.are.equal(2, vim.fn.foldclosed(2))
  end)
end)
