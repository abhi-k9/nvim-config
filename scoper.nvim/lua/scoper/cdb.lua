-- lua/scoper/cdb.lua
--
-- The expensive half of the clangd filter: read compile_commands.json,
-- keep the entries in scope, write the result and its meta file. Every
-- input arrives in `job` (built by lsp.lua) and nothing is read from
-- scoper's state, so the same code runs in this Neovim and in the
-- background process lsp.lua starts (cdb_worker.lua) to keep the main loop
-- free on big databases (~400-500 ms for 10k entries / 20 MB).

local State = require("scoper.state")
local Path = require("scoper.path")
local Util = require("scoper.util")

local M = {}

-- ---------------------------------------------------------------------------
-- The entries whose file `in_scope(path)` accepts.
--
-- A compile_commands entry's `file` may be relative — per the JSON Compilation
-- Database spec it is then relative to that entry's own `directory`, NOT to
-- nvim's cwd. We resolve against `directory` first so databases that emit a
-- relative `file` (some generators do) classify correctly. Absolute `file`
-- values are passed through unchanged.
-- ---------------------------------------------------------------------------
function M.filter(entries, in_scope)
  local kept = {}
  for _, e in ipairs(entries) do
    local file = e.file
    if type(file) == "string" then
      if type(e.directory) == "string" then file = Path.absolute(file, e.directory) end
      if in_scope(file) then table.insert(kept, e) end
    end
  end
  return kept
end

-- Why `entries` isn't a JSON Compilation Database, or nil if it is: a list
-- of objects, each with a string `file` and `directory` and a string
-- `command` or a list of string `arguments`. A bad database is reported
-- and the previous filtered output is left in place.
function M.invalid(entries)
  if not vim.islist(entries) then return "the top level is not a list" end
  for i, e in ipairs(entries) do
    if type(e) ~= "table" then return ("entry %d is not an object"):format(i) end
    if type(e.file) ~= "string" or type(e.directory) ~= "string" then
      return ("entry %d has no file or directory"):format(i)
    end
    local args = e.arguments
    if
      type(e.command) ~= "string"
      and not (
        vim.islist(args)
        and #vim.tbl_filter(function(a)
            return type(a) ~= "string"
          end, args)
          == 0
      )
    then
      return ("entry %d has neither a command nor a list of arguments"):format(i)
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Run one filter job:
--   job.cc          source compile_commands.json
--   job.root        project root the scope's paths are relative to
--   job.scope       { include, exclude }
--   job.out_dir     where compile_commands.json + .scoper-meta.json go
--   job.meta        inputs to record in the meta file (src, mtime, size,
--                   fingerprint; see lsp.lua's freshness cache)
--   job.old_digest  sha256 of the current output, nil when there is none
--
-- Returns a table: { dir, info, changed } when the filter applied,
-- { info } when it couldn't (dir nil), plus `warn` for a message the
-- caller should show (the worker has no UI).
-- ---------------------------------------------------------------------------
function M.run(job)
  local ok, entries = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(job.cc), "\n"))
  end)
  if not ok or type(entries) ~= "table" then
    return { info = "compile_commands.json is not valid JSON" }
  end
  local bad = M.invalid(entries)
  if bad then return { info = "compile_commands.json is not a compilation database: " .. bad } end

  local kept = M.filter(entries, State.build_matcher(job.scope, job.root))
  local encoded = vim.json.encode(kept)
  local out_path = job.out_dir .. "/compile_commands.json"
  -- Did the database clangd will read actually change? Source-database
  -- edits affecting only entries outside this scope rewrite nothing, so
  -- automatic reload can skip restarting clangd. Different scope contents
  -- use separate directories. The meta file hashes the current output.
  local digest = vim.fn.sha256(encoded)
  local changed = digest ~= job.old_digest

  vim.fn.mkdir(job.out_dir, "p")

  -- Atomic write (util.atomic_write: tmp + rename). Same rationale as
  -- state.save, plus one extra reason specific to this file: it is
  -- read by ANOTHER PROCESS (clangd) via inotify on Linux /
  -- ReadDirectoryChangesW on Windows. A direct writefile to out_path
  -- means clangd's watcher could fire on IN_MODIFY mid-write and read
  -- a truncated JSON, which would parse-fail and drop clangd back to
  -- ad-hoc flags — the exact failure mode lsp.lua is structured to
  -- prevent. With the rename, clangd sees one atomic IN_MOVED_TO event
  -- with the final file in place. The PID-suffixed tmp name also handles
  -- two Neovim instances sharing this cache dir.
  if changed then
    local ok_w, w_err = Util.atomic_write(out_path, { encoded })
    if not ok_w then
      return {
        info = "filter " .. w_err,
        warn = "Scoper: failed to install filtered compile_commands: " .. w_err,
      }
    end
  end

  -- Best-effort: a failed meta write just means the next run re-filters.
  local out_st = vim.uv.fs_stat(out_path)
  local meta = vim.tbl_extend(
    "force",
    job.meta,
    { digest = digest, out_size = out_st and out_st.size, kept = #kept, total = #entries }
  )
  Util.atomic_write(job.out_dir .. "/.scoper-meta.json", { vim.json.encode(meta) })

  return {
    dir = job.out_dir,
    info = ("%d/%d entries kept → %s"):format(#kept, #entries, out_path),
    changed = changed,
  }
end

return M
