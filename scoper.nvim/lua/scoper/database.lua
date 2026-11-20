-- Bounded compilation-database resolution. This never executes build commands.
local Path = require("scoper.path")
local M = {}

local function file_path(path, root)
  assert(type(path) == "string" and path ~= "", "database path must be a nonempty string")
  local full = Path.absolute(path, root)
  local st = vim.uv.fs_stat(full)
  if st and st.type == "directory" then full = Path.absolute("compile_commands.json", full) end
  return Path.normalize(full)
end

function M.resolve(root, opts, context, legacy)
  opts = opts or {}
  local explicit, reason = opts.path, "configured path"
  if opts.resolver then
    assert(type(opts.resolver) == "function", "compilation_database.resolver must be a function")
    explicit, reason = opts.resolver(vim.deepcopy(context)), "resolver"
  end
  if explicit ~= nil and explicit ~= false then
    local path = file_path(explicit, root)
    local st = vim.uv.fs_stat(path)
    return {
      path = st and st.type == "file" and path or nil,
      requested = path,
      candidates = { path },
      reason = st and st.type == "file" and reason or "selected database is missing or not a file",
      explicit = true,
    }
  end
  if explicit == false then return { candidates = {}, reason = "database selection disabled" } end
  local candidates = opts.candidates
  if candidates == nil then
    candidates =
      { "compile_commands.json", "build/compile_commands.json", "out/compile_commands.json" }
    -- fs_scandir materializes the whole directory before its first result.
    -- Read bounded batches so the entry limit also bounds enumeration work.
    local dir, err = vim.uv.fs_opendir(root, nil, 64)
    local extra, scanned = {}, 0
    if dir then
      while true do
        local entries
        entries, err = vim.uv.fs_readdir(dir)
        if not entries then break end
        scanned = scanned + #entries
        if scanned > 4096 then break end
        for _, entry in ipairs(entries) do
          if entry.name:match("^cmake%-build%-") then
            if entry.type == "directory" or Path.is_dir(Path.absolute(entry.name, root)) then
              extra[#extra + 1] = entry.name .. "/compile_commands.json"
            end
          end
        end
        if #candidates + #extra > 256 then break end
      end
      vim.uv.fs_closedir(dir)
    end
    if err then return { candidates = {}, reason = "database discovery failed: " .. err } end
    if scanned > 4096 or #candidates + #extra > 256 then
      return {
        candidates = {},
        reason = "database discovery limit reached; select an explicit path",
      }
    end
    table.sort(extra)
    vim.list_extend(candidates, extra)
  end
  assert(
    type(candidates) == "table" and vim.islist(candidates),
    "database candidates must be a list"
  )
  assert(#candidates <= 256, "too many database candidates (maximum 256)")
  local checked, found, seen = {}, {}, {}
  for _, candidate in ipairs(candidates) do
    local path = file_path(candidate, root)
    checked[#checked + 1] = path
    local st = vim.uv.fs_stat(path)
    if st and st.type == "file" then
      local key = Path.key(vim.uv.fs_realpath(path) or path)
      if not seen[key] then
        found[#found + 1], seen[key] = path, true
      end
    end
  end
  -- An explicit ordered candidates list establishes priority. New default
  -- discovery refuses ambiguity; legacy boolean integration keeps first-match.
  local ambiguous = #found > 1 and not legacy and opts.candidates == nil
  return {
    path = not ambiguous and found[1] or nil,
    candidates = checked,
    matches = found,
    ambiguous = ambiguous,
    reason = ambiguous and "multiple compilation databases; select an explicit path"
      or (#found > 0 and "discovered" or "compile_commands.json not found"),
  }
end

return M
