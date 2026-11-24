-- Optional host adapter: neither plugin depends on the other. Decorate existing
-- name components; optionally filter scanned items before Neo-tree builds nodes.
local M = {}
local enabled, override
local filter_enabled, filter_override
local setup_id = 0
local renderer_owner, render_original, render_wrapper

local function refresh()
  local manager = package.loaded["neo-tree.sources.manager"]
  if type(manager) == "table" and type(manager.refresh) == "function" then
    pcall(manager.refresh, "filesystem")
  end
end

function M.toggle_filter()
  if filter_enabled == nil then
    filter_enabled = require("config.settings").get("explorer.scope_filter", false) == true
  end
  filter_enabled = not filter_enabled
  filter_override = filter_enabled
  refresh()
  vim.notify("Explorer scope filter: " .. (filter_enabled and "ON" or "OFF"))
end

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

function M.configure(opts, options, filter_option)
  filter_enabled = filter_option == true
  if filter_override ~= nil then filter_enabled = filter_override end
  -- Configure runs inside Neo-tree loading; toggles themselves never load it.
  pcall(require, "neo-tree.ui.renderer")
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

-- All rows in a render share a tree path. Cache only the last comparison so
-- rerooting a tree takes effect immediately and the cache stays bounded.
local function related_tree_key(scope, tree)
  if type(tree) ~= "string" then return nil end
  if scope.tree ~= tree then
    scope.root_key = scope.root_key or path_key(scope.root)
    local path, base = path_key(tree), scope.root_key
    local related = path == base or path:sub(1, #base + 1) == base .. "/"
    scope.tree, scope.tree_key = tree, related and path or nil
  end
  return scope.tree_key
end

-- Only prune proven exclusions. Keep the tree root and uncertain directories so
-- navigation works without recursively discovering descendants on disk.
local function filter_items(items, scope, tree_path)
  local result = {}
  for _, item in ipairs(items) do
    local path = item.path or item.id
    local keep = true
    if type(path) == "string" then
      if item.type == "file" then
        keep = scope.matches(path) ~= false
      elseif item.type == "directory" and scope.excluded_directory then
        keep = path_key(path) == tree_path or not scope.excluded_directory(path)
      end
    end
    if keep then
      local copy = vim.tbl_extend("force", {}, item)
      if item.children then copy.children = filter_items(item.children, scope, tree_path) end
      result[#result + 1] = copy
    elseif item.type == "file" and item.children then
      -- An excluded nesting parent must not hide included nested files.
      for _, child in ipairs(filter_items(item.children, scope, tree_path)) do
        child.is_nested = false
        result[#result + 1] = child
      end
    end
  end
  return result
end

local function install_filter()
  local renderer = package.loaded["neo-tree.ui.renderer"]
  if type(renderer) ~= "table" or type(renderer.show_nodes) ~= "function" then return end
  renderer_owner, render_original = renderer, renderer.show_nodes
  local original, id = render_original, setup_id
  -- Neo-tree has no configurable predicate. Keep this single exported-function
  -- integration isolated and covered against the pinned renderer's item API.
  render_wrapper = function(items, state, parent, callback)
    if id == setup_id and filter_enabled and items and state.name == "filesystem" then
      local scope = capture()
      local tree_key = scope.root and related_tree_key(scope, state.path)
      if tree_key then
        local ok, filtered = pcall(filter_items, items, scope, tree_key)
        if ok then items = filtered end -- Fail open if an optional predicate fails.
      end
    end
    return original(items, state, parent, callback)
  end
  renderer.show_nodes = render_wrapper
end

function M.decorate(original, options)
  local id = setup_id
  return function(config, node, state)
    local result = original(config, node, state)
    if type(result) ~= "table" or type(result.text) ~= "string" then return result end
    if id ~= setup_id or enabled == false then return result end
    local scope = capture()
    if not scope.root or not related_tree_key(scope, state.path) then return result end
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
  -- Other customizations can retain our hooks even after replacing them.
  setup_id = setup_id + 1
  cancel()
  if renderer_owner and renderer_owner.show_nodes == render_wrapper then
    renderer_owner.show_nodes = render_original
  end
  renderer_owner, render_original, render_wrapper = nil, nil, nil
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
  install_filter()
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
      if enabled == false and not filter_enabled then return end
      local ticket = generation
      timer = vim.defer_fn(function()
        if ticket ~= generation then return end
        timer = nil
        if filter_enabled then
          refresh() -- Rebuild pruned trees; also restores entries when Scoper is OFF.
          return
        end
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
