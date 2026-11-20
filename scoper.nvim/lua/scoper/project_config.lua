-- Declarative project settings. Only explicitly allowed data reaches setup;
-- executable paths, compiler trust and Lua callbacks remain local settings.
local Path = require("scoper.path")
local M = {}
local LIMIT = 1024 * 1024

local function text(value)
  assert(
    type(value) == "string" and value ~= "" and not value:find("%z"),
    "expected nonempty string"
  )
end
local function list(value, pattern)
  assert(type(value) == "table" and vim.islist(value), "expected an array")
  assert(#value <= 4096, "too many list entries")
  for _, item in ipairs(value) do
    text(item)
    if pattern then assert(Path.valid_glob(item), "invalid glob: " .. item) end
  end
end
local function enum(value, choices)
  assert(vim.tbl_contains(choices, value), "invalid value: " .. tostring(value))
end
local function boolean(value)
  assert(type(value) == "boolean", "expected boolean")
end

function M.validate(doc, json_shapes)
  -- Trusted Lua options use {} for an empty dictionary. Decoded JSON
  -- preserves the distinction between an empty object and an empty array.
  local function object(value, name, fields)
    assert(
      type(value) == "table" and (not json_shapes or not vim.islist(value)),
      name .. " must be an object"
    )
    for key in pairs(value) do
      assert(fields[key], name .. ": unsupported field " .. tostring(key))
    end
  end
  object(
    doc,
    "project config",
    { version = true, settings = true, scopes = true, active = true, enabled = true }
  )
  assert(doc.version == 1, "unsupported project config version")
  local settings = doc.settings == nil and vim.empty_dict() or doc.settings
  object(
    settings,
    "settings",
    { default_excludes = true, picker = true, compilation_database = true, lsp = true }
  )
  if settings.default_excludes ~= nil then list(settings.default_excludes, true) end
  if settings.picker ~= nil then enum(settings.picker, { "auto", "fzf", "telescope" }) end
  if settings.compilation_database ~= nil then
    local db = settings.compilation_database
    object(db, "compilation_database", { path = true, candidates = true })
    if db.path ~= nil and db.path ~= false then text(db.path) end
    if db.candidates ~= nil then
      list(db.candidates)
      assert(#db.candidates <= 256, "too many database candidates")
    end
  end
  if settings.lsp ~= nil then
    local lsp = settings.lsp
    object(lsp, "lsp", {
      mode = true,
      startup = true,
      watch = true,
      debounce_ms = true,
      prepare_timeout_ms = true,
      shutdown_timeout_ms = true,
      exit_timeout_ms = true,
    })
    if lsp.mode ~= nil then enum(lsp.mode, { "disabled", "native", "selected", "filtered" }) end
    if lsp.startup ~= nil then enum(lsp.startup, { "fallback", "prepare" }) end
    if lsp.watch ~= nil then boolean(lsp.watch) end
    for _, key in ipairs({
      "debounce_ms",
      "prepare_timeout_ms",
      "shutdown_timeout_ms",
      "exit_timeout_ms",
    }) do
      local n = lsp[key]
      if n ~= nil then
        assert(
          type(n) == "number" and n >= 1 and n <= 600000 and n % 1 == 0,
          key .. " must be 1..600000"
        )
      end
    end
  end
  if doc.scopes ~= nil then
    assert(type(doc.scopes) == "table" and next(doc.scopes), "scopes must be a nonempty object")
    for name, scope in pairs(doc.scopes) do
      assert(
        type(name) == "string" and name:match("^[%w_%-%.]+$") and name ~= "." and name ~= "..",
        "invalid scope name"
      )
      object(scope, "scope " .. name, { include = true, exclude = true })
      if scope.include ~= nil then list(scope.include, true) end
      if scope.exclude ~= nil then list(scope.exclude, true) end
    end
  end
  if doc.active ~= nil then
    text(doc.active)
    assert(doc.scopes and doc.scopes[doc.active], "active must name a configured scope")
  end
  if doc.enabled ~= nil then boolean(doc.enabled) end
  return doc
end

function M.path(root)
  return Path.absolute(".scoper.json", root)
end

-- Compare the object and generation, ignoring access-time changes caused by
-- this read. Concurrent edits/replacements must not be accepted as one snapshot.
local function same_file(a, b)
  return a
    and b
    and a.type == "file"
    and b.type == "file"
    and a.dev == b.dev
    and a.ino == b.ino
    and a.size == b.size
    and vim.deep_equal(a.mtime, b.mtime)
    and vim.deep_equal(a.ctime, b.ctime)
end

function M.read(root)
  local path = M.path(root)
  local stat, err, code = vim.uv.fs_lstat(path)
  if not stat then
    if code == "ENOENT" then return {} end
    return nil, err
  end
  if stat.type ~= "file" then return nil, ".scoper.json must be a regular file (no symlinks)" end
  if stat.size > LIMIT then return nil, ".scoper.json exceeds 1 MiB" end
  local ok, doc = pcall(function()
    -- A bounded read also covers a file growing after the size check.
    local fd = assert(vim.uv.fs_open(path, "r", 0))
    local opened = vim.uv.fs_fstat(fd)
    local contents, read_err = vim.uv.fs_read(fd, LIMIT + 1, 0)
    local after = vim.uv.fs_fstat(fd)
    vim.uv.fs_close(fd)
    assert(contents, read_err)
    assert(
      same_file(stat, opened)
        and same_file(opened, after)
        and same_file(after, vim.uv.fs_lstat(path)),
      "project config changed while reading; reload to retry"
    )
    assert(#contents <= LIMIT, ".scoper.json exceeds 1 MiB")
    assert(#contents == opened.size, "incomplete project config read")
    return M.validate(vim.json.decode(contents), true)
  end)
  if not ok then return nil, tostring(doc) end
  return doc
end

-- Pretty JSON without an external formatter; strings are encoded by Neovim.
local function pretty(value, depth)
  if type(value) ~= "table" then return vim.json.encode(value) end
  local array, rows = vim.islist(value), {}
  local keys = array and vim.fn.range(1, #value) or vim.tbl_keys(value)
  if not array then table.sort(keys) end
  for _, key in ipairs(keys) do
    rows[#rows + 1] = string.rep("  ", depth + 1)
      .. (array and "" or vim.json.encode(key) .. ": ")
      .. pretty(value[key], depth + 1)
  end
  local left, right = array and "[" or "{", array and "]" or "}"
  if #rows == 0 then return left .. right end
  return left .. "\n" .. table.concat(rows, ",\n") .. "\n" .. string.rep("  ", depth) .. right
end

function M.export(root, doc, overwrite)
  local ok, err = pcall(M.validate, doc, true)
  if not ok then return false, tostring(err) end
  local encoded = pretty(doc, 0) .. "\n"
  if #encoded > LIMIT then return false, "export exceeds 1 MiB" end
  local path = M.path(root)
  local stat, stat_err, code = vim.uv.fs_lstat(path)
  if not stat and code ~= "ENOENT" then return false, stat_err end
  if stat and (not overwrite or stat.type ~= "file") then
    return false, "config exists or is not a regular file; use ! to replace a regular file"
  end
  -- Publish a complete file. A hard link gives no-clobber creation even if
  -- another editor creates the target concurrently. Unsupported filesystems
  -- fail explicitly rather than falling back to overwriting another file.
  local temp = path .. ".tmp." .. vim.fn.getpid() .. "." .. vim.uv.hrtime()
  local fd, open_err = vim.uv.fs_open(temp, "wx", 384)
  if not fd then return false, open_err end
  local written, write_err = vim.uv.fs_write(fd, encoded, 0)
  local closed, close_err = vim.uv.fs_close(fd)
  local published, publish_err
  if written == #encoded and closed then
    if overwrite then
      published, publish_err = vim.uv.fs_rename(temp, path)
    else
      published, publish_err = vim.uv.fs_link(temp, path)
    end
  end
  vim.uv.fs_unlink(temp)
  return published == true,
    write_err or close_err or publish_err or (not published and "incomplete write" or nil)
end

return M
