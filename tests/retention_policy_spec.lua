local settings = require("config.settings")

describe("owned file retention policies", function()
  local dir, viewdir, logfile, log
  before_each(function()
    settings.reset()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/views", "p")
    viewdir = vim.o.viewdir
    vim.o.viewdir = dir .. "/views"
    log = require("vim.lsp.log")
    logfile = log.get_filename
    log.get_filename = function()
      return dir .. "/lsp.log"
    end
  end)
  after_each(function()
    settings.reset()
    vim.o.viewdir = viewdir
    log.get_filename = logfile
    vim.fn.delete(dir, "rf")
  end)

  it("keeps old views when cleanup is disabled", function()
    settings.configure({ retention = { views_days = false } })
    local path = vim.o.viewdir .. "/=+tmp=+old.txt="
    vim.fn.writefile({ "view" }, path)
    local old = os.time() - 100 * 86400
    assert(vim.uv.fs_utime(path, old, old))
    vim.api.nvim_exec_autocmds("VimLeavePre", { group = "user_view_janitor" })
    assert.is_not_nil(vim.uv.fs_stat(path))
  end)

  it("applies a custom view cutoff only to recognized native view names", function()
    settings.configure({ retention = { views_days = 1 } })
    local path = vim.o.viewdir .. "/=+tmp=+old.txt="
    local unrelated = vim.o.viewdir .. "/notes.txt"
    for _, target in ipairs({ path, unrelated }) do
      vim.fn.writefile({ "fixture" }, target)
      local old = os.time() - 2 * 86400
      assert(vim.uv.fs_utime(target, old, old))
    end
    vim.api.nvim_exec_autocmds("VimLeavePre", { group = "user_view_janitor" })
    assert.is_nil(vim.uv.fs_stat(path))
    assert.is_not_nil(vim.uv.fs_stat(unrelated))
  end)

  it("disables startup log rotation or applies an explicit byte threshold", function()
    vim.fn.writefile({ "a log bigger than eight bytes" }, dir .. "/lsp.log")
    settings.configure({ retention = { log_max_bytes = false } })
    dofile("lua/config/autocmds/lsplog.lua")
    assert.is_not_nil(vim.uv.fs_stat(dir .. "/lsp.log"))
    assert.is_nil(vim.uv.fs_stat(dir .. "/lsp.log.old"))
    settings.configure({ retention = { log_max_bytes = 8 } })
    dofile("lua/config/autocmds/lsplog.lua")
    assert.is_nil(vim.uv.fs_stat(dir .. "/lsp.log"))
    assert.are.same({ "a log bigger than eight bytes" }, vim.fn.readfile(dir .. "/lsp.log.old"))
  end)
end)
