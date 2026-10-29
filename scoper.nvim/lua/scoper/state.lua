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
--   schema_version = 1,
--   active  = "frontend",            -- name of currently active scope
--   enabled = true,                   -- whether scope filtering is on
--   database_path = "/build/compile_commands.json", -- optional project-wide selection
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
local Scope = require("scoper.scope")
local Store = require("scoper.store")

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
    schema_version = Store.SCHEMA_VERSION,
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
-- pipeline.lua additionally encodes names that cannot be filesystem components.
local function valid_scope_name(name)
  return type(name) == "string"
    and name:match("^[%w_%-%.]+$") ~= nil
    and name ~= "."
    and name ~= ".."
end

-- Project/application state. Disk ownership belongs to store.lua and matching
-- belongs to scope.lua. Legacy state/accessors remain for existing callers;
-- new consumers use snapshot() and supported mutators.
local root, root_resolver, store
local revision = 0
local result = { applied = false, persisted = true, reason = "initial" }
local dirty = false
-- Only unsaved sessions are retained. This is recovery within this editor,
-- not a second concurrently active project or an automatic disk-state merge.
local unsaved = {}

local function resolve_root()
  local cwd = Path.normalize(Path.cwd())
  local chosen = root_resolver
  if type(root_resolver) == "function" then chosen = root_resolver(cwd) end
  if chosen == nil or chosen == false or chosen == "" then return cwd end
  assert(type(chosen) == "string", "Scoper project.root must resolve to a path string")
  return Path.absolute(chosen, cwd)
end

function M.configure_project(resolver)
  assert(
    resolver == nil or type(resolver) == "string" or type(resolver) == "function",
    "Scoper project.root must be a path or function"
  )
  root_resolver = resolver
end

function M.root()
  return root or resolve_root()
end

local function ensure_store()
  if not store then
    root = resolve_root()
    store = Store.new(root, fresh_state)
  end
  return store
end

local function present()
  for _, message in ipairs(ensure_store().messages()) do
    vim.notify(message.message, message.level)
  end
end

function M.last_result()
  return vim.deepcopy(result)
end

local function unapplied(reason, err)
  result = { applied = false, persisted = not dirty, reason = reason, error = err }
  return M.last_result()
end

local function fire_change(reason, fields)
  revision = revision + 1
  vim.api.nvim_exec_autocmds("User", {
    pattern = "ScoperChanged",
    modeline = false,
    data = {
      root = M.root(),
      scope = M.state.active,
      revision = revision,
      reason = reason or "scope",
      changed = vim.deepcopy(fields or { "scope" }),
      database = M.database(),
      persistence = M.last_result(),
    },
  })
end

local function read_state(source)
  local state = ensure_store().load(source)
  present()
  return state
end

function M.load(opts)
  opts = opts or {}
  root = opts.root and Path.absolute(opts.root, Path.cwd()) or resolve_root()
  store = Store.new(root, fresh_state)
  unsaved[store.path()] = nil
  local loaded = read_state()
  M.state = loaded or fresh_state()
  dirty = false
  result = {
    applied = true,
    persisted = loaded ~= nil,
    reason = loaded and "loaded" or store.reason(),
    error = store.error(),
  }
  if not opts.quiet then
    fire_change("load", { "project", "scope", "database" })
  else
    revision = revision + 1
  end
  return M.last_result()
end

function M.reload(opts)
  opts = vim.deepcopy(opts or {})
  if dirty and not opts.force then
    return unapplied("unsaved", "local scope changes are not saved; use force=true to discard them")
  end
  opts.root = M.root()
  return M.load(opts)
end

function M.initialize()
  local next_root = resolve_root()
  local next_store = Store.new(next_root, fresh_state)
  if store and store.path() == next_store.path() then return M.last_result() end
  if store and dirty then
    unsaved[store.path()] = { state = M.state, store = store, result = result }
  end
  local previous = unsaved[next_store.path()]
  if not previous then return M.load({ root = next_root }) end
  unsaved[next_store.path()] = nil
  root, store = next_root, previous.store
  M.state, result, dirty = previous.state, previous.result, true
  fire_change("restore_unsaved", { "project", "scope", "database" })
  return M.last_result()
end

function M.follow_cwd()
  return M.initialize()
end

function M.save()
  local ok, err, reason = ensure_store().save(M.state)
  result = { applied = true, persisted = ok, reason = reason, error = err }
  dirty = not ok
  present()
  return ok, M.last_result()
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

-- Legacy mutable scope accessor (or nil). New consumers use copied snapshots
-- and supported mutators so revisions and persistence cannot be bypassed.
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

-- Re-read the state file if another instance changed its contents.
-- No event: the mutation that follows fires ScoperChanged itself.
local function sync()
  ensure_store()
  -- A failed publication must not let a later refresh replace local edits.
  -- A successful retry or an explicit forced reload resolves this state.
  if dirty then return end
  if store.error() then return end
  local source = store.source()
  if source.error then
    read_state(source) -- report the unsafe read without replacing local edits
    result = { applied = false, persisted = false, reason = store.reason(), error = store.error() }
  elseif source.version ~= store.version() then
    local refreshed = read_state(source)
    if refreshed then
      M.state = refreshed
      result = { applied = true, persisted = true, reason = "refreshed" }
      return true
    else
      result =
        { applied = false, persisted = false, reason = store.reason(), error = store.error() }
    end
  end
end

-- A picker can outlive a project/scope switch. Refresh before capturing or
-- checking its target, including changes saved by another editor meanwhile.
function M.context()
  -- A canceled picker has no subsequent mutator to announce a refresh.
  if sync() then fire_change("refresh", { "scope", "database" }) end
  return {
    root = Path.key(M.root()),
    scope = M.active_name(),
    revision = revision,
    database = M.database(),
  }
end

function M.database()
  return M.state.database_path
end

function M.set_database(path)
  sync()
  assert(path == nil or type(path) == "string", "database selection must be a path or nil")
  M.state.database_path = path and path ~= "" and Path.absolute(path, M.root()) or nil
  M.save()
  fire_change("database", { "database" })
  return M.last_result()
end

-- Add directory/path entries to the active scope's include list. Duplicates
-- are silently skipped. Paths are stored as cwd-relative when possible;
-- ~ and $VARS in them are expanded.
--
-- Returns the number added, missing literal paths (files or directories), and
-- the structured publication result. Missing paths remain selected because a
-- generated file/directory may appear later; globs are not existence-checked.
function M.add_paths(paths)
  sync()
  if type(paths) == "string" then paths = { paths } end
  local scope = M.active_scope()
  if not scope then return 0, {}, unapplied("missing_scope") end

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
      if not Path.is_glob(p) and not vim.uv.fs_stat(abs) then table.insert(missing, stored) end
    end
  end

  if added > 0 then
    M.save()
    fire_change()
  else
    unapplied("unchanged")
  end
  return added, missing, M.last_result()
end

-- Remove paths from the active scope's include list. Matches both stored
-- form and normalized absolute form.
function M.remove_paths(paths)
  sync()
  if type(paths) == "string" then paths = { paths } end
  local scope = M.active_scope()
  if not scope then return 0, unapplied("missing_scope") end

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
  else
    unapplied("unchanged")
  end
  return removed, M.last_result()
end

-- Add exclude pattern(s) — glob strings. Returns the number added and the
-- list of rejected patterns the shared matcher cannot parse, followed by the
-- structured publication result. Backend-specific acceptance is not enough.
function M.add_excludes(patterns)
  sync()
  if type(patterns) == "string" then patterns = { patterns } end
  local scope = M.active_scope()
  if not scope then return 0, {}, unapplied("missing_scope") end
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
  else
    unapplied(#invalid > 0 and "invalid" or "unchanged")
  end
  return added, invalid, M.last_result()
end

function M.remove_excludes(patterns)
  sync()
  if type(patterns) == "string" then patterns = { patterns } end
  local scope = M.active_scope()
  if not scope then return 0, unapplied("missing_scope") end
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
  else
    unapplied("unchanged")
  end
  return removed, M.last_result()
end

-- Empty the active scope's includes (keeps excludes).
function M.clear_active()
  sync()
  local scope = M.active_scope()
  if not scope then return unapplied("missing_scope") end
  scope.include = {}
  M.save()
  fire_change()
  return M.last_result()
end

-- Create a new scope (seeded with default_excludes) and switch to it.
-- Returns false if the name is taken or unusable.
--
-- Keep names simple to type and complete in commands: word characters plus
-- '.', '-', '_', excluding traversal components. pipeline.cache_dir separately
-- encodes Windows device names, trailing dots, and overlong components so
-- existing logical names remain readable on every platform.
function M.new_scope(name)
  sync()
  if not name or name == "" then
    local err = "name required"
    return false, err, unapplied("invalid", err)
  end
  if not valid_scope_name(name) then
    local err = "invalid name (use letters, digits, '.', '-', '_')"
    return false, err, unapplied("invalid", err)
  end
  if M.state.scopes[name] then
    local err = "scope already exists"
    return false, err, unapplied("exists", err)
  end
  M.state.scopes[name] = fresh_scope()
  M.state.active = name
  M.save()
  fire_change()
  return true, nil, M.last_result()
end

function M.delete_scope(name)
  sync()
  if not M.state.scopes[name] then
    local err = "no such scope"
    return false, err, unapplied("missing_scope", err)
  end
  if vim.tbl_count(M.state.scopes) == 1 then
    local err = "cannot delete the last scope"
    return false, err, unapplied("last_scope", err)
  end
  M.state.scopes[name] = nil
  if M.state.active == name then M.state.active = fallback_scope(M.state.scopes) end
  M.save()
  fire_change()
  return true, nil, M.last_result()
end

function M.set_active(name)
  sync()
  if not M.state.scopes[name] then
    local err = "no such scope"
    return false, err, unapplied("missing_scope", err)
  end
  M.state.active = name
  M.save()
  fire_change()
  return true, nil, M.last_result()
end

function M.set_enabled(on)
  sync()
  M.state.enabled = on == true
  M.save()
  fire_change("enabled", { "enabled" })
  return M.last_result()
end

function M.toggle()
  -- Read another instance's saved value before computing its inverse.
  sync()
  return M.set_enabled(not M.is_enabled())
end

-- ---------------------------------------------------------------------------
-- Stateless matching remains available under the old name for compatibility.
M.build_matcher = Scope.compile

function M.matcher(cwd)
  local definition = M.active_scope()
  if not M.is_enabled() or not definition or #definition.include == 0 then
    return function()
      return true
    end
  end
  return Scope.compile(definition, cwd or M.root())
end

function M.is_in_scope(path, cwd)
  return M.matcher(cwd)(path)
end

function M.query()
  return Scope.query(M.active_scope(), M.root(), M.is_enabled())
end

function M.snapshot()
  return {
    root = M.root(),
    scope = M.active_name(),
    revision = revision,
    enabled = M.is_enabled(),
    definition = vim.deepcopy(M.active_scope()),
    database = M.database(),
    result = M.last_result(),
    unsaved = dirty,
  }
end

-- Directory-only legacy accessor. New search adapters use query().roots.
function M.active_dirs()
  local out = {}
  for _, entry in ipairs((M.active_scope() or {}).include or {}) do
    local absolute = Path.absolute(entry, M.root())
    if Path.is_dir(absolute) then out[#out + 1] = absolute end
  end
  return out
end

return M
