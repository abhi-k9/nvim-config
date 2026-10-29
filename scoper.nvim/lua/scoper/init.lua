-- lua/scoper/init.lua
--
-- Scoper — scope searches to directories, files or globs, and optionally
-- select/filter clangd's compilation database. The main public API lives here;
-- the state/scope guides document the supported lower-level interfaces.
--
-- USAGE
--   require("scoper").setup({
--     lsp = { mode = "filtered" }, -- auto-refresh an immutable scoped database
--   })
--
-- See plugin/scoper.lua for the user commands registered automatically.

local M = {}

-- Lazy-require sub-modules so `require("scoper")` is cheap; the heavy bits
-- only load when the user actually invokes a command.
-- stylua: ignore start
local function State() return require("scoper.state") end
local function UI()    return require("scoper.ui") end
local function LSP()   return require("scoper.lsp") end
local function Pick()  return require("scoper.pickers") end
-- stylua: ignore end

local function same_context(context, scope_sensitive)
  local current = State().context()
  if
    current.root == context.root
    and (
      not scope_sensitive
      or (current.scope == context.scope and current.revision == context.revision)
    )
  then
    return true
  end
  vim.notify(
    "Scoper: project or scope changed while selecting; operation cancelled",
    vim.log.levels.WARN
  )
  return false
end

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------
local defaults = {
  project = {},
  compilation_database = {},
  picker = "auto",
  -- LSP integration (opt-in).
  lsp = {
    extra_args = {},
    query_drivers = {},
    startup = "fallback",
    watch = true,
    debounce_ms = 500,
    clangd = false, -- legacy automatic filtered integration; source database stays intact
    -- Base flags scoper launches clangd with (it prepends its own
    -- --compile-commands-dir on top when applicable). These defaults
    -- are reasonable, but they're OPINIONS, not requirements of the
    -- plugin — override the whole list in setup() if your project
    -- wants different tidy/completion behaviour.
    clangd_args = {
      "--background-index",
      "--clang-tidy",
      "--completion-style=detailed",
      "--header-insertion=iwyu",
    },
  },
  -- Exclude patterns every new scope starts with, including the "default"
  -- scope of a project without saved scopes. Empty here because people
  -- disagree about defaults (some want node_modules ignored, some need to
  -- search it). Set in your setup() call if you like.
  default_excludes = {},
}

M.config = vim.deepcopy(defaults)

-- Dictionary settings merge; list values, including {}, replace as a unit.
local dictionaries = { project = true, compilation_database = true, lsp = true }
local function merge(base, overrides)
  for key, value in pairs(overrides) do
    if
      type(value) == "table"
      and type(base[key]) == "table"
      and (dictionaries[key] or (not vim.islist(value) and not vim.islist(base[key])))
    then
      merge(base[key], value)
    else
      base[key] = vim.deepcopy(value)
    end
  end
  return base
end

function M.setup(opts)
  assert(opts == nil or type(opts) == "table", "Scoper setup options must be a table")
  -- Full setup is deterministic. patch() is the explicit cumulative operation.
  M.config = merge(vim.deepcopy(defaults), opts or {})
  State().default_excludes = vim.deepcopy(M.config.default_excludes or {})
  local previous_lsp = package.loaded["scoper.lsp"]
  if previous_lsp then
    if previous_lsp.dispose then
      previous_lsp.dispose()
    else
      previous_lsp.detach_auto()
    end
  end
  State().configure_project(M.config.project and M.config.project.root)
  State().initialize()
  if M.config.lsp and (M.config.lsp.clangd or M.config.lsp.mode) then
    local ok, err = pcall(function()
      if LSP().configure then
        LSP().configure()
      elseif M.config.lsp.clangd then
        LSP().attach_auto()
        LSP().apply_initial()
      end
    end)
    if not ok then
      vim.notify("Scoper LSP: initial config failed: " .. tostring(err), vim.log.levels.WARN)
    end
  end
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("scoper_dir", { clear = true }),
    pattern = "global",
    callback = function()
      State().follow_cwd()
    end,
  })
  return M.status_snapshot()
end

function M.patch(opts)
  return M.setup(merge(vim.deepcopy(M.config), opts or {}))
end

function M.snapshot()
  return State().snapshot()
end

function M.status_snapshot()
  local status = State().snapshot()
  local integration = package.loaded["scoper.lsp"]
  if integration and integration.status then status.lsp = integration.status() end
  return status
end

function M.reload(opts)
  local result = State().reload(opts)
  if not result.applied then vim.notify("Scoper: " .. result.error, vim.log.levels.WARN) end
  return result
end

function M.select_database(path)
  return State().set_database(path)
end

-- ---------------------------------------------------------------------------
-- Public API — thin wrappers around state.lua with notifications.
-- ---------------------------------------------------------------------------

function M.add(paths)
  if not paths or (type(paths) == "table" and #paths == 0) then
    local context = State().context()
    UI().pick_dirs(function(picked)
      if #picked > 0 and same_context(context, true) then M.add(picked) end
    end)
    return
  end
  local n, missing, result = State().add_paths(paths)
  vim.notify(("Scoper: added %d path(s) to %q"):format(n, State().active_name()))
  if #missing > 0 then
    vim.notify(
      "Scoper: not an existing path (added anyway): " .. table.concat(missing, ", "),
      vim.log.levels.WARN
    )
  end
  return result
end

function M.remove(paths)
  if not paths or (type(paths) == "table" and #paths == 0) then
    local context = State().context()
    local scope = State().active_scope()
    if not scope or #scope.include == 0 then
      vim.notify("Scoper: active scope is empty", vim.log.levels.WARN)
      return
    end
    UI().pick_many(scope.include, { prompt = "Remove from scope" }, function(picked)
      if #picked > 0 and same_context(context, true) then M.remove(picked) end
    end)
    return
  end
  local n, result = State().remove_paths(paths)
  vim.notify(("Scoper: removed %d path(s) from %q"):format(n, State().active_name()))
  return result
end

function M.exclude(patterns)
  if not patterns or (type(patterns) == "table" and #patterns == 0) then
    local context = State().context()
    UI().input("Exclude glob (e.g. **/node_modules/**): ", "", function(p)
      if same_context(context, true) then M.exclude({ p }) end
    end)
    return
  end
  local n, invalid, result = State().add_excludes(patterns)
  vim.notify(("Scoper: added %d exclude(s) to %q"):format(n, State().active_name()))
  if #invalid > 0 then
    vim.notify(
      "Scoper: not a valid glob (not added): " .. table.concat(invalid, ", "),
      vim.log.levels.WARN
    )
  end
  return result
end

-- Remove exclude pattern(s). No args → multi-select picker over the
-- active scope's excludes.
function M.remove_exclude(patterns)
  if not patterns or (type(patterns) == "table" and #patterns == 0) then
    local context = State().context()
    local scope = State().active_scope()
    if not scope or #scope.exclude == 0 then
      vim.notify("Scoper: active scope has no excludes", vim.log.levels.WARN)
      return
    end
    UI().pick_many(scope.exclude, { prompt = "Remove exclude(s)" }, function(picked)
      if #picked > 0 and same_context(context, true) then M.remove_exclude(picked) end
    end)
    return
  end
  if type(patterns) == "string" then patterns = { patterns } end
  local n, result = State().remove_excludes(patterns)
  vim.notify(("Scoper: removed %d exclude(s) from %q"):format(n, State().active_name()))
  return result
end

function M.clear()
  local result = State().clear_active()
  vim.notify(("Scoper: cleared scope %q"):format(State().active_name()))
  return result
end

-- Show the active scope's contents in a floating panel.
function M.show()
  local scope = State().active_scope()
  if not scope then return end
  local lines = {
    -- stylua: ignore start
    ("Active scope:  %s"):format(State().active_name()),
    ("Enabled:       %s"):format(State().is_enabled() and "yes" or "no"),
    -- stylua: ignore end
    "",
    ("Include (%d):"):format(#scope.include),
  }
  if #scope.include == 0 then
    table.insert(lines, "  (empty — :ScoperAdd <path>)")
  else
    for _, p in ipairs(scope.include) do
      table.insert(lines, "  " .. p)
    end
  end
  table.insert(lines, "")
  table.insert(lines, ("Exclude (%d):"):format(#scope.exclude))
  if #scope.exclude == 0 then
    table.insert(lines, "  (none)")
  else
    for _, p in ipairs(scope.exclude) do
      table.insert(lines, "  " .. p)
    end
  end
  local snapshot = M.status_snapshot()
  vim.list_extend(lines, {
    "",
    "Project: " .. snapshot.root,
    "Revision: " .. snapshot.revision,
    "Persistence: " .. tostring(snapshot.result.reason),
    "Selected database: " .. tostring(snapshot.database or "automatic/configured"),
  })
  if snapshot.lsp then
    vim.list_extend(lines, {
      "LSP mode: " .. tostring(snapshot.lsp.mode),
      "Database source: "
        .. tostring(snapshot.lsp.source or snapshot.lsp.database or "native discovery"),
      "LSP status: " .. tostring(snapshot.lsp.reason or snapshot.lsp.info or "ready"),
    })
  end
  UI().show_lines(lines, "Scoper — " .. State().active_name())
end

function M.new(name)
  if not name or name == "" then
    local context = State().context()
    UI().input("New scope name: ", "", function(n)
      if same_context(context, false) then M.new(n) end
    end)
    return
  end
  local ok, err, result = State().new_scope(name)
  if not ok then
    vim.notify("Scoper: " .. err, vim.log.levels.ERROR)
  else
    vim.notify(("Scoper: created and switched to %q"):format(name))
  end
  return result
end

function M.use(name)
  if not name or name == "" then
    local context = State().context()
    UI().pick_one(State().scope_names(), { prompt = "Switch to scope:" }, function(choice)
      if same_context(context, false) then M.use(choice) end
    end)
    return
  end
  local ok, err, result = State().set_active(name)
  if not ok then
    vim.notify("Scoper: " .. err, vim.log.levels.ERROR)
  else
    vim.notify(("Scoper: active scope → %q"):format(name))
  end
  return result
end

function M.delete(names)
  -- Normalize: nil / empty list → picker. String → singleton list.
  -- Same shape as M.add and M.remove (the dispatcher already converts
  -- the no-arg case to nil, so an empty-string slipping through here
  -- would be a programming error; we don't special-case it).
  if not names or (type(names) == "table" and #names == 0) then
    local context = State().context()
    UI().pick_many(State().scope_names(), { prompt = "Delete scope(s)" }, function(picked)
      if #picked > 0 and same_context(context, false) then M.delete(picked) end
    end)
    return
  end
  if type(names) == "string" then names = { names } end

  -- Loop over the list, collecting successes and failures separately
  -- so a single bad name (e.g. typo, or the "last scope" guard tripping
  -- partway through) doesn't suppress reporting of the ones that did
  -- delete. delete_scope's own guard against deleting the final scope
  -- still fires per-iteration, so :ScoperDelete a b c d (where these
  -- are ALL the scopes) will delete the first three and report the
  -- fourth as "cannot delete the last scope".
  local deleted, errors, outcomes = {}, {}, {}
  for _, name in ipairs(names) do
    local ok, err, result = State().delete_scope(name)
    outcomes[#outcomes + 1] = { name = name, result = result }
    if ok then
      table.insert(deleted, name)
    else
      table.insert(errors, ("%s (%s)"):format(name, err))
    end
  end

  if #deleted > 0 then
    vim.notify(("Scoper: deleted %d scope(s): %s"):format(#deleted, table.concat(deleted, ", ")))
  end
  if #errors > 0 then
    vim.notify("Scoper: could not delete " .. table.concat(errors, "; "), vim.log.levels.ERROR)
  end
  return { deleted = deleted, errors = errors, outcomes = outcomes }
end

-- Show a panel listing every scope with member counts.
function M.scopes()
  local lines = { "Scopes:" }
  for _, name in ipairs(State().scope_names()) do
    local marker = name == State().active_name() and "→ " or "  "
    local sc = State().scope(name)
    table.insert(
      lines,
      ("%s%s  (%d include, %d exclude)"):format(marker, name, #sc.include, #sc.exclude)
    )
  end
  table.insert(lines, "")
  table.insert(lines, "Use :ScoperUse <name> to switch.")
  UI().show_lines(lines, "Scoper — all scopes")
end

function M.toggle()
  local result = State().toggle()
  vim.notify(("Scoper: %s"):format(State().is_enabled() and "ON" or "OFF"))
  return result
end

function M.status()
  local sc = State().active_scope()
  vim.notify(
    ("Scoper: %s · scope=%q · %d include · %d exclude"):format(
      State().is_enabled() and "ON" or "OFF",
      State().active_name(),
      sc and #sc.include or 0,
      sc and #sc.exclude or 0
    )
  )
end

-- ---------------------------------------------------------------------------
-- Lualine component. Add to your sections to show scope at a glance:
--   lualine_x = { require("scoper").lualine, ... }
-- ---------------------------------------------------------------------------
function M.lualine()
  if not State().is_enabled() then return "" end
  return ("◎ %s"):format(State().active_name())
end

-- ---------------------------------------------------------------------------
-- Pickers (delegate)
-- ---------------------------------------------------------------------------
-- stylua: ignore start
function M.find()    Pick().find() end
function M.grep(q)   Pick().grep(q) end
function M.replace() Pick().replace() end
-- stylua: ignore end
function M.toggle_picker()
  Pick().toggle_picker()
end

-- ---------------------------------------------------------------------------
-- LSP (delegate)
-- ---------------------------------------------------------------------------
function M.lsp_reload()
  LSP().reload_clangd()
end
function M.clangd_cmd(extra)
  return LSP().clangd_cmd(extra)
end

-- Predicate: useful for plugins that want to check scope themselves. The
-- optional `cwd` is what relative paths and includes resolve against
-- (default: the project root). Each call prepares the scope again; to
-- test many paths, get a matcher once and call it per path.
function M.is_in_scope(path, cwd)
  return State().is_in_scope(path, cwd)
end

-- fn(path) → bool for the active scope as it is now.
function M.matcher(cwd)
  return State().matcher(cwd)
end

return M
