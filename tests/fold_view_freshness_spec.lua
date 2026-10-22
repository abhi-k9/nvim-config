describe("fold view freshness", function()
  local dir, viewdir, buf, source, view
  before_each(function()
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
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.o.viewdir = viewdir
    vim.fn.delete(dir, "rf")
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
