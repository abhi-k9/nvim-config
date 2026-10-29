-- lua/config/options.lua
--
-- Vim options. These run BEFORE any plugin loads, so leader keys, encoding,
-- and anything plugins may read at setup time must live here.

-- ---------------------------------------------------------------------------
-- Leader keys
-- ---------------------------------------------------------------------------
-- Must be set before lazy.nvim loads so plugin keymaps resolve correctly.
-- stylua: ignore start
if vim.g.mapleader == nil then vim.g.mapleader = " " end
if vim.g.maplocalleader == nil then vim.g.maplocalleader = "\\" end
-- stylua: ignore end

-- ---------------------------------------------------------------------------
-- Disable some built-in plugins we don't need (faster startup)
-- ---------------------------------------------------------------------------
-- netrw is replaced by neo-tree. (lazy.lua also disables netrwPlugin; these
-- globals take effect even earlier.)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------
local opt = vim.opt

-- stylua: ignore start
opt.number = true             -- show absolute line number on current line
opt.relativenumber = true     -- relative numbers everywhere else (great for j/k motions)
opt.cursorline = true         -- highlight the line the cursor is on
opt.signcolumn = "yes"        -- always show the sign column; avoids text jumping when diagnostics appear
opt.scrolloff = 8             -- keep 8 lines visible above/below the cursor
opt.sidescrolloff = 8         -- same, horizontally
opt.wrap = false              -- don't soft-wrap long lines by default
opt.linebreak = true          -- if wrap is enabled, break at word boundaries
opt.showmode = false          -- lualine already shows the mode; hide the native one
opt.pumheight = 12            -- max items shown in completion popup
opt.laststatus = 3            -- single global statusline (looks better with splits)
opt.splitbelow = true         -- horizontal splits open below
opt.splitright = true         -- vertical splits open to the right
opt.splitkeep = "screen"      -- keep text on-screen position stable when splitting
opt.fillchars = {             -- nicer separators / fold characters
  eob = " ",                  -- hide ~ on empty lines past EOF
  fold = " ",
  foldopen = "▾",             -- glyph next to an open fold
  foldsep = "│",              -- vertical separator between folds
  foldclose = "▸",            -- glyph next to a closed fold
}
-- stylua: ignore end
opt.list = true -- show some invisible characters
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
-- Default border for floating windows (core hover/signature/diagnostic
-- floats and plugins that inherit it); plugin specs set a border only where
-- the plugin ignores 'winborder'.
opt.winborder = "rounded"

-- ---------------------------------------------------------------------------
-- Editing / indentation
-- ---------------------------------------------------------------------------
-- stylua: ignore start
opt.expandtab = true          -- tabs insert spaces
opt.shiftwidth = 2            -- 2 spaces per indent level
opt.tabstop = 2               -- a real tab counts as 2 columns
opt.softtabstop = 2           -- backspace deletes 2 spaces at a time
-- stylua: ignore end
-- No 'smartindent': ignored wherever an indentexpr exists, and elsewhere its
-- C rules misfire (a `#` line jumps to column 0).
opt.breakindent = true -- wrapped lines keep their indent (cosmetic)

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------
-- stylua: ignore start
opt.ignorecase = true         -- case-insensitive search...
opt.smartcase = true          -- ...unless the pattern has uppercase
opt.inccommand = "split"      -- live-preview :s/.../.../ in a split
-- stylua: ignore end

-- ---------------------------------------------------------------------------
-- Files & undo
-- ---------------------------------------------------------------------------
-- Swap files ON: they are Vim's only warning that another instance is
-- editing the same file, and they enable crash recovery. They live under
-- stdpath("state")/swap//, big files opt out, and the SwapExists handler
-- (autocmds/swap.lua) opens a file held by a LIVE instance read-only and
-- shows a one-line prompt for crash leftovers. :SwapDelete removes a
-- leftover; `vim.g.swap_guard = false` / :SwapGuardToggle restores stock
-- behaviour.
opt.swapfile = true
opt.undofile = true -- persistent undo across sessions (stdpath("state")/undo)
-- 'updatetime' also sets how often the swap file is flushed to disk.
-- stylua: ignore start
opt.updatetime = 250          -- faster CursorHold (gitsigns / LSP hovers)
opt.timeoutlen = 400          -- ambiguous-keymap wait; which-key has its own delay
-- stylua: ignore end

-- ---------------------------------------------------------------------------
-- Clipboard — explicit, not implicit
-- ---------------------------------------------------------------------------
-- NOT "unnamedplus": with it every d/c/x also overwrites the system
-- clipboard, so a stray `dd` loses what you copied elsewhere. Reach the
-- clipboard explicitly with "+y / "+p / "+d. To get the old behaviour back:
-- opt.clipboard = "unnamedplus"

-- ---------------------------------------------------------------------------
-- Folding (used by nvim-ufo; ufo overrides foldmethod at runtime)
-- ---------------------------------------------------------------------------
-- stylua: ignore start
opt.foldcolumn = "1"          -- show a small column for fold markers
opt.foldlevel = 99            -- start with everything unfolded
-- stylua: ignore end
opt.foldlevelstart = 99

-- Fold persistence uses view files (autocmds/folds.lua), storing folds ONLY
-- — no cursor, cwd or options. Loading fold commands can still move the
-- cursor, so folds.lua also preserves the live cursor/scroll around :loadview.
-- This works independently of sessions and of nvim-ufo.
opt.viewoptions = { "folds" }

-- ---------------------------------------------------------------------------
-- Sessions
-- ---------------------------------------------------------------------------
-- What :mksession (auto-session) saves.
--   localoptions  restores `filetype`, so treesitter / LSP re-attach.
--   no "options"  global options in a session override later config edits.
--   no "folds"    folds come from view files (above), in one place only.
opt.sessionoptions = {
  "blank",
  "buffers",
  "curdir",
  "help",
  "tabpages",
  "winsize",
  "winpos",
  "localoptions",
  -- no "terminal": restored terminals come back as dead [Process exited]
  -- buffers. "globals" is needed by scope.nvim's per-tab buffer map.
  "globals",
}

-- ---------------------------------------------------------------------------
-- Mouse + misc
-- ---------------------------------------------------------------------------
-- stylua: ignore start
opt.mouse = "a"               -- mouse in all modes (resize splits, etc.)
opt.confirm = true            -- ask to save instead of failing on :q with changes
-- stylua: ignore end

-- Remind on the first interactive start/focus, then every 30 days. Set 0 to
-- disable, or any positive number of days; keep values supplied before init.
if vim.g.tooling_reminder_days == nil then vim.g.tooling_reminder_days = 30 end

-- Jumplist as a browser-style back/forward stack: a new jump after <C-o>
-- discards the forward entries. :append keeps Neovim's default "clean" flag.
opt.jumpoptions:append("stack")
opt.completeopt = { "menu", "menuone", "noselect" } -- nicer completion behavior
-- stylua: ignore start
opt.shortmess:append("c")     -- don't pass messages to ins-completion-menu
opt.shortmess:append("I")     -- no intro screen
opt.spelllang = { "en_us" }   -- toggle with `:set spell`
opt.virtualedit = "block"     -- visual-block mode can move past EOL (handy for column edits)
-- stylua: ignore end
-- formatoptions (no auto-continued comments) is set in a FileType autocmd
-- (autocmds/editing.lua): ftplugins would overwrite it if set here.

-- Regex syntax only matters where treesitter doesn't parse; 240 columns is
-- plenty for real code and avoids scanning minified one-liners.
opt.synmaxcol = 240

-- ---------------------------------------------------------------------------
-- Project-local config ('exrc') — opt-in, trust-gated
-- ---------------------------------------------------------------------------
-- Runs `.nvim.lua` / `.nvimrc` / `.exrc` from the cwd and its parent
-- directories — the place for per-project settings (clangd flags, a scope,
-- 'makeprg'). A trusted file in a parent (e.g. your home folder) applies to
-- every project below it.
-- Safety: an UNTRUSTED file is never run; Neovim prompts and you `:trust`
-- it after viewing. Trust is by content hash, so any edit asks again. It is
-- not a sandbox — trusted Lua runs with full power, so only trust files you
-- would run by hand. Revoke with `:trust ++remove`; opt out with
-- `vim.o.exrc = false`.
opt.exrc = true
