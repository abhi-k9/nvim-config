-- Optional host adapter: neither plugin depends on the other. Decorate existing
-- name components and request redraws, never alter tree membership or scan files.
local M = {}
local enabled, override

function M.toggle()
  if enabled == nil then
    local option = require("config.settings").get("explorer.scope_markers", false)
    enabled = option == true or type(option) == "table" and option.enabled == true
  end
  enabled = not enabled
  override = enabled
  local manager = package.loaded["neo-tree.sources.manager"]
  if type(manager) == "table" and type(manager.redraw) == "function" then
    pcall(manager.redraw, "filesystem")
  end
  vim.notify("Explorer scope markers: " .. (enabled and "ON" or "OFF"))
end

function M.configure(opts, options)
  -- Reload defaults normally; an explicit toggle owns this editor's choice.
  enabled = options == true or type(options) == "table" and options.enabled == true
  if override ~= nil then enabled = override end
  options = type(options) == "table" and vim.deepcopy(options) or {}
  options.enabled = true
  M.setup(opts, options)
end
local cached, owner, timer, generation = nil, nil, nil, 0
local wrappers = setmetatable({}, { __mode = "k" })

local function cancel()
  generation = generation + 1
  if timer then
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    timer = nil
  end
end

local function capture()
  local scoper = package.loaded.scoper
  if cached and owner == scoper then return cached end
  owner, cached = scoper, {}
  if
    type(scoper) ~= "table"
    or type(scoper.snapshot) ~= "function"
    or type(scoper.matcher) ~= "function"
  then
    return cached
  end
  local ok, snapshot = pcall(scoper.snapshot)
  if
    not ok
    or type(snapshot) ~= "table"
    or not snapshot.enabled
    or type(snapshot.root) ~= "string"
  then
    return cached
  end
  local matched, matcher = pcall(scoper.matcher, snapshot.root)
  if matched and type(matcher) == "function" then
    cached = { root = snapshot.root, scope = snapshot.scope, matches = matcher }
    if type(scoper.excluded_directory_matcher) == "function" then
      local ok_dir, excluded = pcall(scoper.excluded_directory_matcher, snapshot.root)
      if ok_dir and type(excluded) == "function" then cached.excluded_directory = excluded end
    end
  end
  return cached
end

local function path_key(path)
  local windows = vim.fn.has("win32") == 1
  local key = vim.fs.normalize(path, { expand_env = false, win = windows }):gsub("/+$", "")
  return windows and key:lower() or key
end

local function related(tree, root)
  if type(tree) ~= "string" then return false end
  local path, base = path_key(tree), path_key(root)
  return path == base or path:sub(1, #base + 1) == base .. "/"
end

function M.decorate(original, options)
  return function(config, node, state)
    local result = original(config, node, state)
    if type(result) ~= "table" or type(result.text) ~= "string" then return result end
    if enabled == false then return result end
    local scope = capture()
    if not scope.root or not related(state.path, scope.root) then return result end
    if node.type == "directory" and node:get_depth() == 1 and options.show_scope ~= false then
      result = vim.tbl_extend("force", {}, result)
      result.text = result.text .. " [scope: " .. tostring(scope.scope or "active") .. "]"
    end
    if node.type == "file" or node.type == "directory" and scope.excluded_directory then
      local path = node:get_id()
      if type(path) ~= "string" then return result end
      local directory = node.type == "directory"
      local ok, value = pcall(directory and scope.excluded_directory or scope.matches, path)
      if ok and (directory and value == true or not directory and value == false) then
        result = vim.tbl_extend("force", {}, result)
        local marker = options.marker or "-"
        result.text = (marker ~= "" and marker .. " " or "") .. result.text
        if options.dim ~= false then result.highlight = options.highlight or "NeoTreeDimText" end
      end
    end
    return result
  end
end

function M.setup(opts, options)
  cancel()
  cached, owner = nil, nil
  local group = vim.api.nvim_create_augroup("config_scoper_explorer", { clear = true })
  local existing = opts.filesystem and opts.filesystem.components
  if existing then
    while wrappers[existing.name] do
      existing.name = wrappers[existing.name]
    end
  end
  if not options or options == false or type(options) == "table" and not options.enabled then
    return
  end
  options = type(options) == "table" and options or {}
  opts.filesystem = opts.filesystem or {}
  opts.filesystem.components = opts.filesystem.components or {}
  local components = opts.filesystem.components
  local original = components.name or require("neo-tree.sources.common.components").name
  components.name = M.decorate(original, options)
  wrappers[components.name] = original
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ScoperChanged",
    callback = function()
      cached, owner = nil, nil
      cancel()
      if enabled == false then return end
      local ticket = generation
      timer = vim.defer_fn(function()
        if ticket ~= generation then return end
        timer = nil
        if enabled == false then return end
        local manager = package.loaded["neo-tree.sources.manager"]
        if type(manager) == "table" and type(manager.redraw) == "function" then
          -- Neo-tree redraw visits only visible trees and does not rescan.
          pcall(manager.redraw, "filesystem")
        end
      end, options.debounce_ms or 100)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = cancel })
end

return M
