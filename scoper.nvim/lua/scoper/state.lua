-- lua/scoper/state.lua
--
-- All mutable state for Scoper. Two layers:
--
--   1. In-memory state (M.state)  – the source of truth at runtime
--   2. JSON on disk               – persisted per-project (keyed by cwd hash)
--
-- The JSON file lives in stdpath("data")/scoper/<cwd-hash>.json so each
-- project gets its own scopes and the active selection survives restarts.
--
-- Data shape:
-- {
--   active  = "frontend",            -- name of currently active scope
--   enabled = true,                   -- whether scope filtering is on
--   scopes  = {
--     frontend = {
--       include = { "src/frontend", "shared/" },        -- allow-list
--       exclude = { "**/node_modules/**", "**/dist/**" } -- deny-list (globs)
--     },
--     ...
--   }
-- }
--
-- Includes are stored as cwd-relative paths when possible. Excludes are
-- glob patterns, kept verbatim.

local Path = require("scoper.path")
local Util = require("scoper.util")

local M = {}

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

-- Excludes every new scope starts with, including the "default" scope of a
-- project that has no state file yet. setup() sets it from
-- `default_excludes`.
M.default_excludes = {}

local function fresh_scope()
  return { include = {}, exclude = vim.deepcopy(M.default_excludes) }
end

local function fresh_state()
  return {
    active = "default",
    enabled = false,
    scopes = { default = fresh_scope() },
  }
end

M.state = fresh_state()

-- Scope to fall back to when the active one is missing: "default" if it
-- exists, else the first name in sorted order (pairs() order is arbitrary).
local function fallback_scope(scopes)
  if scopes.default then return "default" end
  local names = vim.tbl_keys(scopes)
  table.sort(names)
  return names[1]
end

-- Scope names are command-friendly identifiers; "." and ".." are out.
-- lsp.lua additionally encodes names that cannot be filesystem components.
local function valid_scope_name(name)
  return type(name) == "string"
    and name:match("^[%w_%-%.]+$") ~= nil
    and name ~= "."
    and name ~= ".."
end

-- The strings of list `t`, in order; anything else is dropped.
local function strings(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "string" and v ~= "" then out[#out + 1] = v end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Project root: the normalized global cwd the state was loaded for. The
-- state file, relative includes and the clangd cache all key off this
-- rather than the cwd of the moment, so a window or tab directory (:lcd,
-- :tcd, 'autochdir') can never make a save land in another project's file.
-- load() sets it; follow_cwd() reloads after a :cd.
-- ---------------------------------------------------------------------------
local root

function M.root()
  return root or Path.normalize(Path.cwd())
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------
local function store_dir()
  return vim.fn.stdpath("data") .. "/scoper"
end

-- Where on disk the per-project state file lives. We hash the cwd
-- rather than putting it in the filename verbatim because raw paths
-- contain `/`, `\`, drive colons, and other filesystem-unfriendly bytes;
-- a 16-char sha256 prefix avoids that without realistic collision risk
-- for the < ~1000 distinct projects any one person works on.
-- The hash itself lives in util.cwd_hash because lsp.cache_dir keys its
-- filtered-compile-commands cache off the SAME value; two independent
-- implementations could drift and silently split one project in two.
--
-- The hash is of Path.key(root) — lower-cased on Windows, where the same
-- directory is routinely reached as "C:\Proj" and "c:\proj" and would
-- otherwise get two unrelated state files. A file saved under the
-- case-sensitive hash (legacy_store_path) is still read and moves to the
-- new name on the next save; on other platforms both paths are identical.
local function store_path()
  return store_dir() .. "/" .. Util.cwd_hash(Path.key(M.root())) .. ".json"
end

local function legacy_store_path()
  return store_dir() .. "/" .. Util.cwd_hash(M.root()) .. ".json"
end

-- mtime of the state file as this instance last read or wrote it. Two
-- Neovim instances in the same project share one state file and each
-- keeps the state in memory, so every mutator calls sync() first: if the
-- file changed on disk since we last touched it, it is reloaded before the
-- change applies, and the other instance's edits survive.
local file_mtime
-- Failed reads must never turn session defaults into an overwrite of scopes
-- we could not inspect or back up. A successful explicit load clears this.
local read_error

local function stat_mtime(path)
  local st = vim.uv.fs_stat(path)
  return st and (st.mtime.sec .. "." .. st.mtime.nsec) or nil
end

local function ensure_dir()
  vim.fn.mkdir(store_dir(), "p")
end

-- Fire a User autocmd so consumers (lualine, LSP integration) can react.
-- We use a User event rather than direct calls so the dependency graph
-- stays one-way: state knows nothing about lualine.
local function fire_change()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "ScoperChanged",
    modeline = false,
  })
end

-- Read the state file for the current root. Tolerant of every plausible
-- failure mode: file missing or empty → fresh state; file unparseable →
-- fresh state, with the broken file copied aside so a hand-editing slip
-- (a trailing comma, say) doesn't cost every scope of the project. Unreadable
-- files or failed backups block saves until an explicit successful reload.
-- The defensive table-filling below is essential: older files lack some
-- fields, and a partial or hand-edited JSON file must not crash anything.
-- Sets file_mtime.
local function read_state()
  read_error = nil
  local path = store_path()
  local st, stat_err, stat_code = vim.uv.fs_stat(path)
  if not st and (stat_code == "ENOENT" or stat_code == "ENOTDIR") then
    path = legacy_store_path()
    st, stat_err, stat_code = vim.uv.fs_stat(path)
  end
  file_mtime = nil
  local ok, lines
  if not st and (stat_code == "ENOENT" or stat_code == "ENOTDIR") then return fresh_state() end
  if st and st.type == "file" then
    ok, lines = pcall(vim.fn.readfile, path)
  elseif st then
    stat_err = "expected a regular file, got " .. tostring(st.type)
  end
  if not ok then
    read_error = tostring(lines or stat_err)
    vim.notify(
      ("Scoper: could not read %s (%s). Saves are blocked; fix the file and run setup() again to reload it."):format(
        path,
        read_error
      ),
      vim.log.levels.ERROR
    )
    return nil
  end
  file_mtime = stat_mtime(path)
  if #lines == 0 then return fresh_state() end

  local parsed
  ok, parsed = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok or type(parsed) ~= "table" then
    -- EXCL: never overwrite an earlier backup from the same second.
    local stamp, backup, copied = os.date("%Y%m%d-%H%M%S"), nil, nil
    for n = 0, 99 do
      backup = ("%s.corrupt-%s%s"):format(path, stamp, n > 0 and ("-" .. n) or "")
      copied = vim.uv.fs_copyfile(path, backup, { excl = true })
      if copied or vim.uv.fs_stat(backup) == nil then break end
    end
    if not copied then read_error = "corrupt state could not be backed up" end
    vim.notify(
      ("Scoper: corrupt state file, using defaults. %s"):format(
        copied and ("The old file is kept as " .. backup)
          or ("Could not back up " .. path .. "; saves are blocked until a successful reload")
      ),
      vim.log.levels.WARN
    )
    return fresh_state()
  end

  -- Defensive: backfill anything the JSON might be missing. Notably:
  --   * an empty scopes table gets a "default" scope so the rest of the
  --     plugin can always assume at least one scope exists
  --   * the active scope name is validated against the available scopes
  --     and reset to a real one if it points at nothing (e.g. user
  --     hand-edited the file and deleted the active scope)
  --   * `enabled` is coerced to boolean to avoid surprises if it
  --     somehow ended up as "true" (string) or 1 (number)
  --   * JSON `null` decodes to vim.NIL (a truthy userdata), so a plain
  --     `x or {}` would let a hand-edited `"include": null` through to an
  --     ipairs() that throws. Anything that is not the expected
  --     type is replaced, non-table scope entries and scopes with a name
  --     :ScoperNew wouldn't accept are dropped, and so are list items
  --     that aren't strings.
  if type(parsed.scopes) ~= "table" then parsed.scopes = {} end
  for name, sc in pairs(parsed.scopes) do
    if type(sc) ~= "table" or not valid_scope_name(name) then
      parsed.scopes[name] = nil
    else
      sc.include = type(sc.include) == "table" and strings(sc.include) or {}
      sc.exclude = type(sc.exclude) == "table" and strings(sc.exclude) or {}
    end
  end
  if vim.tbl_isempty(parsed.scopes) then parsed.scopes.default = fresh_scope() end
  if type(parsed.active) ~= "string" or not parsed.scopes[parsed.active] then
    parsed.active = fallback_scope(parsed.scopes)
  end
  parsed.enabled = parsed.enabled == true
  return parsed
end

-- Load the state of the project in the global cwd and make it the root.
-- load() fires ScoperChanged like the mutators do, so after `:cd
-- other-project` clangd switches to the new project's filtered
-- compile_commands immediately. During setup() this fire is a harmless
-- no-op because lsp.attach_auto() registers its listener after the
-- initial load.
function M.load(opts)
  root = Path.normalize(Path.cwd())
  M.state = read_state() or fresh_state()
  if not (opts and opts.quiet) then fire_change() end
end

-- DirChanged handler: reload only when the global cwd now names another
-- project than the loaded one.
function M.follow_cwd()
  if Path.key(Path.cwd()) ~= Path.key(M.root()) then M.load() end
end

-- Persist the in-memory state to disk. The write is atomic (temp file +
-- rename; see util.atomic_write for the full rationale). This matters
-- more than it might look — without atomicity, a Neovim crash (OS
-- reboot, OOM, SIGKILL) mid-write would truncate the JSON file and the
-- user would lose every scope on next load. Two instances racing to
-- save the same project end with last-write-wins on the final path,
-- never with a corrupt file.
--
-- Mutators re-read the file first (sync), so edits another instance saved
-- earlier are kept. Only two saves in the same instant can still race: the
-- later rename wins.
--
-- vim.uv.fs_rename is cross-platform — on Windows libuv internally
-- uses MoveFileEx with MOVEFILE_REPLACE_EXISTING, so the destination
-- being present doesn't break the rename.
--
-- Returns false (after notifying) when the file couldn't be written; the
-- in-memory change stays and the next successful save persists it. After an
-- unsafe read, saves remain blocked until load() can read or back up the file.
function M.save()
  local ok, err
  if read_error then
    ok, err = false, "state was not safely read; fix the file and run setup() again"
  else
    local called
    called, ok, err = pcall(function()
      ensure_dir()
      return Util.atomic_write(store_path(), { vim.json.encode(M.state) })
    end)
    if not called then
      ok, err = false, ok
    end
  end
  if not ok then
    vim.notify(
      ("Scoper: failed to save %s (%s). %s"):format(
        store_path(),
        err,
        read_error
            and "The change applies to this session only; reload after fixing the state file."
          or "The change applies to this session only, until a later change saves."
      ),
      vim.log.levels.ERROR
    )
    return false
  end
  file_mtime = stat_mtime(store_path())
  return true
end

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------
function M.active_name()
  return M.state.active
end

function M.active_scope()
  return M.state.scopes[M.state.active]
end

-- Look up a scope by name (or nil). Public accessor so consumers —
-- including scoper/init.lua — never reach into M.state directly; the
-- internal shape stays free to change.
function M.scope(name)
  return M.state.scopes[name]
end

function M.scope_names()
  local names = vim.tbl_keys(M.state.scopes)
  table.sort(names)
  return names
end

function M.is_enabled()
  return M.state.enabled == true
end

-- ---------------------------------------------------------------------------
-- Mutators. All of them save and fire ScoperChanged on success.
-- ---------------------------------------------------------------------------

-- Re-read the state file if another instance changed it (see file_mtime).
-- No event: the mutation that follows fires ScoperChanged itself.
local function sync()
  if read_error then return end
  local now = stat_mtime(store_path())
  if now ~= nil and now ~= file_mtime then
    local refreshed = read_state()
    if refreshed then
      M.state = refreshed
      return true
    end
  end
end

-- A picker can outlive a project/scope switch. Refresh before capturing or
-- checking its target, including changes saved by another editor meanwhile.
function M.context()
  -- A canceled picker has no subsequent mutator to announce a refresh.
  if sync() then fire_change() end
  return { root = Path.key(M.root()), scope = M.active_name() }
end

-- Add directory/path entries to the active scope's include list. Duplicates
-- are silently skipped. Paths are stored as cwd-relative when possible;
-- ~ and $VARS in them are expanded.
--
-- Returns the number added and the list of added entries that aren't an
-- existing directory (nor a glob) — likely typos, kept anyway because a
-- build directory may simply not exist yet.
function M.add_paths(paths)
  sync()
  if type(paths) == "string" then paths = { paths } end
  local scope = M.active_scope()
  if not scope then return 0, {} end

  local cwd = M.root()
  local added, missing = 0, {}
  for _, p in ipairs(paths) do
    local abs = Path.absolute(p, cwd, { expand_env = true })
    local rel = Path.relative(abs, cwd)
    -- Use the shorter, more portable form: relative if it's actually under
    -- cwd, otherwise keep absolute.
    local stored = (rel ~= abs) and rel or abs
    -- Dedupe by path identity (Path.key: case-insensitive on Windows),
    -- comparing absolute forms so "src" and "<cwd>/src" are one entry.
    local dup = false
    for _, existing in ipairs(scope.include) do
      if Path.key(Path.absolute(existing, cwd)) == Path.key(abs) then
        dup = true
        break
      end
    end
    if not dup then
      table.insert(scope.include, stored)
      added = added + 1
      if not Path.is_glob(p) and not Path.is_dir(abs) then table.insert(missing, stored) end
    end
  end

  if added > 0 then
    M.save()
    fire_change()
  end
  return added, missing
end

-- Remove paths from the active scope's include list. Matches both stored
-- form and normalized absolute form.
function M.remove_paths(paths)
  sync()
  if type(paths) == "string" then paths = { paths } end
  local scope = M.active_scope()
  if not scope then return 0 end

  local cwd = M.root()
  local targets = {}
  for _, p in ipairs(paths) do
    targets[Path.key(Path.absolute(p, cwd, { expand_env = true }))] = true
  end

  local removed = 0
  local kept = {}
  for _, stored in ipairs(scope.include) do
    if targets[Path.key(Path.absolute(stored, cwd))] then
      removed = removed + 1
    else
      table.insert(kept, stored)
    end
  end
  scope.include = kept

  if removed > 0 then
    M.save()
    fire_change()
  end
  return removed
end

-- Add exclude pattern(s) — glob strings. Returns the number added and the
-- list of rejected patterns that vim.glob can't parse (the clangd filter
-- couldn't apply them, while rg in the pickers might).
function M.add_excludes(patterns)
  sync()
  if type(patterns) == "string" then patterns = { patterns } end
  local scope = M.active_scope()
  if not scope then return 0, {} end
  local added, invalid = 0, {}
  for _, p in ipairs(patterns) do
    -- Reject nil, empty, and whitespace-only patterns. The whitespace
    -- case slips through `p ~= ""` and would corrupt the exclude list if a
    -- user typed `:ScoperExclude   ` (just spaces).
    if type(p) == "string" and p:match("%S") and not vim.tbl_contains(scope.exclude, p) then
      if Path.valid_glob(p) then
        table.insert(scope.exclude, p)
        added = added + 1
      else
        table.insert(invalid, p)
      end
    end
  end
  if added > 0 then
    M.save()
    fire_change()
  end
  return added, invalid
end

function M.remove_excludes(patterns)
  sync()
  if type(patterns) == "string" then patterns = { patterns } end
  local scope = M.active_scope()
  if not scope then return 0 end
  local set = {}
  for _, p in ipairs(patterns) do
    set[p] = true
  end
  local removed = 0
  local kept = {}
  for _, p in ipairs(scope.exclude) do
    if set[p] then
      removed = removed + 1
    else
      table.insert(kept, p)
    end
  end
  scope.exclude = kept
  if removed > 0 then
    M.save()
    fire_change()
  end
  return removed
end

-- Empty the active scope's includes (keeps excludes).
function M.clear_active()
  sync()
  local scope = M.active_scope()
  if not scope then return end
  scope.include = {}
  M.save()
  fire_change()
end

-- Create a new scope (seeded with default_excludes) and switch to it.
-- Returns false if the name is taken or unusable.
--
-- Keep names simple to type and complete in commands: word characters plus
-- '.', '-', '_', excluding traversal components. lsp.cache_dir separately
-- encodes Windows device names, trailing dots, and overlong components so
-- existing logical names remain readable on every platform.
function M.new_scope(name)
  sync()
  if not name or name == "" then return false, "name required" end
  if not valid_scope_name(name) then
    return false, "invalid name (use letters, digits, '.', '-', '_')"
  end
  if M.state.scopes[name] then return false, "scope already exists" end
  M.state.scopes[name] = fresh_scope()
  M.state.active = name
  M.save()
  fire_change()
  return true
end

function M.delete_scope(name)
  sync()
  if not M.state.scopes[name] then return false, "no such scope" end
  if vim.tbl_count(M.state.scopes) == 1 then return false, "cannot delete the last scope" end
  M.state.scopes[name] = nil
  if M.state.active == name then M.state.active = fallback_scope(M.state.scopes) end
  M.save()
  fire_change()
  return true
end

function M.set_active(name)
  sync()
  if not M.state.scopes[name] then return false, "no such scope" end
  M.state.active = name
  M.save()
  fire_change()
  return true
end

function M.set_enabled(on)
  sync()
  M.state.enabled = on == true
  M.save()
  fire_change()
end

function M.toggle()
  -- Read another instance's saved value before computing its inverse.
  sync()
  M.set_enabled(not M.is_enabled())
end

-- ---------------------------------------------------------------------------
-- The hot path: is this file in the active scope?
--
-- A file is in scope iff:
--   * it lies under at least one `include` entry that's a directory, OR
--     matches an `include` entry that's a glob, AND
--   * it does NOT match any `exclude` glob. Excludes match the path
--     relative to the cwd, or, for a file outside the cwd, relative to the
--     include directory it is in (what rg sees when searching that dir).
--
-- If scoping is disabled or includes are empty, EVERYTHING is in scope.
-- That last rule means turning Scoper on with an empty scope doesn't
-- silently hide every file — it's a no-op until you add something.
--
-- matcher(cwd) prepares the scope once and returns fn(path) → bool; the
-- clangd filter calls it for every compile_commands entry. `cwd` defaults
-- to the project root.
-- ---------------------------------------------------------------------------
local function everything()
  return true
end

function M.matcher(cwd)
  if not M.is_enabled() then return everything end
  local scope = M.active_scope()
  if not scope or #scope.include == 0 then return everything end
  return M.build_matcher(scope, cwd or M.root())
end

-- The matcher for `scope` ({ include, exclude }) relative to `cwd`, without
-- reading any state, so the background filter process (scoper.cdb) builds
-- exactly the same one.
function M.build_matcher(scope, cwd)
  cwd = Path.normalize(cwd)
  local cwd_key = Path.fold(cwd)
  local dirs, globs, excludes = {}, {}, {}
  for _, entry in ipairs(scope.include) do
    local absolute = Path.absolute(entry, cwd)
    table.insert(dirs, Path.key(absolute))
    local first = absolute:find("[%*%?%[{]")
    if first then
      -- Excludes of an outside glob are relative to its deepest complete
      -- literal ancestor. For /build/lib*/**/*.c that is /build, whereas
      -- /build/lib/**/*.c starts at /build/lib. Retain the slash for roots.
      local ancestor = absolute:sub(1, first - 1):match("^(.*)/")
      table.insert(globs, { pattern = entry, root = Path.key((ancestor or "") .. "/") })
    end
  end
  for _, pat in ipairs(scope.exclude) do
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
    local abs = Path.absolute(path, cwd)
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

-- One-off check. Loops should build M.matcher() once instead.
function M.is_in_scope(path, cwd)
  return M.matcher(cwd)(path)
end

-- ---------------------------------------------------------------------------
-- Helper: list of absolute include directories that exist on disk.
-- Used by pickers to set search_dirs. Glob includes have no directory to
-- search from, so they only filter (is_in_scope, the clangd filter).
-- ---------------------------------------------------------------------------
function M.active_dirs()
  local scope = M.active_scope()
  if not scope then return {} end
  local cwd = M.root()
  local out = {}
  for _, entry in ipairs(scope.include) do
    local abs = Path.absolute(entry, cwd)
    if Path.is_dir(abs) then table.insert(out, abs) end
  end
  return out
end

return M
