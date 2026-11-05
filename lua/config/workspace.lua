-- An on-demand view of existing state, not another project/root authority.
local M = {}

local function attempt(fn)
  local ok, value = pcall(fn)
  return ok and value or nil, not ok and tostring(value) or nil
end

local function text(value)
  if type(value) == "string" then return (value:gsub("%c", " ")) end
  if value == nil then return "(none)" end
  if type(value) == "function" or type(value) == "thread" then return "(computed at launch)" end
  return type(value) == "table" and "(structured value)" or tostring(value)
end

function M.snapshot(win)
  win = win or vim.api.nvim_get_current_win()
  local data = { global_cwd = vim.fn.getcwd(-1, -1), clients = {}, trees = {} }
  if not vim.api.nvim_win_is_valid(win) then
    data.origin_error = "Original window was closed"
    return data
  end
  local tab = vim.api.nvim_win_get_tabpage(win)
  local buf = vim.api.nvim_win_get_buf(win)
  data.filename = vim.api.nvim_buf_get_name(buf)
  data.window_cwd = vim.api.nvim_win_call(win, vim.fn.getcwd)
  data.tab_cwd = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tab))
  data.project_root, data.project_error = attempt(function()
    return vim.api.nvim_win_call(win, function()
      return require("config.settings").project_root()
    end)
  end)
  data.debug_root, data.debug_error = attempt(function()
    return vim.api.nvim_win_call(win, function()
      return require("config.dap").root()
    end)
  end)
  if not data.debug_error then
    data.launch_file, data.launch_error = attempt(function()
      return vim.api.nvim_win_call(win, function()
        return require("config.dap").launch_file(data.debug_root)
      end)
    end)
  end

  local manager = package.loaded["neo-tree.sources.manager"]
  if type(manager) == "table" and type(manager.get_state_for_window) == "function" then
    for _, tree_win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      local state, err = attempt(function()
        return manager.get_state_for_window(tree_win)
      end)
      data.neotree_error = data.neotree_error or err
      if type(state) == "table" then
        data.trees[#data.trees + 1] = { source = state.name, root = state.path }
      end
    end
  end
  data.neotree = #data.trees > 0 and "visible"
    or manager and (type(manager) == "table" and type(manager.get_state_for_window) == "function" and "not visible (saved root not queried)" or "status API unavailable")
    or "not loaded"
  local scoper = package.loaded.scoper
  if type(scoper) == "table" and type(scoper.status_snapshot) == "function" then
    data.scope, data.scope_error = attempt(function()
      return vim.api.nvim_win_call(win, scoper.status_snapshot)
    end)
    if not data.scope_error and type(data.scope) ~= "table" then
      data.scope, data.scope_error = nil, "status snapshot unavailable"
    end
  end
  data.scoper = not scoper and "not loaded"
    or type(scoper) == "table" and type(scoper.status_snapshot) == "function" and "loaded"
    or "status API unavailable"

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    data.clients[#data.clients + 1] =
      { name = client.name, root = client.root_dir or (client.config or {}).root_dir }
  end
  table.sort(data.clients, function(a, b)
    return a.name < b.name
  end)
  local dap = package.loaded.dap
  data.dap = not dap and "not loaded"
    or type(dap) == "table" and type(dap.session) == "function" and "no active session"
    or "status API unavailable"
  if type(dap) == "table" and type(dap.session) == "function" then
    local session, err = attempt(dap.session)
    data.dap_error = err
    if type(session) == "table" then
      local config = type(session.config) == "table" and session.config or {}
      data.dap = "active"
      data.launch = {
        name = rawget(config, "name"),
        type = rawget(config, "type"),
        program = rawget(config, "program"),
        cwd = rawget(config, "cwd"),
      }
    end
  end
  return data
end

function M.lines(data)
  if data.origin_error then
    return {
      "Workspace context",
      "",
      data.origin_error
        .. ". Close this report and run :WorkspaceInfo from the source window again.",
      "Global cwd: " .. text(data.global_cwd),
    }
  end
  local lines = {
    "Workspace context (read-only)",
    "",
    "File: " .. text(data.filename),
    "Window cwd: " .. text(data.window_cwd),
    "Tab cwd: " .. text(data.tab_cwd),
    "Global cwd: " .. text(data.global_cwd),
    "Configured project root: " .. text(data.project_error or data.project_root),
    "",
    "Neo-tree: " .. text(data.neotree_error or data.neotree),
  }
  for _, tree in ipairs(data.trees) do
    lines[#lines + 1] = "  " .. text(tree.source) .. ": " .. text(tree.root)
  end
  lines[#lines + 1] = "Scoper: " .. text(data.scope_error or data.scoper)
  if data.scope then
    local scope = data.scope
    vim.list_extend(lines, {
      "  Project: " .. text(scope.root),
      "  Scope: " .. text(scope.scope) .. " (filter " .. (scope.enabled and "ON" or "OFF") .. ")",
      "  Explicit build: " .. text(scope.database),
    })
    local lsp = scope.lsp or {}
    lines[#lines + 1] = "  Resolved database: " .. text((lsp.selection or {}).path or lsp.source)
    lines[#lines + 1] = "  Preparation: " .. text(lsp.freshness or lsp.reason)
  end
  vim.list_extend(lines, { "", "Language servers attached to this file:" })
  if #data.clients == 0 then lines[#lines + 1] = "  (none; :checkhealth vim.lsp for setup)" end
  for _, client in ipairs(data.clients) do
    lines[#lines + 1] = "  " .. client.name .. " — " .. text(client.root)
  end
  vim.list_extend(lines, {
    "",
    "Debugger: " .. text(data.dap_error or data.dap),
    "  Next launch root: " .. text(data.debug_error or data.debug_root),
    "  Launch file: "
      .. (
        not data.launch_file and not data.launch_error and not data.debug_error and "disabled"
        or text(data.launch_error or data.launch_file)
      ),
  })
  if data.launch then
    for _, key in ipairs({ "name", "type", "program", "cwd" }) do
      lines[#lines + 1] = "  Active " .. key .. ": " .. text(data.launch[key])
    end
  end
  vim.list_extend(lines, {
    "",
    "These directories can differ by design. This report does not change them.",
    "Tool/setup details: :checkhealth config | Debug logs: :DapShowLog",
  })
  return lines
end

function M.show(win)
  win = win or vim.api.nvim_get_current_win()
  return require("config.readonly").open(M.lines(M.snapshot(win)), {
    title = "Workspace summary",
    footer = " q / Esc: close | r: refresh | h: guide ",
    actions = {
      r = {
        desc = "Refresh original workspace context",
        run = function()
          M.show(win)
        end,
      },
      h = {
        desc = "Read workspace guide",
        run = function()
          require("config.guides").show("workspace")
        end,
      },
    },
  })
end

return M
