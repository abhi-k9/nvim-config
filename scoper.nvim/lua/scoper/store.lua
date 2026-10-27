-- Versioned on-disk scope storage. Each instance owns its read baseline and
-- lock; it never reaches into the active project or UI configuration.
local Path = require("scoper.path")
local Util = require("scoper.util")
local M = {}
M.SCHEMA_VERSION = 1

function M.new(root, fresh_state)
  local data_dir = vim.fn.stdpath("data") .. "/scoper"
  local messages = {}
  local function notify(message, level)
    messages[#messages + 1] = { message = message, level = level }
  end
  local function fresh_scope()
    return fresh_state().scopes.default
  end
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

  local function store_dir()
    return data_dir
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
    return store_dir() .. "/" .. Util.cwd_hash(Path.key(root)) .. ".json"
  end

  local function legacy_store_path()
    return store_dir() .. "/" .. Util.cwd_hash(root) .. ".json"
  end

  -- Content identity of the state this instance actually read or published.
  -- Mutation frequency is low and state is small, so compare the contents rather
  -- than trusting filesystem timestamp resolution or atomic-rename inode reuse.
  local file_version
  -- Failed reads must never turn session defaults into an overwrite of scopes
  -- we could not inspect or back up. A successful explicit load clears this.
  local read_error
  local read_reason

  local function read_source()
    local path = store_path()
    local st, err, code = vim.uv.fs_stat(path)
    if not st and (code == "ENOENT" or code == "ENOTDIR") then
      path = legacy_store_path()
      st, err, code = vim.uv.fs_stat(path)
    end
    if not st and (code == "ENOENT" or code == "ENOTDIR") then
      return { version = "missing:" .. store_path(), path = path }
    end
    if st and st.type == "file" then
      local ok, lines = pcall(vim.fn.readfile, path)
      if ok then
        return {
          path = path,
          lines = lines,
          version = path .. "\0" .. vim.fn.sha256(table.concat(lines, "\n")),
        }
      end
      err = lines
    elseif st then
      err = "expected a regular file, got " .. tostring(st.type)
    end
    return { path = path, error = tostring(err) }
  end

  local function ensure_dir()
    vim.fn.mkdir(store_dir(), "p")
  end

  -- Publish an already-populated directory to acquire the per-project lock.
  -- Unlike a leased file, a live writer's lock is never expired by elapsed time.
  -- Unique owner markers let a reclaimer/releaser remove only the owner it saw;
  -- rmdir then cannot remove a newly published, nonempty owner's directory.
  local function acquire_lock()
    local path = store_path() .. ".lock"
    local owner = ("owner-%d-%.0f"):format(vim.fn.getpid(), vim.uv.hrtime())
    local staging = path .. ".tmp-" .. owner
    local made, err = vim.uv.fs_mkdir(staging, 448)
    if not made then return nil, err end
    local fd
    fd, err = vim.uv.fs_open(staging .. "/" .. owner, "wx", 384)
    if not fd then
      vim.uv.fs_rmdir(staging)
      return nil, err
    end
    vim.uv.fs_close(fd)
    local function discard()
      vim.uv.fs_unlink(staging .. "/" .. owner)
      vim.uv.fs_rmdir(staging)
    end
    for _ = 1, 3 do
      if vim.uv.fs_rename(staging, path) then return { path = path, owner = owner } end
      local scan = vim.uv.fs_scandir(path)
      if scan then
        local name = vim.uv.fs_scandir_next(scan)
        local extra = vim.uv.fs_scandir_next(scan)
        if not name then
          -- Published locks are never empty; this is an interrupted cleanup.
          vim.uv.fs_rmdir(path)
        elseif not extra then
          local pid = tonumber(name:match("^owner%-(%d+)%-%d+$"))
          local called, alive, _, code
          if pid and pid > 0 then
            called, alive, _, code = pcall(vim.uv.kill, pid, 0)
          end
          if called and not alive and code == "ESRCH" then
            if vim.uv.fs_unlink(path .. "/" .. name) then vim.uv.fs_rmdir(path) end
          else
            discard()
            return nil, "another editor owns the state lock; retry after it finishes: " .. path
          end
        else
          discard()
          return nil, "unrecognized state lock; inspect it before removing: " .. path
        end
      elseif vim.uv.fs_lstat(path) then
        discard()
        return nil, "state lock is not an accessible directory: " .. path
      end
    end
    discard()
    return nil, "state is busy; retry the save"
  end

  local function release_lock(lock)
    if vim.uv.fs_unlink(lock.path .. "/" .. lock.owner) then vim.uv.fs_rmdir(lock.path) end
  end

  local function read_state(source)
    read_error, read_reason = nil, nil
    source = source or read_source()
    local path, lines = source.path, source.lines
    file_version = source.version
    if source.error then
      read_error = source.error
      read_reason = "io_error"
      notify(
        ("Scoper: could not read %s (%s). Saves are blocked; fix the file and reload state explicitly."):format(
          path,
          read_error
        ),
        vim.log.levels.ERROR
      )
      return nil
    end
    if not lines or #lines == 0 then return fresh_state() end

    local ok, parsed = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not ok or type(parsed) ~= "table" then
      -- EXCL: never overwrite an earlier backup from the same second.
      local stamp, backup, copied = os.date("%Y%m%d-%H%M%S"), nil, nil
      for n = 0, 99 do
        backup = ("%s.corrupt-%s%s"):format(path, stamp, n > 0 and ("-" .. n) or "")
        copied = vim.uv.fs_copyfile(path, backup, { excl = true })
        if copied or vim.uv.fs_stat(backup) == nil then break end
      end
      if not copied then
        read_error, read_reason = "corrupt state could not be backed up", "io_error"
      end
      notify(
        ("Scoper: corrupt state file, using defaults. %s"):format(
          copied and ("The old file is kept as " .. backup)
            or ("Could not back up " .. path .. "; saves are blocked until a successful reload")
        ),
        vim.log.levels.WARN
      )
      return fresh_state()
    end

    local schema = parsed.schema_version
    if schema ~= nil and schema ~= M.SCHEMA_VERSION then
      read_error = "unsupported state schema " .. tostring(schema) .. "; saves are blocked"
      read_reason = "unsupported_schema"
      notify(
        "Scoper: " .. read_error .. ". Upgrade Scoper or explicitly restore a supported state file.",
        vim.log.levels.ERROR
      )
      return nil
    end
    parsed.schema_version = M.SCHEMA_VERSION
    if type(parsed.database_path) ~= "string" then parsed.database_path = nil end

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
  local function save(state)
    local ok, err, lock
    if read_error then
      ok, err = false, read_error
    else
      local called
      called, ok, err = pcall(function()
        ensure_dir()
        lock, err = acquire_lock()
        if not lock then return false, err end
        local source = read_source()
        if source.error then
          read_error = source.error
          read_reason = "io_error"
          return false, source.error
        end
        -- A caller may save a newly required module before load(). It is safe
        -- to initialize an absent store, but never to overwrite unread scopes.
        if file_version == nil and not source.lines then file_version = source.version end
        if source.version ~= file_version then
          read_error = "state changed in another editor; reload state explicitly before saving"
          read_reason = "conflict"
          return false, read_error
        end
        -- Legacy callers can still provide the old in-memory shape. New
        -- publications always carry the current schema without mutating them.
        local publication = vim.deepcopy(state)
        publication.schema_version = M.SCHEMA_VERSION
        local encoded = vim.json.encode(publication)
        local written, write_err = Util.atomic_write(store_path(), { encoded })
        if written then file_version = store_path() .. "\0" .. vim.fn.sha256(encoded) end
        return written, write_err
      end)
      if not called then
        ok, err = false, ok
      end
    end
    if lock then release_lock(lock) end
    if not ok then
      notify(
        ("Scoper: failed to save %s (%s). %s"):format(
          store_path(),
          err,
          read_error
              and "The change applies to this session only; reload state explicitly before saving."
            or "The change applies to this session only, until a later change saves."
        ),
        vim.log.levels.ERROR
      )
      return false, err, read_reason or "io_error"
    end
    return true, nil, "saved"
  end

  return {
    path = store_path,
    source = read_source,
    load = read_state,
    save = save,
    version = function()
      return file_version
    end,
    error = function()
      return read_error
    end,
    reason = function()
      return read_reason
    end,
    messages = function()
      local pending = messages
      messages = {}
      return pending
    end,
  }
end

return M
