# Changelog archive (older entries, newest first)

> **Historical and undated.** These entries are older than everything in
> [CHANGES.md](../CHANGES.md) and are kept only as a record. They describe
> the config as it was then: commands, keys, file names and version floors
> here may have changed or been removed since. For current behaviour, see
> the README and the cheatsheets.

# Cross-platform paths: Windows temp dir in session suppression, scoper filesystem-root boundary

Two portability fixes.

- `session.lua`'s auto-restore suppression list held fixed Unix entries
  (`~/`, `~/Downloads`, `/tmp`, `/`). `/tmp` is a harmless no-op on
  Windows, whose per-user temp dir lives under `%TEMP%`, so a session was
  silently auto-restored in scratch temp dirs there. The list now appends
  the platform temp dir (`$TEMP` / `$TMP` / `$TMPDIR`, backslashes
  normalized) at load.
- scoper `path.is_under()` / `path.relative()` mishandled a filesystem
  root as the base. `normalize()` strips a trailing separator except on a
  root, so a root parent (`/` on Unix, `c:/` on Windows) keeps its slash;
  the old `parent .. "/"` boundary then became `//` (or `c://`) and matched
  no child. Fixed to reuse the existing trailing slash for a root, with the
  paired `relative()` offset adjusted so a root base doesn't drop the first
  character of the result. Four regression tests added (two cross-platform
  for `/`, two Windows-guarded for `c:/`).

Files touched:

- `lua/plugins/session.lua`, `scoper.nvim/lua/scoper/path.lua`,
  `scoper.nvim/tests/path_spec.lua`

---

# DAP: log points, VS Code function keys, UI auto-close, persistence fixes

Several debugger-workflow additions, plus two persistence bugs.

- **Log points** on `<leader>dP`: prompts for a message (with `{expr}`
  interpolation, like VS Code) and sets it via
  `dap.set_breakpoint(nil, nil, msg)`. Because that bypasses
  persistent-breakpoints (which only writes from inside its own API), it is
  followed by `store_breakpoints()` so the log point round-trips across a
  restart like every other breakpoint here.
- **Clear-all** (`<leader>dX`) now calls persistent-breakpoints'
  `clear_all_breakpoints()` instead of raw `dap.clear_breakpoints()`. The
  raw call cleared only the running session; the on-disk store kept the old
  set, so breakpoints reappeared on the next `BufReadPost`, on `:cd` (the
  plugin reloads on `DirChanged`), or on the next start.
- **VS Code function keys** for muscle memory: `<F5>` continue, `<F6>`
  pause, `<F9>` toggle breakpoint (persistent), `<F10>` step over, `<F11>`
  step into. Only UNMODIFIED F-keys are bound — the modified combos VS Code
  also uses (Shift+F5, Shift+F11, Ctrl+Shift+F5) need the kitty keyboard
  protocol and don't reach nvim on legacy terminals, so those actions stay
  on `<leader>dt` / `dO` / `dR`.
- **UI auto-close** made robust and toggleable. `cppdbg` / OpenDebugAD7
  doesn't emit a `terminated`/`exited` event on a client-initiated
  Terminate, so dap-ui never closed itself; `<leader>dt` now closes it
  explicitly (idempotent, so codelldb — which DOES emit the event — just
  closes once). A `vim.g.dap_autoclose_ui` flag (default true, toggle on
  `<leader>dU`) governs whether the UI closes on exit or stays open for
  post-mortem inspection; the listeners read the flag at event time.

Files touched:

- `lua/plugins/dap.lua`, `docs/cheatsheets/debugging.html`,
  `docs/cheatsheets/vs-to-nvim.html`

---

# Completion: terminal-safe menu trigger + command-line completion

- `<C-n>` / `<C-p>` are remapped to
  `{ "show", "select_next"/"select_prev", "fallback" }`, so the FIRST press
  opens the blink menu (ghost-text preview, nothing inserted) and the next
  moves the selection. This matters because `<C-Space>` — blink's default
  trigger — needs the kitty keyboard protocol; on the Windows console and
  other legacy terminals (incl. zellij/tmux over one) Ctrl+Space collapses
  to a bare `<Space>` = `<leader>` and pops which-key instead. `<C-n>` /
  `<C-p>` transmit cleanly everywhere. Deliberately different from the
  default preset, whose `<C-n>` falls through to Vim's native keyword
  completion on a closed menu.
- blink now completes `:` commands, paths and options as you type.
  Shell/filter commands (`:!`, `:%!`, `:'<,'>!`) are deliberately skipped —
  their completion enumerates all of `$PATH` and hung Neovim for seconds;
  `<Tab>` inside `:!` still invokes native wildmenu on demand.

Files touched:

- `lua/plugins/completion.lua`, `docs/cheatsheets/keymaps.html`,
  `docs/cheatsheets/vs-to-nvim.html`

---

# scoper.nvim: recursive :find fallback, relative compile_commands entries, tested helpers

Correctness fixes in the bundled plugin, plus extraction for testability.

- The plain-vim `:find` fallback built its `path` as
  `table.concat(dirs, ",") .. "/**"`, which appended the recursive `/**` to
  only the LAST scope dir — every earlier scope dir was searched
  non-recursively and missed nested files. `M._find_path()` now appends
  `/**` to EVERY dir (spaces backslash-escaped).
- LSP filtering misclassified compile_commands entries whose `file` is
  relative. Per the JSON Compilation Database spec a relative `file` is
  relative to that entry's own `directory`, not nvim's cwd; the classifier
  now resolves against `directory` before the scope check, so generators
  that emit relative paths classify correctly.
- Extracted `M._find_path` and `M._filter_entries` as named helpers and
  added `tests/pickers_spec.lua` and `tests/lsp_spec.lua` covering them.

Files touched:

- `scoper.nvim/lua/scoper/pickers.lua`, `scoper.nvim/lua/scoper/lsp.lua`,
  `scoper.nvim/tests/pickers_spec.lua`, `scoper.nvim/tests/lsp_spec.lua`

---

# :checkhealth config — external-toolchain health check

New `lua/config/health.lua`, surfaced as `:checkhealth config`. It verifies
the EXTERNAL toolchain this config assumes — a C compiler and `git`, the
search/picker binaries (`rg`, `fzf`, `fd`), the C/C++ tools (`clangd`,
`clang-format`, `clang-tidy`), the language runtimes (`node`, `python3`)
and the dev/test tools — reporting what's missing or the wrong version and
deferring to `:checkhealth mason` for the Mason-managed servers /
formatters / adapters rather than duplicating them.

Files touched:

- `lua/config/health.lua`, `README.md`

---

# Fold restore no longer moves the cursor after a jump

The fold-persistence autocmds call `:loadview` on `BufWinEnter` (and
reassert once). `viewoptions` is folds-only, but `:loadview` can still
reposition the cursor and scroll — so after a `gd` / `<C-o>` / `<C-i>` jump,
an unguarded loadview yanked the cursor off the jump target a beat later.
Both loadview calls now wrap it in `winsaveview()` / `winrestview()`: the
folds are applied, the cursor and scroll are restored. All view calls stay
`pcall`'d and `silent!`, so a missing or stale view file can never turn a
buffer open into an error.

Files touched:

- `lua/config/autocmds.lua`

---

# Real duplicate-<leader> registration guard

The original config_spec check reads the LIVE keymap table
(`nvim_get_keymap`), which keeps only the last rhs per `(mode, lhs)` — so a
second mapping of the same leader key overwrites the first and the
collision is gone before the test runs. That check is therefore really a
liveness / well-formed guard, structurally blind to the very
same-lhs duplicates it was named after. The actual duplicate-registration
guard now lives in `tests/minimal_init.lua`, which hooks
`vim.api.nvim_set_keymap` (the single low-level chokepoint all global maps
funnel through) across the synchronous config load and records every
`(mode, lhs)` into `_G.__config_keymap_registrations`. A new describe block
in `config_spec.lua` reads that log and asserts no same-mode `<leader>`
key is registered twice.

Files touched:

- `tests/minimal_init.lua`, `tests/config_spec.lua`

---

# C++ templates: annotated clang-tidy reference + dotfile reconciliation

Added the heavily-annotated clang-tidy reference (shipped as
`.clang-tidy.example`; renamed to `clang-tidy.example` in the later docs
sweep above), the counterpart to the minimal `.clang-tidy` and mirroring
the existing clang-format / clangd pairs. Reconciled the shipped clang
dotfiles and `docs/templates/cpp/README.md` so the minimal and annotated
versions describe the same settings (incl. the `lower_case` naming and the
`-std=c++20` fallback), and refreshed the clang-settings reference sheet.

Files touched:

- `docs/templates/cpp/.clang-tidy`,
  `docs/templates/cpp/clang-format.example`,
  `docs/templates/cpp/README.md`,
  `docs/templates/cpp/.clang-tidy.example` (new),
  `docs/cheatsheets/clang-settings-reference.html`

---

# QOL + standards pass: exrc, jumplist stack, ruff diagnostics, lazydev, render-markdown, gr→Trouble, editorconfig, CI + pre-commit, version guard

Nine changes: three editor-QOL, one standards baseline, two enforcement, one
version-hygiene, plus two plugin additions. Grouped below with rationale.

## Version: single source of truth (was drifting)

`init.lua` said "0.12.3", the README said "0.12.3" in one place and "≥ 0.11.2"
in another, and comments in `util.lua`/`search.lua` cite "verified on 0.12.4".
Now the ONLY authoritative number lives in a guard at the top of `init.lua`:

```lua
local MIN_NVIM = "0.11.2"
if vim.fn.has("nvim-" .. MIN_NVIM) == 0 then ... return end
```

It runs before any `require`, so too-old Neovim aborts with one clear message
instead of a confusing mid-load stack trace from a missing 0.11 API. The
failure branch uses only ancient-safe calls (plain `nvim_echo`, no
`vim.version()`) since it fires precisely when the user is on an old build.
README and the `init.lua` header now defer to this guard rather than restating
a version. "Developed against 0.12.4" is recorded as the verified-against
version; 0.11.2 is the enforced floor (vim.lsp.config + `main`-branch plugins).

## exrc: project-local config, on, trust-gated, fully documented

`opt.exrc = true` in `options.lua`, so a `.nvim.lua` at a project root runs at
startup — the natural companion to the C++/scoper workflow (pin a clangd
`-std`, seed a scope, set `makeprg` per repo). The block carries a full
security write-up because this is the one change here that executes external
code:

- NOT auto-executed. Since Neovim 0.9, exrc routes candidates through
  `vim.secure.read()`; an untrusted file is never sourced — you get the
  `(i)gnore / (v)iew / (d)eny` prompt and `:trust` records the decision.
- Trust is by CONTENT HASH (SHA-256 in `stdpath("state")/trust`), so any edit
  re-prompts — a malicious swap can't ride in on a trusted filename.
- NOT a sandbox. The comment is explicit that a trusted `.nvim.lua` runs with
  full Lua power (unlike vimscript `.exrc`, which still gets Vim's classic
  `sandbox`/`secure` restrictions). Guidance: `:trust` only files you'd run by
  hand. The residual TOCTOU race is named too.
- Opt-out (`vim.o.exrc = false`) and un-trust recipe documented inline.

## jumplist as a browser-style stack

`opt.jumpoptions:append("stack")` in `options.lua`. Default jumplist discards
the forward history the moment you jump somewhere new after going back;
"stack" keeps `<C-o>`/`<C-i>` behaving like browser Back/Forward. Used
`:append` (not assignment) so Neovim's shipped `"clean"` flag — which prunes
unloaded buffers from the jumplist — is preserved rather than clobbered.

## Python: real lint diagnostics (ruff LSP alongside pyright)

Previously ruff was only a *formatter* (conform's `ruff_format` /
`ruff_organize_imports`) and pyright did *type* checking — so ruff's lint rules
(unused imports, undefined names, pyflakes/pycodestyle) never surfaced as
diagnostics. A whole class of Python warnings was silently absent. Now ruff
runs as an LSP too, split cleanly from pyright:

- ruff → lint diagnostics + import sorting; pyright → types + completion +
  hover.
- pyright's own import organizer is disabled (`disableOrganizeImports`) so the
  two don't fight over import edits; ruff's hover is silenced in the
  `LspAttach` handler (name-guarded) so pyright's hover is authoritative.
- `typeCheckingMode = "basic"` as a sane default (bump per-project via exrc /
  pyrightconfig.json).

Install-collision avoided: ruff is now the SAME Mason package serving both the
LSP and conform. Listing it in two `ensure_installed` sets (mason-lspconfig +
mason-tool-installer) could trip the "Package is already installing" race that
`dap.lua` warns about. So ruff is owned by ONE installer (mason-lspconfig in
`lsp.lua`) and REMOVED from mason-tool-installer's list in `formatting.lua`;
the one binary backs both roles. Both files cross-reference the decision.

## lazydev.nvim: real completion for editing this config

New spec `lua/plugins/lazydev.lua` (+ a blink source wired in
`completion.lua`). Feeds `lua_ls` the right type libraries on demand, so
editing this ~8k-line config gets real completion + hover for the whole
`vim.*` API and for `require`d plugin modules — not just the blunt
`diagnostics.globals = { "vim" }` silencer (kept as a pre-attach backstop).
Loads on `ft = lua` only; luv (`vim.uv`) types load when referenced.

## gr → Trouble

In `lsp.lua`'s `LspAttach`, `gr` now opens references in the Trouble panel
(`Trouble lsp_references toggle`) instead of dumping to the quickfix list. `gd`
/ `gD` / `gi` / `gy` stay DIRECT jumps on purpose — for a single destination a
straight jump beats a list; references is the genuinely many-valued one, so
it's the one worth routing to a navigable, previewing panel. `<leader>xl`
(the broader refs/defs/impl view) is unchanged.

## render-markdown.nvim

Added to `editor.lua`. In-buffer rendering of the Markdown this repo is full of
(README, CHANGES, the sub-READMEs): styled headings, bullets, checkboxes,
code-block backgrounds, tables — drawn as virtual text, with raw markup
revealed on the cursor line so it stays editable. `ft = markdown`, renders via
the already-present `markdown`/`markdown_inline` parsers. No leader keymap on
purpose (a Markdown-only toggle doesn't earn a global chord, and hanging one
off an existing single-key leader would add a prefix-wait); `:RenderMarkdown
toggle` at runtime.

## .editorconfig: portable whitespace baseline

New root `.editorconfig`. stylua is a destructive opt-in here (hand-aligned
tree), so there was no automatic format gate on new files. EditorConfig can't
align columns but pins the universal invariants — indent, charset, final
newline, trailing whitespace — across every editor and language. Notable
carve-outs mirror existing config decisions: Markdown keeps trailing
whitespace (hard breaks — same as the trim-on-save autocmd), the C++ templates
use 4-space indent (matching `.clang-format`'s `IndentWidth: 4`), Makefiles
keep tabs. Neovim reads it natively.

## Enforcement: CI + pre-commit hook (was: available, never run)

The Makefile always had `check`/`test`, but nothing ran them. Now:

- `.github/workflows/ci.yml` — two jobs on push/PR: `luacheck` over both trees
  (fast, no Neovim), and the plenary specs (`make test` boots the real
  `init.lua` to prove it loads + has no duplicate leader maps; `make
  test-scoper` runs scoper's logic tests in a clean headless Neovim). Plugin
  cache keyed on the plugin specs so the lazy-clone in the smoke test is paid
  once. Still no `stylua --check` — it has never passed the hand-aligned tree.
- `.githooks/pre-commit` — luacheck on staged `*.lua` before each commit,
  version-controlled and enabled per clone with `make hooks` (sets
  `core.hooksPath`). Degrades gracefully: warns (doesn't block) if luacheck is
  absent, blocks on actual lint failures, `--no-verify` to bypass.
- Makefile gains `ci` (check + test + test-scoper) and `hooks` targets.

Verified: `luacheck lua/ tests/` → 0 warnings / 0 errors across all files
including the additions; every changed/new Lua file byte-compiles; the hook
passes `sh -n`; `ci.yml` parses as valid YAML.

## Cheatsheets updated

- `keymaps.html`: `gr` row now notes the Trouble panel; new jumplist rows
  (`<C-o>`/`<C-i>` stack behavior) in the Jump card.
- `plugins.html`: ruff added to the server list + a pyright/ruff Python split
  note; a lazydev card; lazydev added to blink's source list; a
  render-markdown entry in the Editor Suite card.

## Files touched

- New: `lua/plugins/lazydev.lua`, `.editorconfig`,
  `.github/workflows/ci.yml`, `.githooks/pre-commit`
- Edited: `init.lua`, `lua/config/options.lua`, `lua/plugins/lsp.lua`,
  `lua/plugins/formatting.lua`, `lua/plugins/completion.lua`,
  `lua/plugins/editor.lua`, `Makefile`, `README.md`,
  `docs/cheatsheets/keymaps.html`, `docs/cheatsheets/plugins.html`

---

# Swap guard: opt-out toggle + fully documented modes

Follow-up to the swap re-enable: the read-only collision guard is now
optional, with comments at every decision point.

- New `vim.g.swap_guard` flag (default true; initialized with `== nil`
  so an explicit pre-set `false` in options.lua is respected) and a
  `:SwapGuardToggle` user command for flipping it mid-session. The flag
  is read inside the SwapExists callback — not captured at registration
  — precisely so the runtime toggle affects the very next contested
  open.
- Guard OFF is a faithful replica of Neovim core's deleted default
  handler (choose "e" — edit anyway — plus the W325-style one-line
  warning), so "off" means exactly "what stock Neovim would have done";
  core's own handler cannot be resurrected piecemeal once its augroup
  is deleted, hence the two-line re-implementation. Crash-leftover and
  foreign-swap handling (stock recovery prompt) is identical in both
  modes.
- Toggling does not retroactively promote already-open read-only
  buffers to writable — take-over stays an explicit :e! — by design
  and documented at the command definition.
- options.lua's swapfile comment now routes readers to both opt-outs:
  g:swap_guard for the collision behavior, `opt.swapfile = false` for
  no swap at all (everything degrades gracefully — the handler simply
  never fires). README layout tree mentions :SwapGuardToggle.

Verified live against a real concurrent instance holding three files:
guard ON → readonly + explanatory notify; :SwapGuardToggle → next
contested file opens editable with the exact W325 replica; toggle back
→ protection returns; preset `vim.g.swap_guard = false` before config
load is honored; :SwapGuardToggle registered.

Files touched:

- `lua/config/autocmds.lua`, `lua/config/options.lua`, `README.md`

---

# Safety: swap files re-enabled, with a handler that actually protects

User decision: flip `swapfile` back on for two-instance safety. Doing it
properly required more than the one-line flip; three findings along the
way, all verified end-to-end on NVIM v0.12.4 with real concurrent
instances.

## The flip alone would NOT have restored protection

Neovim 0.10+ ships a default SwapExists handler (runtime
vim/_core/defaults.lua, augroup "nvim.swapfile") that, for a swap owned
by a running same-user Nvim, auto-chooses "e" — EDIT ANYWAY — with a
one-line W325 warning. So on modern Neovim, `swapfile = true` by itself
still leaves two instances free to silently clobber each other; core
traded the guard away for less prompt noise. This config now deletes
core's handler and installs its own:

  * swap owned by a RUNNING same-user Nvim → choose "o": the second
    instance opens the file READ-ONLY with one clear notification
    ("open in another Neovim (pid N) — close it there, then :e! to
    take over"). This also keeps a second instance's auto-session
    restore quiet: shared files come up read-only instead of one E325
    prompt per file.
  * crash leftovers (swapinfo records a pid only for a still-running
    owner; dead owners report pid 0) and different-user or unreadable
    swaps → v:swapchoice stays empty, stock recovery prompt: whether
    to recover or delete possibly-unsaved work is a decision, not a
    default. Core's same-user check (with its win32 exemption) is
    retained.
  * Guard subtlety caught in testing: Lua treats 0 as truthy and
    uv.kill(0, 0) signals the caller's own process group (always
    "succeeds"), so a naive `if not info.pid` + kill-probe would have
    classified crash swaps (pid 0) as live owners and suppressed the
    recovery prompt. The handler requires a real positive pid.

## Big files: the existing swap opt-out was at the wrong event

big_file_apply already set `swapfile = false` per buffer — but on
BufReadPost, and Vim creates the swap and copies the ENTIRE file into
it when the buffer loads, so by then a >1 MB file had already paid a
full extra write. The opt-out moved to the BufReadPre marker handler;
verified: a 2 MB file opens with big_file mode on and an EMPTY
swapname().

## Everything else confirmed unaffected

Swap lives under stdpath("state")/swap// (full-path encoded — nothing
littered in project directories; verified for normal files). Scratch,
nofile, and terminal buffers never create swap, so telescope previews,
neo-tree, and toggleterm are untouched. undofile/backup settings,
sessions, and the janitors are orthogonal.

E2E matrix verified with two concurrent instances sharing XDG state:
live-owner collision → readonly=true, exactly one notification (ours),
core's W325 suppressed; SIGKILL'd owner → pid=0 swap → stock recovery
path; big file → no swap; normal file → swap in state dir.

Files touched:

- `lua/config/options.lua`, `lua/config/autocmds.lua`

---

# Perf sweep: startup-scale wins and measured non-issues

Dedicated performance pass over paths not already fixed this cycle.
Everything below is measured on NVIM v0.12.4; "left alone" verdicts are
recorded so the next audit doesn't re-litigate them.

## Fixed

- **scoper compile_commands filtering now has a freshness cache**
  (~450 ms → 0.1 ms per launch). Since setup() applies the clangd cmd
  at startup, write_filtered_compile_commands ran on EVERY launch —
  unconditionally readfile + json.decode + filter + rewrite. Measured
  on a realistic 10k-entry / 20 MB database: 365–513 ms per launch
  (Linux tmpfs; Windows + Defender and bigger monorepos scale it into
  seconds), all wasted whenever nothing changed. A tiny meta file next
  to the filtered output records the inputs that produced it — source
  path + mtime (sec/nsec) + size, and a sha256 fingerprint of the
  scope's include/exclude content (name and cwd are already in the
  cache path) — plus kept/total counts so the skip path reports the
  same message, suffixed "(cached)". Verified: warm launches 0.1 ms;
  cmake regen (mtime), scope edits (fingerprint), scope switches
  (different dir), and cache deletion all invalidate correctly; the
  rebuilt output had zero out-of-scope leaks; scoper suite still
  21/0/0 and the cold-start clangd regression test passes.
- **Session save no longer lazy-loads neo-tree at quit.** pre_save_cmds
  contained the bare string "Neotree close", which hits lazy.nvim's
  command stub and LOADS neo-tree (plus plenary/nui/devicons) during
  shutdown just to close a tree that may never have been open. Now a
  function guarded on package.loaded["neo-tree"].

## Measured and deliberately left alone

- vim.fn.getbufinfo({buflisted=1}) in pick_replacement's MRU scan
  copies every buffer's b: variables; with 72 buffers carrying
  simulated gitsigns/treesitter state it costs 0.2 ms per call, invoked
  at most once per delete-of-a-displayed-buffer. Not worth replacing
  with manual lastused tracking.
- Fold-persistence mkview/loadview per window switch: 0.07 / 0.05 ms
  per call. Even at a pessimistic 20× multiplier for Windows AV
  scanning it stays sub-2 ms per switch; gating on "has folds" is
  pointless anyway because ufo gives essentially every code buffer
  folds.

Files touched:

- `scoper.nvim/lua/scoper/lsp.lua`, `lua/plugins/session.lua`

---

# Perf: bulk buffer delete from the pickers (60-buffer sweep: ~21 s+ → 0.5 s)

User report: multi-selecting ~60 of 72 buffers in the telescope buffers
picker (<leader>fb, <Tab>, <C-d>) is "extremely slow or has gotten
stuck". Reproduced with real plenary + telescope clones on NVIM v0.12.4;
two independent pathologies found, both fixed.

## Pathology 1: the window repoint chain

Deleting one-by-one inside delete_selection meant that every time the
DISPLAYED buffer died, the origin window was repointed to the MRU
buffer — which, when the selection covers most of the recent buffers,
is simply the next victim. A 60-buffer sweep repointed the window 60
times, each repoint dragging the full BufWinLeave→mkview (disk write) /
BufWinEnter→loadview (disk read) / ufo / gitsigns cascade. Measured
with a realistic 10 ms per window event: 21,040 ms and 60 repoints.
Each skipped buffer additionally fired its own vim.notify, stacking
animated popups.

Fix: new util.delete_buffers_keep_windows(bufs) batch API — dirty
buffers set aside untouched (same never-force-discard guarantee),
every window showing ANY doomed buffer repointed ONCE to a survivor
OUTSIDE the doomed set, then a tight delete loop and ONE summary
notification (util.notify_bulk_result: "Deleted 59 buffer(s); skipped
1 with unsaved changes: f60.c"). The replacement-picking logic was
factored into a shared pick_replacement/detach_set_from_windows core so
the single-buffer path (<leader>bd) and the batch cannot drift. Both
pickers route multi-selections through the batch (telescope <C-d>
then lets delete_selection drop exactly the entries whose buffers
died, so the picker still stays open with skipped rows intact; fzf-lua
ctrl-x with reload=true likewise); single-target behavior unchanged.

## Pathology 2: TSHighlighter destroy re-applying legacy syntax

With the repoint chain fixed, deletes were still slow with the picker
open. LuaJIT profiling put 99% of time on one Neovim-core line:
TSHighlighter:destroy() → nvim_buf_call → re-run of the `syntaxset`
FileType autocmd, i.e. loading LEGACY regex syntax onto the buffer
being deleted — fully wasted work, guarded upstream by
`vim.g.syntax_on == 1`. Neovim 0.11+/0.12 attaches treesitter
highlighters to c/lua/… buffers by default, so every delete pays it,
and with a floating window focused (a picker — exactly where bulk
deletes happen) it turns pathological: measured 131,904 ms for THIRTY
deletes with the picker open vs 3 ms without the float. This also
explains "has gotten stuck".

Fix: delete_buf_quietly() masks vim.g.syntax_on for the microseconds
around each nvim_buf_delete (pcall-protected restore), skipping only
the dead re-apply on the dying buffer; syntax stays on globally and no
other buffer is affected. Used by both the single and batch paths.

## Combined result (exact pathological harness: picker open, syntax on,
## 60-of-72 sweep, one dirty buffer)

  before: 21+ seconds to minutes (chain × syntaxset destroy)
  after:  520 ms, 1 window repoint, 1 notification, dirty buffer
          preserved, picker rows correct, syntax_on restored

Files touched:

- `lua/config/util.lua`, `lua/plugins/finder.lua`

---

# Addendum: precise mechanism of the flash char-mode macro corruption

Follow-up to the previous entry, answering "why did f) land two lines
below?" — traced in flash.nvim's source (plugins/char.lua) and confirmed
by instrumenting it during a true @q replay. Flash never searched for
`)` at all. Three interacting pieces:

1. Char mode keeps per-search state (pattern, visibility), and its
   cleanup depends on the event loop running between keystrokes: the
   `M.jumping` flag is reset in a vim.schedule callback, and the
   CursorMoved autocmd only hides the state when that flag is false.
   A macro replays its whole register before the loop regains control,
   so neither fires — the state from the earlier `f,` is still alive
   and "visible" when the later `f` arrives.

2. With the state alive, flash's own macro guard
   (`reg_executing() == ""`) works as intended and skips the clever-f
   repeat branch; `getchar` then reads `)` as the new target. But the
   pattern update is gated on `if M.state.pattern:empty()` — and the
   reused state's pattern still holds `,`, which is not empty. The
   freshly-read `)` is consumed from the macro key stream and silently
   discarded. Instrumented log at the failing keypress:
   `getchar=true new_char=) pattern_empty=false pattern=[,]`.

3. The jump therefore re-runs the stale `,` search — and char mode is
   multi-line by default — so the cursor lands on the NEXT comma, two
   lines below (observed (3,11)); the macro's subsequent `xx` deleted
   the comma and space there, i.e. characters "behind" the identifier
   on a later line. In execution paths where reg_executing() reads
   empty (`:normal @q` clears it; so does recording), the clever-f
   branch fires instead: `f` repeats the `,` search and the `)` is
   never consumed, executing as Vim's sentence-forward motion — a
   different route to the same wrong line.

The editor.lua comment now records this mechanism verbatim (replacing
the earlier approximate phrasing "f) jumped past both )s", which wrongly
implied a `)` search happened). The fix is unchanged and unaffected:
`modes.char.enabled = false` removes the stateful f/t takeover entirely.

Files touched:

- `lua/plugins/editor.lua` (comment only)

---

# Fix: flash.nvim char mode corrupts f/t motions during macro playback

User report: the macro `fCdtsf,xf)xx:w^M` (turn
`CONCAT( spa_lib_name, ".lib" ))` into `spa_lib_name ".lib" )`) left the
parens alone and "deleted the space behind a CONCAT on the next line".
Three separate things were going on; all reproduced on NVIM v0.12.4
with a real flash.nvim clone.

## The bug (fixed)

editor.lua configured flash with `opts = {}`, which leaves flash's CHAR
MODE at its default: enabled, taking over f/F/t/T/;/, with
multi_line = true. Char mode corrupts those motions during @-register
playback: replaying the user's macro, `fC dts f, x` behaved, then `f)`
jumped PAST both `)`s on the cursor line to a `)` two lines below, so
the two `x`s deleted characters on the wrong line while the intended
targets survived — exactly the reported symptom. (Step execution via
`:normal!` looks fine because it bypasses mappings; register playback
re-enters the mapping engine where flash's f/t maps engage. Flash's own
reg_executing() guard covers only its repeat logic, not the motion.)

Fixed with `modes = { char = { enabled = false } }` — f/F/t/T/;/, are
stock Vim again, everywhere. This also restores a property macros
depend on even when flash behaves: stock `f` FAILS (and safely aborts
the macro) when the char isn't on the line, while flash's multi-line
`f` jumps onward and lets the macro do damage elsewhere. Flash's real
value here (`s` jump, `S` treesitter select, `r`/`R` remote) is
untouched; no cheatsheet advertised the enhanced char motions.

Verified after the fix: the user's macro under flash now behaves
byte-identically to plain Vim, staying on the cursor line.

## Not bugs, but part of what the user saw

- The macro embeds `:w`, and this config trims TRAILING whitespace on
  every save (trim_whitespace autocmd) — so a continuation line ending
  in `CONCAT( ` loses that trailing space on each replay. Reproduced;
  working as designed, but it reads as "the macro deleted a space on
  the next line".
- The macro itself has one `x` too many: in plain Vim,
  `fCdtsf,xf)xx` deletes BOTH closing parens, yielding
  `spa_lib_name ".lib" ` — the extra `x` was likely added while
  fighting the flash misbehavior. The correct macro for the stated
  transform is `fCdtsf,xf)x:w^M` (verified: produces
  `spa_lib_name ".lib" )` exactly).

Files touched:

- `lua/plugins/editor.lua`

---

# Perf: <leader>bd cold-load cascade with large sessions

User report: <leader>bd "extremely slow" with ~60 buffers open. Root
cause found by benchmark, fixed, and re-benchmarked on NVIM v0.12.4.

## Root cause

detach_buffer_from_windows picked the FIRST listed buffer in
nvim_list_bufs() order — the lowest bufnr — as the replacement for every
window showing the dying buffer. In a large session (auto-session
restores buffers listed but UNLOADED), that buffer is almost always
cold, and nvim_win_set_buf on a cold buffer synchronously loads it from
disk and fires the full attach cascade: BufRead autocmds, treesitter
parse, LSP didOpen (clangd re-parses the TU), gitsigns spawning a git
process (~100 ms+ on Windows), ufo fold computation. Every close paid
that cost for a buffer the user never asked to visit, and closing N
buffers in a row walked through N successive cold files (observed
landing path: file00 → file01 → …). The cost scales with how much of
the session is unloaded — hence "slow when lots of buffers are open".

## Fix

Replacement-buffer preference is now, per window: the window's own
alternate buffer ('#') when listed+loaded → the most-recently-used
listed+loaded buffer (getbufinfo lastused, ties to higher bufnr) → the
MRU listed buffer even if cold (last resort; at least it's the user's
most recent file) → a fresh [No Name]. The MRU scan runs at most once
per call; only the O(1) '#' lookup is per-window.

Benchmark (60-buffer restored session, 10 visited, 50 ms simulated
per-cold-load cost, 8 consecutive closes):

  before: 825 ms, 7 cold loads, landing path file00 → file06
  after:    5 ms, 0 cold loads, landing path 48 → 47 → 46 → … (MRU)

UX side effect is deliberate: closing a buffer now lands on the
alternate / most recent file — browser-tab semantics — instead of
whatever has the smallest buffer number.

Shared-helper reach: smart_bdelete (<leader>bd / <leader>bD), the
bufferline context-menu Close and close_command, and both buffer
pickers' bulk-close actions all route through this function, so all of
them stop cold-loading.

Correctness re-verified alongside the benchmark: multi-window layouts
preserved (3 wins before/after), dirty buffers still return "skipped"
untouched, deleting the last listed buffer still parks on [No Name].

Files touched:

- `lua/config/util.lua`

---

# Audit sweep 3: the uncovered ground — tooling truth, docs, templates

Focus: everything earlier sweeps never opened — the docs tree end to end,
the cpp/dap templates, formatting tooling, and the four cheatsheets that
had never been cross-checked (debugging, vs-to-nvim, clang-tools,
clang-settings-reference). Verified on NVIM v0.12.4 + stylua 2.5.2 +
luacheck; 27/27 modules load, `make check` green in both trees.

## Real findings

- **`make check` had never passed.** Audited against the pristine tree:
  `stylua --check` fails on 26 of 28 files (scoper: 11 of 12) — from the
  first commit, not from drift. The codebase is deliberately hand-aligned
  (columnar keymap tables, aligned assignments, compact
  `if x then return end` guards) and stylua reprints the AST, so no
  stylua.toml setting can ever make the existing style pass. A CI gate
  that has never been green is worse than none: `check` in both
  Makefiles now runs the static analysis that IS meaningful (luacheck
  over both trees) and passes; `format` remains as a documented
  DESTRUCTIVE opt-in; stylua.toml (both copies) carries a header
  explaining it exists for editor integration and new code, not
  enforcement. READMEs synced.
- **conform foot-gun defused:** formatting.lua registers
  `lua = { "stylua" }`, so a single `<leader>cf` in any config buffer
  (or every `:w`, with format-on-save enabled) would silently rewrite a
  file's hand alignment using this very stylua.toml. A
  `formatters.stylua.condition` now skips files under
  stdpath("config"); stylua stays fully active for Lua everywhere else.
  (Caveat documented inline: the lsp_format fallback can still reach
  lua_ls's formatter, but only on an explicit request.)
- **clang-tools.html documented `<leader>ca` for "Code action"** — this
  config binds code action to `<leader>la` (LspAttach). Fixed. Found by
  extending the doc↔code keymap cross-check from keymaps.html (sweep 1)
  to ALL eight cheatsheets, both directions.

## Verified clean (no changes needed)

- All 8 cheatsheets parse as well-formed HTML (tag-balance checker).
- Every `<leader>` chord documented anywhere now exists in code, with
  one legitimate class of exceptions: workflows.html's merge-conflict
  step cites diffview's own buffer-local defaults
  (`<leader>co/ct/cb/ca`, `]x`/`[x`) — verified diffview is installed
  and git.lua does not override its keymaps, so those are real.
- DAP keymaps: doc↔code consistent in BOTH directions across
  debugging.html / vs-to-nvim.html / keymaps.html / workflows.html.
- plugins.html has always claimed "python → debugpy" and "bash →
  bashdb" as installed adapters — sweep 2's registration fix is what
  made those rows true; docs and code now agree.
- All five clang template files parse as valid YAML;
  launch.json.example parses (modulo the //-comments and trailing
  commas nvim-dap's vscode loader accepts) and its eight configurations
  carry consistent cppdbg/codelldb field spellings.
- clang-settings-reference.html values spot-checked against the actual
  dotfiles (ColumnLimit 100, IndentWidth 4, PointerAlignment Left,
  BreakBeforeBraces Attach, InsertBraces true, -std=c++20, lower_case
  naming): all agree.
- scoper.nvim's path_spec / util_spec read end to end: thorough,
  platform-aware, and the documented split_args spacey-path limitation
  is consistent with how :ScoperRemoveExclude passes its argument.

Files touched:

- `Makefile`, `scoper.nvim/Makefile`, `stylua.toml`,
  `scoper.nvim/stylua.toml`, `README.md`, `scoper.nvim/README.md`
- `lua/plugins/formatting.lua`
- `docs/cheatsheets/clang-tools.html`

---

# Health-check cleanup: LSP log rotation, compound-filetype overrides

Follow-ups from a user :checkhealth vim.lsp run (135 MB lsp.log warning
plus six "Unknown filetype" warnings). All verified on NVIM v0.12.4.

## Changes

- New LSP-log janitor (autocmds.lua, inline at require time — before
  config.lazy, so before any server can open the log): Neovim never
  rotates or truncates lsp.log, so it grows without bound. If it
  exceeds 20 MB at startup it's renamed to lsp.log.old — rotate, not
  delete, keeping one generation for the :DiagnosticDump post-mortem
  workflow (after a hang → force-kill → restart, the evidence is in
  the PREVIOUS session's log). If another running instance holds the
  file open (Windows sharing violation), the rename silently skips and
  a later solo startup rotates. Functionally verified: 25 MB log
  rotates with a notification, tiny log untouched, .old preserved.
- Silenced the six "Unknown filetype 'X' (Hint: filename extension !=
  filetype)" warnings at their root. Neovim core's
  vim.lsp.health check_enabled_configs() validates every ENABLED
  server's declared filetypes against vim.filetype's known set;
  nvim-lspconfig's stock clangd/marksman/yamlls configs declare
  compound dotted filetypes (c.doxygen, cpp.doxygen, markdown.mdx,
  yaml.docker-compose, yaml.gitlab, yaml.helm-values) that nothing in
  stock Neovim or this config ever produces — dead entries whose only
  observable effect was the warnings. lsp.lua now overrides the three
  filetypes lists to the plain forms (vim.lsp.config replaces
  list-valued keys wholesale — verified — so the overrides are exact),
  with a comment covering how to re-add a compound filetype correctly
  (detection rule + vim.treesitter.language.register) if ever wanted.
  Verified end-to-end: enabled the stock declarations, ran
  :checkhealth vim.lsp (6 warnings), applied lsp.lua's real config()
  (0 warnings).
- Migrated every call site off vim.lsp.get_log_path(), which the
  janitor test surfaced as deprecated on 0.12 (removed in 0.13), to
  vim.lsp.log.get_filename(): diagnostics.lua's log tail, the new
  janitor, three cheatsheets, and the clangd.example template.

Files touched:

- `lua/config/autocmds.lua`, `lua/config/diagnostics.lua`,
  `lua/plugins/lsp.lua`
- `docs/cheatsheets/{plugins,workflows,cpp-diagnostics}.html`,
  `docs/templates/cpp/clangd.example`

---

# Audit sweep 2: visual-selection capture, missing DAP adapters, menu focus

Second full pass over the tree, including adversarial review of sweep 1's
own changes. Everything below verified on NVIM v0.12.4 headless (module
loads 26/26, both search.lua fixes exercised functionally, dap.lua's
config executed end-to-end against a stub, scoper suite 21/0/0, luacheck
0/0 across both trees).

## Real bugs

- search.lua visual `<leader>sr` read the selection via the `'<`/`'>`
  marks — but those are only written when visual mode ENDS, and an
  x-mode Lua mapping runs while it's still active, so the prefill was
  the PREVIOUS selection (reproduced: select "echo", grug-far opens
  with "alpha"). Now reads the live selection ("v" anchor → cursor,
  `mode()`), then feeds <Esc> so grug-far opens from normal mode.
  Verified fixed by driving the real mapping headlessly.
- search.lua `<leader>sf` prefilled grug-far's `paths` with an unquoted
  `expand("%")` — a file path containing spaces silently became two
  bogus search roots (same parser-convention bug class as sweep 1's
  :ScoperReplace fix). Now double-quoted when needed.
- dap.lua never registered a `python` or `bashdb` adapter, and defined
  no python/sh configurations — even though ensure_installed has always
  installed debugpy and bash-debug-adapter, the no-op mason-nvim-dap
  handlers mean nothing else registers them, and the comment claiming
  python was "registered explicitly in the config above" was false.
  Net effect: Python and Bash debugging could not work at all. Both are
  now registered in the file's explicit style (debugpy-adapter via the
  mason_exe shim; bashdb pointing at the vendored bashdb_dir with the
  full path* field set), with ‹fallback› configurations for python and
  sh/bash. The python fallback prefers the active $VIRTUAL_ENV
  interpreter.
- ui.lua context-menu "Toggle pin" / "Close others" ran `:buffer N` in
  whatever window was focused — and right-clicking a bufferline tab
  doesn't move focus, so invoking them while sitting in neo-tree (or a
  terminal / help / trouble panel) loaded the file INTO that panel.
  Both actions now hop to the first regular file window first
  (`in_file_window`); Toggle pin additionally restores the originally
  focused window so it stays fully transparent.
- Regression from sweep 1 (caught by self-review): dropping
  gitcommit/gitrebase from close_with_q also dropped their
  `buflisted = false`, so commit-message buffers started appearing as
  bufferline tabs. Restored via a dedicated `unlist_transient`
  autocmd, without reinstating the `q` map.

## Hardening / docs

- diagnostics.lua's DAP-session section now leads with a review notice:
  `vim.inspect(s.adapter)` / `s.config` routinely embed env blocks and
  credential-bearing command lines, and the dump exists to be handed to
  someone.
- Verified (not just assumed) two semantics sweep 1's scoper work
  depends on: `vim.lsp.config()` REPLACES list-valued keys wholesale
  rather than merging element-wise (a shorter cmd cannot inherit a
  stale `--compile-commands-dir` tail across toggle round-trips), and
  the live-region read handles charwise and linewise selections.
- Files re-read end-to-end and found clean, no changes needed:
  explorer, git, terminal, trouble, which-key, treesitter, completion,
  lazy, options, keymaps, finder, formatting, colorscheme, neogen,
  atone, the scoper plugin spec, scoper path/state/ui, session,
  editor, and tests/config_spec.

Files touched:

- `lua/plugins/search.lua`, `lua/plugins/dap.lua`, `lua/plugins/ui.lua`
- `lua/config/autocmds.lua`, `lua/config/diagnostics.lua`

---

# Audit pass: portability, scoper cold-start, quoting, and shared helpers

Full-config audit (verified on NVIM v0.12.4 headless: luacheck clean over
`lua/ tests/` and the scoper.nvim suite green). Fixes below are grouped by
severity; every behavioural change carries an inline comment at the site
explaining the why, so this entry stays a summary.

## Real bugs

- `tests/minimal_init.lua` never put the config root on `runtimepath`, so
  `make test` only worked when the checkout WAS `~/.config/nvim` (Neovim
  always adds stdpath("config") to rtp, masking the bug on the author
  machine). From any other checkout or CI the suite died immediately with
  `module 'config.options' not found` — reproduced, fixed with the same
  `rtp:prepend(getcwd())` scoper's harness already had.
- scoper.nvim: the advertised clangd cold-start win never applied on cold
  start. `setup()` only hooked `ScoperChanged` (fired by mutations), so a
  fresh nvim in a scoped project started clangd unfiltered. setup() now
  applies `vim.lsp.config("clangd", { cmd = ... })` immediately (no
  restart needed — no client exists yet), and `state.load()` now fires
  `ScoperChanged`, so `:cd other-project` also reconfigures clangd for the
  new cwd instead of serving the previous project's filtered cache.
- scoper.nvim `:ScoperReplace` quoted grug-far `paths` with
  `vim.fn.shellescape`, which single-quotes on Unix; grug-far's own paths
  parser honours double quotes only, so the quotes reached ripgrep as
  literal bytes and scope dirs containing spaces matched nothing. Now
  quoted per grug-far's convention (double quotes, only when needed).
- `close_with_q` covered gitcommit/gitrebase: `q` shadowed macro recording
  exactly where people record macros (rebase todo lists), and the commit
  buffer is usually the ONLY window, so `<cmd>close<cr>` was just an E444
  error. Both filetypes removed; the remaining close is pcall'd for the
  same last-window reason (`nvim +help`).
- fold-persistence `mkview` on BufWritePost ran during `:wa` for
  windowless background buffers via the autocmd window — the eligibility
  check inspected `args.buf` while mkview saved the WRONG window's state.
  Guarded on `nvim_get_current_buf() == args.buf`.
- folding.lua cached NEGATIVE `has_ts_folds` results permanently, but a
  negative is transient on first launch (parsers install asynchronously in
  the background): the language got pinned to the indent provider for the
  whole session even after its parser finished compiling. Only positive
  results are cached now.
- lsp.lua mapped `gr` while Neovim 0.11+'s default `grr/grn/gra/gri/grt`
  maps still existed, turning `gr` into an ambiguous prefix — every press
  waited out timeoutlen (400 ms). The defaults are now deleted (their
  functionality lives on `<leader>lr`, `<leader>la`, `gi`, `gy` here);
  `gi`'s shadowing of the built-in "go to last insert" is now documented
  as deliberate.
- ui.lua context menu: the keyboard entry point (`<leader>bm`) reused
  `getmousepos()`, i.e. wherever the pointer LAST happened to be — (0,0)
  if it never moved — so the menu opened at the top-left corner or at a
  stale click position. `show_menu` takes an anchor now: mouse for
  right-click, cursor for the keymap.

## Robustness / async

- dap.lua pause wrapper: the async `threads` request callback can run
  after the session died or was replaced by a restart; it now re-checks
  `dap.session() == s` before pausing.
- session.lua's post-restore rescue reaches into scope.nvim INTERNAL
  state (`core.cache`); every access is now type-guarded so an upstream
  reshape degrades the rescue to a no-op instead of erroring mid-restore.
- autocmds trim-whitespace guards read `vim.bo[args.buf]` /
  `vim.b[args.buf]` instead of the ambient current buffer — same-buffer
  in the common case, correct under `:wa`.
- SessionLoadPost treesitter re-attach is wrapped in `vim.schedule` so N
  synchronous parses no longer extend the visible restore stall.
- New view-file janitor (VimLeavePre): mkview files accumulated forever;
  entries not touched in 90 days are pruned on exit, everything pcall'd.
- `sessionoptions` no longer contains "terminal": mksession restored
  terminals as dead [Process exited] buffers, and session.lua already
  wiped DAP terminals before save for exactly this reason.

## Duplication extracted

- `scoper.util` gains `cwd_hash` (was implemented twice — state store vs
  clangd cache; divergence would silently split one project in two),
  `atomic_write` (tmp+rename pattern was verbatim in state.lua and
  lsp.lua), and `has`/`prefer_fzf` (backend preference was copy-pasted at
  four call sites across pickers.lua and ui.lua).
- New `lua/config/icons.lua`: the diagnostic glyph set was defined three
  times (vim.diagnostic signs, lualine symbols, bufferline indicator);
  all three now read one table.
- New `config.util.notify_undeleted`: the "Skipped (unsaved changes)"
  warning was copy-pasted between the telescope and fzf-lua buffer
  pickers.
- mini.surround's `keys` function now extends lazy's merged `keys`
  parameter instead of discarding it (also clears the luacheck
  unused-argument warning); scoper pickers.lua drops a dead
  `require("scoper.path")`.

## Features

- `:ScoperRemoveExclude [glob]` (+ `require("scoper").remove_exclude()`):
  `state.remove_excludes` existed and was tested but nothing user-facing
  called it — excludes were append-only short of hand-editing the JSON.
  No args → multi-select picker; completion offers current excludes.
- scoper `:ScoperFind` fd_opts now re-includes `--exclude .git` and
  `--type l`: setting `fd_opts` REPLACES fzf-lua's defaults wholesale,
  and the stock default's `--exclude .git` had been silently dropped.
- scoper plain-vim grep fallback escapes `/` in the pattern (it's the
  :vimgrep delimiter).

## Docs

- init.lua header said 0.12.2 (README says 0.12.3) — bumped.
- README layout tree gains `util.lua` and `icons.lua` (both existed
  or exist now but weren't listed).
- scoper README: new command row, cold-start paragraph in the clangd
  section, an explicit lost-update caveat (atomic saves ≠ locked
  read-modify-write across instances), and a prefix note under
  "Suggested keymaps" for bundled-config users.
- plugins.html scoper card: exclude add/remove row + cold-start note.
- Makefile `lint` now covers `tests/` (the .luacheckrc already declared
  the busted globals it needs); insert-mode undo-break maps document the
  abbreviation-suppression trade-off.

Files touched:

- `tests/minimal_init.lua`, `init.lua`, `Makefile`, `README.md`
- `lua/config/autocmds.lua`, `lua/config/options.lua`,
  `lua/config/keymaps.lua`, `lua/config/util.lua`, `lua/config/icons.lua` (new)
- `lua/plugins/lsp.lua`, `lua/plugins/ui.lua`, `lua/plugins/editor.lua`,
  `lua/plugins/folding.lua`, `lua/plugins/session.lua`,
  `lua/plugins/dap.lua`, `lua/plugins/finder.lua`
- `scoper.nvim/lua/scoper/{init,state,lsp,pickers,ui,util}.lua`,
  `scoper.nvim/plugin/scoper.lua`, `scoper.nvim/README.md`
- `docs/cheatsheets/plugins.html`

---

# Docs: cross-reference fold persistence from folding.lua

Comment-only follow-up to the fold-persistence feature. folding.lua is where a
reader goes to understand fold behaviour, but it described only ufo (which
computes fold structure) and said nothing about where the open/closed STATE is
remembered across restarts. Added a paragraph to its header pointing to the
`fold_persistence` autocmds in autocmds.lua and the `viewoptions` setting in
options.lua, and noting the two are decoupled (ufo never gets called by the
persistence code, so either can change independently). No code change; folding.lua
still parses clean.

Files touched:

- `lua/plugins/folding.lua`.

---

# Feature: persist folds across restarts, decoupled from ufo and sessions

Folds now survive `:qa` and reopen in the open/closed state you left them —
per file. Previously `sessionoptions` contained `folds`, but nvim-ufo recomputes
folds asynchronously on load (foldlevel 99 → everything reopens) and overwrote
the session's restored state, so it never actually worked.

## Approach (and why this one)

Requirement was a solution that doesn't rot when ufo or the session system
changes or is disabled. So this deliberately avoids both:

  * Persistence is native view files (`:mkview` / `:loadview`), not sessions.
    `viewoptions` is set to `folds` only (no cursor, no curdir, no options), so
    a restore can't move the cursor or drag in stale state. `folds` was removed
    from `sessionoptions` so fold state lives in exactly one place and the two
    systems can't fight over it on restore.
  * No coupling to ufo. ufo exposes no "folds applied" event, and its apply is
    async, so "restore right after ufo" would mean depending on its internals.
    Instead we restore on `BufWinEnter` and reassert once on the first
    `CursorHold` after entering. CursorHold fires after `updatetime` (250ms) of
    idle — after ufo has settled — so the reassert lands last and wins, without
    the code referencing ufo at all.

Degradation is graceful by construction: ufo disabled → native folds are ready
at BufWinEnter and the CursorHold pass is a harmless no-op; sessions disabled →
irrelevant, view files are independent; ufo or mksession internals change →
mkview/loadview record and restore whatever folds exist regardless. Everything
is guarded (`buftype == ""`, real name, skip commit/help filetypes) and wrapped
in `silent!` + `pcall`, so no buffer can make it raise. The reassert uses a
per-buffer flag so it fires once per entry and never fights folds you open
yourself afterward.

Trade-off worth knowing: on an LSP-folded file there's a ~250ms window on open
where folds are ufo's default (open) before the CursorHold reassert restores
your state — a brief settle, not a flash loop.

Verified: options.lua and autocmds.lua parse clean under luajit, and the
buffer-eligibility filter passes a mocked table (real files in, terminals /
[No Name] / gitcommit / neo-tree out).

Files touched:

- `lua/config/options.lua`.
- `lua/config/autocmds.lua`.

---

# Fix: recover buffers scope.nvim drops from the session on restore

Symptom: after `:qa` and reopening, the most-recently-opened file would
sometimes be missing from bufferline — sporadically, and only the newest
one(s). The file was actually restored (it opened as a buffer), it just wasn't
listed, so bufferline never drew it. Not caused by the recent buffer-delete
work — nothing in that path runs during quit; this is a pre-existing fragility
in the scope.nvim + auto-session persistence.

## Mechanism

scope.nvim persists a per-tab list of buffer *names* into `g:ScopeState` and,
on `ScopeLoadState`, unlists every buffer and then re-lists only the ones in
that saved list (`scope/session.lua`, `scope/core.lua:on_tab_leave/enter`). If
a buffer isn't in the saved cache, it comes back `buflisted = false` — loaded
but invisible to bufferline. At save time scope captures the current tab via
`get_valid_buffers()` (buflisted buffers), but the newest buffer occasionally
isn't in that set when the capture runs during shutdown — a timing race, hence
"sporadic" and "the latest file". `mksession` still saves that buffer as the
window's buffer (sessionoptions has `buffers`), so on restore it reopens but
scope has already forgotten it: restored, loaded, unlisted, gone from the tabs.

## Fix

A reconciliation step appended to auto-session's `post_restore_cmds`, after
`ScopeLoadState`. It walks scope's per-tab cache, builds the set of buffers
scope accounts for anywhere, and adopts any restored real-file buffer that's in
*no* tab's cache into the CURRENT tab — re-listing it and adding it to
`scope.core.cache[current_tab]` so bufferline shows it again. `buftype == ""`
plus a non-empty name limits this to genuine file buffers (terminals, help,
quickfix, neo-tree, dap panels, `[No Name]` are excluded). Buffers legitimately
scoped to another tab are present in that tab's cache, so they count as
accounted and stay hidden — the net only catches the buffers scope actually
lost, so per-tab scoping is preserved.

Chose a restore-side safety net over trying to win scope's save-time race: it
fixes the observable symptom regardless of why a buffer was dropped, and does
nothing on a clean restore (every restored buffer is already accounted for).

Verified: session.lua parses clean under luajit, and the reconciliation
algorithm passes a mocked harness covering orphan rescue, other-tab buffers
staying hidden, and terminals / `[No Name]` being left alone.

Files touched:

- `lua/plugins/session.lua`.

---

# Change: skip dirty buffers BEFORE detaching, via one shared delete helper

Follow-up to the previous two entries. All three buffer-delete paths detached a
buffer's windows first and only then discovered the delete would fail on unsaved
changes — so a dirty buffer would be left alive but silently nudged out of its
split (its windows re-pointed to another buffer). Reported as annoying, and
correctly so: nothing should touch the layout for a buffer that isn't going
anywhere.

## The fix

New shared routine `util.delete_buffer_keep_windows(bufnr, force)` that checks
`&modified` BEFORE calling `detach_buffer_from_windows`. If the buffer is dirty
and force isn't set, it returns "skipped" and touches nothing — the buffer keeps
its exact place in every window. Otherwise it detaches and deletes, returning
"deleted" or (for a rare non-modified error) "failed". Terminals imply force
since they're never "written". Callers own the messaging so each phrases it for
its context; the helper stays silent.

All three sites now route through it, so they can't diverge:

  * `smart_bdelete` / `<leader>bd` + `<leader>bD` (keymaps.lua) — keeps its
    existing "unsaved changes? <leader>bD force-deletes" warning on skip.
  * telescope `<leader>fb` + `<C-d>` (finder.lua) — returns `status == "deleted"`
    to `delete_selection`, so skipped buffers stay in the list.
  * fzf-lua `<leader>Fb` + `<C-x>` (finder.lua).

## Behaviour change worth noting

`<leader>bd` / `<leader>bD` were pulled into the shared helper too. Previously
`<leader>bd` on a dirty buffer re-pointed the current window before failing;
now it leaves the buffer and its window untouched (same warning as before). The
force path (`<leader>bD`) and clean-buffer path are unchanged. This was
deliberate — leaving `<leader>bd` on the old behaviour while the pickers got the
new one would recreate exactly the kind of divergence this config treats as a
bug (the whole reason the delete logic lives in util.lua).

Verified with a mocked harness covering dirty/no-force (skipped, no detach),
dirty/force (deleted), clean (deleted), terminal (force-deleted), invalid
buffer (no-op), and delete-error (failed) — all pass. util.lua, keymaps.lua and
finder.lua parse clean under luajit.

Files touched:

- `lua/config/util.lua`.
- `lua/config/keymaps.lua`.
- `lua/plugins/finder.lua`.

---

# Change: fzf-lua buffers picker <C-x> is now window-safe, matching telescope's <C-d>

The `<leader>Fb` (fzf-lua buffers) picker used fzf-lua's stock delete action;
`<leader>fb` (telescope buffers) had a custom, window-preserving one. So the
same bulk-close gesture behaved differently depending on which picker you
opened — and the fzf-lua side carried the window-closing bug.

## What was wrong

fzf-lua's default buffers action is `["ctrl-x"] = { fn = actions.buf_del,
reload = true }`. Stock `actions.buf_del` does, per selected entry:

    vim.api.nvim_buf_delete(entry.bufnr, { force = true })

Two problems versus the telescope `<C-d>` action:

  1. No window re-pointing. `nvim_buf_delete` closes every window showing the
     buffer (`:h :bdelete`), so deleting a buffer visible in a split takes the
     split (or a side panel) down with it — the exact layout damage
     `<leader>bd` / `<leader>bJ` and the telescope buffers action all avoid via
     `util.detach_buffer_from_windows`.
  2. `force = true` (after a save dialog) means a bulk sweep can force-discard
     unsaved buffers, where the telescope action skips dirty buffers with a
     warning and leaves them in the list.

## The change

Override just the buffers picker's `<C-x>` action in `finder.lua` with a
handler that mirrors the telescope `<C-d>` action per buffer: detach windows
first via the shared helper, force only for terminals, `pcall` the delete, and
warn + keep on failure (a modified buffer makes the non-force delete fail, so
it's skipped rather than discarded). `reload = true` is preserved, so the picker
stays open with deleted rows removed and you can keep culling. `--multi` is on
by default, so `<Tab>`/`<S-Tab>` still mark and `<C-x>` acts on every marked
buffer (or the highlighted one when nothing is marked).

Only the one action is overridden. fzf-lua's shared open/split actions
(`enter`, `<C-s>`, `<C-v>`, `<C-t>`, …) come from its internal `_actions`
(`globals.actions.files`), a separate table, so they are untouched — verified
against fzf-lua's `defaults.lua`. The bufnr is resolved with
`require("fzf-lua.path").entry_to_file(sel, opts).bufnr`, the same call stock
`buf_del` uses. Both pickers now route buffer deletion through the single
`detach_buffer_from_windows` implementation, so telescope and fzf-lua can't
drift apart. finder.lua parses clean under luajit.

Files touched:

- `lua/plugins/finder.lua`.

---

# Fix: BufferLinePickClose (<leader>bJ) closed the window along with the buffer

Same class of bug that `smart_bdelete` / `<leader>bd` fixed, in a spot that had
been missed. `<leader>bJ` (`BufferLinePickClose`) lets you pick a buffer by
letter and close it. It routes through bufferline's `close_command`, which was:

    close_command = function(n) pcall(vim.api.nvim_buf_delete, n, {}) end,

That deletes the buffer without first re-pointing the windows showing it, so
`nvim_buf_delete` (like `:bdelete`) closes every window displaying that buffer.
Picking a buffer that was visible in a split therefore took the split down with
it — the exact layout damage `<leader>bd` avoids.

The window-preserving logic already lived in
`util.detach_buffer_from_windows(bufnr)` and was already shared by
`smart_bdelete` (keymaps.lua) and the bufferline context menu's "Close" action
(ui.lua). `close_command` simply wasn't wired to it — an oversight, since
`BufferLinePickClose`, the tab close button, and other bufferline-initiated
closes all funnel through `close_command`. Fixed by detaching first, mirroring
the context menu's "Close":

    close_command = function(n)
      require("config.util").detach_buffer_from_windows(n)
      pcall(vim.api.nvim_buf_delete, n, {})
    end,

Now `<leader>bJ`, the close button, and the context menu all preserve the split
layout identically. No new helper was introduced — this reuses the single
shared implementation, so the paths still can't drift apart. ui.lua parses clean
under luajit after the change.

Files touched:

- `lua/plugins/ui.lua`.

---

# Docs fix: correct completion accept keys and grug-far sync rows in keymaps cheatsheet

Three rows in `docs/cheatsheets/keymaps.html` described behaviour that does
not match the config. Found while auditing the cheatsheet against the actual
plugin bindings.

## Completion accept keys (the important one)

`completion.lua` runs blink.cmp with `keymap = { preset = "default" }`. In the
default preset the accept key is `<C-y>` (`select_and_accept`); `<CR>` is left
unbound, so Enter falls through to inserting a newline. Enter-to-accept is a
property of the *separate* `enter` preset, which this config does not use.
The config's own comment in `completion.lua` already says as much
(`<C-y> accept` … `enter` = "Enter accepts").

The cheatsheet had imported the `enter` preset's behaviour by mistake:

    <CR>   Accept selected            <- wrong: <CR> is unbound, inserts a newline
    <C-y>  Accept (without indent)    <- the real accept key, mislabelled

Corrected to:

    <C-y>  Accept selected            (the default preset's accept key)
    <CR>   Inserts a newline — does not accept (note points to <C-y> and the
           `enter` preset for anyone who wants Enter-to-accept)

The "(without indent)" qualifier on `<C-y>` was invented — `select_and_accept`
has no such variant — and was dropped. A reader pressing Enter expecting the
completion to commit would previously have been misled into inserting a
newline instead; this is the one with real behavioural bite.

## grug-far sync rows

The `\s` row read "Sync edited line back". `<localleader>s` is `syncLocations`,
which syncs *all* edited result lines back to their files; the per-line sync is
`syncLine` on `<localleader>l`, which the sheet did not list at all. Relabelled
`\s` as "Sync all edited results back to their files" and added the missing
`\l` row ("Sync current line back to its file").

Not changed: `<leader>?` ("buffer-local keymaps") and `s{cc}` ("2-char jump
anywhere on screen") were both reviewed and are accurate — `<leader>?` is the
canonical `which-key.show({ global = false })` binding, and `s` is flash's jump
(surround lives on `gz` precisely so `s` stays free). Tag balance in the file
was re-checked after the edits (tr/td/kbd/span/code/em all balanced).

Files touched:

- `docs/cheatsheets/keymaps.html`.

---

# Cleanup: de-duplicate the path_display comment in finder.lua

Cosmetic only. The `path_display = { "smart" }` line in the telescope
`defaults` block (`lua/plugins/finder.lua`) carried three identical copies
of its explanatory comment:

    -- "smart" = shorten paths intelligently (drop common prefixes).
    -- "smart" = shorten paths intelligently (drop common prefixes).
    -- "smart" = shorten paths intelligently (drop common prefixes).
    path_display = { "smart" },

Almost certainly a copy/paste slip in an earlier edit. Collapsed to a single
line; the code and behaviour are untouched (telescope still shortens paths by
dropping common prefixes). No other duplicated-comment runs were found
elsewhere in the file. finder.lua parses clean under luajit after the change.

Files touched:

- `lua/plugins/finder.lua`.

---

# Change: fzf-native build detects make/cmake availability instead of OS

Refines the previous entry. The OS check (cmake on Windows, make elsewhere)
was too rigid — it forced cmake on every Windows machine even if make was
present, and assumed make on every non-Windows machine. Now the build string
is chosen by what's actually on PATH, in `lua/plugins/finder.lua`:

    build = (function()
      if vim.fn.executable("make") == 1 then return "make" end
      if vim.fn.executable("cmake") == 1 then return "cmake -S. -Bbuild ... --target install" end
      return "make"  -- neither found: fail naming a tool you can install
    end)()

Preference order: make (upstream default, needs gcc/clang) → cmake (needs
CMake + a C++ toolchain, e.g. MSVC Build Tools on Windows) → make as a last-
resort fallback so the build error names a missing tool. Evaluated when the
spec loads; installing a tool later needs a Neovim restart + :Lazy build.
Verified finder.lua parses and the selection resolves correctly for all four
make/cmake availability combinations (make-only, cmake-only, both, neither).

Docs updated to match:
- `lua/plugins/finder.lua` — both fzf-native comments now describe the
  "whichever is on PATH" detection.
- `README.md` — the `make`/`cmake` prerequisite row now says the spec
  auto-detects which is available (prefers make, falls back to cmake) rather
  than splitting by OS.

Files touched:

- `lua/plugins/finder.lua`, `README.md`.

---

# Fix: telescope-fzf-native builds with cmake on Windows; README version bump

Two requested items.

## fzf-native: cmake on Windows, make elsewhere

`make` isn't available on the user's Windows machine, so the hardcoded
`build = "make"` for telescope-fzf-native never produced the native sorter
there. Made the build string OS-conditional in `lua/plugins/finder.lua`:

    build = vim.fn.has("win32") == 1
        and "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install"
      or "make",

- Windows → the cmake command (the current `--target install` form from
  telescope-fzf-native's README; needs CMake + the MSVC C++ Build Tools,
  which the user already has for their MSVC work).
- Linux/macOS → unchanged `make` (gcc/clang + make).
The string is chosen when the spec loads (vim.fn.has is available then). The
`and/or` idiom is safe here — the cmake branch is always a truthy string.
Verified finder.lua parses and both branches resolve to the right command.

## Docs

- `lua/plugins/finder.lua` — both fzf-native comments now mention the cmake
  path, not just `make`.
- `README.md` — the Recommended-tools `make` row is now `make` / `cmake`,
  noting cmake + MSVC Build Tools is used on Windows.
- `README.md` — "Neovim 0.12.2 configuration" → "0.12.3" to match the user's
  build (NVIM v0.12.3, LuaJIT 2.1.1774638290). Left the "≥ 0.11.2" minimum
  in the prerequisites/verify steps as-is: that's the deliberate compat floor
  (the config targets the vim.lsp.config API introduced in 0.11.2), and
  raising it to 0.12.3 would wrongly exclude 0.11.x / 0.12.0–0.12.2 users.

Files touched:

- `lua/plugins/finder.lua`, `README.md`.

---

# Feature: ]f / [f to jump between file headers in the grug-far results buffer

grug-far has no "next file" action — its built-in location nav (<down>/<up>)
steps match-by-match. Added buffer-local `]f` / `[f` that jump straight to the
next / previous file-path header in the results.

- `lua/config/autocmds.lua` — FileType autocmd (pattern "grug-far"; the plugin
  sets that filetype, confirmed in its farBuffer.lua) sets buffer-local `]f` /
  `[f`. They search for `^\s*$\n\zs\S` — the first non-blank char of a line
  that follows a blank line. grug-far separates each file group with a blank
  line and renders the file path as a column-0 header, so that pattern lands
  exactly on file headers. A plain "column-0 line" match would NOT work: match
  lines show raw source text and may themselves start at column 0 — the
  detection rule was unit-tested in luajit against a buffer containing a col-0
  match line, and it correctly skips it.
- `lua/plugins/search.lua` — note added by the keymaps table pointing to the
  autocmd, and documenting that <down>/<up>/<enter>/\i keep grug-far defaults.

Other grug-far keys are untouched; `]f`/`[f` aren't otherwise mapped in that
buffer. Docs: keymaps.html grug-far card gained a "Navigation (in results)"
block (match nav <down>/<up>/<enter>/\i, which were previously undocumented,
plus the new ]f/[f). Both Lua files luajit-parse clean; HTML balanced.

Files touched:

- `lua/config/autocmds.lua`, `lua/plugins/search.lua`,
  `docs/cheatsheets/keymaps.html`.

---

# Fix/correction: make <Tab> actually fall through to native completion in :!

Follow-up to the previous entry. The question "can I still trigger shell
completion with Tab?" prompted verifying blink's keymap behavior instead of
assuming — and the previous entry's claim that shell commands "fall back to
native <Tab> wildmenu" was WRONG as shipped.

Why it was wrong: blink's default cmdline <Tab> is
{ 'show_and_insert_or_accept_single', 'select_next' } with NO 'fallback'.
Reading blink's keymap/apply.lua: it runs each command in order and, if none
succeeds and there's no explicit 'fallback', the loop ends and the key is
SWALLOWED (no passthrough). So once we removed blink's sources for shell
commands, <Tab> in :! did nothing at all — not native completion.

Fix — `lua/plugins/completion.lua`: added `cmdline.keymap` (preset = "cmdline")
overriding <Tab>/<S-Tab> to append 'fallback'. Now when blink has no
completions (shell/filter commands), <Tab> passes through to Neovim's native
wildmenu, so executable completion inside :! works on demand (the $PATH scan,
but only when you press <Tab>). For normal commands blink still handles <Tab>
first, so fallback is only reached when blink offers nothing. Native wildmenu
is on by Neovim default (no wildmenu/wildchar overrides in options.lua), so
the fallback reaches a working completion.

So, to answer the clarifying question directly: yes — after this change,
<Tab> inside :! triggers native shell-command completion on demand; without
this change it did not.

Docs: completion.lua comment expanded to explain the fallback; keymaps.html
Completion card gained a "Command line (:)" note covering blink cmdline
completion, the shell-command skip, and <Tab>-for-native-on-demand. HTML
balanced; completion.lua luajit-parses clean.

Files touched:

- `lua/plugins/completion.lua`, `docs/cheatsheets/keymaps.html`.

---

# Fix: Neovim hangs for seconds after typing :! (shell-command completion)

Symptom: pressing `:!` froze Neovim for a few seconds before the rest of the
command could be typed.

Cause: blink.cmp provides command-line completion (it loads on CmdlineEnter)
and lists "!" as a cmdline trigger character (confirmed in blink's cmdline
source). Typing `:!` therefore fires blink's cmdline source immediately, and
for a shell/filter command that resolves to Neovim's "shellcmd" completion —
which enumerates every executable on $PATH. On this Windows box the corporate
PATH is large, so that scan blocks the UI for seconds. (Native completion does
the same scan but only on <Tab>; blink auto-triggers it on the keystroke.)

Fix — `lua/plugins/completion.lua`: added a `cmdline.sources` function that
mirrors blink's default source routing (buffer for /?, cmdline for :@) but
returns no sources for shell/filter commands, so blink never computes
shellcmd completion:
  - `vim.fn.getcmdcompltype() == "shellcmd"` catches all forms Neovim has
    already typed as shell, including visual-range filters (:'<,'>!…).
  - a `getcmdline():match("^%s*[%%%d,%.%$;]*!")` pattern catches :!, :%!,
    and :N,M! even before a completion type exists for a bare "!".
Detection was unit-tested in luajit against 15 command-line strings: it skips
:!/:%!/:N,M!/.,$! (and leading-space variants) and correctly leaves :w!, :q!,
:wq!, :e!, :normal! gg, :s/…/…/, and ordinary commands untouched.

Everything else (`:` command names, paths, options) still completes via blink
as before; only shell/filter commands fall back to native <Tab> wildmenu.
completion.lua luajit-parses clean. No cheatsheet documents cmdline completion,
so docs unchanged.

Files touched:

- `lua/plugins/completion.lua`.

---

# Fix: <Tab> in insert mode sometimes jumps up instead of indenting

Symptom: occasionally <Tab> in insert mode moved the cursor a few lines up
rather than inserting spaces, and it wouldn't reproduce on a fresh attempt.

Cause: blink.cmp's "default" preset binds <Tab> = { 'snippet_forward',
'fallback' } and <S-Tab> = { 'snippet_backward', 'fallback' } (confirmed in
blink's keymap/presets.lua). snippet_forward fires whenever a LuaSnip
session is active and jumpable, only falling through to 'fallback' (indent →
spaces, since expandtab is on) when none is. LuaSnip kept a session "active"
after you expanded a snippet and moved away — nothing in the config cleared
it — so a later <Tab> meant to indent jumped back into the stale snippet,
landing on a placeholder above the cursor. Intermittent because it only
happened while a leftover session lingered; once it resolved, <Tab> indented
again, which is why it never reproduced afterward.

Fix (two layers, both LuaSnip-documented):
- `lua/plugins/completion.lua` — gave the LuaSnip dependency a config that
  calls `setup({ region_check_events = "CursorMoved,CursorMovedI",
  delete_check_events = "TextChanged,InsertLeave" })`. The session now exits
  the instant the cursor moves outside the snippet's region (jumping between
  placeholders stays in-region, so normal snippet use is unaffected).
- `lua/config/autocmds.lua` — added a ModeChanged autocmd that unlinks the
  current LuaSnip session when leaving insert mode (i -> n) or exiting select
  mode (s -> n) without an active jump. Backstop for the mode-leave case.

No keymaps changed; <Tab> still jumps placeholders while a snippet is genuinely
active. keymaps.html's <Tab>/<S-Tab> row now notes the auto-exit behavior.
Both edited Lua files luajit-parse clean; cheatsheet tags balanced.

Documentation review (this turn): swept README, which-key.lua, and all
cheatsheets for stale references from this session's changes — none found
(no leftover <C-k>=signature mentions; which-key uses desc fields, nothing
hardcoded). One gap closed: README's `<leader>l` namespace row described
"rename, format, diagnostics" but signature help moved into that group
(<C-k> → <leader>lk earlier this session), so it now reads "rename, format,
diagnostics, signature".

Files touched:

- `lua/plugins/completion.lua`, `lua/config/autocmds.lua`,
  `docs/cheatsheets/keymaps.html`, `README.md`.

---

# Fix: faster <C-f>/<C-b> full-page scroll — and a crash fix in the <C-d>/<C-u> maps

Speeding up <C-f>/<C-b> per request surfaced a latent bug in the neoscroll
custom maps added in the previous change. Both addressed in `editor.lua`.

## <C-f>/<C-b> were sluggish (the actual request)

neoscroll's built-in default duration for the full-page ctrl-f/ctrl-b maps
is 450ms — and since this config runs `duration_multiplier = 0.7`, that's
~315ms of animation for a full-window jump, which dragged. Pulled <C-f>/
<C-b> out of the default `mappings` list and gave them custom maps at
`FULLPAGE_MS = 220` (≈154ms effective). Single named local, easy to tune;
comment notes the 0.7 multiplier and the old 450 value.

## Latent crash: the <C-d>/<C-u> maps had no duration

The <C-d>/<C-u> custom maps from the prior change called
`neoscroll.ctrl_d({ info = "center" })` with no `duration`. Reading the
neoscroll source while sizing the <C-f>/<C-b> change showed
`new_scroll()` does `opts.duration = duration_multiplier * opts.duration`
with NO nil fallback and no default in `default_scroll_opts`, so a
duration-less ctrl_* call is `0.7 * nil` → "attempt to perform arithmetic
on field 'duration' (a nil value)" on every keypress. Verified by
reproducing the arithmetic error in luajit, and confirmed every custom-map
example in neoscroll's own README/source passes an explicit `duration`.

Fixed by giving <C-d>/<C-u> `duration = 250` (≈175ms effective — matches
neoscroll's default half-page feel) alongside the existing info="center".
Added a comment at the map block stating the duration is REQUIRED and why.

(Note: this means the centered half-page scroll from the previous changelog
entry would not have worked until this fix — the keymaps would have errored
rather than scrolled. Now live.)

No cheatsheet references <C-f>/<C-b>/<C-d>/<C-u> durations, so docs unchanged.
editor.lua luajit-parses clean.

Files touched:

- `lua/plugins/editor.lua`.

---

# Fix: two keymap collisions found in the full-plugin audit

Static audit of every plugin (all Lua parsed clean; treesitter-`main`
ecosystem, dap-virtual-text, and the dual terminal plugins all verified
compatible). Two real collisions found and fixed; everything else was
either mode-separated or intentional.

## 1. <C-k> window-up was shadowed in every LSP buffer

`keymaps.lua` maps global <C-k> → <C-w>k (window up). `lsp.lua` mapped a
buffer-local normal-mode <C-k> → signature_help on LSP attach, which won
in any LSP buffer — so window-up was unreachable via <C-k> in code files.
The old comment reasoned about insert-mode i_CTRL-K digraphs but missed
that <C-k> is also the window-nav key.

- `lua/plugins/lsp.lua` — signature help moved to `<leader>lk` (normal
  mode; `<leader>lk` was free). Comment rewritten to explain the move.
  Insert mode still needs no binding (blink.cmp auto-shows the signature
  popup while typing). <C-k> is now window-up everywhere again.

## 2. "Centered" half-page scroll wasn't centering

`keymaps.lua` mapped <C-d>→<C-d>zz / <C-u>→<C-u>zz ("centered"), but
neoscroll (loads at VeryLazy, later) listed <C-d>/<C-u> in its `mappings`
and replaced them with animated scrolls that don't recenter — so the `zz`
was silently dead.

- `lua/config/keymaps.lua` — removed the dead <C-d>zz/<C-u>zz maps (left a
  note pointing at neoscroll).
- `lua/plugins/editor.lua` — neoscroll switched from `opts` to `config`:
  <C-u>/<C-d> dropped from `mappings`, a `post_hook` added that runs
  `zz` only when `info == "center"`, and custom <C-d>/<C-u> maps call
  `neoscroll.ctrl_d/ctrl_u({ info = "center" })`. Result: animated half-
  page scroll that ends centered — the original intent, now actually live.
  (Verified against neoscroll source that ctrl_d/ctrl_u forward opts.info
  to post_hook and compute their own duration.)

## Audited and confirmed NOT bugs

- treesitter + textobjects + context: correct `main`-branch API throughout
  (setup()/install(PARSERS), vim.treesitter.start on FileType, main-branch
  indentexpr; context rides core vim.treesitter, branch-independent).
- nvim-dap-virtual-text on treesitter `main`: degrades cleanly — prefers
  core vim.treesitter.is_in_node_range/get_parser/language.get_lang (all in
  0.12), only falls back to old nvim-treesitter API if core lacks them.
- Two terminal plugins (toggleterm + ywbrian/nvim-term): intentional and
  documented; their <C-hjkl> is terminal-mode buffer-local, no clash.
- Other "duplicate" keys are mode/context-separated, not collisions:
  <leader>sr (n vs v), <A-h/l> (scroll n+x), <A-j/k> (move line n vs sel x),
  <C-d/u/y> (global vs telescope-prompt-local vs neoscroll config),
  <C-s> (n/i/x), <C-h/j/k/l> (global vs terminal-local).
- All repos resolve (the API 403s were rate-limiting, not 404s).

Docs: keymaps.html (signature-help row → <leader>lk; blink insert-mode note
de-staled; <C-d>/<C-u> "recentered" row now accurate), workflows.html and
vs-to-nvim.html (signature-help key → <leader>lk). All HTML balanced; all
edited Lua luajit-parsed clean.

Files touched:

- `lua/plugins/lsp.lua`, `lua/config/keymaps.lua`, `lua/plugins/editor.lua`,
  `docs/cheatsheets/keymaps.html`, `docs/cheatsheets/workflows.html`,
  `docs/cheatsheets/vs-to-nvim.html`.

---

# Feature: per-tab buffer scoping (scope.nvim) — each tab shows only its buffers

Vim buffers are global, so bufferline shows every listed buffer in every
tab. Added `tiagovla/scope.nvim`, which tracks tab→buffer membership and
toggles `buflisted` on tab switch; bufferline only renders listed buffers,
so each tab now shows just the buffers opened in it (VS-Code-style "each
tab owns its files"). No bufferline config change — they compose.

Wiring (all four pieces needed; verified against scope.nvim's README):
- `lua/plugins/ui.lua` — scope.nvim spec, `lazy = false` so its tab
  autocmds are registered before auto-session restores on startup;
  `require("scope").setup({})`.
- `lua/config/options.lua` — `sessionoptions += "globals"` (scope serializes
  its per-tab map into a global; without this, restores lose the scoping).
- `lua/plugins/session.lua` — `"ScopeSaveState"` appended to `pre_save_cmds`
  (runs LAST, after the dap-buffer wipe, so the saved map can't reference
  deleted buffers) and a new `post_restore_cmds = { "ScopeLoadState" }` to
  re-apply the map after restore.
- `lua/plugins/finder.lua` — `<leader>fb` retitled "Buffers (this tab)";
  new `<leader>fB` = "Buffers (all tabs)" (loads scope's telescope
  extension on first use so telescope stays lazy). `<leader>fB` was free.

Mental-model note (documented in-file): tabs become file-set containers;
buffers in other tabs are hidden from `<leader>fb` — reach them with
`<leader>fB` or move one with `:ScopeMoveBuf <tab_nr>`. The `<leader>1`–`9`
bufferline ordinals now index within the current tab.

Docs: README (plugins table + ui.lua layout line), plugins.html (per-tab
note in the Bufferline card), keymaps.html (`<leader>fb` this-tab +
`<leader>fB` all-tabs). All edited Lua luajit-parsed clean; HTML balanced.

Files touched:

- `lua/plugins/ui.lua`, `lua/config/options.lua`, `lua/plugins/session.lua`,
  `lua/plugins/finder.lua`, `README.md`, `docs/cheatsheets/plugins.html`,
  `docs/cheatsheets/keymaps.html`.

---

# Perf: defer LLDB symbol loading in the codelldb fallback (slow first launch)

A dap TRACE log of a ~3-minute codelldb start on a large ACIS/OpenGL Windows
app showed the entire span was symbol/debug-info loading: 104s on a single
`setBreakpoints` (loading the debug info for the breakpoint's module) plus
79s during the startup `module`-event flood (preloading symbols for many big
DLLs). The adapter connected in ~2s, and the lone `runInTerminal` token in the
log was just the `supportsRunInTerminalRequest` capability flag — no terminal
handshake. (The external console window is the OS conhost for a
console-subsystem exe; cosmetic.)

Fix: the codelldb fallback in dap.lua now passes
`initCommands = { "settings set target.preload-symbols false" }`, so LLDB
loads each module's symbols lazily instead of preloading everything at launch.
This is the long-standing, always-safe LLDB setting; the more aggressive
`symbols.load-on-demand true` (per-compile-unit, helps breakpoint resolution
too) is documented as an optional add since it errors on older LLDB. The other
half of the win is OS-side — excluding the build output and the Mason codelldb
dir from Windows Defender real-time scanning — and is documented, not codeable.

Docs: launch.json.example's codelldb example now sets `initCommands` actively
(replacing the commented formatter-import example) with a "slow first launch"
explanation; debugging.html's launch.json card gained a perf row (lazy symbols
+ Defender exclusions). dap.lua luajit-parsed clean; HTML tags balance.

Files touched:

- `lua/plugins/dap.lua` — `initCommands` on the codelldb launch fallback.
- `docs/templates/dap/launch.json.example` — active `initCommands` + rationale.
- `docs/cheatsheets/debugging.html` — perf row in the launch.json card.

---

# Docs fix: console expressions need `?` (debugging cheatsheet)

The new debugging.html showed `/py …` and the file-dump one-liner without the
leading `?`. codelldb's DEBUG CONSOLE defaults to `commands` mode, where bare
input is an LLDB command — so `/py …` is read as a non-existent command and
rejected. Per the manual, expressions are prefixed with `?` and evaluator
prefixes STACK on it: `?/py …`, `?/nat a.size()`. Watch-panel input is already
an expression, so bare `/py …` works there.

Fixed in docs/cheatsheets/debugging.html: added a note in the Python-evaluator
card distinguishing console (`?/py …`) from the Watch panel; the dump anatomy
now shows `?/py open(...)` and explains the `?`; the large-container example is
`?/py len($vec)`. (The REPL card already documented "the console (after ?)".)

Files touched:

- `docs/cheatsheets/debugging.html`

---

# Docs: new debugging cheatsheet (docs/cheatsheets/debugging.html)

Added a dedicated debugging reference, consolidating the nvim-dap / codelldb
knowledge that was scattered (or only in launch.json.example). Matches the
existing cheatsheet styling (Catppuccin Mocha, same CSS, 3-col card grid).

Cards: Session & flow (the full <leader>d* set incl. the new dp/dT/dg/dR/dE);
Breakpoints (types, condition + hit-count syntax, signs); Data breakpoints
(watchpoint set variable …, the 4× HW limit); dap-ui panels & inline values
(expand/o/t/w/e and the breakpoints-panel keys); REPL & the three evaluators
(simple /se, python /py, native /nat; ? to evaluate in commands mode); Watch
expressions & format specifiers (indexing, ,x/,d/…, the ,[N] array window,
pointer-math ranges); the Python evaluator as the centerpiece — $var
substitution, the Value proxy, the codelldb/debugger module, and a line-by-line
anatomy of the file-dump one-liner; Large variables (the max-children cap, the
,[N] window, full dump into the REPL buffer or via /py); an LLDB command
quick-ref; and launch.json codelldb essentials (terminal/stopOnEntry/env/
initCommands and the cppdbg-field-name traps).

All facts verified against codelldb's MANUAL.md (evaluators, Value API, format
specifiers, watchpoint HW limits, hit-condition grammar). HTML tags balanced.
README cheatsheets tree updated.

Files touched:

- `docs/cheatsheets/debugging.html` — new.
- `README.md` — cheatsheets listing.

---

# Feature: debugger QOL pass (pause-without-picker + toggle, inline values, exception/goto/restart keys)

A batch of Visual-Studio-flavored debugging conveniences, all in dap.lua
plus docs.

**1. Pause without the "which thread?" picker — with an escape hatch.**
DAP's `pause` targets a single threadId, so nvim-dap (and the dap-ui ⏸
button, which calls it) prompts when a session has multiple threads —
unbearable with the ~30 a GUI/ACIS app spawns. codelldb is ALL-STOP, so
pausing any one thread halts the whole program; the choice is meaningless.
The config now overrides `dap.pause`: an explicit threadId still wins (e.g.
the dap-ui Threads panel's own pause), otherwise it grabs the first thread
and pauses that — no prompt, and the button benefits too. Because some
adapters DO support non-stop per-thread pausing, `<leader>dT` toggles
`vim.g.dap_pause_pick_thread` to restore nvim-dap's built-in picker on
demand. `<leader>dp` is a dedicated pause key using the same path.

**2. Inline variable values (nvim-dap-virtual-text).** Added
`theHamsta/nvim-dap-virtual-text`, which paints each variable's value as
faded end-of-line text while stopped — the closest analogue to Visual
Studio's inline values. `virt_text_pos = "eol"` so code columns don't
shift; `all_frames = false` to only annotate the current frame. Loads on
VeryLazy (same listener-timing reason as dap-ui). NOTE: it can use
nvim-treesitter to locate variables; with treesitter pinned to `main` that
path may degrade to a simpler scan, but values still render — set
`enabled = false` if it ever errors against the main-branch API.

**3. More VS-equivalent keymaps.**
  - `<leader>dE` — exception breakpoints: prompts to toggle the adapter's
    filters (codelldb: C++ on-throw / on-catch). VS's Exception Settings.
    Run during a session (filters come from the adapter's capabilities).
  - `<leader>dg` — set next statement: `dap.goto_()` jumps execution to the
    cursor line without running what's between. VS's drag-the-yellow-arrow.
  - `<leader>dR` — restart session (`dap.restart()`). VS Ctrl+Shift+F5.

**Breakpoints panel — documented, not extended.** The dap-ui Breakpoints
element natively supports only `o` (jump to it) and `t` (enable/disable);
it has no delete or multi-select. A single-key panel delete was
DELIBERATELY NOT added: doing it means parsing dap-ui's rendered text to
map cursor→breakpoint and then reconciling with persistent-breakpoints'
on-disk store — brittle and version-dependent. Documented the native keys
and the delete workflow (`o` then `<leader>db`) instead. Can be added as an
explicit opt-in if wanted, with the fragility understood.

Docs updated: keymaps.html (dp/dT/dR in Session control, dg in Step, dE in
Breakpoints, plus Inspect notes on inline values and the Breakpoints-panel
keys), plugins.html (new "QOL (Visual-Studio-like)" rows in the DAP card),
README (dap.lua layout line + nvim-dap-virtual-text in the plugins table).
dap.lua luajit-parsed clean.

New keymaps don't collide: existing `<leader>d*` set was
b/B/P/x/X/c/C/i/o/O/r/l/t/k/j/L/u/e; added p/T/g/R/E (all previously free).

Files touched:

- `lua/plugins/dap.lua` — pause override + `dap_pause_pick_thread` toggle;
  `<leader>dp`/`dT`/`dg`/`dR`/`dE` keymaps; nvim-dap-virtual-text spec.
- `docs/cheatsheets/keymaps.html`, `docs/cheatsheets/plugins.html`,
  `README.md` — documentation for all of the above.

---

# Fix: codelldb terminal handling — `terminal:"console"` fallback + template correction

Root cause of a stray blank `[dap-terminal]` window on launch: codelldb's
stdio destination is the `terminal` field, which DEFAULTS to `integrated`
(an integrated terminal opened via a runInTerminal handshake). With no
`terminal` set, every codelldb launch opened that window — and on Windows
the runInTerminal handshake is the same one that can hang. The cure is
`terminal = "console"`, which sends the debuggee's stdio to the dap REPL
and opens no extra window. Verified against codelldb's MANUAL.md: the
field is `terminal` with values `console` / `integrated` (default) /
`external`; codelldb has NO `console` field at all.

Cross-platform: `terminal` and all three values behave identically on
Linux, macOS, and Windows, so `"console"` is a safe default everywhere —
it merely sends stdin through the dap-repl instead of a TTY on every OS.

**1. dap.lua — added codelldb fallback configs.** The `<leader>dc` picker
previously offered only cppdbg fallbacks, forcing codelldb users onto a
project launch.json. Added `‹fallback› Pick executable (codelldb)` (launch)
and `‹fallback› Attach to process (codelldb)` to `dap.configurations.cpp`
BEFORE the deepcopy, so they propagate to c and rust too. These use
codelldb's own field names — `stopOnEntry` (not stopAtEntry),
`terminal = "console"`, and `pid` for attach (not processId) — and
deliberately omit `MIMode` / `setupCommands`, which codelldb ignores.

**2. launch.json.example — corrected the codelldb console guidance.** The
template taught codelldb users to set `"console": "internalConsole"` with
values `internalConsole` / `integratedTerminal` / `externalTerminal` —
that's cppdbg/cpptools vocabulary. codelldb has no `console` field, so
following the template left users on the `integrated` default (still got
the terminal window, and still exposed to the Windows hang). Fixes:
  - the cppdbg→codelldb field-map row now maps `console:<mode>` to
    `terminal:<mode>` (different name AND values);
  - the "THE `console` FIELD" section rewritten as "THE `terminal` FIELD"
    with codelldb's real values (console/integrated/external), a note that
    `console:` is silently ignored on codelldb, an explicit cross-platform
    statement, and the Windows-prefer-`console` guidance retargeted;
  - the launch example now sets `"terminal": "console"`;
  - the commented codelldb core-dump example and the MSVC/cppvsdbg note
    both switched from `console:internalConsole` to `terminal:console`.
  The genuine cppdbg `console`/`externalConsole`-free configs and the
  `cppvsdbg` example (which DOES use `console`) were left intact.

This also corrects the user-facing launch.json a reader would copy: a
codelldb launch needs `stopOnEntry` (not stopAtEntry), `terminal:"console"`
(not console/MIMode/setupCommands), and `env` as an object (not the cppdbg
`environment` array).

dap.lua luajit-parsed clean. Template console/terminal references audited:
only cppdbg/cppvsdbg retain `console`; all codelldb paths use `terminal`.

Files touched:

- `lua/plugins/dap.lua` — codelldb launch + attach fallback configs.
- `docs/templates/dap/launch.json.example` — codelldb console→terminal
  correction (field map, prose section, launch example, core-dump example,
  MSVC note); cross-platform note added.

---

# Fix: dap-ui now auto-opens on the FIRST debug session (load on VeryLazy)

Symptom: stop at a breakpoint and the debugger panels (scopes, stack,
watches, REPL) never appear — you just get the source window plus a blank
[dap-terminal] / console split.

Cause: the nvim-dap-ui spec was lazy-loaded ONLY on its own
`<leader>du` / `<leader>de` keys, but the auto-open/close listeners
(`dap.listeners.before.launch.dapui_config = dapui.open()`, etc.) are
registered inside that spec's `config`. `dap.listeners` only invoke
listeners that already exist when a session starts, so on the first
session of an nvim instance — before any `<leader>du`/`<leader>de` press —
no listener existed and the UI never opened. (Pressing `<leader>du` once
loaded the plugin and fixed it for the rest of that nvim session, which is
why it seemed intermittent.) The docs already assumed auto-open
(launch.json.example's Windows note says "the dap-ui opens"), so this was
a genuine behavior gap, not a doc mismatch.

Fix: added `event = "VeryLazy"` to the nvim-dap-ui spec so its `config`
runs at startup and registers the listeners before any session begins.
`dapui.setup()` opens no windows by itself, so the early load is cheap;
the `<leader>du` / `<leader>de` keymaps still work unchanged. nvim-dap is
a declared dependency, so it loads first and the listener registration is
valid.

dap.lua luajit-parsed clean. No doc changes: keymaps.html already lists
`<leader>du`/`<leader>de`, and the launch.json auto-open assumption is now
actually true.

Files touched:

- `lua/plugins/dap.lua` — `event = "VeryLazy"` on the nvim-dap-ui spec;
  header comment rewritten to explain the listener-timing requirement.

---

# Fix: drop "jsonc" from treesitter PARSERS (unsupported on main)

`:TSUpdate` / install was emitting "skipping unsupported language: jsonc".
Cause: `jsonc` was a parser on nvim-treesitter's old `master` branch but
does not exist on `main` (which this config pins) — `main`'s registry has
`json`, `json5`, and `jsonnet`, no `jsonc`. Passing it to install() is an
unknown language, hence the skip warning. Cosmetic only; nothing was
broken, and the entry predated the recent scheme/neo-tree work.

Removed `"jsonc"` from the PARSERS list. No behavior change: it was being
skipped anyway, so jsonc-filetype files (.jsonc, tsconfig.json, VS Code
settings.json, .eslintrc, .babelrc, …) keep the exact highlighting they
had — Vim's built-in syntax, which is comment-aware. Nothing maps
jsonc -> json automatically (Neovim core's ft_to_lang only registers
help/checkhealth -> vimdoc), so no treesitter parser was ever resolving
for those buffers.

A NOTE in treesitter.lua records why jsonc is absent and how to opt into
treesitter highlighting for it if ever wanted: add `"json5"` and
`vim.treesitter.language.register("json5", "jsonc")`. json5 (not plain
json) because it tolerates comments + trailing commas, whereas the json
grammar would render them as ERROR nodes. Left off by default — json5 is
a looser superset and, on `main`, ships only highlights/injections
queries (no folds or indents), so it's close to a lateral move versus the
Vim syntax already in place plus the jsonls LSP.

Verified against source: `jsonc` absent from `main`'s parsers.lua (present
on `master`); core ft_to_lang = { help, checkhealth }; json5 query
coverage on main = highlights + injections only. treesitter.lua
luajit-parsed clean.

Files touched:

- `lua/plugins/treesitter.lua` — `"jsonc"` removed from PARSERS; NOTE added.

---

# Neo-tree: save guard + main-branch mappings (quick_jump / multi-select) + copy-path

Four related explorer/keymap changes.

**1. `<C-s>` no longer errors in non-file buffers.** The global `<C-s>` →
`:write` (lua/config/keymaps.lua) fired in any normal-mode buffer,
including UI buffers with `buftype` set (neo-tree, Trouble, help, dap-ui,
terminals), where `:write` raises "E382: Cannot write, 'buftype' option
is set". The three `<C-s>` maps now route through a `guarded_write()`
helper that returns early unless `vim.bo.buftype == ""`, so saving still
works in real files and is a silent no-op everywhere else.

**2. neo-tree moved from `v3.x` to `main`.** The requested `quick_jump`,
`select`, and `clear_selection` commands exist ONLY on neo-tree's `main`
branch — `v3.x` predates them, so mapping to them there silently does
nothing. `lua/plugins/explorer.lua` now pins `branch = "main"`. Caveat in
the file: main is the active dev branch (less frozen than v3.x); pin back
and drop the three mappings if a regression appears, and run `:Lazy sync`
after a branch change so lazy re-checks-out. `close_if_last_window` still
exists on main, so the documented last-window race workaround is intact.

**3. Added the main-branch mappings.** In window.mappings:
`<C-s>` → `quick_jump` (labelled jump, `on_jump = open_or_toggle`),
`<Tab>` → `select` (multi-select toggle), `<C-;>` → `clear_selection`.
The neo-tree-local `<C-s>` shadows the global save inside the tree, so
quick_jump wins there while the guard from change 1 covers other special
buffers. Flagged the `<C-;>` terminal caveat (Ctrl+punctuation often
isn't transmitted).

**4. Copy node path as text (`<C-S-c>` / `Y`).** A `copy_node_path(state)`
helper writes the node's absolute path (`node:get_id()`) to the `"+"`
register and notifies — distinct from neo-tree's `y`, which only stages a
FILE-copy in neo-tree's internal clipboard for a later `p` and never
touches the OS clipboard. Bound to `<C-S-c>` (Windows "copy path"
convention) and `Y` (reliable fallback): most terminals, Windows Terminal
included, intercept Ctrl+Shift+C as their own copy shortcut and never
pass it to Neovim, so `<C-S-c>` typically only fires in GUI builds while
`Y` always works.

All edited Lua luajit-parsed clean. Mapping/command names verified against
neo-tree `main` source (quick_jump/select/clear_selection are absent from
`v3.x`, present in `main`).

Files touched:

- `lua/config/keymaps.lua` — `guarded_write()`; the three `<C-s>` maps.
- `lua/plugins/explorer.lua` — `branch = "main"`; `copy_node_path` helper;
  quick_jump / select / clear_selection / `<C-S-c>` / `Y` mappings; in-file
  key-list header corrected (the `y/x/p` "yank" framing was wrong — it's a
  file-clipboard op) and expanded with the new keys.
- Docs synced: `docs/cheatsheets/keymaps.html` (Inside-the-tree rows —
  corrected `y/x/p`, added `Y`/`<C-S-c>`, `/`+`D`, `<C-s>` quick-jump,
  `<Tab>`/`<C-;>`, plus the main-branch + terminal caveats),
  `docs/cheatsheets/plugins.html` (neo-tree card: in-tree key additions +
  branch note), `docs/cheatsheets/workflows.html` (corrected the `y/x/p`
  note, added `Y`), `README.md` (the `<C-s>` save note now mentions the
  buftype guard).

---

# Feature: auto-install formatters (mason-tool-installer) + C/C++ conform entry + scheme parser

Three related gaps closed in one pass, all surfaced while auditing what
Mason actually installs for a given language.

**1. Formatters now auto-install.** mason-lspconfig installed LSP servers
and mason-nvim-dap installed DAP adapters, but NOTHING installed the
formatters conform references — `:Mason`'s Formatter tab stayed empty on
a fresh setup, and `<leader>cf` silently fell back to LSP formatting (or
did nothing where the server can't format, e.g. Python under pyright).
Added a `WhoIsSethDaniel/mason-tool-installer.nvim` spec to
`lua/plugins/formatting.lua` with
`ensure_installed = { stylua, clang-format, ruff, shfmt }` — the
formatters for the languages actually in use — running once on startup
on the same ensure_installed pattern as the LSP/DAP installers. The spec
loads EAGERLY (no lazy event): mason-tool-installer triggers its install
from a `VimEnter` autocmd in its own `plugin/` file, so loading it on a
later event (e.g. `VeryLazy`) would register that hook after `VimEnter`
has already fired and the install would silently never run. `:MasonToolsInstall`
triggers it by hand regardless.
Deliberately excludes `rustfmt` (ships with the rustup toolchain and is
found on PATH; a Mason copy would shadow it) and anything for
scheme/batch (no formatter exists). No fresh-install collision with the
LSP/DAP lists: every package is distinct (clang-format ≠ clangd,
ruff ≠ pyright, …), so the "Package is already installing" race the
dap.lua comment warns about can't occur here.

**2. C/C++ were missing from conform.** `formatters_by_ft` had no `c` or
`cpp` key, so `<leader>cf` on a C/C++ buffer hit the `["_"]` catch-all
and only trimmed whitespace — the actual clang-format run happened solely
via the separate LSP path (`<leader>lf`, clangd driving clang-format).
Added `c = { "clang_format" }` and `cpp = { "clang_format" }` (conform's
underscore name; the Mason package is the dashed `clang-format`).
clang-format auto-discovers the project-root `.clang-format`, so the two
format paths now produce identical output.

**3. Scheme treesitter parser.** `scheme` was absent from the PARSERS
list in `lua/plugins/treesitter.lua`, so Scheme files got no treesitter
highlighting — and since Scheme has no LSP and no formatter in the
Mason/conform ecosystem, it had no automatic tooling at all. Added
`"scheme"` to PARSERS; the existing FileType autocmd starts highlighting
once `:TSUpdate` compiles the parser. A NOTE in the file records that
highlighting is the only automatic support Scheme gets and that
structural editing still wants a parinfer/paredit plugin (not bundled).

Docs: README per-language quick-guide table corrected (the
"Auto-installed via Mason" column now distinguishes LSP vs formatter and
is accurate post-installer; `rustfmt`-from-rustup and the "install on
demand" formatters called out; Scheme and Batch rows added with their
"no tooling" caveat), README layout tree updated to show
mason-tool-installer alongside conform, and this CHANGES entry. The
edited Lua was luajit-parsed clean.

Files touched:

- `lua/plugins/formatting.lua` — mason-tool-installer spec; `c`/`cpp`
  added to `formatters_by_ft`.
- `lua/plugins/treesitter.lua` — `"scheme"` added to PARSERS + caveat note.
- `README.md` — per-language guide accuracy, Scheme/Batch rows, layout tree.

---

# Feature: normal-mode line move (<A-j>/<A-k> for the current line)

The Alt-j/k line move was visual-mode only (move the selected block).
Added the normal-mode counterpart: <A-j>/<A-k> now move the CURRENT line
down/up with no selection needed, mirroring the visual gesture.

Implemented as guarded functions rather than a raw `:m .+1<CR>==`
mapping, because a bare :m at the file edge throws "E16: Invalid range"
(<A-k> on line 1, <A-j> on the last line) — that error would flash in the
command line every time you bump the top/bottom. The guards make the
boundary a silent no-op. `==` re-indents the moved line; normal J (join)
and K (keywordprg/hover) are untouched.

Verified on nvim 0.12.2: moves reorder lines correctly and both edges
no-op with no E16. Cheatsheet row updated to note normal + visual; which-
key shows the desc.

---

# Feature: <A-h>/<A-l> horizontal scroll (single chord, repeatable)

Built-in zl/zh need the z prefix (two keys) and move one column, so
scrolling a long line means mashing. Added <A-l>/<A-h> (keymaps.lua,
normal + visual) -> 16zl / 16zh: one chord, scrolls a chunk, and holds-
to-repeat via OS key-repeat. Mirrors the <A-j>/<A-k> line-move
convention; <A-h>/<A-l> were free (only <A-j>/<A-k> were bound). Step is
a HSCROLL_STEP local (16) — bump for bigger jumps, or use zL/zH for a
half-screen leap. Only meaningful with nowrap (the config default).

Verified on nvim 0.12.2: maparg resolves to 16zl/16zh and the rhs moves
winsaveview().leftcol 0 -> 16. Cheatsheet row added under the movement
card.

Terminal caveat: Alt-chords depend on the terminal/multiplexer passing
Alt through (some send ESC-prefixed sequences). If <A-h>/<A-l> don't
register, it's the terminal eating Alt, not the mapping — remap to
another free chord in that case.

---

# Feature: <leader>lv toggles diagnostic virtual-text vs virtual-lines

When a diagnostic is long, inline virtual_text trails off the right edge
and can't be read — it never wraps, and neither :set wrap nor horizontal
scroll reveals it (it's painted-on, not buffer text). <leader>lv
(keymaps.lua) flips the display to virtual_lines (full message on its own
wrapped line(s) below the code, current line only) and back.

Snapshots the live virtual_text config via vim.diagnostic.config() so
toggling back restores exactly what lua/plugins/lsp.lua set (no hardcoded
copy to drift). Verified on nvim 0.12.2: text→lines→text round-trips with
prefix/spacing/source intact. <leader>ld (float) remains the one-shot
alternative. Cheatsheet rows + which-key "lsp" group desc added.

---

# Restructure: docs/ (cheatsheets + templates), flesh out launch.json.example

The cheatsheets/ folder had three different kinds of thing dumped
together — browser cheatsheets, clang project templates, and a DAP
template. Reorganized into a clear tree and folded in last turn's
cpp-config/:

  docs/
    cheatsheets/    keymaps, plugins, workflows, vs-to-nvim,
                    cpp-diagnostics, clang-tools, clang-settings-reference  (HTML)
    templates/
      cpp/          .clang-format .clang-tidy .clangd  (ready-to-copy)
                    clang-format.example clangd.example (annotated reference)
                    README.md
      dap/          launch.json.example

The templates/ files are things you copy into a PROJECT, never loaded by
nvim; the cpp/README explains the dotfile-vs-.example split (concise
ready-to-copy vs heavily-annotated reference) and that clangd.example's
inline Diagnostics.ClangTidy block is an alternative to a standalone
.clang-tidy. Aligned the example files' tidy naming to the lower_case
override.

launch.json.example fleshed out (6 -> 9 active configs + commented
variants), all JSONC-validated:
  + CMake preset / multi-config output path
  + post-mortem core-dump debugging (cppdbg + codelldb variant)
  + remote debugging over gdbserver (miDebuggerServerAddress, sourceFileMap)
  + system-specific linux:/osx:/windows: property blocks (nvim-dap feature)
  + an `inputs` block with a pickString example for ${input:...}
  + preLaunchTask caveat: nvim-dap core IGNORES it (build yourself or use
    overseer.nvim) — a real footgun the old file didn't mention
  + cppvsdbg note: that adapter isn't among the Mason installs, so a
    copied VS Code MSVC config silently does nothing

Updated all live cross-references (plugins/workflows/cpp-diagnostics
HTML) and the README tree to the new paths. CHANGES.md history left as-is
(it records where files were at the time). Re-verified: Lua syntax,
clang-format/.clang-tidy/.clangd validity, JSONC parse.

---

# Bundle the C/C++ config files + cheatsheets into the nvim zip

Added a top-level `cpp-config/` folder to the config so the clang files
travel with everything else (previously they shipped only as a separate
zip). Structure:

  cpp-config/
    project-root-files/    .clang-format .clang-tidy .clangd + README.md
    cheatsheets/           clang-tools.html  clang-settings-reference.html

The files under project-root-files/ are NOT loaded by Neovim — they're
meant to be copied to the C++ project root (the README in that folder
says so, and notes they're dotfiles hidden by default). Two cheatsheets
in the house Catppuccin card style, both render-checked:
  * clang-tools.html — what each tool does, the three files, the
    C++98/header fix, key clang-format knobs, tidy families + gotchas,
    and how the standard/naming/formatting interact.
  * clang-settings-reference.html — the exact values in THIS project's
    shipped files, with the lower_case Function/Member naming overrides
    flagged.

Verified the leading-dot files survive zipping (zip -r includes
dotfiles). The standalone cpp-project-config.zip is still produced too
for direct extraction at the project root.

---

# Example: full modern-C++ project config set (.clang-format/.clang-tidy/.clangd)

Delivered all three clang project-root files as a bundle (cpp-project-config.zip),
separate from the nvim config since they live in the project tree, not the
editor config.

* .clang-format — based on LLVM with documented modern overrides: 4-space
  indent, 100 col, left-attached pointers (`int* p`), InsertBraces (braces
  on single-statement if/for/while), include regrouping (project "" first,
  then library <...>, stdlib last), FixNamespaceComments, one-arg-per-line
  bin-packing off, QualifierAlignment left at Leave (auto-moving const is
  unsafe). VALIDATED with a real clang-format: caught and fixed a wrong
  enum (`BreakBeforeBraces: Attached` -> `Attach`); formats sample code
  cleanly demonstrating every choice.
* .clang-tidy — modern check families with the noisy members subtracted,
  naming convention, and brace-init nudge via
  modernize-use-default-member-init.UseAssignment=false. Per request,
  FunctionCase and MemberCase are now `lower_case` (private members are
  lower_case + trailing `_`, e.g. `frame_count_`), consistent with the
  formatter output.
* .clangd — fallback `-std=c++20` so headers / orphan TUs don't fall back
  to an ancient standard under scoper filtering (from the earlier session).

README LSP section already documents the clang-tidy and header-standard
interactions; no nvim code changed in this step.

---

# Docs + example: project .clang-tidy for modern C++

Added an example `.clang-tidy` (delivered as a project-root file, not in
the nvim config) and a short "clang-tidy checks" note in the scoper
README's LSP section.

The example enables the high-signal families (bugprone, cppcoreguidelines,
modernize, performance, readability, misc) and subtracts the noisy/
stylistic members, with a modern naming convention block and member-init
style pinned to brace form via
`modernize-use-default-member-init.UseAssignment: false` (the closest
clang-tidy gets to "universal initialization" — it nudges toward `int
i{5};`, it does not blanket-rewrite every =/() init). Verified against
LLVM 21/23 docs for clangd 22: the deprecated
`cppcoreguidelines-prefer-member-initializer.UseAssignment` option
(removed in clang-tidy 19) was caught and replaced with the surviving
`modernize-use-default-member-init` options. YAML validated.

README note explains that the existing `--clang-tidy` flag makes clangd
read a project `.clang-tidy` live, that `WarningsAsErrors` is ignored for
editor diagnostics (CLI/CI only), and that removed option keys are
silently dropped so they should track the clangd version.

---

# Docs: header files and the C++ standard under scoper LSP filtering

Added a "Header files and the C++ standard" subsection to the scoper
README's LSP section. No code change — documents an inherent consequence
of compile_commands filtering that users hit as spurious "C++98 / C++NN
extension" errors when editing headers.

compile_commands.json never lists headers, only .cpp TUs. clangd parses
a header by borrowing flags from a source file that includes it; with
filtering on, that sibling .cpp may be absent from the scoped database,
so clangd falls back to a default (old) standard. The note explains the
cause (and that an include/ vs src/ split is irrelevant — clangd matches
by which TU includes the header, not directory adjacency) and the fix: a
project-root .clangd with `CompileFlags.Add: [-std=c++NN]`, with a
reminder to re-index afterwards. A ready-to-edit .clangd template is
provided alongside this build for dropping into the project root.

---

# Bugfix: telescope buffers picker drifted / stacked markers as you moved

`<leader>fb` (Telescope buffers) progressively mis-indented rows as you
navigated, and `<Tab>` multi-select stacked multiple `+` prefixes on a
row instead of one. All rows started aligned; moving the cursor smeared
them rightward.

Root cause: `selection_caret` was set to a multibyte Nerd-Font glyph
(arrow + space) in lua/plugins/finder.lua. Telescope lays out each row
assuming the caret occupies the same number of display CELLS as
entry_prefix, and rewrites that leading column on every cursor move
(Picker:update_prefix). When a glyph's computed width
(strdisplaywidth) disagrees with how the terminal+font actually render
it, the selected row shifts by a cell; because the column is rewritten
on each move, the misalignment accumulates, and the multi-select marker
gets caught in the same mis-replacement (hence stacked `+`).

Reproduced in a real-UI nvim 0.12.2 via tmux: with the glyph caret the
selected/`renderer_gl` row rendered one column left of its neighbours
and markers smeared; with an ASCII caret every row — selected,
multi-selected, plain — stayed aligned and each selection showed a
single `+`.

Fix: use a cell-stable ASCII `selection_caret = "> "` and pin
`entry_prefix = "  "` / `multi_icon = "+"` explicitly so the
caret/prefix/icon set is width-consistent (2 / 2 / 1 cells). Comment
notes the arrow glyph can be restored if the terminal+Nerd-Font render
it as exactly one cell; the drift is the signal that it doesn't.

Note: stacked `+` markers were part of this bug, not expected behaviour
— one `+` per multi-selected row is correct.

---

# Feature: open the bufferline tab context menu from the keyboard

The tab context menu (pin / copy path / open in split / close / close
others) was right-click only. Added `<leader>bm` to open the same menu
for the CURRENT buffer without a mouse.

Implementation: `buffer_context_menu` and `show_menu` are locals inside
bufferline's opts closure in `lua/plugins/ui.lua`, so a keymap defined
in keymaps.lua can't reach them. ui.lua now exposes a thin wrapper on
`_G.__bufferline_user.context_menu()` that resolves the current buffer
and calls the existing menu builder; `<leader>bm` (keymaps.lua) invokes
it, guarded so it's a harmless warning if pressed before bufferline
loads at VeryLazy. The menu was already fully keyboard-navigable once
open (focus enters the float with cursorline; j/k + <CR>, 1-9 to pick
directly, q/<Esc> to dismiss) — no changes needed there. Skips
unlisted buffers (neo-tree, terminals, help) with a notify, since they
have no tab in the strip.

Verified end-to-end on nvim 0.12.2: the global is exposed on load,
invoking it opens the 8-item menu float with cursorline and the
expected <CR>/<Esc> mappings, and <leader>bm is registered. Cheatsheet
row added in cheatsheets/keymaps.html; which-key picks up the desc
under the existing "buffer" group automatically.

---

# Docs: "Refine a search" cheatsheet card (AND/OR/exclude + directory scoping)

Added a card to cheatsheets/workflows.html documenting search query
syntax, after repeated confusion about the difference between the file
finders and the grep tools. No code changes.

The card makes the core distinction explicit: FILE FINDERS
(<leader>ff, <leader>Ff, :ScoperFind) match paths with the fuzzy
matcher, so fzf operators go straight in the prompt; LIVE GREP
(<leader>fg, <leader>Fg, :ScoperGrep) matches line content with
ripgrep, so the prompt is a regex and the same operators apply only
after a ` -- ` separator.

Covers, all verified empirically against the installed fzf / ripgrep /
telescope on nvim 0.12.2:
* File-finder operators: space=AND, `|`=OR, `!`=exclude, `'exact`,
  `^prefix`, `suffix$`, and chaining (`hbr .cpp$ !compiled`). Identical
  on all three finders (telescope-fzf-native and fzf both implement
  fzf's extended-search syntax).
* Grep: regex semantics (literal spaces, no quotes needed), the ` -- `
  fzf secondary filter for AND/exclude, and the PCRE2 lookahead form
  for any-order word matching (`--pcre2`).
* Restricting to / excluding directories four ways: in-query path
  tokens (`hbr ^src/`, `hbr !vendor/`); telescope
  `search_dirs=src,lib` (comma-separated, confirmed by the command
  parser); fzf-lua `cwd=` and `fd_opts="--exclude build"` /
  `rg_opts="--glob=!build"`; and scope-wide via :ScoperAdd /
  :ScoperExclude.

---

# Bugfix: ScoperFind / ScoperGrep searched only the first scope dir (fzf-lua)

`:ScoperFind` and `:ScoperGrep` are supposed to search every directory
in the active scope. On the fzf-lua backend they effectively searched
only the first — or, depending on layout, errored and returned nothing.

**Root cause:** both passed `cwd = ctx.dirs[1]` AND `search_paths =
ctx.dirs` to fzf-lua. fzf-lua makes `search_paths` relative to the real
Neovim cwd, then RUNS the fd/rg command from `opts.cwd`. With cwd set
to the first scope dir, those two disagree: fd received e.g.
`fdfind ... . 'src' 'lib'` but executed inside `<root>/src`, so it
looked for `src/src` and `src/lib`, found neither, and listed nothing
(`fd error: Search path 'lib' is not a directory`). The grep path hit
the identical contradiction (`rg: lib: IO error ... No such file`).

**Fix:** drop `cwd` from both fzf-lua calls and rely on `search_paths`
alone (`lua/scoper/pickers.lua`, M.find and M.grep). `search_paths`
then resolves against the real cwd and the command runs from there —
correct for scope dirs inside the project (stored relative) and
outside it (kept absolute). Verified end-to-end on nvim 0.12.2 with a
two-dir scope (`src` + `lib`, `vendor` excluded): the composed command
is `fdfind ... . 'src' 'lib'` and returns all four in-scope files with
vendor excluded; the same shape works for an out-of-tree absolute
scope dir.

The stale comment claiming "older fzf-lua only honours cwn / searches
dirs[1]" is replaced with an accurate explanation of the cwd vs.
search_paths interaction. The telescope and grug-far backends were
already correct (`search_dirs` / `paths`, no cwd) and are unchanged.

Requirement noted in the README Limitations: the fzf-lua backend needs
a `search_paths`-capable fzf-lua (mid-2024+); the telescope backend
works regardless of version.

---

# Bufferline scrolling keymaps + multi-select buffer close

Follow-up to the truncation-marker investigation: bufferline's "N tabs
hidden" markers are plain text with no click handler (clicks near them
hit the adjacent tab's region — see the cell-map analysis from the
session), and the plugin exposes NO view-only scroll API: the strip
always tracks the current buffer.

**1. `<S-l>` / `<S-h>` now run `BufferLineCycleNext/Prev`** (was
`:bnext`/`:bprevious`) in `lua/config/keymaps.lua`. Two wins:
* Cycling follows the tabline's VISUAL order (pinned-first, custom
  sort) instead of raw buffer numbers, so the highlight moves the way
  the strip looks.
* Since bufferline keeps the current buffer in view, cycling IS the
  scroll — hidden tabs come into view as you cycle. This is the
  keyboard replacement for the (never-functional) marker "buttons".
Caveat noted in the comment: the commands exist once bufferline loads
at VeryLazy, milliseconds after startup; pressing them inside that
window errors harmlessly.

**2. Multi-select buffer close in the Telescope buffers picker**
(`lua/plugins/finder.lua`): `<Tab>`/`<S-Tab>` multi-select rows
(telescope default), `<C-d>` deletes every selected buffer — or just
the highlighted one when nothing is selected — mirroring scoper's
multi-select `:ScoperRemove` flow. Implementation details:
* Replaces stock `actions.delete_buffer` with a custom action built on
  the public `Picker:delete_selection` API. The stock action calls
  `nvim_buf_delete` directly, which closes every window still showing
  the buffer (:h :bdelete) and can wreck the split layout — the exact
  problem `<leader>bd` solves. The custom action re-points windows
  first via the shared `config.util.detach_buffer_from_windows`.
* Dirty buffers are skipped with a warning and STAY in the picker
  (`delete_selection` only removes entries whose callback returns
  true), so a bulk sweep never force-discards unsaved work. Terminal
  buffers are force-deleted (they're never "written"; same special
  case as stock).
* Verified headlessly on nvim 0.12.2 with the full config: two
  multi-selected buffers deleted in one `<C-d>`, picker stays open,
  and a split window showing one of the deleted buffers was re-pointed
  instead of closed.

Cheatsheet updates in `cheatsheets/keymaps.html`: the `<S-l>/<S-h>`
row documents visual-order cycling and the non-clickable markers; the
buffers-picker `<C-d>` row documents multi-select bulk close.

---

# Bugfix: triple-split layout when quitting with a modified buffer

**Symptom:** `:q` on the last file window, while any modified buffer
exists (classically a readonly buffer you forced edits into), sometimes
produced a broken three-pane layout — [neo-tree | file | file], the
same modified buffer shown twice — plus a doubled Neo-tree warning
("Cannot close because one of the files is modified").

**Root cause (upstream neo-tree, reproduced on nvim 0.12.2 with this
config):** `close_if_last_window` is implemented as a WinClosed autocmd
in neo-tree's `plugin/neo-tree.lua`. When the tree is the last pane and
a modified buffer exists, it SCHEDULES "warn + rightbelow vsplit + :b
<modified buffer>". Two flaws combine:

1. The autocmd fires for every WinClosed — including floating windows.
2. The scheduled callback never re-checks the layout; it splits
   whatever window is current when it eventually runs.

incline.nvim (ui.lua) tears down its floating winbar with a debounced
`nvim_win_close` shortly after the file window closes — a second
WinClosed. If that lands while the tree is still the only pane (a
timing race; more likely under load), neo-tree's handler passes all its
checks again and schedules a second pass. The first pass splits the
tree and reopens the file; the second pass then splits the *reopened
file window* and `:b`s the same buffer into it. Result: the triple
split and the doubled warning.

**Fix:** `close_if_last_window = false` in `lua/plugins/explorer.lua`
(no local monkey-patching of the upstream handler — deliberately).
Trade-off: `:q` on the last file window now leaves neo-tree open as the
sole window; quit with `:q` again or `:qa`. Nothing else changes —
`<leader>bd` never relied on this option (smart_bdelete re-points
windows before deleting).

Comments referencing the old behaviour were updated in keymaps.lua,
config/util.lua, plugins/ui.lua, and the `:bd` row in
cheatsheets/workflows.html. Worth re-enabling only if upstream adds
re-validation inside the scheduled callback.

---

# Audit pass 6: full-config audit (bugs, races, brittleness, docs)

A top-to-bottom audit of the config and scoper.nvim — coding
practices, documentation accuracy, architecture, event-loop races,
bugs, and brittleness. Twelve fixes, four hardening changes, and a
documentation sweep. Cheatsheets (keymaps / plugins / vs-to-nvim /
workflows), both READMEs, and the test suite were updated to match.

**Bug fixes:**

1. **`lua/config/keymaps.lua`: visual move-lines now on `<A-j>`/`<A-k>`.**
   The code bound plain `J`/`K` while the comment claimed Alt-j/k —
   silently shadowing visual `J` (join lines) and `K`. The comment was
   right; the code now matches it. Visual `J` joins again.

2. **`lua/config/keymaps.lua`: visual maps use mode `"x"`, not `"v"`.**
   `"v"` covers visual AND select mode; select mode is what
   LuaSnip/blink put you in on a snippet placeholder, where typing
   must REPLACE the selection. A `"v"` map of a printable key (`<`,
   `>`, `J`, `K`) hijacked typing inside placeholders. All visual maps
   in the file (indent-keep-selection, move-lines, paste, `<C-s>`)
   now use `"x"`.

3. **`lua/plugins/lsp.lua`: nvim-ufo's `K` fold-peek was unreachable.**
   The LspAttach handler bound a buffer-local `K` → hover, which wins
   over ufo's global `K` (peek fold, fall through to hover) in every
   LSP-attached buffer — i.e. exactly the buffers that have folds. The
   buffer-local map is gone; ufo's peek-or-hover owns `K` everywhere.

4. **`lua/config/keymaps.lua` + `lua/config/util.lua` (new):
   `smart_bdelete` no longer closes other splits showing the buffer.**
   `nvim_buf_delete` behaves like `:bdelete` — ALL windows showing the
   buffer are closed. The old implementation re-pointed only the
   current window, so the same buffer visible in a second split still
   lost that split (and could leave neo-tree as the last window →
   `close_if_last_window` → nvim exits: the exact scenario the code
   claimed to prevent). The window-detach logic now lives in
   `lua/config/util.lua` and is shared with the bufferline context
   menu's "Close" action, which previously had its own (correct but
   duplicated) copy. Failed deletes (unsaved changes) now notify
   instead of being silently swallowed by pcall.

5. **`lua/plugins/formatting.lua`: `:FormatToggle` removed from the
   lazy `cmd` trigger list.** The `init` block creates the real
   command at startup; listing the same name in `cmd` also made
   lazy.nvim register a loader stub, and the two clobbered each other
   — the stub path ended in "load conform, delete stub, re-run a
   command that no longer exists". The command only flips flags and
   needs no plugin load.

6. **`lua/plugins/lsp.lua`: document-highlight autocmds are torn down
   on LspDetach.** After `:LspStop`, a server crash, or scoper's
   clangd restart, the CursorHold autocmds kept calling
   `document_highlight` into a buffer with no capable client. The
   detach handler clears references and deletes the augroup — unless
   another attached client still supports the method.

7. **`lua/config/autocmds.lua`: `formatoptions` removal moved into a
   FileType autocmd.** 'formatoptions' is buffer-local and most
   ftplugins re-set it AFTER user options run, so the one-shot
   `opt.formatoptions:remove` in options.lua was silently overridden
   the moment any filetype loaded. Re-applying on every FileType is
   the only form that sticks.

8. **`scoper.nvim`: scope names are validated (and the cache path is
   sanitized).** Names become directory components in the clangd
   cache (`stdpath("cache")/scoper/<hash>/<name>/`), but
   `state.new_scope` accepted any string: `foo/bar` nested
   directories, `..` traversed, `:`/`*` failed mkdir on Windows.
   Creation now rejects anything outside `[%w_%-.]` with a clear
   error; `lsp.cache_dir` additionally sanitizes defensively for
   names that predate the check or were hand-edited into the JSON.
   New tests in `tests/state_spec.lua` cover both directions.

**Event-loop / async fixes (scoper.nvim/lua/scoper/lsp.lua):**

9. **Lost-update in the reload guard.** `reload_clangd`'s re-entrancy
   guard simply dropped calls that arrived mid-reload — losing the
   LAST scope change whenever no further event followed, leaving
   clangd configured for a stale scope. A `_pending` flag now
   remembers the request and replays exactly one more pass when the
   in-flight reload finishes.

10. **clangd restart is asynchronous.** The old `vim.wait(2000)` froze
    the UI for up to 2 s on every debounced scope change and pumped
    the event loop while blocking (the source of the re-entrancy
    window above). A 50 ms libuv polling timer replaces it; input
    stays responsive for the whole restart. If old clients are still
    draining after 2 s, the re-attach is SKIPPED (re-firing FileType
    alongside a live client meant two clangds indexing the same
    project) and a warning points at `:ScoperLspReload`.

**Brittleness / hardening:**

11. **`lua/plugins/editor.lua` + `which-key.lua`: mini.surround moved
    to the `gz` prefix** (`gza`/`gzd`/`gzr`/`gzf`/`gzF`/`gzh`/`gzn`).
    flash.nvim owns `s`; with both registered, every flash jump waited
    `timeoutlen` (400 ms) for Vim to rule out `sa`/`sd`/…, and a
    slow-typed surround chord fell into flash. Same solution LazyVim
    ships. which-key gets a `gz` = "surround" group.

12. **`lua/config/keymaps.lua`: visual `p` uses the built-in `P`.**
    Neovim ≥0.9's visual `P` is natively "paste without clobbering
    the register"; the old `"_dP` trick misplaced the paste at
    end-of-line and for linewise registers.

13. **`lua/plugins/lsp.lua`: `<C-k>` signature help is normal-mode
    only.** The insert-mode binding silently removed i_CTRL-K digraph
    entry, and blink already covers insert mode (auto-show while
    typing + its own `<C-k>` toggle, no longer shadowed).

14. **`lua/plugins/treesitter.lua`: FileType handler gates on
    `vim.b.big_file`.** Previously big-file protection depended on
    undocumented autocmd ordering (treesitter started, then
    big_file_apply happened to stop it), and the treesitter indentexpr
    was installed on huge files regardless.

15. **`lua/config/autocmds.lua`: trim-whitespace skips big_file
    buffers and markdown.** A buffer-wide `:s` on a 50 MB file was a
    save-time stall; markdown trailing double-spaces are hard line
    breaks.

16. **`lua/plugins/finder.lua`: dropped the broad
    `file_ignore_patterns`** (`dist/`, `build/`, `%.lock`). Telescope
    matches these as unanchored Lua patterns against the full path, so
    they hid legitimate sources and lockfiles from find/grep; fd/rg
    already honour .gitignore, which excludes real build output at the
    source. Only `%.git/` and `node_modules/` remain.

17. **`scoper.nvim`: clangd flags are configuration, not hardcoded
    opinion.** `setup({ lsp = { clangd_args = {...} } })` replaces the
    flag list baked into `base_clangd_cmd`; defaults unchanged.
    List-valued options (clangd_args, default_excludes) are assigned
    wholesale rather than index-merged by tbl_deep_extend.

18. **`scoper.nvim/lua/scoper/pickers.lua`: untranslatable globs warn
    instead of silently matching nothing** on the telescope backend
    (`{a,b}` alternation, `[!…]` negation — both fine on fzf-lua).

19. **`lua/plugins/ui.lua`: context-menu width measured in display
    cells** (`strdisplaywidth`), not bytes — multibyte filenames in
    the title no longer over-allocate the float.

20. **`scoper.nvim/lua/scoper/state.lua` + `init.lua`: new
    `State.scope(name)` accessor**; init.lua no longer reaches into
    `State().state.scopes` internals.

**Documentation corrections (comments that said untrue things):**

* `lua/plugins/dap.lua`: the persistent-breakpoints "no race" comment
  claimed nvim-dap loads "on the first <leader>d* keypress" — lazy
  loads dependencies WITH their dependents, so DAP is effectively
  loaded near startup (BufReadPost / VeryLazy). Conclusion unchanged,
  mechanism corrected.
* `lua/config/options.lua`: the `synmaxcol` comment argued the
  opposite of what the line does (240 is a REDUCTION from the default
  3000); rewritten. The netrw-disable comment now notes the deliberate
  overlap with lazy.lua's `disabled_plugins`.
* `lua/plugins/session.lua`: noted that `dap.terminate()` is async and
  the force-wipe loop is the actual guarantee for session saves.
* `tests/config_spec.lua`: documented the duplicate-keymap test's
  blind spots (buffer-local maps, prefix shadowing, late-registered
  plugin maps).

**Docs/cheatsheets updated to match:** `README.md` (surround verbs,
move-lines, flash note), `scoper.nvim/README.md` (clangd_args,
scope-name rule, async restart semantics), `cheatsheets/keymaps.html`
(move-lines, surround on gz, `<C-k>` normal-only + digraph note, blink
`<C-k>` no longer shadowed), `cheatsheets/plugins.html` (surround
verbs + why gz), `cheatsheets/vs-to-nvim.html` (signature help,
surround examples), `cheatsheets/workflows.html` (surround examples).

---

# Audit pass 5: focused data-race re-audit (cross-process / silent-failure)

Per the user's "check for more data races, be thorough" instruction
after pass 4 wrapped, this pass traced every async / scheduled /
cross-process pattern in the codebase one more time. Two new fixes
surfaced — both defense-in-depth against failure modes that were
present but rare enough to slip past the earlier passes. Nine
patterns re-verified clean.

**Fixes applied:**

1. **`scoper.nvim/lua/scoper/lsp.lua`: filtered cache write is now
   atomic.** The cache file at
   `stdpath("cache")/scoper/<project>/<scope>/compile_commands.json`
   was written with a direct `vim.fn.writefile(...)`. clangd reads
   this same file via a filesystem watcher (inotify on Linux,
   ReadDirectoryChangesW on Windows), so a mid-write IN_MODIFY event
   could deliver a truncated JSON to clangd, which would parse-fail
   and drop back to ad-hoc flags — exactly the failure mode this
   whole file is structured to prevent. Now writes to
   `<out_path>.tmp.<pid>` first, checks the writefile return code,
   then atomic-renames via `vim.uv.fs_rename`. clangd's watcher
   sees one IN_MOVED_TO event with the final file in place.

   The PID-suffixed tmp filename also handles two Neovim instances
   working on the same project with the same active scope: each
   has its own tmp file, last rename wins on the final path,
   neither produces a half-file.

   This matches the pattern applied to `state.save` in audit
   pass 2 — same shape, same rationale, with the additional
   cross-process angle (clangd watching) that makes it materially
   more impactful here than I gave it credit for in pass 2.

2. **`lua/config/diagnostics.lua`: writefile return code is now
   checked.** `vim.fn.writefile` returns `0` on success and `-1` on
   failure (disk full, permission denied, read-only filesystem,
   etc). The dump command silently dropped that return value and
   emitted a success notification regardless. The user typically
   runs `:DiagnosticDump` *because* something is already broken
   — having the dump silently no-op puts them in "I'm reading the
   dump but it's empty / stale" territory, debugging the wrong
   layer. Now escalates to an `ERROR` notify on failure, and the
   function returns `nil` instead of a stale path.

**Re-verified clean — patterns traced through this pass, with notes
so the next audit doesn't repeat the trace:**

- **`scoper.nvim/lua/scoper/state.lua` mutators** (`add_paths`,
  `remove_paths`, `add_excludes`, `clear_active`, `new_scope`,
  `delete_scope`, `set_active`, `set_enabled`, `toggle`). Each
  follows the same shape: read `M.state`, mutate, call `M.save()`
  (atomic), call `fire_change()` (which is synchronous —
  `nvim_exec_autocmds`, not a deferred dispatch). No inter-call
  interleaving possible under Neovim's single-threaded execution.
  Cross-instance: atomic save means each instance produces a
  coherent snapshot; last writer wins on disk; no partial state.

- **`reload_clangd` window between steps.** Sequence:
  `vim.lsp.config(cmd)` → `vim.lsp.stop_client(...)` →
  `vim.wait(...)` → re-attach via `doautocmd FileType` per buffer.
  A new buffer attaching during the vim.wait would use the new cmd
  (good); the deduplication-by-root_dir in Neovim's LSP module
  prevents a duplicate client. The `_reloading` guard (pass 2)
  prevents overlapping invocations. Eventually-consistent; bumpy
  but correct.

- **`vim.lsp.config` write ordering between `lua/plugins/lsp.lua`
  (startup) and `scoper.nvim`'s `reload_clangd` (ScoperChanged).**
  lsp.lua's config write happens in lazy.nvim's sync `config =
  function()`. scoper's writes only happen after user actions
  (ScoperChanged fires from mutators). So lsp.lua always runs
  first; scoper overrides. Last-write-wins is the intended
  semantic — scoper's whole purpose is to override the default
  clangd cmd.

- **`bufferline` context menu `current_menu_win` closure variable.**
  Mutated on open/close. Single-threaded. `vim.schedule(action)`
  defers one tick, during which another right-click could open a
  new menu. The `nvim_win_is_valid` + `pcall` cleanup is defensive
  against the prior window already being closed. Worst case is
  surprising action ordering, never data corruption.

- **`BufWritePre auto_mkdir`** with `vim.uv.fs_realpath(event.match)
  or event.match`. `fs_realpath` returns nil for not-yet-existing
  files; the fallback handles it. `mkdir(..., "p")` is idempotent;
  concurrent `mkdir -p` from two processes on the same tree is
  POSIX-atomic per-component.

- **`SessionLoadPost` handler.** Sequential loop, `filetype detect`
  per buffer in `nvim_buf_call` context, then `pcall(treesitter.
  start, buf)`. `treesitter.start` is idempotent. The
  `filetype detect` may re-fire FileType autocmds which themselves
  may call `treesitter.start`; still idempotent.

- **`big_file` BufReadPre → BufReadPost handoff via
  `vim.b[buf].big_file`.** Neovim dispatches these in order for the
  same buffer; no other handler in this config writes the marker
  between them.

- **`fire_change()` (`nvim_exec_autocmds("User", { pattern =
  "ScoperChanged" })`).** Synchronous — all listeners run and
  return before the call site continues. The 500 ms debounced
  timer in `attach_auto` is reset on each fire, so rapid mutations
  coalesce into one `reload_clangd` invocation.

- **Treesitter `vim.defer_fn(...)` install kickoff.** Returns a
  `uv_timer` that auto-closes on fire; no leaked handle.
  `ensure_installed` is idempotent on already-installed parsers.

**Findings explicitly NOT changed — and why:**

- **`vim.lsp.buf.format({ async = true })`** at `<leader>lf`. The
  async-format callback fires after the LSP responds; if the buffer
  was modified or closed in between, Neovim's LSP module handles
  the response correctly (it edits only when safe). Not our race
  surface.

- **`gitsigns.on_attach`** re-runs on `:Lazy reload`. The
  `vim.keymap.set(...)` calls are idempotent with the same
  buffer/lhs/rhs; no race, no leak.

- **Two-process / two-instance cache races for non-scope files** —
  the only multi-instance shared file is the scoper state JSON
  (handled by pass 2's atomic save) and the scoper filtered cache
  (handled by this pass). Diagnostic dumps now have PID-suffixed
  filenames (pass 3); no shared mutable path.

Files touched:

- `scoper.nvim/lua/scoper/lsp.lua` — atomic write for the filtered
  `compile_commands.json` cache.
- `lua/config/diagnostics.lua` — writefile return-code check on
  the diagnostic dump.

---

# Audit pass 4: consistency, comments, documentation extended to the rest of the config

Last sweep — consistency / good-practice / comment-accuracy check
extended across the remaining files: every `lua/plugins/*.lua` spec
not previously touched, the build/lint/format infrastructure
(`.luacheckrc`, `Makefile`, `stylua.toml`), the `lua/config/lazy.lua`
bootstrap, the `tests/minimal_init.lua` runner, and all six
cheatsheets in `cheatsheets/`. Four real fixes, the rest verified
clean.

**Fixes applied:**

1. **`lua/plugins/ui.lua`: stale `fugitive` in lualine extensions.**
   The lualine `extensions` list still included `"fugitive"`, but
   fugitive isn't installed in this config — the original
   cleanup-pass entry removed it from `autocmds.lua`'s
   `close_with_q` filetype list when nothing else referenced it,
   but missed this one. Removing the extension is a no-op runtime-
   wise (lualine silently skips unknown extensions), but it's
   technically incorrect documentation of what this config uses.

2. **`README.md` troubleshooting row: stale `fugitive` reference.**
   The "Common surprises" table at the bottom of the README had
   "gitsigns / fugitive blocking" as the explanation for a git-
   operation hang. Fugitive isn't installed; the actual git
   plugins are gitsigns and diffview. Row updated to match.

3. **`cheatsheets/plugins.html`: Scoper Add/Remove description
   doesn't reflect multi-arg.** The row was "Add/remove the current
   path" — accurate before audit pass 1 when both commands
   operated on one path at a time, stale after that pass extended
   them to accept whitespace-separated lists and multi-select
   pickers. Now reads "Add/remove one or more paths (no args →
   multi-select picker)".

4. **`lua/plugins/terminal.lua`: `TermOpen` autocmd missing augroup.**
   This was the only autocmd in the whole config not wrapped in a
   `vim.api.nvim_create_augroup(..., { clear = true })` group.
   Running `:Lazy reload toggleterm.nvim` would re-execute the
   `config` function and register an additional `TermOpen`
   handler. Each duplicate would re-set the same buffer-local
   `<C-h/j/k/l>` keymaps to the same RHS (so behaviour stays
   correct — keymaps are idempotent in this shape), but `:au
   TermOpen` output would accumulate stale entries. Now grouped
   under `user_toggleterm_term_nav` matching the pattern used
   everywhere else in the config; reload now cleanly replaces the
   handler instead of stacking it.

**Found but deliberately not changing — rationale:**

- **`lua/plugins/atone.lua` `HISTORY:` comment block** explains
  that atone was previously miswired as a colorscheme. CHANGES.md
  is the canonical home for change history, and a future reader
  could in principle look there — but the in-source note helps
  someone who notices `:colorscheme atone` in old documentation
  or screenshots understand the trail without digging through
  changelogs. Documenting a non-obvious past gotcha at the
  point-of-use is the right call.

- **`lua/plugins/formatting.lua` `:FormatToggle`** flips
  `vim.g.disable_autoformat` / `vim.b.disable_autoformat` flags
  that nothing reads unless the user uncomments the function-form
  `format_on_save` in `opts`. This UX wart is already documented
  in the surrounding comments — the command works as designed for
  the "format-on-save enabled" case, and the comment-out is
  deliberate to keep format-on-save off by default.

- **`lua/plugins/finder.lua`'s `file_ignore_patterns = { "build/",
  ... }`** hides `build/compile_commands.json` from
  `:Telescope find_files`. Could trip scoper users on a cmake-
  out-of-source layout. But this is the FINDER's default ignore
  list, not scoper's — `:ScoperFind` uses its own (in
  `pickers.lua`). The user can override per-picker call. Working
  as intended, pre-existing.

- **`cheatsheets/launch.json.example` uses
  `${workspaceFolder}/build/Debug/app`** throughout for the
  `program` field. Unlike the clangd.example
  `CompilationDatabase: build/` value that committed the template
  to one build-layout, launch.json examples are user-template
  files: users copy them into a project and edit the program path
  for their own build. The `build/` here is illustrative —
  matches CMake out-of-source defaults that the launch.json
  examples are demonstrating — not a layout decision baked into
  the template.

**Files surveyed and verified clean (no changes):**

- `.luacheckrc` — minimal, focused, correctly excludes
  `scoper.nvim/` (which has its own).
- `Makefile` — six clean targets with a top docstring noting
  Windows-without-make alternatives.
- `stylua.toml` — seven lines of unambiguous style choices.
- `lua/config/lazy.lua` — bootstrap with the
  `(vim.uv or vim.loop).fs_stat` cross-version dance; thorough
  comments on the `lazy = false` project default and the rtp
  disable list (with reasons for keeping `matchparen` and
  `matchit`).
- `lua/plugins/colorscheme.lua` — catppuccin spec with explicit
  `priority = 1000` rationale.
- `lua/plugins/completion.lua` — blink.cmp with the LuaSnip
  jsregexp portability note already documented.
- `lua/plugins/editor.lua` — eight small QoL plugins (autopairs,
  Comment.nvim, flash, neoscroll, smear-cursor, blink.indent,
  mini.surround, mini.align, todo-comments), each with a
  paragraph of context.
- `lua/plugins/git.lua` — gitsigns + diffview, both with `on_attach`
  / `opts` rationale comments.
- `lua/plugins/search.lua` — grug-far with the deliberate
  `<leader>sr` mode-overloaded keymap (the comment explicitly
  flags this for the test suite's duplicate-detector).
- `lua/plugins/trouble.lua` — Trouble with the smart `[q` / `]q`
  fallback to native quickfix, pcall'd against E42.
- `lua/plugins/which-key.lua` — clean group registrations.
- `lua/plugins/neogen.lua` — per-language annotation conventions
  documented; the C/C++ doxygen override flagged as
  documentation-as-code.
- `lua/plugins/scoper.lua` — short, cross-platform via
  `stdpath("config")`.
- `lua/plugins/atone.lua` — clean (keeping the HISTORY note as
  noted above).
- `cheatsheets/cpp-diagnostics.html`,
  `cheatsheets/keymaps.html`,
  `cheatsheets/workflows.html`,
  `cheatsheets/clang-format.example` — all match the current
  configuration; no clipboard / scoper / fugitive bleed-through.
- `tests/minimal_init.lua` — clean plenary bootstrap + dofile
  into the real config (which is the smoke test's whole point).

Files touched:

- `lua/plugins/ui.lua` — one-character removal of `"fugitive"`
  from lualine extensions.
- `lua/plugins/terminal.lua` — TermOpen autocmd wrapped in
  `vim.api.nvim_create_augroup("user_toggleterm_term_nav",
  { clear = true })`, comment expanded to explain why.
- `cheatsheets/plugins.html` — Scoper Add/Remove row updated to
  mention multi-arg + multi-select picker.
- `README.md` — troubleshooting row's "fugitive" replaced with
  "diffview".

---

# Audit pass 3: extending the survey to the rest of the codebase

The previous audit pass focused on scoper.nvim. This one extended the
same race / portability / test-gap check to the user's main config
(`lua/config/`, `lua/plugins/`, and `init.lua`). Most of the code is
already in good shape — only the diagnostics module had real fixes.

**Fixes applied:**

1. **`lua/config/diagnostics.lua` — filename collision and missing
   log directory.** The dump destination was built with
   `os.date("%Y%m%d_%H%M%S")` only (second-level resolution): two
   `:DiagnosticDump` invocations within the same second overwrote
   each other silently, as did concurrent dumps from two Neovim
   instances. The filename now appends `_<pid>` so each instance
   produces unique names even at sub-second cadence. Separately,
   `stdpath("log")` is not guaranteed to exist on a fresh install
   (especially on Windows); added a `vim.fn.mkdir(log_dir, "p")`
   call before the writefile so we don't silently fail with the
   directory missing.

**Found but deliberately left alone — with rationale:**

- **`lua/plugins/folding.lua` `has_ts_folds_cache` staleness.**
  Module-level cache, keyed by language. If a parser is installed
  mid-session (e.g. `:TSInstall typescript` after opening a TS
  file), the cache still holds the pre-install `false` and would
  keep returning false until restart. Single-threaded execution
  means it's not a data race; only a staleness window for a rare
  workflow. Fix would require an autocmd on `TSUpdate` to invalidate
  by language, which is more code than the rarity of the case
  justifies.

- **`vim.fs.joinpath` vs `..` "/" concatenation.** Internally
  consistent within each file but mixed across files: `dap.lua`
  uses the canonical Neovim API, others use string concatenation.
  Both forms work on every OS (Windows file APIs accept mixed
  separators), and `Path.normalize` (in scoper.path) handles the
  ugly cases. Standardising is churn for no behavioural win.

- **`session.lua`'s `dap.terminate()` is async.** The pre_save_cmds
  fire and forget; the following `[dap-*]` buffer-wipe loop is
  belt-and-braces against any session-time leftover. Verified
  against the original CHANGES entry where the E94/E95 bugs were
  fixed. Safe as written.

- **`auto_mkdir` autocmd's `vim.uv.fs_realpath`** can produce
  `\\?\`-prefixed long paths on Windows. The downstream
  `fnamemodify` and `mkdir` handle either form. Pre-existing,
  working, untouched.

**Race / re-entrancy patterns surveyed and verified clean:**

- `LspAttach` handler: per-buffer augroups (`user_lsp_highlight_<bufnr>`),
  inlay-hints first-init under single-thread execution.
- `vim.defer_fn(..., 0)` in treesitter for the install kickoff:
  fire-and-forget, no leaked handle.
- `BufReadPre` → `BufReadPost` ordering for big-file detection:
  guaranteed in-order for the same buffer by Neovim's event
  dispatch.
- `SessionLoadPost` re-firing `filetype detect` and
  `treesitter.start`: both are idempotent on a per-buffer basis.

**Portability gaps surveyed and verified clean:**

- `mason_exe` in `dap.lua` handles Windows `.cmd` shims, correctly
  excludes WSL (which reports as Linux to `has("win32")`).
- LuaSnip's `jsregexp` build deliberately skipped for Windows
  + LuaJIT compatibility — documented in `completion.lua`.
- DAP `MIMode` selects `lldb` on macOS vs `gdb` elsewhere — handled.
- `suppressed_dirs = { "~/", "~/Downloads", "/tmp", "/" }` in
  `session.lua` — auto-session resolves `~`; `/tmp` is a benign
  no-match on Windows.

**On tests NOT added:**

The main config's test strategy is deliberately minimal — per the
README's Testing section, the suite exists to catch "the kinds of
breakage that show up after big refactors": smoke (does the config
load?) plus the leader-key duplicate detector. Adding unit tests
for individual config helpers like `file_tail`, `smart_bdelete`,
`has_ts_folds`, or `capture` would exceed the stated scope. The
pure-logic helpers in `scoper.nvim` are tested because it's a real
plugin meant to stand alone; the main config's helpers are
configuration glue that ride along with the surrounding nvim state
and aren't valuable enough in isolation to justify the maintenance
of unit tests against them. Honoring the policy.

Files touched:

- `lua/config/diagnostics.lua` — log directory `mkdir -p` + PID
  suffix on dump filename.

---

# Audit pass 2: data races, portability, unit-test extraction

Three real safety fixes and one testability refactor surfaced by a
deliberate check for concurrency hazards, cross-platform issues, and
gaps in unit coverage. None of these change observable behaviour
for the happy path; all of them harden a narrow edge.

**1. `state.save()` is now atomic.** Previously wrote directly to the
final per-project JSON path via `vim.fn.writefile`. A Neovim crash
(OS reboot, OOM, SIGKILL) between opening and finishing the write
would truncate the file mid-save, taking every scope with it on
next load. The new version writes to `<path>.tmp.<pid>`, checks
that the temp write succeeded (returns -1 on disk-full /
permissions), then atomically renames over the final path via
`vim.uv.fs_rename`. The PID in the temp name also handles two
Neovim instances racing to save the same project — each has its
own temp file, the rename is last-write-wins on the final path,
neither can produce a corrupt file. libuv internally uses
`MoveFileExW` with `MOVEFILE_REPLACE_EXISTING` on Windows so the
destination being present doesn't break the rename.

**2. `reload_clangd` has a re-entrancy guard.** `vim.wait` (used to
deterministically wait for clangd clients to stop before re-attach)
pumps the event loop while it blocks, so the 500 ms debounced
callback in `attach_auto` could fire *during* the 2-second wait
window. With rapid scope edits — `:ScoperToggle` mashed twice
within a second — that produced two overlapping restart sequences
racing the same `vim.lsp.config` writes. The new version checks an
`M._reloading` flag at entry; if a reload is already in flight,
the new call is dropped (the in-flight one will finish, and
whichever ScoperChanged event fires next will trigger the next
reload). The body is wrapped in `pcall` so an unexpected error
doesn't leak the guard flag and lock the session out forever.
Factored the body into `M._reload_body` so the guard wrapper
stays thin.

**3. `find_compile_commands` normalizes `start_dir` up front.** Pure
hygiene — `vim.uv.cwd()` returns OS-native separators (backslashes
on Windows), then we concatenate with hard-coded `/`. Windows file
APIs accept the mixed result, but downstream string comparisons
and the rendered notify messages become noisy with both separator
styles. Now passes the input through `Path.normalize` first so all
constructed candidate paths are uniformly forward-slash on every
OS. No behaviour change, just cleaner.

**4. `split_args` extracted to `scoper.util` and unit-tested.** The
helper was a `local function` inside `plugin/scoper.lua`, invisible
to `require` and therefore untestable from busted. Promoted it
into a new `lua/scoper/util.lua` module dedicated to small pure
helpers (room to grow). The new `tests/util_spec.lua` covers 11
cases: nil/empty/whitespace inputs return nil (so the caller
routes to the picker), runs of whitespace collapse, leading and
trailing whitespace are trimmed, token order is preserved (the
delete loop's "last-scope guard" depends on it), backslash paths
survive intact as single tokens, and the deliberate spaces-in-
paths limitation is pinned down so a future refactor that "fixes"
it has to think about the picker-route fallback first. The test
file documents the limitation in comments so anyone reading the
spec understands why a `C:\Program Files\foo` case looks broken.

**On data races NOT fixed:** the stale-picker-data hazard (user
opens a multi-select picker, scope changes via some other path,
user confirms an outdated set) isn't a Lua-level race — Neovim is
single-threaded — and the picker UX gives the user visible
feedback (the items shown ARE the items being acted on), so the
"stale" choice is honestly what the user picked. The narrow race
that mattered was `reload_clangd` re-entrance; that one is fixed.

**On portability NOT changed:** the `nargs = "*"` whitespace
splitting in command dispatchers does not honour quoted paths.
This was a pre-existing limitation and applies equally to the
unmodified `:ScoperAdd`; the picker route is the safe path for
paths with spaces. The limitation is now documented in
`scoper.util.split_args`'s header and pinned by a test case.

**On tests NOT added:** the README's stated policy is "pure-logic
modules only — pickers, LSP, UI not unit-tested". `M.delete`'s
loop+aggregate logic and `M.clangd_cmd`'s three-mode dispatch are
both technically pure, but they hard-depend on `UI()` and
`find_compile_commands` respectively. Extracting their pure cores
would require enough refactoring to make them testable that the
testability tail starts wagging the design dog. Honored the
policy and left them to manual exercise.

Files touched:

- `scoper.nvim/lua/scoper/util.lua` — new file, holds `split_args`.
- `scoper.nvim/lua/scoper/state.lua` — `M.save` rewritten as
  write-tmp + rename atomic.
- `scoper.nvim/lua/scoper/lsp.lua` — `M.reload_clangd` gains a
  re-entrancy guard, body factored into `M._reload_body`;
  `find_compile_commands` normalizes `start_dir`.
- `scoper.nvim/plugin/scoper.lua` — inline `split_args` removed,
  now `require("scoper.util").split_args`.
- `scoper.nvim/tests/util_spec.lua` — new file, 11 cases.
- `scoper.nvim/README.md` — Testing section's "pure-logic modules"
  list extended to mention `util.lua`.

---

# Audit pass: comment accuracy, helper extraction, file headers

A consistency / good-practice review across everything touched in the
preceding entries. No behavior changes (apart from one negligible
edge case noted below); just comment accuracy, internal symmetry,
and a small refactor. Per-file:

- `scoper.nvim/lua/scoper/lsp.lua` — top-of-file commentary
  restructured into a clean three-mode breakdown (filter applies /
  no filter but file located / no file at all) rather than two
  paragraphs split across an explainer for the override rationale.
  Removed a contradictory phrase in the `cache_dir` comment
  ("no rewrite needed... except we always rewrite"). Cleaned up
  the `reload_clangd` comment's awkward "see init.lua / lsp.lua"
  self-reference.

- `scoper.nvim/lua/scoper/ui.lua` — file header rewritten to list
  all five exports (`show_lines`, `pick_one`, `pick_many`, `input`,
  `pick_dirs`) with one-line summaries; the old header referred to a
  non-existent `pick_dir` (singular) and claimed `pick_one` was "used
  everywhere", which stopped being true when `pick_many` landed. The
  `pick_many` docstring's claim that "an empty array means the user
  aborted" was inaccurate for the picker backends (they don't fire
  the callback on abort at all); rewritten to describe the real
  per-backend behaviour. The `has(mod)` helper moved from between
  the docstring and `pick_many` (where it was wedged awkwardly) to
  module scope right after `local M = {}`, matching the same pattern
  in `pickers.lua`. The fallback loop's manual `for _, v in
  ipairs(items) do table.insert(...)` table copy replaced with
  `vim.list_extend({}, items)`.

- `scoper.nvim/lua/scoper/init.lua` — `M.delete`'s normalization
  check simplified from `names == nil or names == "" or
  (type(names) == "table" and #names == 0)` to the family pattern
  `not names or (type(names) == "table" and #names == 0)`. The
  removed `names == ""` branch is unreachable from the dispatcher
  (which converts the no-arg case to nil) and only affects a direct
  call like `M.delete("")` — which used to trigger the picker and
  now routes through the loop, where `delete_scope("")` reports
  "no such scope". An obscure edge case; behaviour change is
  acceptable.

- `scoper.nvim/plugin/scoper.lua` — extracted a `split_args(s)`
  helper for the three near-duplicate "no args → nil, else split
  whitespace" dispatcher bodies (`:ScoperAdd`, `:ScoperRemove`,
  `:ScoperDelete`). Cuts six lines and unifies the pattern. The
  `:ScoperAdd` description switched from "Add directory(ies) to
  active scope" to "Add one or more directories to active scope" to
  match `:ScoperRemove` / `:ScoperDelete`. The `:ScoperLspReload`
  description switched from "Filter compile_commands.json by scope
  and restart clangd" — inaccurate after the toggle-off fix, since
  the command no longer always filters — to "Reconfigure clangd for
  current scope and restart".

- `cheatsheets/vs-to-nvim.html` — the "Ctrl+L → dd" row (VS Code's
  "cut line") was stale after the clipboard change: VS Code's Ctrl+L
  copies-then-deletes, so under the old `unnamedplus` it round-
  tripped through the system clipboard, but `dd` is now in-buffer
  only. Row now annotates `dd` as in-buffer and points to `"+dd`
  for the actual clipboard cut.

- `scoper.nvim/README.md` — Commands section's introduction
  rewritten to describe three distinct selector shapes (multi-select
  picker / free-form text loop / single-pick) rather than lumping
  `:ScoperAdd`'s text loop with `:ScoperRemove` and `:ScoperDelete`'s
  Tab-multi-select pickers, and incorrectly characterising
  `:ScoperNew` (free-form text input) as a single-select picker.

---

# Scoper: multi-select for `:ScoperRemove` and `:ScoperDelete`

Asymmetric multi-select support across the three list-producing
Scoper commands made `:ScoperDelete` and the no-args path of
`:ScoperRemove` annoying when you actually had several items to deal
with. State before:

| Command | Command-line | Picker |
|---|---|---|
| `:ScoperAdd` | multi (whitespace-separated) | multi (`pick_dirs` loop) |
| `:ScoperRemove` | multi | **single** (`pick_one`) |
| `:ScoperDelete` | **single** (`nargs = "?"`) | **single** (`pick_one`) |

Two changes land together.

**1. `:ScoperDelete` accepts a list at the command line.** `nargs`
moves from `"?"` to `"*"`; the dispatcher splits on whitespace and
hands a list to `M.delete`. `M.delete` now accepts string, list, or
nil/empty (picker). Successes and failures are collected separately
and reported with one notify each, so a single bad name doesn't hide
the deletions that did succeed. The "cannot delete the last scope"
guard in `state.lua` still fires per-iteration, so
`:ScoperDelete a b c d` (where these are *all* the scopes) deletes
the first three and reports the fourth as an error.

**2. `ui.lua` gains `pick_many`.** Three backends, auto-detected at
call time, matching `pickers.lua`'s preference order:

- **fzf-lua:** `fzf_exec` with `--multi`. `<Tab>` toggles a row,
  `<C-a>` toggles all, `<CR>` confirms (or commits the highlighted
  row if nothing was toggled).
- **telescope:** custom picker (no generic multi-select builtin
  exists, so we build with `pickers.new` + `finders.new_table`).
  `actions.select_default` is overridden to read
  `get_multi_selection()` first, falling back to the highlighted
  entry if no Tab-toggles happened. `<Tab>` / `<S-Tab>` toggle, `<CR>`
  confirms.
- **plain `vim.ui.select` fallback:** looped pick with a synthetic
  `(done)` sentinel as the first item. Each pick removes the chosen
  row from the remaining list and re-prompts with the running count
  shown in the prompt; `(done)` or `<Esc>` commits.

`M.remove` and `M.delete` now route their no-args paths through
`pick_many`. `M.use` and `M.new` keep `pick_one` because exactly one
scope is active at a time and "use multiple" makes no sense.

The fzf-lua and telescope branches feel like real multi-select; the
fallback loop is a reasonable degraded mode for environments without
either picker. `pick_one` stays in `ui.lua` for `M.use` and is
still available for any caller that wants single-pick semantics.

Files touched:

- `scoper.nvim/lua/scoper/ui.lua` — new `pick_many` helper; `pick_one`
  unchanged.
- `scoper.nvim/lua/scoper/init.lua` — `M.remove` uses `pick_many` in
  the picker branch; `M.delete` accepts a list, loops, reports per-
  iteration success/failure, uses `pick_many` in the picker branch.
- `scoper.nvim/plugin/scoper.lua` — `:ScoperDelete` switches to
  `nargs = "*"` with whitespace split; both `:ScoperRemove` and
  `:ScoperDelete` get descriptions that mention "one or more".
- `scoper.nvim/README.md` — Commands section gains a top-level note
  explaining the per-backend multi-select keybinds; table rows for
  `:ScoperRemove` and `:ScoperDelete` updated to mention multi-select.

---

# clangd cheatsheet: no longer commits to a CompilationDatabase layout

`cheatsheets/clangd.example` previously defaulted to
`CompilationDatabase: build/`, with a brief "adjust to your build
dir" comment. That value is fine for CMake out-of-source builds and
wrong for everything else, and the failure mode when it's wrong is
silent: clangd loads the .clangd file, fails to find the database,
falls back to `-Wall -Wextra` ad-hoc flags, and every project
include resolves to "file not found" with no warning.

The template now leaves the `CompilationDatabase` line commented out
and the commentary above it lists the common options
(`.`, `build/`, `out/`, `cmake-build-*/`) with an explicit warning
about the silent fallback. Users who copy this file into a project
are forced into a deliberate choice rather than inheriting a default
that's wrong for ~half of common layouts.

Files touched:

- `cheatsheets/clangd.example` — `CompilationDatabase` line commented
  out; surrounding commentary block rewritten to document the layout
  options and the silent-fallback failure mode.

---

# Scoper: toggle-off now restores baseline clangd in the same session

`scoper.nvim/lua/scoper/lsp.lua` had a behavioural gap: when scoping
was disabled (`:ScoperToggle`, empty include list, missing
`compile_commands.json`, or a parse error), `reload_clangd()`
notified and early-returned without touching the running clangd or
the stored `vim.lsp.config("clangd", { cmd = ... })`. Net effect: if
you had scoped clangd earlier in the session, toggling scope off
left clangd pinned to the previous filtered cache. The only way out
within the session was to scope-on again with everything included
(self-defeating) or to restart Neovim.

The fix has two halves, landed together:

**1. `reload_clangd` proceeds unconditionally.** A new
`base_clangd_cmd()` helper holds the default flag set
(`--background-index`, `--clang-tidy`, `--completion-style=detailed`,
`--header-insertion=iwyu`) so the scoped and unscoped paths can't
drift. `clangd_cmd()` now always returns a usable cmd.

**2. `--compile-commands-dir` is kept in the unscoped case too,
pointing at the project's real `compile_commands.json` directory.**
This was the second turn of the screw, after the first attempt
(dropping the flag entirely on toggle-off) was tested against a
real C++ project on Windows and clangd failed to find the database.
The log showed clangd loading `.clangd` and then
`Failed to find compilation database for ...`, falling back to
`-Wall -Wextra` ad-hoc flags with every include resolving to
`'no such file or directory'`. The culprit was the project's
`.clangd` file's `CompileFlags.CompilationDatabase` setting
disagreeing with where the database actually lived: the explicit
`--compile-commands-dir` flag had been masking that mismatch while
scoper was on, and removing it exposed it.

`--compile-commands-dir` overrides any `.clangd`-side
`CompilationDatabase` setting, which means passing it explicitly
removes a whole class of discovery failure. Scoper already knows
exactly where the database is (it found it in step 1 of the filter
pipeline), so we use that knowledge in both modes:

- **Scope on, filter applies:** clangd reconfigured with
  `--compile-commands-dir=<scoper cache>` + default flags. Restart.
- **Scope off / empty / parse error, but database located:** clangd
  reconfigured with `--compile-commands-dir=<project's real dir>` +
  default flags. Restart. This is the "always explicit" branch.
- **Database not located anywhere scoper looks:** clangd
  reconfigured with default flags only (no
  `--compile-commands-dir`). Restart. This is the only case where
  clangd's built-in discovery and any `.clangd` config get to
  decide; if scoper truly can't find a database, neither can it
  point clangd at one.

The notify message describes which case applied:

- `Scoper LSP: N/M entries kept → /scoper/cache/...` (filtered)
- `Scoper LSP: disabled; clangd pointed at /project/dir — restarted N clangd client(s)`
- `Scoper LSP: compile_commands.json not found (...); clangd will use built-in discovery — restarted N clangd client(s)`

**API change worth noting:** `require("scoper").clangd_cmd(extra)`
previously returned `(nil, info)` when filtering wasn't possible.
The public README documented a usage example that fed the result
directly into `vim.lsp.config("clangd", { cmd = cmd })`, which under
the old contract would silently set `cmd = nil` and break clangd
entirely. The new contract is that `clangd_cmd` *always* returns a
usable cmd — strictly safer for the documented usage; any caller
that was checking `if not cmd then ...` will simply never enter
that branch now.

Files touched:

- `scoper.nvim/lua/scoper/lsp.lua` — top-of-file rationale block
  expanded (with the `.clangd` interaction documented); new
  `base_clangd_cmd()` helper; `write_filtered_compile_commands`
  reordered (cheap state checks before disk I/O) and its `info`
  strings stripped of both the `"Scoper LSP: "` prefix and any
  speculation about clangd's behaviour, since the disposition is now
  decided in `clangd_cmd`; `clangd_cmd` gains the unscoped-but-
  explicit fallback path; `reload_clangd` proceeds unconditionally.
- `scoper.nvim/README.md` — "clangd integration" section rewritten
  to describe the three-case disposition (filtered / unscoped-with-
  located-CC.json / unconfigured) and the `.clangd` rationale.

The on-disk filtered `compile_commands.json` is still a single line
(internal cache scaffolding; clangd doesn't care).

---

# Clipboard behaviour — yank/paste no longer implicit

Removed `opt.clipboard = "unnamedplus"` from `lua/config/options.lua`.
Previously every yank AND every delete went through the system
clipboard via Vim's unnamed-register aliasing — the convenience
(`yy` copies, `p` pastes from anywhere) wasn't worth the surprise
(`dd` silently wipes the browser-copied URL you were about to paste).

System clipboard access is now explicit:

```
"+y / "+yy   yank to clipboard
"+p / "+P    paste from clipboard
"+d          cut to clipboard
```

Plain `y` / `p` / `d` / `dd` still work in-buffer — the unnamed and
numbered registers behave exactly as Vim intends, just without the
clipboard bridge. The old setting is preserved as a commented-out line
in `options.lua` with rationale, so flipping back is one uncomment
away. A matching one-liner lives in the README's "Common tweaks"
section.

Files touched:

- `lua/config/options.lua` — main change + expanded rationale comment,
  with the old line kept commented for easy restoration.
- `lua/config/keymaps.lua` — comment on the `"_dP` visual-paste remap
  now reflects what it actually protects under the new setup (the
  unnamed register), with a parenthetical note about the prior
  clipboard-protection role.
- `cheatsheets/vs-to-nvim.html` — the Cut/Copy/Paste row no longer
  claims `d`/`y`/`p` reach the system clipboard; the `"+y`/`"+p` row
  is rewritten from "redundant fallback" to "the primary mechanism".
- `README.md` — new entry under "Common tweaks" for re-enabling
  implicit-clipboard behaviour.

---

# Cleanup-pass fixes

Applied to the config based on the review. Grouped roughly by severity.
All Lua files still parse with `luac -p`.

## Real bugs

- **dap.lua** — `c` and `rust` configs were aliased to the same Lua table as
  `cpp`; future mutation of one would silently mutate all three. Now uses
  `vim.deepcopy(dap.configurations.cpp)`.
- **scoper.nvim/lsp.lua** — `vim.defer_fn`'s timer was leaked on every rapid
  scope-change cancellation (`:stop()` alone doesn't close the uv handle).
  Now stops and closes before reassigning.
- **scoper.nvim/lsp.lua** — removed the dead `if not vim.lsp.config then …`
  branch in `reload_clangd()`; `vim.lsp.config` exists on Neovim 0.11+ so
  the notify path was unreachable. The "fall back to `:LspStart` for 0.11"
  path is kept since the README still claims 0.11.2 minimum. Comment
  rewritten to reflect what's actually live.
- **lsp.lua** — `<leader>lh` (toggle inlay hints) is now gated on the
  client supporting the method, and the toggle preference is tracked in
  `vim.g.user_inlay_hints_enabled` so disabling hints isn't silently
  re-enabled on every new buffer of the same language.
- **scoper.nvim/state.lua** — `add_excludes` rejected `""` but accepted
  whitespace-only patterns, so `:ScoperExclude   ` would corrupt the
  exclude list with no-op entries. Now rejects via `p:match("%S")`.
- **terminal.lua** — `size = function(term) … end` returned `nil` for
  `direction == "float"`. Works today by luck (toggleterm doesn't read it
  for floats), but a footgun on update. Now explicit.

## Stale or misleading comments

- **init.lua** — clarified the diagnostics module's plugin dependencies
  (registration is plugin-free; the command body queries dap/lazy via
  pcall when invoked).
- **lazy.lua** — clarified that `lazy = false` is OUR project default,
  not lazy.nvim's (lazy.nvim's default is the opposite).
- **keymaps.lua** — comment about `close_if_last_window = false` was
  wrong; explorer.lua actually sets it `true`, and smart_bdelete is what
  makes that setting safe to keep on.
- **treesitter.lua** — spelled out that `vim.g.no_plugin_maps = true`
  globally suppresses default keymaps from every built-in ftplugin, not
  just colliding ones.
- **explorer.lua** — spelled out that the `once = true` BufEnter autocmd
  is reload-safe because of the `isdirectory(f) == 1` guard.
- **scoper.nvim/path.lua** — `is_dir` comment claimed `uv.fs_lstat`; the
  code uses `vim.uv.fs_stat` (which follows symlinks). Comment fixed to
  match the code, which is the intentionally correct behavior here.
- **tests/config_spec.lua** — smoke test comment mentioned
  `vim.g.lazy_did_setup`; the assertion checks `package.loaded["lazy"]`.
  Comment now matches the check.
- **autocmds.lua (close_with_q)** — pruned filetypes for plugins not
  actually installed (fugitive, git, notify, startuptime, tsplayground,
  neotest-output, neotest-summary). Kept built-ins plus
  PlenaryTestPopup (plenary is a Telescope dep).
- **autocmds.lua (big_file)** — was running `vim.uv.fs_stat` a second
  time in BufReadPost just to format the MB number; now caches the size
  on `vim.b[buf].big_file_bytes` in BufReadPre.
- **folding.lua** — `has_ts_folds` cached by filetype; now caches by
  language via `vim.treesitter.language.get_lang(ft)` so tsx and
  typescriptreact (and similar) don't store two cache entries.

## Cheatsheets

- **plugins.html** — `:lsp start` / `:lsp stop` were wrong; the actual
  0.12 names are `:lsp enable` / `:lsp disable` (verified against
  nvim-lspconfig docs and the 0.12 changelog). Restart was already
  correct.
- **plugins.html** — removed `gopls` from "Servers pre-installed" (it's
  commented out in `lsp.lua`) and added a note about how to re-enable it.
- **plugins.html** — `:ScoperSwitch` → `:ScoperUse` to match the actual
  command name in `plugin/scoper.lua`.
- **plugins.html** — was telling users to manually update the lualine
  `theme` field when changing catppuccin flavour; lualine uses
  `theme = "auto"` so it auto-syncs.
- **plugins.html** — context-menu key range was "1..9" but only 8
  actions exist in the menu; now "1..8".
- **plugins.html** — moved "smarter folds" out of the LSP card's
  "Features auto-enabled" list, since it's actually provided by the
  separately-installed nvim-ufo plugin.
- **workflows.html** — "(or gr to reset)" was missing the `<leader>`
  prefix (`gr` is the LSP References keymap).
- **workflows.html** — the merge-conflict workflow used to recommend
  `:Gitsigns stage_hunk`, which doesn't resolve conflicts. Replaced with
  diffview's actual default conflict-resolution keymaps (`<leader>co`,
  `<leader>ct`, `<leader>cb`, `<leader>ca`), verified against
  `doc/diffview.txt`.
- **keymaps.html** — split the "Leader Namespaces" table: real
  which-key namespaces (b/c/d/f/F/g/l/s/t/w/x) up top, standalone
  leader commands (e, ?, L) in a labelled sub-section below.
- **keymaps.html** — renamed the "Jump (flash.nvim)" card to "Jump
  (flash + treesitter)" and labelled each sub-section with the actual
  plugin (flash.nvim / nvim-treesitter-textobjects / treesitter-context).
- **keymaps.html** — Completion `<C-k>` row now documents that in LSP
  buffers the LSP buffer-local map shadows blink's default.
- **keymaps.html** — auto-session suppressed-dirs list now includes
  `~/Downloads` to match session.lua.
- **clangd.example** — replaced the removed `:LspLog` reference with the
  0.12-compatible `:lua vim.cmd.edit(vim.lsp.get_log_path())`.
- **clang-format.example** — noted that
  `AlwaysBreakTemplateDeclarations` was renamed to
  `BreakTemplateDeclarations` in clang-format 19+; the legacy alias
  still works.
- **cpp-diagnostics.html** — footer was overly conservative about
  NOLINTBEGIN/END (claimed 18+); it landed in clang-tidy 14.

## Intentionally not changed

- `<leader>dl` (run last) vs `<leader>dL` (validate launch.json) — the
  case-only difference is a UX nit, but both actions are non-destructive,
  so left alone to preserve muscle memory.
- `client:supports_method` (colon-form) — valid on 0.11+, no change.
- `editor.lua` smear-cursor `hide_target_hack = false` — terminal-
  dependent default; left alone.
- The custom buffer-context-menu BufLeave/WinLeave autocmd — the
  existing `nvim_win_is_valid` guard in `close()` already makes double-
  close safe; the cleanup was cosmetic.
