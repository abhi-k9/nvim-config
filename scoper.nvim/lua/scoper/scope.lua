-- Stateless scope compilation shared by state, search and the CDB worker.
local Path = require("scoper.path")
local M = {}

function M.compile(scope, cwd)
  cwd = Path.normalize(cwd)
  local aliases = {}
  local function canonical(path)
    return Path.expand_short(path, aliases)
  end
  local cwd_key = Path.fold(canonical(cwd))
  local dirs, globs, excludes = {}, {}, {}
  for _, entry in ipairs(scope.include) do
    local absolute = canonical(Path.absolute(entry, cwd))
    table.insert(dirs, Path.key(absolute))
    local first = absolute:find("[%*%?%[{]")
    if first then
      -- Excludes of an outside glob are relative to its deepest complete
      -- literal ancestor. For /build/lib*/**/*.c that is /build, whereas
      -- /build/lib/**/*.c starts at /build/lib. Retain the slash for roots.
      local ancestor = absolute:sub(1, first - 1):match("^(.*)/")
      table.insert(globs, { pattern = absolute, root = Path.key((ancestor or "") .. "/") })
    end
  end
  for _, pat in ipairs(scope.exclude) do
    if Path.is_absolute(pat) then pat = canonical(pat) end
    local m = Path.exclude_matcher(pat)
    if m then table.insert(excludes, m) end
  end

  -- `key` relative to `base` (both folded), or nil when it isn't under it.
  local function rel_to(key, base)
    if not Path.key_under(key, base) then return nil end
    if key == base then return "." end
    return key:sub(#base + (base:sub(-1) == "/" and 1 or 2))
  end

  return function(path)
    local abs = canonical(Path.absolute(path, cwd))
    local key = Path.fold(abs)
    local root_dir
    for _, d in ipairs(dirs) do
      if Path.key_under(key, d) then
        root_dir = d
        break
      end
    end
    local included = root_dir ~= nil
    if not included then
      for _, g in ipairs(globs) do
        if Path.match_glob(abs, g.pattern, cwd) then
          included = true
          if Path.key_under(key, g.root) then root_dir = g.root end
          break
        end
      end
    end
    if not included then return false end
    if #excludes > 0 then
      local rel = rel_to(key, cwd_key) or (root_dir and rel_to(key, root_dir)) or key
      for _, ex in ipairs(excludes) do
        if ex(key, rel) then return false end
      end
    end
    return true
  end
end

local function everything()
  return true
end

-- Search roots never require scanning a whole filesystem to expand a glob.
-- The exact matcher is normative; adapters must not broaden these results.
function M.query(scope, root, enabled)
  scope = vim.deepcopy(scope or { include = {}, exclude = {} })
  if enabled == false or #(scope.include or {}) == 0 then
    return {
      roots = nil,
      restricted = false,
      in_scope = everything,
      matches = everything,
      excludes = {},
      missing = {},
    }
  end
  local matches = M.compile(scope, root)
  local roots, missing, seen = {}, {}, {}
  for _, entry in ipairs(scope.include) do
    local path = Path.absolute(entry, root)
    if Path.is_glob(entry) then
      local first = path:find("[%*%?%[{]")
      local literal = first and path:sub(1, first - 1) or path
      path = literal:match("^(.*)/") or root
      if path == "" then path = "/" end
      if path:match("^%a:$") then path = path .. "/" end
    end
    local stat = vim.uv.fs_stat(path)
    if stat and (stat.type == "directory" or stat.type == "file") then
      local key = Path.key(path)
      if not seen[key] then
        roots[#roots + 1], seen[key] = path, true
      end
    else
      missing[#missing + 1] = entry
    end
  end
  return {
    roots = roots,
    restricted = true,
    in_scope = matches,
    matches = matches,
    excludes = vim.deepcopy(scope.exclude or {}),
    missing = missing,
  }
end

return M
