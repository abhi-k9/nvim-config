-- lua/scoper/util.lua
--
-- Small helpers shared by ≥2 callers. Kept small on purpose; if this
-- file grows much further, the contents probably want to live in
-- topic-specific modules instead. atomic_write (I/O) lives here too:
-- state.lua and lsp.lua both need it, and one copy beats two.

local M = {}

-- ---------------------------------------------------------------------------
-- Turn a raw user-command args string into either nil (no arguments) or
-- a list of whitespace-separated tokens. The dispatchers in
-- plugin/scoper.lua use this to forward to the picker (when nil) vs the
-- direct path (when a list).
--
-- A backslash-escaped space ("my\ dir") stays inside its token and is
-- unescaped. That is exactly what `complete = "dir"` inserts for a
-- directory containing spaces, so `:ScoperAdd my<Tab>` works (splitting on
-- every space would give the two bogus paths "my\" and "dir").
-- Only "\" + whitespace is special, so Windows paths ("C:\src\app") pass
-- through untouched.
--
-- Returns:
--   nil           when `s` is empty or whitespace-only
--   { tok, ... }  list of non-empty tokens otherwise
-- ---------------------------------------------------------------------------
function M.split_args(s)
  if not s or s == "" then return nil end
  local out, cur, i = {}, {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    local nxt = s:sub(i + 1, i + 1)
    if c == "\\" and nxt:match("%s") then
      cur[#cur + 1] = nxt
      i = i + 2
    elseif c:match("%s") then
      if #cur > 0 then
        out[#out + 1] = table.concat(cur)
        cur = {}
      end
      i = i + 1
    else
      cur[#cur + 1] = c
      i = i + 1
    end
  end
  if #cur > 0 then out[#out + 1] = table.concat(cur) end
  if #out == 0 then return nil end
  return out
end

-- ---------------------------------------------------------------------------
-- Module availability. `require` inside pcall is enough: under lazy.nvim
-- a package.loaders hook makes require() load lazy plugins on demand, so
-- this both answers the question and (deliberately) loads the backend.
-- Callers must short-circuit any user preference check BEFORE calling
-- this, so we never load a picker the user opted out of.
-- ---------------------------------------------------------------------------
function M.has(mod)
  return (pcall(require, mod))
end

-- Backend preference, shared by pickers.lua and ui.lua. Order matters: the
-- vim.g check must run first so `has()` never force-loads fzf-lua for a
-- telescope user (see above).
function M.prefer_fzf()
  return vim.g.scoper_picker ~= "telescope" and M.has("fzf-lua")
end

-- ---------------------------------------------------------------------------
-- Per-project key: first 16 hex chars of sha256 of the (already
-- normalized) cwd. Used for both the state store filename and the
-- filtered compile_commands cache dir — it MUST stay one function, or
-- the two could silently disagree about which project is which.
-- ---------------------------------------------------------------------------
function M.cwd_hash(normalized_cwd)
  return vim.fn.sha256(normalized_cwd):sub(1, 16)
end

-- ---------------------------------------------------------------------------
-- Atomic file write: write to a PID-suffixed temp file in the same
-- directory, then rename over the target. rename(2) within one
-- filesystem is atomic, so readers (another nvim instance, or clangd's
-- inotify watch, which fires IN_MOVED_TO for renames) never observe a
-- half-written file. The PID and a per-process counter in the suffix keep
-- two nvim instances, or two writes of one instance, from sharing a temp
-- file.
--
-- Never throws: writefile() raises an error on failure (it doesn't just
-- return -1), so it runs under pcall.
--
-- Returns: ok:boolean, err:string|nil ("write failed: ..." | "rename failed: ...")
-- ---------------------------------------------------------------------------
local write_seq = 0

function M.atomic_write(path, lines)
  write_seq = write_seq + 1
  local tmp = ("%s.tmp.%d.%d"):format(path, vim.fn.getpid(), write_seq)
  local wrote, res = pcall(vim.fn.writefile, lines, tmp)
  if not wrote or res ~= 0 then
    pcall(vim.uv.fs_unlink, tmp)
    return false, "write failed: " .. tostring(res)
  end
  local ok, err = vim.uv.fs_rename(tmp, path)
  if not ok then
    pcall(vim.uv.fs_unlink, tmp)
    return false, "rename failed: " .. tostring(err)
  end
  return true
end

return M
