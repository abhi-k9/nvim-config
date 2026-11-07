-- Plugin-free native filesystem coverage for the local session bridge.
vim.opt.rtp:prepend(vim.fn.getcwd())
local function normal(path)
  return vim.fs.normalize(path, { expand_env = false })
end
local root = normal(vim.fn.tempname() .. " session $NVIM_SCOPE_LITERAL % #")
vim.fn.mkdir(root, "p")
vim.env.NVIM_SCOPE_LITERAL = "must-not-expand"

local ok, err = xpcall(function()
  local names = {
    root .. "/hidden $NVIM_SCOPE_LITERAL # % [x].txt",
    root .. "/other tab with spaces.txt",
  }
  if vim.fn.has("win32") == 0 then
    names[3] = root .. "/hidden | let g:session_filename_executed = 1"
  end
  for _, name in ipairs(names) do
    assert(vim.fn.writefile({ name }, name) == 0)
  end

  -- The existing buffer uses the name index; the others require literal bufadd.
  local existing = vim.fn.bufadd(names[1])
  vim.cmd("tabnew")
  local tabs = vim.api.nvim_list_tabpages()
  local current = vim.api.nvim_get_current_tabpage()
  local core = { cache = {}, last_tab = 99999 }
  core.on_tab_enter = function()
    for _, buf in ipairs(core.cache[vim.api.nvim_get_current_tabpage()] or {}) do
      vim.bo[buf].buflisted = true
    end
  end
  package.loaded["scope.core"] = core
  local first = { names[1], names[1] }
  if names[3] then first[#first + 1] = names[3] end
  vim.g.ScopeState = vim.json.encode({ cache = { first, { names[2] } }, last_tab = 99999 })
  local policy = require("config.session")
  assert(policy.restore_scopes())
  assert(core.cache[tabs[1]][1] == existing, "existing buffer not reused")
  assert(#core.cache[tabs[1]] == (names[3] and 2 or 1), "duplicate buffer not coalesced")
  assert(core.last_tab == 0, "stale tab handle retained")
  assert(vim.g.session_filename_executed == nil, "filename executed as Ex code")
  for tab, buffers in pairs(core.cache) do
    for _, buf in ipairs(buffers) do
      local name = normal(vim.api.nvim_buf_get_name(buf))
      assert(vim.tbl_contains(names, name), "filename expanded: " .. name)
      assert(vim.bo[buf].buflisted == (tab == current), "wrong tab visibility")
      vim.fn.bufload(buf)
      assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == name, "wrong file loaded")
    end
  end
  policy.save_scopes()
  local saved = vim.json.decode(vim.g.ScopeState)
  assert(normal(saved.cache[1][1]) == names[1] and normal(saved.cache[2][1]) == names[2])
  package.loaded["scope.core"] = nil
  policy.save_scopes()
  assert(vim.g.ScopeState == nil, "stale metadata retained without scope.nvim")
end, debug.traceback)
vim.cmd("silent! tabonly!")
vim.cmd("silent! %bwipeout!")
vim.fn.delete(root, "rf")
assert(ok, err)
print("session scope fixture passed")
