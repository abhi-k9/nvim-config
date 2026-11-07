-- Session policy and literal per-tab buffer persistence.
-- auto-session's pre-save hooks run after panel cleanup and cannot distinguish
-- manual from automatic saves. Apply our automatic-only veto at its public
-- save boundary instead, before it can change the visible layout.
local M = {}
local owners = setmetatable({}, { __mode = "kv" })

function M.suppressed(session_name)
  -- A normal automatic save passes nil; restore passes a display name.
  -- This context's cwd is active/window-local, while backend session names
  -- are based on the global cwd unless the user explicitly names a session.
  local predicate = require("config.settings").get("sessions.suppress")
  return type(predicate) == "function"
    and predicate({ cwd = vim.fn.getcwd(), session_name = session_name }) == true
end

function M.attach(session)
  if type(session.save_session) ~= "function" then return false end
  local owned = owners[session]
  if owned and session.save_session == owned.wrapper then return true end
  owned = { original = session.save_session }
  local function wrapper(name, opts, ...)
    if opts and opts.is_autosave and M.suppressed(name) then return false end
    return owned.original(name, opts, ...)
  end
  owned.wrapper = wrapper
  session.save_session = wrapper
  owners[session] = owned
  return true
end

function M.detach(session)
  local owned = owners[session]
  if owned and session.save_session == owned.wrapper then session.save_session = owned.original end
  owners[session] = nil
end

local function scope_core()
  if require("config.settings").get("sessions.global_buffers", false) then return nil end
  -- A save/restore must not load a disabled or unavailable optional plugin.
  local core = package.loaded["scope.core"]
  if
    type(core) == "table"
    and type(core.cache) == "table"
    and type(core.on_tab_enter) == "function"
  then
    return core
  end
end

-- Own the serialization boundary: the pinned upstream loader concatenates
-- filenames into :badd and scans all buffers again for each saved filename.
-- Keep its JSON shape while using literal APIs and visual tab order locally.
function M.save_scopes()
  vim.g.ScopeState = nil
  local core = scope_core()
  if not core then return end
  local current = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then current[#current + 1] = buf end
  end
  core.cache[vim.api.nvim_get_current_tabpage()] = current
  local cache = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local names = {}
    for _, buf in ipairs(type(core.cache[tab]) == "table" and core.cache[tab] or {}) do
      if vim.api.nvim_buf_is_valid(buf) then names[#names + 1] = vim.api.nvim_buf_get_name(buf) end
    end
    cache[#cache + 1] = names
  end
  -- last_tab is a runtime handle, not a portable session identifier.
  vim.g.ScopeState = vim.json.encode({ cache = cache, last_tab = 0 })
end

function M.restore_scopes()
  local core = scope_core()
  if not core or vim.g.ScopeState == nil then return end
  local encoded, tabs, current =
    vim.g.ScopeState, vim.api.nvim_list_tabpages(), vim.api.nvim_get_current_tabpage()
  local ok, cache = pcall(function()
    local saved = vim.json.decode(encoded)
    assert(
      type(saved) == "table" and type(saved.cache) == "table" and vim.islist(saved.cache),
      "expected a list of tab buffer lists"
    )
    -- Validate the entire input before creating buffers or changing visibility.
    for _, names in ipairs(saved.cache) do
      assert(type(names) == "table" and vim.islist(names), "expected a tab buffer list")
      for _, name in ipairs(names) do
        assert(
          type(name) == "string" and not name:find("%z"),
          "expected a filename without NUL bytes"
        )
      end
    end
    local by_name, restored = {}, {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      by_name[vim.api.nvim_buf_get_name(buf)] = buf
    end
    for index, tab in ipairs(tabs) do
      local buffers, seen = {}, {}
      for _, name in ipairs(saved.cache[index] or {}) do
        if name ~= "" then
          local buf = by_name[name] or vim.fn.bufadd(name)
          assert(buf > 0 and vim.api.nvim_buf_is_valid(buf), "could not add saved buffer")
          by_name[name] = buf
          if not seen[buf] then
            buffers[#buffers + 1], seen[buf] = buf, true
          end
        end
      end
      restored[tab] = buffers
    end
    return restored
  end)
  if not ok then
    vim.notify(
      "Session buffer groups could not be restored: " .. tostring(cache),
      vim.log.levels.WARN
    )
    return false
  end
  -- bufadd can fire BufNew hooks, including a nested session or tab switch.
  if
    scope_core() ~= core
    or vim.g.ScopeState ~= encoded
    or vim.api.nvim_get_current_tabpage() ~= current
    or not vim.deep_equal(vim.api.nvim_list_tabpages(), tabs)
  then
    vim.notify(
      "Session buffer groups skipped: the session or tabs changed during restore",
      vim.log.levels.WARN
    )
    return false
  end
  core.cache, core.last_tab = cache, 0
  local visible = {}
  for _, buf in ipairs(cache[vim.api.nvim_get_current_tabpage()] or {}) do
    visible[buf] = true
  end
  -- Retained buffers stay listed: avoid redundant BufDelete/BufAdd events.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and not visible[buf] then
      vim.bo[buf].buflisted = false
    end
  end
  core.on_tab_enter()
  return true
end

return M
