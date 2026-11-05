-- A local chooser over DAP's documented configuration providers. Inspect only
-- literal fields: dynamic launch values and adapter factories belong to DAP.
local M = {}

local function literal(value, fallback)
  if value == nil then return fallback or "(unset)" end
  if type(value) == "string" then return (value:gsub("%c", " ")) end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  return "(computed at launch)"
end

function M.adapter_status(dap, name)
  local registry = type(dap.adapters) == "table" and dap.adapters or {}
  local adapter = type(name) == "string" and rawget(registry, name) or nil
  if type(adapter) == "function" then return "dynamic adapter", false end
  if type(adapter) ~= "table" then
    if getmetatable(registry) then return "dynamic registration", false end
    return "adapter not configured", true
  end
  local command = rawget(adapter, "command")
  local executable = rawget(adapter, "executable")
  local options = rawget(adapter, "options")
  -- DAP/libuv own executable lookup in a custom spawn environment/directory.
  -- The editor's executable() result cannot establish availability there.
  local custom_context = type(options) == "table"
      and (rawget(options, "cwd") ~= nil or rawget(options, "env") ~= nil)
    or type(executable) == "table" and rawget(executable, "cwd") ~= nil
  if not command and type(executable) == "table" then command = rawget(executable, "command") end
  if type(command) == "string" and custom_context then
    return "custom launch context", false, command
  end
  if type(command) == "string" then
    local found = vim.fn.executable(command) == 1
    return found and "command found" or "missing command", not found, command
  end
  return command and "dynamic command" or "remote adapter", false
end

function M.describe(config, provider, dap)
  local status, unavailable, command = M.adapter_status(dap, rawget(config, "type"))
  local mt = getmetatable(config)
  if unavailable and type(mt) == "table" and type(rawget(mt, "__call")) == "function" then
    status, unavailable = "dynamic configuration", false
  end
  return {
    config = config,
    provider = provider,
    name = literal(rawget(config, "name"), "Unnamed launch"),
    kind = literal(rawget(config, "type")),
    request = literal(rawget(config, "request")),
    program = literal(
      rawget(config, "program"),
      rawget(config, "request") == "attach" and "(attach target)" or "(adapter default)"
    ),
    cwd = literal(rawget(config, "cwd"), "(adapter default)"),
    adapter = status,
    unavailable = unavailable,
    command = command,
  }
end

function M.label(row)
  return ("%s | %s/%s | %s | program=%s | cwd=%s"):format(
    row.name,
    row.kind,
    row.request,
    row.adapter,
    row.program,
    row.cwd
  )
end

local function unchanged(context, check_focus)
  return vim.api.nvim_win_is_valid(context.win)
    and vim.api.nvim_win_get_buf(context.win) == context.buf
    and vim.api.nvim_win_call(context.win, vim.fn.getcwd) == context.cwd
    and vim.fn.getcwd(-1, -1) == context.global_cwd
    and (not check_focus or vim.api.nvim_get_current_win() == context.win)
end

function M.collect(dap, buf, context)
  local rows = {}
  local providers = type(dap.providers) == "table" and dap.providers.configs
  if type(providers) ~= "table" then
    vim.notify(
      "Debugger configuration providers are unavailable. Check :Lazy or :ConfigHelp debugging.",
      vim.log.levels.WARN
    )
    return nil
  end
  local keys = vim.tbl_keys(providers)
  keys = vim.tbl_filter(function(key)
    return type(key) == "string"
  end, keys)
  table.sort(keys)
  for _, name in ipairs(keys) do
    if context and not unchanged(context, true) then
      vim.notify(
        "Launch discovery cancelled: the source context changed. Choose again from the source window.",
        vim.log.levels.INFO
      )
      return nil
    end
    local ok, configs = pcall(providers[name], buf)
    if context and not unchanged(context, true) then
      vim.notify(
        "Launch discovery cancelled: the source context changed. Choose again from the source window.",
        vim.log.levels.INFO
      )
      return nil
    end
    if ok and type(configs) == "table" and vim.islist(configs) then
      for _, config in ipairs(configs) do
        if type(config) == "table" then rows[#rows + 1] = M.describe(config, name, dap) end
      end
    else
      vim.notify(
        "Debug configurations from "
          .. name
          .. " could not be read: "
          .. (ok and "expected a list" or tostring(configs))
          .. ". Use :DapLoadLaunchJSON or :ConfigHelp debugging.",
        vim.log.levels.WARN
      )
    end
  end
  return rows
end

local function with_configs(callback)
  local ok, dap = pcall(require, "dap")
  if not ok or type(dap) ~= "table" then
    vim.notify(
      "Debugger unavailable. Check :Lazy; :ConfigHelp debugging describes setup.",
      vim.log.levels.WARN
    )
    return
  end
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local filetype = vim.b["dap-srcft"] or vim.bo[buf].filetype
  local context = {
    filetype = filetype,
    win = win,
    buf = buf,
    cwd = vim.fn.getcwd(),
    global_cwd = vim.fn.getcwd(-1, -1),
  }
  local available, async = pcall(require, "dap.async")
  if not available or type(async) ~= "table" or type(async.run) ~= "function" then
    vim.notify(
      "Debugger installation is incomplete. Check :Lazy; use :ConfigHelp debugging for setup.",
      vim.log.levels.WARN
    )
    return
  end
  async.run(function()
    local rows = M.collect(dap, buf, context)
    if not rows then return end
    if #rows == 0 then
      vim.notify(
        "No debug configurations for "
          .. filetype
          .. ". Use :DapLoadLaunchJSON, :DapEditLaunch or :ConfigHelp debugging.",
        vim.log.levels.INFO
      )
      return
    end
    callback(dap, rows, context)
  end)
end

function M.choose()
  with_configs(function(dap, rows, context)
    -- Always offer the choice, even for one row, so its setup is visible.
    local selected, err = pcall(
      vim.ui.select,
      rows,
      { prompt = "Debug launch (details: :DapLaunchInfo)", format_item = M.label },
      function(row)
        if not row then return end
        -- Another buffer/launch provider may have changed while the picker ran.
        if not vim.api.nvim_win_is_valid(context.win) then
          vim.notify(
            "Launch cancelled: the original window was closed. Choose a launch again.",
            vim.log.levels.INFO
          )
          return
        end
        if not unchanged(context) then
          vim.notify(
            "Launch cancelled: the source buffer or working directory changed. Choose a launch again.",
            vim.log.levels.INFO
          )
          return
        end
        local checked = M.describe(row.config, row.provider, dap)
        if checked.unavailable then
          vim.notify(
            "Cannot launch "
              .. row.name
              .. ": "
              .. checked.adapter
              .. (checked.command and " (" .. checked.command .. ")" or "")
              .. ". Use :checkhealth config, :Mason or :DapLoadLaunchJSON. Adapter logs: :DapShowLog.",
            vim.log.levels.WARN
          )
          return
        end
        local ran, err = pcall(vim.api.nvim_win_call, context.win, function()
          dap.run(row.config, { filetype = context.filetype })
        end)
        if not ran then
          vim.notify(
            "Debug launch failed: "
              .. tostring(err)
              .. ". Inspect :DapShowLog and :DapLoadLaunchJSON; :ConfigHelp debugging explains setup.",
            vim.log.levels.ERROR
          )
        end
      end
    )
    if not selected then
      vim.notify(
        "Debug selector unavailable: "
          .. tostring(err)
          .. ". Inspect :DapLaunchInfo; check :Lazy or :ConfigHelp debugging. No launch was started.",
        vim.log.levels.WARN
      )
    end
  end)
end

function M.start()
  local ok, dap = pcall(require, "dap")
  if ok and type(dap) == "table" then
    local inspected, active = pcall(function()
      if type(dap.session) == "function" and dap.session() then return true end
      local sessions = type(dap.sessions) == "function" and dap.sessions()
      return type(sessions) == "table" and next(sessions) ~= nil
    end)
    if not inspected then
      vim.notify(
        "Cannot inspect debugger sessions: "
          .. tostring(active)
          .. ". Inspect :DapShowLog or :Lazy before retrying.",
        vim.log.levels.WARN
      )
      return
    end
    if active then
      if type(dap.continue) == "function" then return dap.continue() end
      vim.notify(
        "Debugger continue is unavailable. Check :Lazy or :ConfigHelp debugging.",
        vim.log.levels.WARN
      )
      return
    end
  end
  return M.choose()
end

function M.info()
  with_configs(function(_, rows, context)
    local lines = {
      "Debug launch configurations (before expansion)",
      "",
      "Providers are read; launch-field functions, inputs and environment substitutions stay unevaluated.",
      "Command presence does not guarantee adapter/runtime compatibility.",
      "Invocation cwd: " .. literal(context.cwd),
      "",
    }
    for _, row in ipairs(rows) do
      vim.list_extend(lines, {
        row.name .. " — " .. row.kind .. "/" .. row.request,
        "  Provider: " .. row.provider,
        "  Program: " .. row.program,
        "  Working directory: " .. row.cwd,
        "  Adapter: " .. row.adapter .. (row.command and " — " .. row.command or ""),
        "",
      })
    end
    require("config.readonly").open(lines, { title = "Debug launch details" })
  end)
end

function M.edit()
  local config = require("config.dap")
  local ok, path = pcall(config.launch_file)
  if not ok then
    vim.notify(
      "Cannot resolve launch file: "
        .. tostring(path)
        .. ". Review local settings with :ConfigHelp debugging.",
      vim.log.levels.WARN
    )
    return
  end
  if not path then
    vim.notify(
      "Project launch files are disabled in local settings. Use :ConfigHelp debugging to review the policy.",
      vim.log.levels.INFO
    )
    return
  end
  -- Opening a new split preserves unsaved code. No directory/file is written.
  vim.cmd.split({ args = { path } })
end

return M
