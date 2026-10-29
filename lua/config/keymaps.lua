-- lua/config/keymaps.lua
--
-- Global, non-plugin keymaps. Plugin-specific keymaps live next to each
-- plugin's spec in lua/plugins/ so you can disable a plugin without leaving
-- dangling mappings.
--
-- Convention:
--   <leader>f...  → find / files / fuzzy (telescope)
--   <leader>F...  → fzf-lua mirror of the above
--   <leader>g...  → git
--   <leader>l...  → LSP / diagnostics
--   <leader>c...  → code-level actions (format, treesitter swap/jump)
--   <leader>x...  → trouble (diagnostics list)
--   <leader>s...  → search/replace (grug-far)
--   <leader>d...  → debug (DAP)
--   <leader>t...  → terminal
--   <leader>b...  → buffer
--   <leader>w...  → window / session  (pure prefix — save lives on <C-s>)
--   <leader>1..9  → jump to bufferline ordinal N (matches superscript on tab)
--   <leader>0     → jump to last bufferline buffer
--   <leader>?     → which-key buffer-local keys

local map = vim.keymap.set
local settings = require("config.settings")

-- ---------------------------------------------------------------------------
-- Quality-of-life
-- ---------------------------------------------------------------------------
-- Clear search highlight + close hover-style popups with <Esc>. The original
-- <Esc> behavior (cancel pending operator, etc.) is preserved.
--
-- Only popups that tag their window are closed: LSP hover, signature help
-- and diagnostic floats (vim.lsp.util.open_floating_preview sets
-- w:lsp_floating_bufnr) and gitsigns hunk previews (w:gitsigns_preview).
-- UI chrome floats (treesitter-context, incline, fidget, smear-cursor's
-- hidden pool) carry neither and stay put; closing them would only make them
-- flicker back on the next redraw.
local ESC_CLOSE_WIN_VARS = { "lsp_floating_bufnr", "gitsigns_preview" }
map("n", "<Esc>", function()
  vim.cmd("nohlsearch")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    -- Closing a popup can fire WinClosed hooks that close its companions,
    -- invalidating later entries in this snapshot.
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= "" then
      for _, var in ipairs(ESC_CLOSE_WIN_VARS) do
        if vim.w[win][var] ~= nil then
          pcall(vim.api.nvim_win_close, win, false)
          break
        end
      end
    end
  end
end, { desc = "Clear hlsearch & dismiss floats" })

-- Better up/down on wrapped lines: j/k respect display lines unless used
-- with a count (so `5j` still jumps 5 real lines, good for relativenumber).
-- stylua: ignore start
if settings.get("mappings.navigation", true) then
  map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true, desc = "Down (display line)" })
  map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true, desc = "Up (display line)" })
end
-- stylua: ignore end

-- Keep cursor centered on big motions; small thing, huge readability win.
-- NOTE: <C-d>/<C-u> are intentionally NOT mapped here. neoscroll (editor.lua)
-- owns them so the half-page scroll is animated, and it re-centers via a
-- post_hook (info="center"); a <C-d>zz map here would be overridden by
-- neoscroll on load.
if settings.get("mappings.navigation", true) then
  map("n", "n", "nzzzv", { desc = "Next search match (centered)" })
  map("n", "N", "Nzzzv", { desc = "Prev search match (centered)" })
  if settings.get("ui.reduced_motion", false) then
    map({ "n", "x" }, "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
    map({ "n", "x" }, "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })
  end
end

-- Horizontal scroll in ONE chord, repeatable by holding.
-- Built-in zl/zh need the `z` prefix (two keys) and move a single column,
-- so scrolling any distance means mashing. <A-l>/<A-h> mirror the j/k
-- line-move convention (<A-j>/<A-k>) and scroll a chunk per press; hold the
-- key and OS key-repeat keeps it going. Only meaningful with `nowrap`
-- (set in options.lua) — with wrap on, long lines fold instead and there's
-- nothing to scroll horizontally.
--
-- HSCROLL_STEP columns per press: ~a third of a typical window, smooth when
-- held, decisive on a tap. Bump it if you want bigger jumps; for a
-- half-screen leap on a single key use zL/zH directly instead.
local HSCROLL_STEP = 16
if settings.get("mappings.navigation", true) then
  map("n", "<A-l>", HSCROLL_STEP .. "zl", { desc = "Scroll right" })
  map("n", "<A-h>", HSCROLL_STEP .. "zh", { desc = "Scroll left" })
  -- Same in visual mode so you can scroll while keeping a selection.
  map("x", "<A-l>", HSCROLL_STEP .. "zl", { desc = "Scroll right" })
  map("x", "<A-h>", HSCROLL_STEP .. "zh", { desc = "Scroll left" })
end

-- Stay in visual mode after indenting (so you can `>` repeatedly).
--
-- Mode note: these (and every "visual" map in this file) use "x", NOT
-- "v". "v" covers visual AND select mode, and select mode is what
-- LuaSnip/blink put you in on a snippet placeholder — there, typing
-- should REPLACE the selection, so a "v" map of a printable key (J, K,
-- <, >) would hijack typing inside placeholders.
map("x", "<", "<gv", { desc = "Indent left (keep selection)" })
map("x", ">", ">gv", { desc = "Indent right (keep selection)" })

-- Move highlighted lines up/down with Alt-j/k. Auto-re-indents.
-- (Alt, not plain J/K: visual `J` is join-lines and `K` is keywordprg,
-- both worth keeping.)
--
-- A function rather than the classic `:m '>+1<CR>gv=gv` string for the
-- same reason as the normal-mode pair below: at the first/last line a
-- raw `:move` throws "E16: Invalid range" (and, without <silent>, flashes
-- the command line on every press). The selection is read LIVE via
-- line("v")/line(".") — the '< / '> marks still describe the PREVIOUS
-- selection while visual mode is active — and at a file edge the map is a
-- silent no-op that keeps the selection.
-- A count moves by that many lines (`3<A-j>`), clamped at the file edge.
local function move_selection(down)
  local n = vim.v.count1
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  n = down and math.min(n, vim.fn.line("$") - e) or math.min(n, s - 1)
  if n <= 0 then return end
  vim.cmd("normal! \27") -- leave visual so '< / '> are written
  vim.cmd(down and ("'<,'>move '>+" .. n) or ("'<,'>move '<-" .. (n + 1)))
  vim.cmd("normal! gv=gv")
end
-- stylua: ignore start
map("x", "<A-j>", function() move_selection(true) end,  { desc = "Move selection down" })
map("x", "<A-k>", function() move_selection(false) end, { desc = "Move selection up" })
-- stylua: ignore end

-- Normal-mode counterpart: move the CURRENT line up/down with the same
-- Alt-j/k, no selection needed. Implemented as functions rather than a raw
-- `:m` mapping so the file edges no-op silently: a bare `:m .-2` on line 1
-- (or `:m .+1` on the last line) throws "E16: Invalid range", which would
-- flash in the command line every time you bump the top/bottom. The guards
-- below skip the move at the boundary. After moving, `==` re-indents the
-- line to fit its new context. Normal `J` (join) and `K` (keywordprg/hover)
-- stay untouched — this is Alt-j/k.
map("n", "<A-j>", function()
  local n = math.min(vim.v.count1, vim.fn.line("$") - vim.fn.line("."))
  if n > 0 then
    vim.cmd("m .+" .. n)
    vim.cmd("normal! ==")
  end
end, { desc = "Move line down (count ok)" })
map("n", "<A-k>", function()
  local n = math.min(vim.v.count1, vim.fn.line(".") - 1)
  if n > 0 then
    vim.cmd("m .-" .. (n + 1))
    vim.cmd("normal! ==")
  end
end, { desc = "Move line up (count ok)" })

-- Don't yank when pasting over a selection. By default visual-mode `p`
-- deletes the selection into the unnamed register before putting, which
-- means a second `p` would put what you just replaced rather than what
-- you originally yanked. Since Neovim 0.9, visual-mode `P` is exactly
-- "paste without clobbering the register" as a built-in, so we alias
-- `p` to it. (Unlike the classic `"_dP` trick, the built-in also gets the
-- end-of-line and linewise-register cases right.)
map("x", "p", "P", { desc = "Paste without yanking replaced" })

-- ---------------------------------------------------------------------------
-- Buffers (cycling and the tab menu are bufferline keys in plugins/ui.lua)
-- ---------------------------------------------------------------------------
-- Delete the current buffer WITHOUT closing any window it lives in.
--
-- Plain `:bdelete` (and nvim_buf_delete) closes EVERY window showing
-- the buffer — fine with one window, but it causes two annoyances when
-- you have more:
--   1. Layout damage: a careful split arrangement loses windows for
--      the trivial act of dropping a buffer.
--   2. Vanishing side panels: neo-tree (or any panel) can swallow the
--      whole layout when a buffer drop takes its window along.
--
-- The fix: re-point every window showing the buffer at another listed
-- buffer (or a fresh [No Name]) BEFORE deleting. That logic lives in
-- lua/config/util.lua and is shared with the bufferline context menu, its
-- close button and both buffer pickers.
local util = require("config.util")

local function smart_bdelete(force)
  local cur = vim.api.nvim_get_current_buf()
  -- Shared routine (lua/config/util.lua) skips dirty buffers BEFORE touching
  -- any window, so <leader>bd on unsaved work leaves the buffer and its splits
  -- exactly where they were — same behaviour as both buffer pickers.
  local status = util.delete_buffer_keep_windows(cur, force)
  if status == "skipped" then
    -- Unsaved changes with force=false. Say so — a silently-swallowed failure
    -- here once made <leader>bd feel randomly broken on dirty buffers.
    vim.notify(
      "Buffer not deleted (unsaved changes? <leader>bD force-deletes)",
      vim.log.levels.WARN
    )
  elseif status == "failed" then
    vim.notify("Buffer not deleted", vim.log.levels.WARN)
  end
end

map("n", "<leader>bd", function()
  smart_bdelete(false)
end, { desc = "Delete buffer (keep window)" })
map("n", "<leader>bD", function()
  smart_bdelete(true)
end, { desc = "Force-delete buffer (keep window)" })

-- ---------------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------------
-- Navigate splits with Ctrl-hjkl (matches tmux muscle memory).
map("n", "<C-h>", "<C-w>h", { desc = "Window: left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window: down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window: up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window: right" })

-- Resize splits with Ctrl-arrows.
-- stylua: ignore start
map("n", "<C-Up>",    "<cmd>resize +2<cr>",         { desc = "Resize ↑" })
map("n", "<C-Down>",  "<cmd>resize -2<cr>",         { desc = "Resize ↓" })
map("n", "<C-Left>",  "<cmd>vertical resize -2<cr>",{ desc = "Resize ←" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>",{ desc = "Resize →" })
-- stylua: ignore end

-- stylua: ignore start
map("n", "<leader>ws", "<cmd>split<cr>",  { desc = "Split horizontally" })
map("n", "<leader>wv", "<cmd>vsplit<cr>", { desc = "Split vertically" })
map("n", "<leader>wc", function()
  -- In the last window of the last tab :close only prints E444; say what
  -- to do instead.
  local normal = vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
  if #normal <= 1 and #vim.api.nvim_list_tabpages() == 1 then
    vim.notify("Last window — <leader>bd closes the buffer, :q quits", vim.log.levels.INFO)
    return
  end
  vim.cmd("close")
end, { desc = "Close window" })
map("n", "<leader>wo", "<cmd>only<cr>",   { desc = "Close other windows" })
-- stylua: ignore end

-- ---------------------------------------------------------------------------
-- Window zoom toggle (<leader>wm — "maximize")
-- ---------------------------------------------------------------------------
-- Temporarily make the focused window fill the screen, then restore the
-- saved sizes on a second press if the split layout is unchanged. Useful for
-- "I want to see neo-tree at
-- full height for a moment" / "let me get more vertical space on this
-- buffer."
--
-- DESIGN: save current window sizes via `winrestcmd()`, then maximize via
-- `wincmd _ | wincmd |`. On the second press, replay the saved sizes.
--
-- Why not open the buffer in a new tab? That fails for neo-tree, which
-- forces `winfixwidth = true` and a 32-column width that snaps back even
-- alone in a tab, and closing such a tab could leave Neovim without a
-- valid current tab. Resizing in place avoids both: we explicitly clear
-- winfixwidth/winfixheight on the zoomed window for the duration, then
-- restore them.
--
-- Edge cases handled:
--   * Only one window open — notify and no-op.
--   * Zoomed window is closed before un-zoom — pcall the resize replay so
--     we don't error; the saved winfix options are skipped via win_is_valid.
--   * State variable is cleared FIRST on un-zoom so a partial failure
--     doesn't strand us in "zoomed" forever.
--   * The ordered layout changed while zoomed (splits opened, closed or
--     exchanged):
--     winrestcmd() replays sizes by window NUMBER, so it would hand the old
--     sizes to the wrong windows. In that case equalize (`wincmd =`)
--     instead of replaying a stale snapshot.
local function zoom_layout_key()
  -- winrestcmd addresses window numbers, so order and split orientation
  -- matter even when the set of window IDs has not changed. winlayout()
  -- includes both while excluding floating windows and transient sizes.
  return vim.json.encode(vim.fn.winlayout())
end

local function toggle_window_zoom()
  if vim.t.zoom_state then
    local state = vim.t.zoom_state
    vim.t.zoom_state = nil
    if state.layout == zoom_layout_key() then
      pcall(vim.cmd, state.restore_cmd)
    else
      vim.cmd("wincmd =")
    end
    if vim.api.nvim_win_is_valid(state.win) then
      vim.wo[state.win].winfixwidth = state.fixwidth
      vim.wo[state.win].winfixheight = state.fixheight
    end
    return
  end
  if vim.fn.winnr("$") == 1 then
    vim.notify("Only one window — nothing to zoom", vim.log.levels.INFO)
    return
  end
  local win = vim.api.nvim_get_current_win()
  vim.t.zoom_state = {
    restore_cmd = vim.fn.winrestcmd(),
    layout = zoom_layout_key(),
    win = win,
    fixwidth = vim.wo[win].winfixwidth,
    fixheight = vim.wo[win].winfixheight,
  }
  -- Clear winfix settings so neo-tree (or any other fixed-size window)
  -- can actually grow. Restored on un-zoom.
  vim.wo[win].winfixwidth = false
  vim.wo[win].winfixheight = false
  -- stylua: ignore start
  vim.cmd("wincmd _")  -- max height
  vim.cmd("wincmd |")  -- max width
  -- stylua: ignore end
end

map("n", "<leader>wm", toggle_window_zoom, { desc = "Zoom window (toggle)" })

-- ---------------------------------------------------------------------------
-- File / quit
-- ---------------------------------------------------------------------------
-- <C-s> saves in every mode so <leader>w can stay a pure prefix (used for
-- window + session sub-keymaps). The insert-mode binding returns to normal
-- after the write; the visual-mode one drops back to normal first because
-- :write inside a visual range only writes the range, not the buffer.
--
-- Guarded on 'buftype': pressing <C-s> in a NON-FILE buffer (neo-tree,
-- Trouble, help, dap-ui, a :terminal, …) is a silent no-op rather than
-- :write's "E382: Cannot write, 'buftype' option is set". (neo-tree on `main` binds
-- its own buffer-local <C-s> to quick_jump, which shadows this inside the
-- tree anyway — the guard still covers every other special buffer.)
--
-- The insert-mode map replaces Neovim's default i_CTRL-S (LSP signature
-- help); blink.cmp shows the signature popup automatically while typing
-- arguments, and <leader>lk opens it from normal mode.
local function guarded_write()
  if vim.bo.buftype ~= "" then return end -- UI/special buffer → nothing to write
  vim.cmd("write")
end
map("n", "<C-s>", guarded_write, { desc = "Save" })
map("i", "<C-s>", function()
  guarded_write()
  vim.cmd("stopinsert")
end, { desc = "Save (leaves insert)" })
map("x", "<C-s>", function()
  vim.cmd("normal! \27")
  guarded_write()
end, { desc = "Save" })

-- stylua: ignore start
map("n", "<leader>W", "<cmd>wa<cr>",        { desc = "Save all" })
map("n", "<leader>q", "<cmd>confirm q<cr>", { desc = "Quit" })
map("n", "<leader>Q", "<cmd>qa!<cr>",       { desc = "Force quit all" })
-- stylua: ignore end

-- ---------------------------------------------------------------------------
-- Insert mode — undo granularity (prose buffers only)
-- ---------------------------------------------------------------------------
-- After sentence-level punctuation, drop an undo break (<C-g>u) so one `u`
-- in a long insert (Markdown, commit messages) doesn't undo a paragraph.
-- Not on <Space>/<CR> (per-word undo), closing brackets (mid-expression)
-- or quotes. Prose filetypes only: after <C-g>u, `.` repeats only the text
-- typed since the last mapped character (:h i_CTRL-G_u), so in code
-- `A;<Esc>j.` would lose most of the insert. Trade-off: a mapped char no
-- longer triggers an :iabbrev expansion (none are defined here).
local UNDO_BREAK_CHARS = { ",", ".", "!", "?", ";", ":" }
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_undo_break", { clear = true }),
  desc = "Undo break after punctuation in prose buffers",
  callback = function(ev)
    -- Policy can change while the same buffer stays open. Remove only owned
    -- mappings, even when its old punctuation is absent from the new policy.
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(ev.buf, "i")) do
      if
        mapping.rhs == mapping.lhs .. "<C-G>u"
        and mapping.desc == "Undo break after " .. mapping.lhs
      then
        vim.keymap.del("i", mapping.lhs, { buffer = ev.buf })
      end
    end
    if
      settings.get("editing.prose_undo", true) == false
      or settings.get("editing.prose_undo.enabled", true) == false
    then
      return
    end
    local filetypes =
      settings.get("editing.prose_undo.filetypes", { "markdown", "text", "gitcommit" })
    if not vim.tbl_contains(filetypes, vim.bo[ev.buf].filetype) then return end
    for _, ch in ipairs(settings.get("editing.prose_undo.chars", UNDO_BREAK_CHARS)) do
      -- Do not replace an independent buffer-local mapping. FileType hooks
      -- and user remaps may already own this character.
      local mapped = false
      for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(ev.buf, "i")) do
        if mapping.lhs == ch then
          mapped = true
          break
        end
      end
      if type(ch) == "string" and vim.fn.strchars(ch) == 1 and not mapped then
        map("i", ch, ch .. "<C-g>u", { buffer = ev.buf, desc = "Undo break after " .. ch })
      end
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Diagnostics (works without LSP too, e.g. for lint plugins)
-- ---------------------------------------------------------------------------
-- The built-in ]d / [d (and ]D / [D) jump; on_jump opens the float for the
-- diagnostic under the cursor after every jump.
vim.diagnostic.config({
  jump = {
    on_jump = function(_, bufnr)
      vim.diagnostic.open_float({ bufnr = bufnr, scope = "cursor", focus = false })
    end,
  },
})
map("n", "<leader>ld", vim.diagnostic.open_float, { desc = "Line diagnostics" })

-- Toggle diagnostic display between virtual TEXT (compact, trails off the
-- right edge — the default set in lua/plugins/lsp.lua) and virtual LINES
-- (rendered on their own wrapped line(s) below the code, so a long clang
-- message is fully readable in place). virtual_text never wraps, so this is
-- the fix when a diagnostic runs off-screen — flip to lines, read it, flip
-- back. (`vim.diagnostic.open_float`/`<leader>ld` is the one-shot
-- alternative if you don't want to change the display mode.)
--
-- We snapshot the LIVE virtual_text config the first time we toggle off
-- (vim.diagnostic.config() with no args returns the current global opts),
-- so toggling back restores exactly what lua/plugins/lsp.lua set — no
-- hardcoded copy to drift out of sync. virtual_lines uses
-- `current_line = true` so only the cursor's line expands; showing every
-- diagnostic's full block at once gets noisy fast in a busy file.
do
  local saved_vtext = nil
  local lines_on = false
  map("n", "<leader>lv", function()
    lines_on = not lines_on
    if lines_on then
      if saved_vtext == nil then
        -- capture whatever virtual_text is currently configured (Neovim's
        -- own default is off)
        local cur = vim.diagnostic.config() or {}
        saved_vtext = cur.virtual_text or false
      end
      vim.diagnostic.config({ virtual_text = false, virtual_lines = { current_line = true } })
      vim.notify("Diagnostics: virtual lines (wrapped, current line)", vim.log.levels.INFO)
    else
      vim.diagnostic.config({ virtual_lines = false, virtual_text = saved_vtext })
      vim.notify("Diagnostics: virtual text (compact)", vim.log.levels.INFO)
    end
  end, { desc = "Toggle diagnostic virtual text / lines" })
end

-- ---------------------------------------------------------------------------
-- Terminal-mode escape
-- ---------------------------------------------------------------------------
-- `<Esc><Esc>` to leave terminal mode. Single <Esc> still reaches TUI apps
-- (vim/nvim inside :terminal, fzf prompts, etc.), but only after
-- 'timeoutlen' (400 ms), since Neovim waits to see whether a second <Esc>
-- follows. Terminals that need an instant <Esc> override it with a
-- buffer-local `nowait` map (lazygit: plugins/terminal.lua; fzf-lua does
-- the same for its own pickers when <Esc> aborts).
map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
