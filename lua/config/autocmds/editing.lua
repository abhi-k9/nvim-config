-- lua/config/autocmds/editing.lua
--
-- Everyday editing: yank flash, last cursor position, split resize, trailing
-- whitespace, formatoptions, q-to-close panels, auto-mkdir, checktime.

local augroup = require("config.util").augroup
local settings = require("config.settings")

-- ---------------------------------------------------------------------------
-- Highlight on yank — quick visual confirmation that the yank happened.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup("highlight_yank"),
  callback = function()
    -- vim.hl is the 0.11+ name; vim.highlight is deprecated and shims to it.
    vim.hl.on_yank({ timeout = 150 })
  end,
})

-- ---------------------------------------------------------------------------
-- Restore cursor to its last position when reopening a file.
-- Skips git commit messages (you usually want a fresh cursor there).
-- This BufReadPost handler runs before filetype detection (see
-- autocmds/init.lua), so the filetype is matched here directly.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup("last_loc"),
  callback = function(args)
    local exclude = { "gitcommit", "gitrebase" }
    local buf = args.buf
    local ft = vim.bo[buf].filetype
    if ft == "" then ft = vim.filetype.match({ buf = buf }) or "" end
    if vim.tbl_contains(exclude, ft) then return end
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local lcount = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= lcount then pcall(vim.api.nvim_win_set_cursor, 0, mark) end
  end,
})

-- ---------------------------------------------------------------------------
-- Resize splits proportionally when the host terminal resizes.
-- nvim_win_call instead of `tabdo`: tabdo fires TabEnter/WinEnter/BufEnter
-- in every tab, which scope.nvim reacts to by re-listing buffers.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("VimResized", {
  group = augroup("resize_splits"),
  callback = function()
    if settings.get("editing.equalize_windows", true) == false then return end
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(tab), function()
        vim.cmd("wincmd =")
      end)
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Trim trailing whitespace on save. Keeps diffs clean.
--
-- Skipped for:
--   * binary / diff buffers      — whitespace can be load-bearing
--   * big_file buffers (>1 MB)   — a buffer-wide :s on a 50 MB log is a
--                                  multi-second save-time stall
--   * markdown                   — trailing double-spaces are hard line
--                                  breaks; stripping them changes rendering
--   * EditorConfig files that set trim_trailing_whitespace (either way) —
--                                  the project decides; Neovim's built-in
--                                  editorconfig support trims when "true"
-- Add filetypes to the skip list below if you work in other formats
-- where trailing whitespace is meaningful.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("trim_whitespace"),
  pattern = "*",
  callback = function(args)
    -- Read the EVENT buffer's options, not the ambient current buffer's.
    -- They're the same buffer in the common `:w` case, but during `:wa`
    -- Vim visits background buffers through the autocmd window; indexing
    -- by args.buf keeps the guards correct regardless of context (and
    -- the :s below operates on the current buffer, which IS args.buf
    -- inside a BufWritePre callback).
    local buf = args.buf
    if vim.bo[buf].binary or vim.bo[buf].filetype == "diff" then return end
    if vim.b[buf].big_file then return end
    local policy = settings.get("editing.trim_whitespace", true)
    if policy == false or type(policy) == "function" and not policy(buf) then return end
    if
      vim.tbl_contains(
        settings.get("editing.trim_skip_filetypes", { "markdown", "diff" }),
        vim.bo[buf].filetype
      )
    then
      return
    end
    local ec = vim.b[buf].editorconfig
    if type(ec) == "table" and ec.trim_trailing_whitespace ~= nil then return end
    -- Skip buffers the :s can't (or shouldn't) touch: read-only ones, and
    -- special buffers (nofile/help/terminal/prompt/quickfix) — writing one of
    -- those to a path would otherwise throw E21 from the substitute below.
    if not vim.bo[buf].modifiable or vim.bo[buf].readonly or vim.bo[buf].buftype ~= "" then
      return
    end
    vim.api.nvim_buf_call(buf, function()
      local view = vim.fn.winsaveview()
      vim.cmd([[keeppatterns %s/\s\+$//e]])
      vim.fn.winrestview(view)
    end)
  end,
})

-- ---------------------------------------------------------------------------
-- Don't auto-continue comments when opening new lines (o / O / <CR>
-- inside a comment).
--
-- This MUST be an autocmd rather than a one-shot `opt.formatoptions:
-- remove` in options.lua: 'formatoptions' is buffer-local and most
-- ftplugins set it again AFTER user options have run (`:verbose set
-- fo?` shows e.g. the runtime lua ftplugin winning). Re-applying on
-- every FileType is the only way the removal survives.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("formatoptions"),
  callback = function(args)
    if settings.get("editing.continue_comments", false) then return end
    vim.bo[args.buf].formatoptions = vim.bo[args.buf].formatoptions:gsub("[cro]", "")
  end,
})

-- ---------------------------------------------------------------------------
-- Quickfix / help / man / etc.: close with `q` (Vim convention).
--
-- Listed filetypes must actually be reachable in this config. Built-ins
-- (help/man/qf/checkhealth) plus PlenaryTestPopup (plenary is a
-- Telescope dep). If you add a plugin whose floating window forgets to
-- bind `q` (older fugitive, neotest, etc.), add its filetype here.
--
-- gitcommit/gitrebase were removed from this list deliberately:
--   * `q` there shadows macro recording, which people genuinely use
--     while reordering rebase todo lists;
--   * a commit message is usually the ONLY window, so the :close was
--     just an E444 error;
--   * "quit without saving" in a commit buffer means "abort the
--     commit", which deserves the explicit :q! / :cq, not a stray tap
--     of q.
-- The `close` is wrapped in pcall for the same last-window reason —
-- e.g. a help buffer opened in the sole window via `nvim +help`.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("close_with_q"),
  pattern = {
    "help",
    "man",
    "qf",
    "checkhealth",
    "PlenaryTestPopup",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", function()
      pcall(vim.cmd.close)
    end, { buffer = event.buf, silent = true, desc = "Close window" })
  end,
})

-- gitcommit/gitrebase get the UNLISTING from the group above but not the
-- q map (see rationale there), so a commit message never shows up as a
-- bufferline tab mid-commit.
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("unlist_transient"),
  pattern = { "gitcommit", "gitrebase" },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
  end,
})

-- ---------------------------------------------------------------------------
-- Auto-create parent directories when saving to a new path
-- (e.g. `:w lua/new/dir/file.lua` works without mkdir).
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("auto_mkdir"),
  callback = function(event)
    if event.match:match("^%w%w+:[\\/][\\/]") then return end -- skip URLs (oil://, fugitive://, …)
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- ---------------------------------------------------------------------------
-- Reload files when they change on disk + notify on the gain
-- (relies on 'autoread', which is on by default).
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
  group = augroup("checktime"),
  callback = function()
    if vim.o.buftype ~= "nofile" then vim.cmd("checktime") end
  end,
})
