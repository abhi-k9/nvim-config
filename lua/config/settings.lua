-- Machine-local customization is read before core behavior or plugin setup.
-- Project overlays are registered explicitly by trusted code; this module
-- never searches for, trusts, or executes configuration in a project.
local M = {}
local values, projects, captured = {}, {}, {}
local source, loaded = nil, false

local function copy(value)
  return type(value) == "table" and vim.deepcopy(value) or value
end

local function at(tbl, path)
  for part in path:gmatch("[^.]+") do
    if type(tbl) ~= "table" then return nil end
    tbl = tbl[part]
  end
  return tbl
end

local function merge(base, override)
  if type(base) ~= "table" or type(override) ~= "table" then return copy(override) end
  if next(override) == nil or vim.islist(base) or vim.islist(override) then
    return copy(override)
  end
  local result = copy(base)
  for key, value in pairs(override) do
    result[key] = result[key] ~= nil and merge(result[key], value) or copy(value)
  end
  return result
end

local function global_cwd()
  return vim.fn.getcwd(-1, -1)
end

local function absolute(path, base)
  -- Do not expand $NAME, %, # or a literal POSIX backslash in real paths.
  if path == "~" or path:sub(1, 2) == "~/" or path:sub(1, 2) == "~\\" then
    path = (vim.uv.os_homedir() or "~") .. path:sub(2)
  end
  local windows = vim.fn.has("win32") == 1
  if windows and path:match("^%a:[^/\\]") then
    error("Use a fully qualified Windows root; drive-relative paths are ambiguous: " .. path)
  end
  if windows and path:sub(1, 1) == "\\" and path:sub(1, 2) ~= "\\\\" then
    local drive = base:match("^%a:")
    assert(drive, "Use a fully qualified Windows root when the project is on a UNC share")
    path = drive .. path
  end
  local is_absolute = path:sub(1, 1) == "/"
    or windows and (path:match("^%a:[/\\]") or path:sub(1, 2) == "\\\\")
  if not is_absolute then path = vim.fs.joinpath(base, path) end
  return vim.fs.normalize(path, { expand_env = false })
end

local function key(path)
  path = absolute(path, global_cwd())
  return vim.fn.has("win32") == 1 and path:lower() or path
end

local function matching_projects()
  local cwd, out = key(global_cwd()), {}
  for root, item in pairs(projects) do
    local prefix = root:sub(-1) == "/" and root or root .. "/"
    if cwd == root or cwd:sub(1, #prefix) == prefix then out[#out + 1] = item end
  end
  table.sort(out, function(a, b)
    return #a.root < #b.root
  end)
  return out
end

-- Exact machine values replace fallback values, including false and empty
-- lists. Matching project overlays merge dictionaries; lists replace.
function M.get(path, fallback)
  local section, tail = path:match("^([^.]+)%.?(.*)$")
  local effective = values[section]
  for _, project in ipairs(matching_projects()) do
    local override = project.values[section]
    if override ~= nil then effective = merge(effective, override) end
  end
  local value
  if tail == "" then
    value = effective
  else
    value = at(effective, tail)
  end
  if value == nil then value = fallback end
  return copy(value)
end

function M.configure(opts)
  assert(type(opts) == "table", "configuration must be a table")
  for name, value in pairs(opts) do
    values[name] = values[name] ~= nil and merge(values[name], value) or copy(value)
  end
end

function M.for_project(root, opts)
  assert(type(root) == "string" and root ~= "", "project root must be a nonempty path")
  assert(type(opts) == "table", "project configuration must be a table")
  local identity = key(root)
  projects[identity] = { root = identity, values = copy(opts) }
end

function M.reset()
  values, projects, captured = {}, {}, {}
  source, loaded = nil, false
end

function M.load(path)
  values, projects = {}, {}
  source, loaded = path, true
  if path == false or path == nil then return true end
  assert(type(path) == "string", "local configuration path must be a string or false")
  local stat, stat_err, stat_code = vim.uv.fs_stat(path)
  if not stat and stat_code == "ENOENT" then return true end
  if not stat then
    vim.notify(
      "Local configuration could not be read: " .. path .. " (" .. tostring(stat_err) .. ")",
      vim.log.levels.ERROR
    )
    return false, stat_err
  end
  local ok, result = pcall(dofile, path)
  if ok and type(result) == "table" then
    values = copy(result)
    return true
  end
  values, projects = {}, {}
  local message = ok and "expected a returned table" or tostring(result)
  vim.notify(
    "Local configuration could not be loaded: " .. path .. " (" .. message .. ")",
    vim.log.levels.ERROR
  )
  return false, message
end

function M.capture_options()
  captured = {}
  for name, info in pairs(vim.api.nvim_get_all_options_info()) do
    if info.was_set then
      local ok, value = pcall(vim.api.nvim_get_option_value, name, { scope = "global" })
      if ok then captured[name] = value end
    end
  end
end

function M.apply_globals()
  local globals = M.get("globals", {})
  if type(globals) ~= "table" then
    vim.notify("Local globals must be a table", vim.log.levels.ERROR)
    return false
  end
  for name, value in pairs(globals) do
    local ok, err = pcall(function()
      vim.g[name] = copy(value)
    end)
    if not ok then
      vim.notify(
        "Invalid local global " .. tostring(name) .. ": " .. tostring(err),
        vim.log.levels.ERROR
      )
    end
  end
  return true
end

function M.apply_options()
  local options = copy(captured)
  local overrides = M.get("options", {})
  if type(overrides) ~= "table" then
    vim.notify("Local options must be a table", vim.log.levels.ERROR)
    return false
  end
  for name, value in pairs(overrides) do
    options[name] = value
  end
  for name, value in pairs(options) do
    local ok, err = pcall(function()
      vim.opt[name] = value
    end)
    if not ok then
      vim.notify(
        "Invalid local option " .. tostring(name) .. ": " .. tostring(err),
        vim.log.levels.ERROR
      )
    end
  end
  return true
end

function M.bootstrap(config_root)
  if loaded then return end
  M.capture_options()
  local path = vim.g.config_local_file
  if path == nil then path = vim.fs.joinpath(config_root, "local.lua") end
  if path ~= false and type(path) ~= "string" then
    vim.notify("g:config_local_file must be a filename or false", vim.log.levels.ERROR)
    path = false
  end
  M.load(path)
  M.apply_globals()
end

local function context()
  return {
    cwd = global_cwd(),
    filename = vim.api.nvim_buf_get_name(0),
    bufnr = vim.api.nvim_get_current_buf(),
  }
end

local function evaluate(value, ctx, fallback)
  if type(value) == "function" then value = value(ctx) end
  if value == nil or value == false then return fallback end
  assert(type(value) == "string" and value ~= "", "root resolver must return a path or nil")
  return absolute(value, ctx.cwd)
end

function M.project_root()
  local ctx = context()
  local selected = M.get("project.root")
  if selected == nil then
    selected = M.get("scoper.project.root")
    -- Scoper's standalone API accepts global_cwd, not this module's context.
    if type(selected) == "function" then selected = selected(ctx.cwd) end
  end
  return evaluate(selected, ctx, ctx.cwd)
end

function M.resolve(intent)
  local ctx = context()
  if intent == nil or intent == "cwd" then return vim.fn.getcwd() end
  if intent == "project" then return M.project_root() end
  if intent == "scope" then
    local state = package.loaded["scoper.state"]
    return state and state.root() or M.project_root()
  end
  if intent == "file" then
    if ctx.filename == "" or ctx.filename:match("^%a[%w+.-]*://") then return vim.fn.getcwd() end
    return vim.fs.dirname(ctx.filename)
  end
  return evaluate(intent, ctx, vim.fn.getcwd())
end

function M.plugin_specs()
  local specs = M.get("plugins", {})
  if type(specs) ~= "table" or not vim.islist(specs) then
    vim.notify("Local plugins must be a list of Lazy specs", vim.log.levels.ERROR)
    return {}
  end
  return specs
end

function M.info()
  return { source = source, projects = vim.tbl_keys(projects) }
end

return M
