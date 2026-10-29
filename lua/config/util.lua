-- lua/config/util.lua
--
-- Shared helpers for this config:
--
--   * delete_buffer_keep_windows — the full "skip-if-dirty, detach, delete"
--     routine, used by smart_bdelete / <leader>bd (lua/config/keymaps.lua),
--     the bufferline context menu + close_command (lua/plugins/ui.lua) and
--     delete_buffers_from_picker (below).
--   * delete_buffers_keep_windows / notify_bulk_result — the batched
--     variant for multi-select deletes.
--   * notify_undeleted — the shared "why didn't that buffer close?"
--     message for single deletes.
--   * delete_buffers_from_picker — the whole delete action of BOTH buffer
--     pickers (telescope <C-d>/<M-d>, fzf-lua <C-x>, lua/plugins/finder.lua);
--     each picker only turns its entries into bufnrs and refreshes its list.
--   * augroup, is_file_buffer, the buffer_menu hook and windows_tar_shim.
--
-- The configured buffer-close mappings, menus and pickers share these helpers.
-- Normal closes skip unsaved changes; an explicitly forced single close can
-- discard them. Terminal deletion needs force and stops its running job.
-- Raw :bdelete/:bwipeout commands retain Neovim's own behavior.

local M = {}

-- Pick the buffer a window should land on when its current buffer goes
-- away. `excluded` is a set (bufnr -> true) of buffers that must not be
-- chosen — for a single delete that's just the dying buffer, for a bulk
-- delete it's the whole doomed set (choosing a fellow victim is what
-- made bulk deletes chain; see delete_buffers_keep_windows below).
--
-- Preference order (rationale in the delete functions' comments):
--   1. the window's own alternate buffer ('#'), if listed + LOADED
--   2. most-recently-used listed + LOADED buffer (lastused desc,
--      ties -> higher bufnr)
--   3. MRU listed buffer even if unloaded (cold load unavoidable)
--   4. nil -> caller parks the window on a fresh [No Name]
local function pick_replacement(win, excluded, cache)
  local alt = vim.api.nvim_win_call(win, function()
    return vim.fn.bufnr("#")
  end)
  if
    alt > 0
    and not excluded[alt]
    and vim.api.nvim_buf_is_valid(alt)
    and vim.bo[alt].buflisted
    and vim.api.nvim_buf_is_loaded(alt)
  then
    return alt
  end
  -- MRU scan, computed once per operation and cached across windows.
  if not cache.scanned then
    cache.scanned = true
    local infos = vim.fn.getbufinfo({ buflisted = 1 })
    table.sort(infos, function(a, b)
      if a.lastused ~= b.lastused then return a.lastused > b.lastused end
      return a.bufnr > b.bufnr
    end)
    for _, info in ipairs(infos) do
      if not excluded[info.bufnr] and vim.api.nvim_buf_is_valid(info.bufnr) then
        if not cache.mru_any then cache.mru_any = info.bufnr end
        if info.loaded == 1 then
          cache.mru_loaded = info.bufnr
          break
        end
      end
    end
  end
  return cache.mru_loaded or cache.mru_any
end

-- Re-point every window showing any buffer in `excluded` (a set) at a
-- replacement outside the set. Shared by the single- and bulk-delete
-- paths below.
local function detach_set_from_windows(excluded)
  local cache = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    -- A replacement's BufWinEnter hooks may close other windows in this
    -- snapshot. Revalidate before inspecting each one and after a switch.
    if vim.api.nvim_win_is_valid(win) and excluded[vim.api.nvim_win_get_buf(win)] then
      local alt = pick_replacement(win, excluded, cache)
      -- Switching to an UNLOADED replacement reads its file, which can
      -- raise (a swap-file prompt answered with Abort → E325, a read
      -- error); fall back to [No Name] then.
      if
        not (alt and pcall(vim.api.nvim_win_set_buf, win, alt))
        and vim.api.nvim_win_is_valid(win)
      then
        if vim.wo[win].winfixbuf then
          -- 'winfixbuf' refuses every buffer switch (E1513), [No Name]
          -- included, so the window closes with its buffer.
          pcall(vim.api.nvim_win_close, win, false)
        else
          -- No listed buffer survives: park the window on a fresh
          -- [No Name] buffer, mirroring what Vim does when you :bd the
          -- last buffer. nvim_win_call keeps focus where it was.
          pcall(vim.api.nvim_win_call, win, function()
            vim.cmd("enew")
          end)
        end
      end
    end
  end
end

-- Delete a buffer with vim.g.syntax_on masked. Why: Neovim's
-- TSHighlighter:destroy() (fired via on_detach when a
-- treesitter-highlighted buffer is deleted) re-runs the `syntaxset`
-- FileType autocmd inside nvim_buf_call to re-apply LEGACY regex syntax
-- to the buffer — a buffer that is in the middle of being deleted, so
-- the work is 100% wasted. That branch is guarded by
-- `vim.g.syntax_on == 1`, and with a floating window focused (a
-- telescope/fzf picker — exactly where bulk deletes happen) it turns
-- pathological: profiled 99% of time on highlighter.lua's
-- nvim_buf_call line, at 100 ms up to SECONDS per buffer (measured
-- 131,904 ms for 30 deletes with the picker open on 0.12.4; 3 ms for
-- the same deletes without the mask absent the float). Masking the
-- flag for the duration of the delete call skips that redundant re-apply;
-- existing highlighters in other buffers are not explicitly disabled.
-- pcall-protected so the flag is always restored.
local function delete_buf_quietly(b, opts)
  local saved = vim.g.syntax_on
  vim.g.syntax_on = nil
  local ok = pcall(vim.api.nvim_buf_delete, b, opts or {})
  vim.g.syntax_on = saved
  return ok
end

-- For every window currently displaying `bufnr`, switch that window to
-- another listed buffer (or a fresh [No Name] when none exists) so a
-- subsequent buffer delete doesn't take the window with it.
--
-- Why this matters: nvim_buf_delete wipes the buffer like :bwipeout, and
-- like :bdelete/:bwipeout it closes ALL windows showing it ("Any windows
-- for this buffer are closed"). Re-pointing EVERY window that shows it
-- (not just the current one) first makes the delete strictly a buffer
-- operation.
local function detach_buffer_from_windows(bufnr)
  -- WHICH buffer each window lands on matters for speed: pick_replacement
  -- prefers the alternate / most-recent LOADED buffer, because switching a
  -- window to an unloaded buffer loads it synchronously and fires the whole
  -- attach cascade (BufRead autocmds, treesitter, LSP didOpen, gitsigns,
  -- ufo). Measured: 8 consecutive closes ≈ 50 ms this way vs 825 ms when
  -- cold buffers were picked.
  detach_set_from_windows({ [bufnr] = true })
end

function M.delete_buffer_keep_windows(bufnr, force)
  if not vim.api.nvim_buf_is_valid(bufnr) then return "deleted" end
  force = force or vim.bo[bufnr].buftype == "terminal"
  if not force and vim.bo[bufnr].modified then return "skipped" end
  detach_buffer_from_windows(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return "deleted" end
  local ok = delete_buf_quietly(bufnr, { force = force })
  return ok and "deleted" or "failed"
end

-- Standard warning for a delete_buffer_keep_windows call that didn't
-- delete, so every caller words it the same way. `status` is
-- the return value of delete_buffer_keep_windows; "deleted" is a no-op
-- so callers can pass every result through unconditionally.
function M.notify_undeleted(bufnr, status)
  if status == "deleted" then return end
  local msg = status == "skipped" and "Skipped (unsaved changes): %s" or "Not deleted: %s"
  vim.notify(
    msg:format(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")),
    vim.log.levels.WARN
  )
end

-- Bulk variant: delete many buffers as ONE operation. This is not a
-- loop over delete_buffer_keep_windows, and the difference is the whole
-- point. Deleting one-by-one, every time the DISPLAYED buffer dies its
-- window is repointed to the MRU buffer — which, when most recent
-- buffers are selected, is the next victim — so the window chains
-- through one repoint per buffer, each dragging BufWinLeave->mkview,
-- BufWinEnter->loadview, ufo, gitsigns and incline along. Measured on a
-- 60-buffer sweep: ~21 s one-by-one vs a single repoint batched. Each
-- skipped buffer would also fire its own notification.
--
-- The batch does it right:
--   1. dirty buffers are set aside untouched (bulk deletion has no explicit
--      force-discard option),
--   2. every window showing ANY doomed buffer is repointed ONCE to a
--      survivor OUTSIDE the doomed set,
--   3. the buffers are deleted in a tight loop,
--   4. one summary is returned; callers show one notification via
--      notify_bulk_result instead of N popups.
--
-- Returns { deleted = n, skipped = {names}, failed = {names} }.
function M.delete_buffers_keep_windows(bufs)
  local res = { deleted = 0, skipped = {}, failed = {} }
  local doomed, names = {}, {}
  local function shortname(b)
    local n = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
    return n ~= "" and n or ("[buf %d]"):format(b)
  end
  for _, b in ipairs(bufs) do
    if b and vim.api.nvim_buf_is_valid(b) then
      if vim.bo[b].modified then
        table.insert(res.skipped, shortname(b))
      else
        doomed[b] = true
        names[b] = shortname(b)
      end
    end
  end
  detach_set_from_windows(doomed)
  for b in pairs(doomed) do
    -- Hooks fired while detaching may already have wiped another target.
    if not vim.api.nvim_buf_is_valid(b) then
      res.deleted = res.deleted + 1
    else
      -- Terminals need force to end the running job; modified targets have
      -- already been excluded above.
      local force = vim.bo[b].buftype == "terminal"
      if delete_buf_quietly(b, { force = force }) then
        res.deleted = res.deleted + 1
      else
        table.insert(res.failed, names[b])
      end
    end
  end
  return res
end

-- One summary notification for a bulk delete. Listing a few names keeps
-- the "why didn't everything close?" question answerable without
-- stacking one popup per buffer.
function M.notify_bulk_result(res)
  local parts = { ("Deleted %d buffer(s)"):format(res.deleted) }
  local function name_list(t)
    local shown = vim.list_slice(t, 1, 3)
    local suffix = #t > 3 and (" (+%d more)"):format(#t - 3) or ""
    return table.concat(shown, ", ") .. suffix
  end
  if #res.skipped > 0 then
    table.insert(
      parts,
      ("skipped %d with unsaved changes: %s"):format(#res.skipped, name_list(res.skipped))
    )
  end
  if #res.failed > 0 then table.insert(parts, ("failed: %s"):format(name_list(res.failed))) end
  local level = (#res.skipped + #res.failed) > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  vim.notify(table.concat(parts, "; "), level)
end

-- The delete action shared by both buffer pickers. `bufs` are the target
-- bufnrs: the multi-selection, or just the highlighted entry. One target
-- goes through delete_buffer_keep_windows with its specific "why not"
-- message; several go through the batched path with a single summary.
-- Either way dirty buffers are skipped untouched and terminals are forced.
-- The caller refreshes its list afterwards (deleted buffers are invalid).
function M.delete_buffers_from_picker(bufs)
  local list = {}
  for _, b in ipairs(bufs) do
    if b then list[#list + 1] = b end
  end
  if #list > 1 then
    M.notify_bulk_result(M.delete_buffers_keep_windows(list))
  elseif list[1] and vim.api.nvim_buf_is_valid(list[1]) then
    M.notify_undeleted(list[1], M.delete_buffer_keep_windows(list[1]))
  end
end

-- Augroup with the config's "user_" prefix, cleared on (re)creation.
function M.augroup(name)
  return vim.api.nvim_create_augroup("user_" .. name, { clear = true })
end

-- Decode a stored comma-separated path option like copy_option_part().
-- Only a backslash before a comma is removed; Windows/UNC separators
-- remain literal. :set's own escaping has already happened at this point.
function M.option_paths(value)
  local entries, pos = {}, 1
  while pos <= #value do
    local chars = {}
    while pos <= #value and value:sub(pos, pos) ~= "," do
      if value:sub(pos, pos + 1) == "\\," then pos = pos + 1 end
      chars[#chars + 1] = value:sub(pos, pos)
      pos = pos + 1
    end
    entries[#entries + 1] = table.concat(chars)
    pos = pos + 1
    while value:sub(pos, pos) == " " do
      pos = pos + 1
    end
  end
  return entries
end

-- Is `buf` an ordinary file buffer: buftype "", a name, and that name not
-- a URI ("diffview://…", "fugitive://…", "oil://…"; file:// counts as a
-- file)? The single definition of "real file" for fold views, the LSP
-- attach guard, session rescue and the bufferline menu.
function M.is_file_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return false end
  return not name:match("^%a[%w+.-]+://") or name:match("^file://") ~= nil
end

-- ---------------------------------------------------------------------------
-- Buffer tab menu hook. lua/plugins/ui.lua registers the bufferline context
-- menu here once bufferline is set up; <leader>bm (same file) opens it.
-- ---------------------------------------------------------------------------
M.buffer_menu = nil

-- ---------------------------------------------------------------------------
-- Windows: make `tar` mean Windows' own bsdtar for Neovim's child processes.
--
-- Mason unpacks archives with `tar --no-same-owner -xvf …` (or `gtar` when
-- present). On Windows the first `tar` on PATH is often NOT
-- C:\Windows\System32\tar.exe but one bundled with some other tool (Git
-- for Windows, MSYS, vendor shells such as "ds_shell"), and those can reject
-- the option — "tar.EXE: unrecognized option `--no-same-owner'" — or
-- misread "C:\…" paths as remote hosts. Every Mason install that ships a
-- tarball then fails (shellcheck, …).
--
-- Fix, scoped to this Neovim process and its children: copy System32's
-- tar.exe once into stdpath("data")/tar-shim/ and put THAT directory first
-- on $PATH. Only `tar` changes — putting all of System32 first would also
-- swap `find`, `sort`, … for the Windows versions. No-op elsewhere, when
-- `tar` already is System32's, or when System32 has no tar.exe (pre-1803
-- Windows 10). Opt out with `vim.g.windows_tar_shim = false`.
--
-- `o` overrides the environment for tests: { is_win, system_tar, dir }.
-- Returns the shim directory when it was put on PATH, else nil.
-- ---------------------------------------------------------------------------
function M.windows_tar_shim(o)
  o = o or {}
  local is_win = o.is_win
  if is_win == nil then is_win = vim.fn.has("win32") == 1 end
  if not is_win or vim.g.windows_tar_shim == false then return nil end
  local system_tar = o.system_tar
    or ((vim.env.SystemRoot or "C:\\Windows") .. "\\System32\\tar.exe")
  local src = vim.uv.fs_stat(system_tar)
  if not src then return nil end
  local function same(a, b)
    return vim.fs.normalize(a):lower() == vim.fs.normalize(b):lower()
  end
  local current = vim.fn.exepath("tar")
  if current ~= "" and same(current, system_tar) then return nil end
  local dir = o.dir or (vim.fn.stdpath("data") .. "/tar-shim")
  local shim = dir .. "/" .. vim.fs.basename(system_tar)
  -- The copy is current when it is a plain file with the source's size AND
  -- modification time (set on the copy below), so an update of System32's
  -- tar that keeps its size still refreshes it. A link is never reused.
  -- Copied to a temp name and renamed, so a failed copy can't leave a
  -- truncated tar.exe first on PATH.
  local dst = vim.uv.fs_lstat(shim)
  if not dst or dst.type ~= "file" or dst.size ~= src.size or dst.mtime.sec ~= src.mtime.sec then
    vim.fn.mkdir(dir, "p")
    local tmp = shim .. ".tmp"
    local ok, err = vim.uv.fs_copyfile(system_tar, tmp)
    if ok then
      ok, err = vim.uv.fs_utime(tmp, src.atime.sec, src.mtime.sec)
    end
    if ok then
      if dst and dst.type ~= "file" then vim.uv.fs_unlink(shim) end
      ok, err = vim.uv.fs_rename(tmp, shim)
    end
    if not ok then
      vim.uv.fs_unlink(tmp)
      vim.notify(
        "tar shim: could not copy " .. system_tar .. ": " .. tostring(err),
        vim.log.levels.WARN
      )
      return nil
    end
  end
  local sep = is_win and ";" or ":"
  if not vim.startswith(vim.env.PATH or "", dir .. sep) then
    vim.env.PATH = dir .. sep .. (vim.env.PATH or "")
  end
  return dir
end

return M
