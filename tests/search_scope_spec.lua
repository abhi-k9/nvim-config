describe("current-file search scope", function()
  local grug, original_open, original_notify, old_cwd, root, captured
  local callback
  for _, key in ipairs(require("plugins.search").keys) do
    if key[1] == "<leader>sf" then callback = key[2] end
  end

  before_each(function()
    require("lazy.core.loader").load("grug-far.nvim", { cmd = "spec" })
    grug = require("grug-far")
    original_open, original_notify = grug.open, vim.notify
    grug.open = function(opts)
      captured = opts
    end
    vim.notify = function() end
    captured = nil
    old_cwd = vim.fn.getcwd()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.cmd.cd(root)
    vim.cmd("enew!")
  end)

  after_each(function()
    grug.open, vim.notify = original_open, original_notify
    vim.cmd("bwipeout!")
    vim.cmd.cd(old_cwd)
    vim.fn.delete(root, "rf")
  end)

  it("keeps a single-character file confined in the real ripgrep backend", function()
    vim.fn.writefile({ "AUDIT_SENTINEL" }, root .. "/x")
    vim.fn.writefile({ "AUDIT_SENTINEL" }, root .. "/outside.txt")
    vim.cmd.edit("x")
    callback()
    local args = require("grug-far.engine.ripgrep.getArgs")({
      search = "AUDIT_SENTINEL",
      replacement = "",
      flags = "",
      filesFilter = "",
      paths = captured.prefills.paths,
    }, {
      engines = { ripgrep = { path = "rg", extraArgs = "" } },
      __grug_far_context__ = { options = {} },
    }, {})
    local command = { "rg" }
    vim.list_extend(command, args)
    local result = vim.system(command, { cwd = root, text = true }):wait()
    assert.equals(0, result.code, result.stderr)
    assert.is_not_nil(result.stdout:find("AUDIT_SENTINEL", 1, true))
    assert.is_nil(result.stdout:find("outside.txt", 1, true))
  end)

  it("round-trips spaces through the pinned path parser", function()
    local file = root .. "/file with spaces.lua"
    vim.fn.writefile({ "return true" }, file)
    vim.cmd.edit(file)
    callback()
    assert.are.same({ file }, require("grug-far.utils").splitPaths(captured.prefills.paths))
  end)

  it("refuses an unnamed buffer instead of prefilling the whole project", function()
    callback()
    assert.is_nil(captured)
  end)

  it("refuses a named buffer that has not been saved", function()
    vim.api.nvim_buf_set_name(0, root .. "/unsaved.lua")
    callback()
    assert.is_nil(captured)
  end)

  it("refuses special buffers even when their names are readable files", function()
    local file = root .. "/scratch.lua"
    vim.fn.writefile({ "return true" }, file)
    vim.api.nvim_buf_set_name(0, file)
    vim.bo.buftype = "nofile"
    callback()
    assert.is_nil(captured)
  end)

  it("refuses names that the backend would split into multiple paths", function()
    if vim.fn.has("win32") == 1 then return end
    local file = root .. "/line\nbreak.lua"
    vim.fn.writefile({ "return true" }, file)
    vim.api.nvim_buf_set_name(0, file)
    callback()
    assert.is_nil(captured)
  end)
end)
