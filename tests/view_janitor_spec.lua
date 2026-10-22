describe("view janitor ownership", function()
  local dir, viewdir, buf
  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/views", "p")
    vim.cmd("enew")
    viewdir = vim.o.viewdir
    vim.o.viewdir = dir .. "/views"
  end)
  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.o.viewdir = viewdir
    vim.fn.delete(dir, "rf")
  end)

  it("removes old encoded views while keeping unrelated files and recent views", function()
    local old = os.time() - 100 * 86400
    local source = dir .. "/source.txt"
    vim.fn.writefile({ "a real file" }, source)
    vim.api.nvim_cmd({ cmd = "edit", args = { source } }, {})
    buf = vim.api.nvim_get_current_buf()
    vim.cmd("mkview")
    vim.cmd("mkview 1")
    local native_views = vim.fn.readdir(vim.o.viewdir)
    assert.are.equal(2, #native_views)
    for _, name in ipairs(vim.list_extend(vim.deepcopy(native_views), { "README.txt", "notes=" })) do
      local path = vim.o.viewdir .. "/" .. name
      vim.fn.writefile({ "fixture" }, path)
      assert(vim.uv.fs_utime(path, old, old))
    end
    local recent = vim.o.viewdir .. "/=+tmp=+recent.txt="
    vim.fn.writefile({ "recent view" }, recent)
    local nested = vim.o.viewdir .. "/=+tmp=+directory="
    vim.fn.mkdir(nested)
    assert(vim.uv.fs_utime(nested, old, old))

    vim.api.nvim_exec_autocmds("VimLeavePre", { group = "user_view_janitor" })

    for _, name in ipairs(native_views) do
      assert.is_nil(vim.uv.fs_stat(vim.o.viewdir .. "/" .. name))
    end
    assert.is_not_nil(vim.uv.fs_stat(vim.o.viewdir .. "/README.txt"))
    assert.is_not_nil(vim.uv.fs_stat(vim.o.viewdir .. "/notes="))
    assert.is_not_nil(vim.uv.fs_stat(recent))
    assert.is_not_nil(vim.uv.fs_stat(nested))
  end)
end)
