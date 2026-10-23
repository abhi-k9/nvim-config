describe("exact current-file history mappings", function()
  local original, command, notify, buffer, spec, calls, notices, root

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    original = vim.api.nvim_get_current_buf()
    buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "one", "two", "three" })
    spec, calls, notices = dofile(vim.fn.getcwd() .. "/lua/plugins/git.lua")[2], {}, {}
    command, notify = vim.api.nvim_cmd, vim.notify
    vim.api.nvim_cmd = function(cmd, opts)
      if cmd.cmd ~= "DiffviewFileHistory" then return command(cmd, opts) end
      calls[#calls + 1] = cmd
    end
    vim.notify = function(message)
      notices[#notices + 1] = message
    end
  end)

  after_each(function()
    vim.api.nvim_cmd, vim.notify = command, notify
    vim.cmd.normal({ "\27", bang = true })
    if vim.api.nvim_buf_is_valid(original) then vim.api.nvim_set_current_buf(original) end
    vim.api.nvim_buf_delete(buffer, { force = true })
    vim.fn.delete(root, "rf")
  end)

  local function action(lhs, mode)
    for _, key in ipairs(spec.keys) do
      if key[1] == lhs and (key.mode or "n") == (mode or "n") then return key[2] end
    end
    error("missing history mapping")
  end

  it("preserves ordinary backend-neutral current-file and pinned-working-copy commands", function()
    vim.api.nvim_buf_set_name(buffer, root .. "/odd|percent%#quote'.lua")
    require("lazy.core.loader").load("diffview-plus.nvim", { cmd = "spec" })
    local git = require("diffview.vcs.adapters.git").GitAdapter
    local paths = git.get_repo_paths({ "%" })
    assert.same({ vim.api.nvim_buf_get_name(buffer) }, paths)
    action("<leader>gh")()
    action("<leader>gl")()
    assert.same({ "%" }, calls[1].args)
    assert.same({ "--pin-local", "%" }, calls[2].args)
    assert.same({}, notices)
  end)

  it("refuses glob and magic-prefix names before invoking any VCS backend", function()
    for _, name in ipairs({ "file[ab].lua", "file*.lua", "file?.lua", ":(exclude)file.lua" }) do
      vim.api.nvim_buf_set_name(buffer, root .. "/" .. name)
      action("<leader>gh")()
      action("<leader>gl")()
    end
    assert.same({}, calls)
    assert.equals(8, #notices)
    assert.is_truthy(notices[1]:find("cannot preserve this filename literally", 1, true))
  end)

  it("refuses a POSIX backslash filename before the adapter changes its separator", function()
    if vim.fn.has("win32") == 1 then
      pending("POSIX filename semantics")
      return
    end
    vim.api.nvim_buf_set_name(buffer, root .. "/back\\slash.lua")
    action("<leader>gh")()
    assert.same({}, calls)
    assert.equals(1, #notices)
  end)

  it("passes the active visual line range for an ordinary filename", function()
    vim.api.nvim_buf_set_name(buffer, root .. "/ordinary.lua")
    vim.cmd.normal({ "ggVj", bang = true })
    action("<leader>gh", "x")()
    assert.same({ 1, 2 }, calls[1].range)
    assert.same({}, calls[1].args)
    assert.equals("n", vim.api.nvim_get_mode().mode)
  end)

  it("also guards selected-line history and rejects unnamed or URI buffers", function()
    action("<leader>gh")()
    vim.api.nvim_buf_set_name(buffer, "diffview://revision/file.lua")
    action("<leader>gh")()
    vim.api.nvim_buf_set_name(buffer, root .. "/file[ab].lua")
    action("<leader>gh", "x")()
    assert.same({}, calls)
    assert.equals(3, #notices)
  end)

  it("leaves repository history and raw Diffview commands available", function()
    assert.equals("<cmd>DiffviewFileHistory<cr>", action("<leader>gH"))
    assert.is_true(vim.tbl_contains(spec.cmd, "DiffviewFileHistory"))
  end)
end)
