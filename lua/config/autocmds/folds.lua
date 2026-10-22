-- lua/config/autocmds/folds.lua
--
-- Fold persistence via view files (:mkview / :loadview) and the view-file
-- janitor.

local augroup = require("config.util").augroup

-- ---------------------------------------------------------------------------
-- Fold persistence — remember which folds you had open/closed, per file,
-- across restarts. Uses native view files (:mkview / :loadview); see the
-- viewoptions note in lua/config/options.lua for why this is decoupled from
-- both the session system and nvim-ufo.
--
-- The one wrinkle is timing: ufo recomputes folds ASYNCHRONOUSLY when a buffer
-- loads (LSP-backed) and would reopen them. Rather than hook ufo — it exposes
-- no "folds applied" event, and coupling to its internals is exactly what we're
-- avoiding — we restore on BufWinEnter AND reassert once on the first
-- CursorHold after entering. CursorHold fires after `updatetime` (250ms) of
-- idle, i.e. after ufo has settled, so the reassert lands last and wins without
-- this code ever mentioning ufo. If ufo is absent, native folds are ready at
-- BufWinEnter and the reassert is a harmless no-op. NOTE: viewoptions is
-- folds-only, but that alone does NOT hold the cursor still — :loadview can
-- still shift it as a side effect of its fold-restore commands (the zE +
-- fold-recreation motions leave the cursor wherever they finish, and with no
-- `cursor` entry in the view there is nothing to put it back). Because the
-- reassert fires ~updatetime after entry — often just after a gd / <C-o> /
-- <C-i> jump has settled — an unguarded loadview yanks the cursor off the
-- jump target a beat later. So BOTH loadview calls below wrap it in
-- winsaveview()/winrestview(): the folds are applied, the cursor/scroll are
-- put back exactly where they were.
-- ---------------------------------------------------------------------------
local fold_persistence = augroup("fold_persistence")

-- Only real, named file buffers get a persisted view. buftype ~= "" excludes
-- terminals, help, quickfix, neo-tree, dap panels, etc.; the skip-list covers
-- filetypes where a remembered fold state is unwanted (commit messages).
local FOLD_VIEW_SKIP_FT = { gitcommit = true, gitrebase = true, hgcommit = true, help = true }
-- URI-named buffers (diffview://, fugitive://, …) are excluded even though
-- some have buftype "": their names aren't files, and loadview on one
-- failed with "E484: Can't open file …/view//diffview:=+…".
local function fold_view_eligible(buf)
  return require("config.util").is_file_buffer(buf) and not FOLD_VIEW_SKIP_FT[vim.bo[buf].filetype]
end

-- The file :mkview writes for `buf` (Neovim's get_view_file()): the
-- home-relative path with "=" doubled and every path separator turned
-- into "=+" (on Windows ":" into "=-"), plus a trailing "=".
local function view_file(buf)
  local win = vim.fn.has("win32") == 1
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p:~")
  name = name:gsub("[=/\\:]", function(c)
    if c == "=" then return "==" end
    if c == "/" or (win and c == "\\") then return "=+" end
    if win and c == ":" then return "=-" end
  end)
  return vim.fs.joinpath(vim.o.viewdir, name .. "=")
end

-- Load the saved folds unless there is no view yet (loadview would leave
-- E484 in v:errmsg) or the file changed on disk after the view was
-- written (e.g. `git checkout`): stale manual fold ranges would land on
-- the wrong lines.
local function load_fold_view(buf)
  local saved = vim.uv.fs_stat(view_file(buf))
  local source = vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
  if not saved or not source then return end
  -- getftime() loses subsecond precision: a rapid external rewrite in
  -- the same second can otherwise replay fold ranges from old contents.
  if
    source.mtime.sec > saved.mtime.sec
    or (source.mtime.sec == saved.mtime.sec and source.mtime.nsec > saved.mtime.nsec)
  then
    return
  end
  -- Apply only the folds; loadview can otherwise move the cursor (see the
  -- header note), so bracket it with a view save/restore.
  local view = vim.fn.winsaveview()
  pcall(vim.cmd, "silent! loadview")
  pcall(vim.fn.winrestview, view)
end

-- Save fold state when leaving a window or after writing. silent! + pcall so an
-- odd buffer can never raise (e.g. a name that can't be encoded to a viewfile).
--
-- The view is saved IN a real window that shows the buffer
-- (nvim_win_call), found across all tabs. Two cases need this:
--   * Quitting: `:qa` fires BufWinLeave for every window while some OTHER
--     buffer is current, so "save only if the buffer is current" would
--     keep just one window's folds.
--   * `:wa`: background buffers are written from the temporary autocmd
--     window, which is a float; mkview there would record the autocmd
--     window's state. Floats are never used as the source.
vim.api.nvim_create_autocmd({ "BufWinLeave", "BufWritePost" }, {
  group = fold_persistence,
  callback = function(args)
    if not fold_view_eligible(args.buf) then return end
    -- Prefer the current window; otherwise the first NON-floating window
    -- showing the buffer in ANY tab (win_findbuf — bufwinid() only looks
    -- at the current tab, and while quitting the buffer's window is
    -- usually in another one).
    local win = vim.api.nvim_get_current_win()
    if
      vim.api.nvim_win_get_buf(win) ~= args.buf
      or vim.api.nvim_win_get_config(win).relative ~= ""
    then
      win = nil
      for _, w in ipairs(vim.fn.win_findbuf(args.buf)) do
        if vim.api.nvim_win_get_config(w).relative == "" then
          win = w
          break
        end
      end
    end
    if not win then return end
    pcall(vim.api.nvim_win_call, win, function()
      vim.cmd("silent! mkview")
    end)
  end,
})

-- Restore on entering the window (works immediately when ufo is absent)...
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = fold_persistence,
  callback = function(args)
    if fold_view_eligible(args.buf) then
      vim.b[args.buf].fold_view_settled = nil -- allow one reassert this entry
      load_fold_view(args.buf)
    end
  end,
})

-- ...then reassert exactly once, after things go idle, to land after ufo's
-- async fold apply. The buffer-local flag makes this fire a single time per
-- entry, so it never fights folds you open yourself afterward.
vim.api.nvim_create_autocmd("CursorHold", {
  group = fold_persistence,
  callback = function(args)
    if vim.b[args.buf].fold_view_settled then return end
    vim.b[args.buf].fold_view_settled = true
    if fold_view_eligible(args.buf) then
      -- Fires ~updatetime after a gd / <C-o> / <C-i> jump settles, hence the
      -- cursor-preserving load.
      load_fold_view(args.buf)
    end
  end,
})

-- ---------------------------------------------------------------------------
-- View-file janitor. mkview above creates one file per edited buffer and
-- Neovim never deletes them, so 'viewdir' would grow without bound (a few
-- KB per file, but thousands of files after a year — and stale views for
-- long-gone projects). On exit, prune entries not touched in 90 days:
-- loadview refreshes a file's mtime implicitly via the following mkview
-- on leave, so anything 90 days cold belongs to files you no longer
-- open. Everything is pcall'd — a janitor must never turn quitting into
-- an error — and the scan is a flat readdir of small files, microseconds
-- in practice.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = augroup("view_janitor"),
  callback = function()
    -- 'viewdir' defaults to ".../view//"; strip the trailing separators so
    -- the joined paths below are clean.
    local dir = (vim.o.viewdir:gsub("[/\\]+$", ""))
    local handle = vim.uv.fs_scandir(dir)
    if not handle then return end
    local cutoff = os.time() - 90 * 86400
    while true do
      local name, t = vim.uv.fs_scandir_next(handle)
      if not name then break end
      -- This directory is configurable and may contain unrelated files.
      -- Native view names encode a path separator as =+ and finish with
      -- = (the default view) or =[1-9].vim (a numbered view).
      if
        t == "file"
        and name:find("=+", 1, true)
        and (name:sub(-1) == "=" or name:match("=[1-9]%.vim$"))
      then
        local path = dir .. "/" .. name
        local st = vim.uv.fs_stat(path)
        if st and st.mtime and st.mtime.sec < cutoff then pcall(vim.uv.fs_unlink, path) end
      end
    end
  end,
})
