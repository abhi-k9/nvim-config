describe("session scope ordering", function()
  local spec, core, first_buf, second_buf, first_tab, second_tab

  before_each(function()
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! %bwipeout!")
    core = require("scope.core")
    core.cache = {}
    spec = dofile(vim.fn.getcwd() .. "/lua/plugins/session.lua")
    vim.cmd("enew")
    first_buf, first_tab = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_tabpage()
    vim.api.nvim_buf_set_name(first_buf, vim.fn.tempname() .. "-first.txt")
    vim.cmd("tabnew")
    second_buf, second_tab = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_tabpage()
    vim.api.nvim_buf_set_name(second_buf, vim.fn.tempname() .. "-second.txt")
    vim.cmd("tabmove 0")
  end)

  after_each(function()
    vim.g.ScopeState = nil
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! %bwipeout!")
    core.cache = {}
  end)

  local function save_scopes()
    local hook = spec.opts.pre_save_cmds[3]
    if type(hook) == "string" then
      vim.cmd(hook)
    else
      hook()
    end
  end

  it("serializes in visual tab order after moving a tab", function()
    save_scopes()
    local saved = vim.json.decode(vim.g.ScopeState)
    assert.are.equal(vim.api.nvim_buf_get_name(second_buf), saved.cache[1][1])
    assert.are.equal(vim.api.nvim_buf_get_name(first_buf), saved.cache[2][1])
  end)

  it("restores moved tabs without assigning their buffers to another tab", function()
    save_scopes()
    spec.opts.post_restore_cmds[1]()
    assert.are.same({ second_buf }, core.cache[second_tab])
    assert.are.same({ first_buf }, core.cache[first_tab])
  end)

  it("restores pins after scope recreates a hidden buffer", function()
    local line = require("bufferline")
    line.setup({})
    local name = vim.fn.tempname() .. ",hidden.lua"
    vim.g.ScopeState = vim.json.encode({ cache = { {}, { name } } })
    vim.g.BufferlinePinnedBuffers = "bufferline-pins-v1:" .. vim.json.encode({ name })
    vim.api.nvim_exec_autocmds("SessionLoadPost", {})
    for _, hook in ipairs(spec.opts.post_restore_cmds) do
      hook()
    end
    local hidden = core.cache[first_tab][1]
    assert.is_true(line.is_pinned(hidden))
    assert.is_false(vim.bo[hidden].buflisted)
    vim.g.BufferlinePinnedBuffers = nil
  end)

  it("restores hidden filenames literally without executing Ex syntax", function()
    local name = vim.fn.tempname() .. " hidden | let g:session_filename_executed = 1"
    vim.g.ScopeState = vim.json.encode({ cache = { { name }, {} }, last_tab = 0 })
    vim.g.session_filename_executed = nil
    local ok, err = pcall(spec.opts.post_restore_cmds[1])
    local executed = vim.g.session_filename_executed
    vim.g.session_filename_executed = nil
    assert.is_nil(executed)
    assert.is_true(ok, tostring(err))
    assert.equals(name, vim.api.nvim_buf_get_name(core.cache[second_tab][1]))
  end)

  it("preserves all current buffer visibility when saved scope metadata is malformed", function()
    local hidden = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(hidden, vim.fn.tempname() .. "-hidden.txt")
    local before = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      before[b] = vim.bo[b].buflisted
    end
    vim.g.ScopeState = "{invalid JSON"
    local ok, err = pcall(function()
      spec.opts.post_restore_cmds[1]()
      spec.opts.post_restore_cmds[2]()
    end)
    assert.is_true(ok, tostring(err))
    for b, listed in pairs(before) do
      assert.equals(listed, vim.bo[b].buflisted)
    end
  end)

  it("does not toggle buffer visibility merely to capture the current tab", function()
    local events = 0
    local id = vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete" }, {
      callback = function()
        events = events + 1
      end,
    })
    local ok, err = pcall(save_scopes)
    vim.api.nvim_del_autocmd(id)
    assert.is_true(ok, tostring(err))
    assert.equals(0, events)
  end)

  it("does not publish a stale tab map if creating a buffer changes the layout", function()
    vim.g.ScopeState = vim.json.encode({ cache = { { vim.fn.tempname() .. "-new.txt" }, {} } })
    local opened, snapshot
    local id = vim.api.nvim_create_autocmd("BufNew", {
      once = true,
      callback = function()
        vim.cmd("tabnew")
        opened = vim.api.nvim_get_current_tabpage()
        snapshot = vim.deepcopy(core.cache)
      end,
    })
    local ok, err = pcall(spec.opts.post_restore_cmds[1])
    pcall(vim.api.nvim_del_autocmd, id)
    local after = vim.deepcopy(core.cache)
    if opened and vim.api.nvim_tabpage_is_valid(opened) then vim.cmd("tabclose!") end
    assert.is_true(ok, tostring(err))
    assert.is_not_nil(opened)
    assert.same(snapshot, after)
  end)

  it("saves and restores without scope.nvim while clearing stale scope metadata", function()
    vim.api.nvim_del_user_command("ScopeSaveState")
    vim.api.nvim_del_user_command("ScopeLoadState")
    local saved_core, saved_utils = package.loaded["scope.core"], package.loaded["scope.utils"]
    package.loaded["scope.core"], package.loaded["scope.utils"] = nil, nil
    vim.g.ScopeState = '{"cache":[["stale.txt"]]}'
    local ok, err = pcall(function()
      save_scopes()
      assert.is_nil(vim.g.ScopeState)
      spec.opts.post_restore_cmds[1]()
      spec.opts.post_restore_cmds[2]()
      assert.is_nil(package.loaded["scope.core"])
    end)
    package.loaded["scope.core"], package.loaded["scope.utils"] = saved_core, saved_utils
    require("scope").setup({})
    assert.is_true(ok, tostring(err))
  end)

  it("round-trips native literal filenames without optional plugins", function()
    local result = vim
      .system({
        vim.v.progpath,
        "--headless",
        "--noplugin",
        "-u",
        "NONE",
        "-l",
        "tests/fixtures/session_scope.lua",
      }, { text = true })
      :wait(5000)
    assert.equals(0, result.code, result.stderr)
    assert.is_truthy((result.stdout .. result.stderr):find("session scope fixture passed", 1, true))
  end)
end)
