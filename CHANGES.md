# Changelog

Newest first. Entries record their own revision's behavior and evidence; later
changes can supersede earlier defaults or instructions. Use the README and
feature guides for current operation. New entries use one `## YYYY-MM-DD — <title>` heading per
change, with `### Fixed` / `### Changed` / `### Docs` subsections. An item
that a later change undid is marked *(Reverted in …)* where it appears.

## 2026-10-28 — Add workflow and Visual Studio migration guides

### Docs

- Add a short workflow guide covering a first session, navigation, editing,
  replacement, builds/tests, debugging, Git, layouts/sessions and optional Scoper.
- Add a detailed Visual Studio migration and feature reference with its own
  quick start, C++/MSBuild/CMake setup, debugger recipes, project/context model,
  feature boundaries and troubleshooting.
- Link both guides from the README and existing workflow/Visual Studio
  cheatsheets. Keep platform installation and advanced settings in their
  existing maintained guides.

## 2026-10-28 — Audit documentation, examples and source comments

### Fixed

- Refresh externally saved Scoper state before capturing the first search or
  replacement query. Newly saved roots/restrictions now apply immediately;
  two failing-before/passing-after regressions cover the boundary.
- Correct the annotated clangd example's `FullyQualifiedNamespaces` value to an
  empty list instead of a scalar that could be treated as a namespace name.

### Docs

- Reconcile all tracked documentation and comment surfaces with current code and
  locked dependencies. Correct setup/tooling, trust, debugging, C/C++, search,
  session, clipboard, fold, state-cleanup and CI claims; expand recipes and
  explain backend boundaries, recovery costs and privacy limits.
- Explain that plugin rollback requires restoring the desired lockfile before
  `:Lazy restore`; updating plugins rewrites the on-disk lockfile.
- Preserve dated audit/changelog evidence with explicit historical notices and
  later correction notes. See the [coverage and verification report](docs/documentation-audit-2026-10-28.md).

## 2026-10-28 — Document on-demand CodeLLDB symbols for slow launches

### Docs

- Include both symbol-loading commands in the CodeLLDB project launch example
  as optional tuning for large native programs and repeated slow launches.
  Explain module-level loading, breakpoint/expression tradeoffs, compatibility
  checks and rollback in the debugger guide and cheatsheet.
- Correct earlier per-compile-unit/always-safe claims and remove broad antivirus
  exclusion advice from the active performance guidance. The generated launch
  fallback retains its existing preload-only default; project configurations
  continue to own their `initCommands`.

## 2026-10-27 — Generalize debugger width protection to fixed columns

### Changed

- Replace the Neo-tree-specific width guard with one based on `winfixwidth` and
  the native split layout. Preserve independent left/right and stacked fixed
  columns across DAP UI operations, including unwanted shrinkage. Each call uses
  current widths, with Neovim clamping requests when space is limited.
- Exclude DAP UI's own window IDs and horizontal panels sharing a flexible editor
  column, so panel resizing and ordinary editing layouts retain their behavior.
  No Neo-tree filetype/position checks or parallel compatibility path remain.

### Docs

- The [debugger guide](docs/debug-terminal-configuration.md#fixed-window-widths-during-debugging)
  explains native option opt-in/opt-out, layout behavior and narrow-screen limits.

## 2026-10-27 — Keep Neo-tree width stable across debugger sessions

### Fixed

- DAP UI could give its closing left panel's 41 columns to Neo-tree on every
  session exit, even with `winfixwidth` enabled. Preserve each existing sidebar's
  current width around DAP UI operations, including partial closes and temporary
  session-save closures. Manual widths and independent tab sidebars survive;
  constrained windows can still shrink when needed.

### Docs

- The [debugger guide](docs/debug-terminal-configuration.md#fixed-window-widths-during-debugging)
  explains the cause and how to undo previously accumulated width once.

## 2026-10-26 — Broader configuration and independent Scoper build selection

### Fixed

- Explicit leaders, `exrc=false`, debugger adapters/configurations and pause
  choices survive startup and repeated setup. Custom launch-file roots now
  affect the real DAP provider, not only a validation command.
- Tool identities, version pins and intentional opt-outs agree across automatic
  installation, health and offline completeness. Unsupported requested tools
  remain incomplete for offline seeds. Explicit compiler paths are passed through
  supported build interfaces, including literal CMake argv for paths with spaces.
- Search exclusions match directory components instead of hiding similarly named
  paths. Scoper file/glob includes use the same exact matcher in pickers and CDB
  filtering. Scope revisions invalidate stale selectors even when names repeat.
- Scoper notices selected-source regeneration independently of scope changes,
  preserves base clangd argv/environment, exposes copied status and retains local
  changes after failed saves, including a project switch within the same editor.

### Changed

- Optional, Git-ignored `local.lua` loads before core behavior and plugin setup.
  It supports machine policy, explicitly registered trusted runtime project
  overlays and ordinary Lazy overrides. No project Lua is discovered by the loader.
- Scoper separates project root, named scope, persisted build selection and
  `disabled`/`native`/`selected`/`filtered` integration modes. Legacy `lsp.clangd`
  behavior remains compatible; the bundled automatic-filtering default remains.
  New explicit modes refuse ambiguous default build discovery. Arbitrary nested
  or external database locations need no hard-coded build-folder changes.
- Scoper state uses schema version 1, read-only snapshots and structured
  persistence outcomes. Unsupported schemas cannot be overwritten. `setup()`
  starts from defaults; `patch()` explicitly layers configuration. Use
  `:ScoperReload` for saved state, and `:ScoperReload!` only to discard local edits.
- Optional asynchronous prepare-before-first-clangd attachment has a bounded
  timeout; the default immediate startup/fallback policy remains available.
- Tool lists, Python provider coordination, root/visibility/selector policies,
  manual sessions/global buffers, trimming/prose, retention, stock themes,
  ASCII indicators and reduced motion can be selected without editing defaults.
- **Migration:** Windows terminals inherit `vim.o.shell`; set
  `terminal.shell="legacy"` for the previous automatic PowerShell preference.
  Compiler execution trust is explicit through `scoper.lsp.query_drivers`;
  inferred path-prefix and hard-coded MSYS whitelists are removed. Existing
  explicit clangd arguments are retained. Review trusted compiler paths if
  system-header discovery requires `--query-driver`.

### Docs

- [Customization](docs/customization.md) explains load order, replacement rules,
  trust, context, migration and feature-specific guides. Those guides describe
  defaults, supported backend boundaries, inspection and targeted regressions.
- Scoper's README now reflects file/glob matching, configuration lifecycle,
  recovery commands and independent database/clangd policies.

## 2026-10-20 — Scoper and config robustness (remaining NV/S2 findings)

### Fixed

- scoper: a `compile_commands.json` that isn't a compilation database
  (not a list, an entry without `file`/`directory`, without `command` or
  `arguments`) is now reported, and the previous filtered output stays in
  place. Before, it could be filtered to an empty database (S2-010).
- scoper: the filtered compile_commands cache is used only while the
  output still has the size the filter wrote. A truncated or edited cache
  is filtered again (S2-004).
- scoper: a filter result that lands after `:cd` switched to another
  project is dropped, and the reload is replayed for the new project
  (S2-009).
- scoper: the background job file's `writefile()` result is checked, not
  only whether it threw (NV-006). Two writes of one Neovim no longer share
  a temp file name (NV-005).
- scoper: a hand-edited state file can no longer bring in a scope named
  `..` or non-string include/exclude items; they are dropped on load
  (S2-007). A second corrupt state file in the same second gets its own
  backup (S2-012). A failed save says the change applies to this session
  only (S2-006).
- Big-file mode: re-reading the file (`:e!`) after it shrinks below the
  limit turns its swap file back on (S2-005).
- `:SwapClean` and the swap section of `:DiagnosticDump` skip a swap dir
  that is missing or unreadable instead of failing (S2-016).
- `:DiagnosticDump` twice in one second writes two files (S2-014).

## 2026-10-20 — Third-pass audit: swap deletion, scoper fallbacks, tar shim

Addresses S3-001 to S3-009 of the 2026-10-20 third-pass audit. S3-010
(`vim.g.no_plugin_maps` is global) stays as it is: it is intentional and
documented in `lua/plugins/treesitter.lua`.

### Fixed

- `:SwapDelete <path>` could delete any existing file after the
  confirmation, not only a swap (S3-001). An explicit path must now be a
  regular file (not a link or folder) named `*.sw?`, and Neovim must be able
  to read its swap header. An unreadable swap needs `:SwapDelete!`. Each
  file is checked again just before it is deleted, and is skipped if it has
  been replaced in the meantime. `:SwapClean` now points to `:SwapDelete!`
  for unreadable swaps.
- scoper: the plain `:find` fallback of `:ScoperFind` ignored the scope's
  excludes (S3-002). It now opens the first match the excludes don't hide,
  and says so when all matches are excluded. It also no longer changes
  `'path'` while its prompt is open (S3-006): the search path goes straight
  to `findfile()`.
- scoper: the plain `:vimgrep` fallback of `:ScoperGrep` broke patterns
  with an escaped slash such as `abc\/def` (S3-003). Only unescaped `/` are
  escaped now. The command runs through `nvim_cmd` with `bar = false`, so a
  `|` or `"` in the pattern stays part of it.
- scoper: `:ScoperReplace` turned whitespace in an exclude glob into `?`,
  which can exclude other files than intended (S3-005). It now refuses to
  open and says which exclude to rewrite.
- The Windows tar shim reused its copy of System32's `tar.exe` whenever the
  sizes matched (S3-007). Now the size and modification time must both
  match, and a link is never reused. The copy goes to a temp name first and
  is then renamed, so a failed copy can't leave a broken `tar.exe` first on
  PATH.
- Treesitter's on-demand parser install gave up on a language for the
  rest of the session after one attempt (S3-008). It now starts once the
  tree-sitter CLI appears on PATH, and retries a failed build after 5
  minutes at the earliest.

### Changed

- scoper: `:ScoperFind` on telescope now follows directory links like the
  fzf-lua backend (S3-004). `vim.g.scoper_follow_links = false` keeps both
  backends to the scope's own dirs.
- `:DiagnosticDump` redacts the DAP adapter and launch config: every
  `env` value, and the values of keys that look secret (token, password,
  auth, api key, cookie, …). The keys stay visible. `:DiagnosticDump!`
  writes them unredacted (S3-009).

### Added

- Specs:
  - `tests/behavior_spec.lua`: `:SwapDelete` with a non-swap file, a link,
    a folder, an unreadable swap, and cancel; the tar shim when the system
    tar keeps its size; DAP redaction.
  - `scoper.nvim/tests/pickers_spec.lua`: the `:find` fallback with
    excludes and an open prompt; `:vimgrep` patterns with `/`, `\/`, `|`
    and `"`; the `follow_links` switch on both backends; the
    `:ScoperReplace` refusal.

## 2026-10-20 — Offline seed: safe install, fail-closed check, tests

Addresses the installer findings of the 2026-10-18 and 2026-10-20 audits
(NV-001, NV-012, S2-001, S2-002, S2-003, S2-013, S2-015).

### Fixed

- `offline-seed.py install` could write outside the data folder. A zip seed
  was unpacked with plain `extractall`, so with `--force` an existing
  `lazy/` that was a symlink or junction got the seed written through it,
  into wherever it pointed. A dangling link also slipped past the "already
  installed" check. Now every entry, zip or tar, is checked before anything
  is written (see Changed). The seed unpacks into a new staging folder
  inside the data folder. `lazy/`, `mason/` and `site/` are then moved into
  place, and any existing ones, links included, are first moved to an
  `offline-seed-backup-*` folder. If a move fails, every move is undone.
- The completeness check (`check`, and `build` before packing) reported
  "complete" when Neovim crashed, hit an error or wrote nothing. Now it
  passes only if Neovim exits 0 and writes a `{"version":1,"missing":[…]}`
  report. `scripts/offline-seed-check.lua` reports its own errors and exits
  1. A check that can't run makes `check` exit 2 and `build` stop, unless
  you pass `--no-check`.
- `scripts/check-docs.sh` failed on files that running things leaves
  behind (`__pycache__/`, `*.pyc`, swap files, `.DS_Store`). It now skips
  them.

### Changed

- `install` checks every entry before writing anything. Each one must sit
  under `lazy/`, `mason/` or `site/`, or be the manifest. These are refused:
  absolute, `..`, drive-letter or backslash paths; duplicates (ignoring case
  on Windows and macOS); devices and zip symlinks; tar links pointing out of
  the seed (the Python links inside Mason venvs are the exception); and
  entries written through an archive link.
- It also refuses seeds over the size limits (`--max-total-mb`,
  `--max-file-mb`, `--max-entries`) or larger than the free disk space.
- `build` writes `<seed>.sha256` and prints the hash. It also re-reads the
  finished archive with the installer's rules, so it can't produce a seed
  `install` would refuse.
- `install` compares the seed with `--sha256 <hex>`, or else with the
  `.sha256` file, and stops if neither matches; `--no-verify` skips this.
- A seed built from a different `lazy-lock.json` now stops the install
  instead of warning. `--allow-lock-mismatch` overrides that.
- `--force` now only means "replace existing data", and the old data is
  moved to the backup folder, not merged. Installing a seed from another
  platform needs the new `--allow-platform-mismatch`.

### Added

- `tests/offline_seed_test.py` (30 tests, Python `unittest`, temporary
  folders only): hostile seeds, `--force` with a linked `lazy/`, rollback
  on a failed swap, the checksum, lockfile and platform gates, the size
  limits, and the check against a fake `nvim` that crashes, hangs, errors
  or writes no report. Run it with `make test-seed`; it is part of
  `make ci`. A new CI job, `test-seed`, runs it on Ubuntu, Windows and
  macOS.

### Docs

- `docs/workflows/offline-install.md`: covers the `.sha256` file and when
  to pass `--sha256` instead, what the installer checks and in which order,
  the backup folder, all install options, and `check`'s exit codes.
  `install-update-uninstall.md` explains how to roll back from the backup
  folder.

## 2026-10-14 — Install / update / uninstall docs for every platform

### Fixed

- README "Clearing caches": on Windows `stdpath('cache')` is `%TEMP%\nvim`,
  not `%LOCALAPPDATA%\Temp\nvim-data`. The level 1–3 commands deleted a
  folder that doesn't exist and left the real cache in place. The paths
  table now has Windows and Linux/macOS columns, and the single-plugin and
  ShaDa tips give paths for both.
- The zip holds a top-level `nvim/` folder, but the README said to unzip it
  "directly into your nvim config directory", which gives `nvim/nvim/`. It
  now says to extract into the parent folder (`~/.config`,
  `%LOCALAPPDATA%`), with a table.
- `.githooks/pre-commit`, `scripts/check-docs.sh` and
  `scripts/offline-seed.py` are now executable in git (mode 100755), so the
  hook runs after `make hooks` on Linux/macOS and unzip keeps the bit.

### Docs

- New `docs/workflows/install-update-uninstall.md`: where everything lives
  per OS; install (moving an existing config aside, extract commands for
  PowerShell and for bash/zsh/fish, with `unzip`, `bsdtar` or Python);
  trying it side by side with `NVIM_APPNAME`; updating to a new zip (keep
  `nvim.bak`, diff your edits, `:Lazy restore` + `:Lazy clean` or
  `:Lazy sync`); rollback; uninstall and what's left outside the four
  folders.
- README: points to it from the intro and setup step 2, and the layout tree
  lists it. workflows.html: Initial setup step 1 has the extract commands,
  an offline note, and a new "Update / uninstall" card. offline-install.md
  links to the extract step.

## 2026-10-14 — Offline seed: install on a machine without internet

### Added

- `scripts/offline-seed.py` (Python 3.8+, standard library; Windows, Linux,
  macOS, any shell): `check` lists what this install would still download;
  `build` packs `lazy/` (lockfile entries only, each verified at its
  lockfile commit), `mason/` (without `staging/`) and `site/` plus a JSON
  manifest into `nvim-offline-seed_<os>-<arch>_lock-<hash>.zip` (Windows) or
  `.tar.gz` (Linux/macOS, keeps exec bits and Mason's relative symlinks);
  `install` unpacks a seed into `stdpath('data')`. It refuses an existing
  data folder or another platform's seed without `--force`, refuses tar
  entries written through a symlink, and re-points Mason's Python venvs
  (debugpy, clang-format) at the local Python when the build machine's is
  missing and major.minor match.
- `scripts/offline-seed-check.lua`: the Neovim side of `check`; reads the
  Mason and parser lists from the resolved lazy.nvim specs.

### Changed

- `lua/plugins/treesitter.lua`: the parser list is passed as
  `opts = { parsers = … }` so the check can read it; behaviour unchanged.

### Docs

- New `docs/workflows/offline-install.md`. README: layout tree (`scripts/`,
  the new workflow), a pointer in the first-time setup checklist, and a
  "Stuck during setup?" entry for tree-sitter's `Lock file … appears stale`
  (left when Neovim quits while a parser compiles; gitcommit takes minutes).

## 2026-10-14 — diffview.nvim → diffview-plus.nvim

### Changed

- `lua/plugins/git.lua`: `sindrets/diffview.nvim` (no commits since 2024)
  replaced by its maintained fork `dlyongemallo/diffview-plus.nvim`. Same
  module and commands, same `opts`; the lazy-load `cmd` list adds the new
  commands. `lazy-lock.json` updated. The catppuccin `diffview`
  integration still applies.
- Keys: `<leader>gd` now toggles (`:DiffviewToggle`; `<leader>gD` still
  closes); `<leader>gh` in visual mode shows the selected lines' history;
  new `<leader>gl` (file history vs the working copy, `--pin-local`) and
  `<leader>gw` (`:DiffviewWorktreeOverview`).
- New plugin defaults now in effect: the view follows index changes,
  reviewed-file marks in the file panel (`w` / `H` / `C`), whole-side
  merge picks (`<leader>cso/cst/csb`), and open views restored with the
  session through a `<session>.diffview.json` next to the session file.

### Docs

- keymaps.html Git card, plugins.html diffview card (new commands, file
  panel keys, whole-side merge keys), workflows.html review and merge
  steps, vs-to-nvim.html, README (layout tree, leader groups, built-ins
  table), `docs/workflows/state-files.md` (the session sidecar).

## 2026-10-14 — :DiagnosticDump: settings, swap files, scoper

### Changed

- `:DiagnosticDump` gained three sections: **Settings** (`NVIM_APPNAME`,
  swap/undo options, `updatetime`, the swap guard, big-file and tar-shim
  flags, `v:this_session`), **Swap files** (every swap, classified by the
  same scan as `:SwapClean`, now `require("config.autocmds.swap").inventory()`)
  and **Scoper** (root, active scope, clangd integration, reload state, the
  clangd cmd last applied, the last filter result and how the last
  background run ended). scoper.nvim records the last two in
  `lsp._last_filter` / `lsp._last_worker`. Nothing runs until the command
  does. New spec in `tests/behavior_spec.lua`.

## 2026-10-14 — Swap and state-file workflows, :SwapClean

### Added

- `:SwapClean` (`lua/config/autocmds/swap.lua`): reviews every swap in the
  swap folder, deletes the leftovers that hold no work (no running owner and
  no unsaved changes, or empty and over a minute old) after one confirm
  (default Cancel), and lists the kept ones with the reason. Two specs in
  `tests/behavior_spec.lua`.

### Docs

- New `docs/workflows/`: `swap-files.md` (where swaps live per OS, what each
  prompt means, recovering and comparing, `:SwapClean`, shell commands for
  Windows / Linux / macOS, avoiding leftovers) and `state-files.md` (undo
  history, ShaDa and E138, sessions, breakpoints, logs: locations, trimming,
  a periodic tidy-up).
- README: layout tree, a swap warning before the level-3 reset, pointers in
  Clearing caches. Cheatsheets: `:SwapClean` row (plugins.html), troubleshoot
  row and footer (workflows.html).

## 2026-10-14 — scoper: compile_commands filter off the main loop

### Changed

- scoper.nvim: reloads (scope edits, `:ScoperLspReload`) and the refresh after
  startup filter `compile_commands.json` in a background
  `nvim --clean --headless` process (new `scoper/cdb.lua` +
  `cdb_worker.lua`). On a 10k-entry database the editor was blocked for
  ~300 ms per filter; now ~30 ms, independent of database size. Startup never
  filters: without a previous filter result clangd starts on the unfiltered
  database and is switched once the filter is done. If the process can't run,
  the filter runs in Neovim as before (one warning). `clangd_cmd()` still
  filters synchronously, since it must return a ready cmd.

## 2026-10-13 — tree-sitter CLI install guide (README)

### Docs

- README: new **Installing the tree-sitter CLI** section (package manager when
  the version is ≥ 0.26.1, then `cargo install --locked tree-sitter-cli`, then
  GitHub release binaries; npm called out as unsupported). macOS Homebrew recipe
  installs `tree-sitter`; Linux defers to that section. Cheatsheet and
  `:checkhealth config` text point at the same order.

## 2026-10-13 — Audit fixes: 0.12 floor, built-ins over plugins, safer buffers and sessions

### Changed

- **Neovim 0.12.0 is the minimum** (was 0.11.2); nvim-treesitter's `main`
  branch requires it. The tree-sitter CLI must be 0.26.1 or newer, from a
  package manager, `cargo` or a release binary, not npm. `:checkhealth
  config` checks both. CI's 0.11.2 job is gone; the spec jobs run on stable.
- **C comments use `//`**, as in C++, instead of ts-context-commentstring's `/* */`.
- **clangd gets `--query-driver`** for the gcc / g++ on `PATH` and MSYS2's
  toolchains, so MinGW / MSYS2 compile databases find their system headers.
  MSVC projects need nothing.
- **stylua is no longer pinned:** CI installs the latest release, like Mason.
  When a release reformats code, run `:MasonToolsUpdate` and `make format`.
- **The gitcommit and git_rebase parsers install with the others** instead of
  on first use, which a short `$GIT_EDITOR` session could cut off.
- **Removed plugins, and their keys:**
  - Comment.nvim: Neovim's built-in `gc` / `gcc` comment instead. The
    block-comment keys `gb` / `gbc` are gone.
  - nvim-term: `<leader>tT` and `:NvimTerm*` are gone; use toggleterm.
  - mason-nvim-dap: `:DapInstall` / `:DapUninstall` are gone.
    mason-tool-installer (`lua/plugins/formatting.lua`) now installs
    debugpy, codelldb, cpptools and bash-debug-adapter.
- **Changed keys:**
  - `K` peeks a closed fold, else shows LSP hover, else runs Vim's own `K`
    (`'keywordprg'`, count kept), so it works in help, Vim script and man
    buffers again.
  - `]d` / `[d` are Neovim's built-ins (`]D` / `[D` jump to the last /
    first); the diagnostic float still opens after each jump.
  - `ZR` runs `:restart!`, so only auto-session saves and restores the
    session. `9ZR` restarts even with unsaved changes, discarding them.
  - `<Esc>` closes only LSP hover, signature-help and diagnostic floats and
    gitsigns previews; UI floats (treesitter-context, incline, fidget) stay.
  - Insert-mode `<C-k>` enters digraphs again; blink no longer takes it.
  - Punctuation undo breaks apply only in markdown, text and gitcommit
    buffers. In code, `.` repeats the whole insert.
  - The `<leader>w` session keys run `:AutoSession search|save|restore|delete`
    (the `:Session*` commands are deprecated).
  - Visual `<leader>sr` prefills grug-far's search with the selection.
  - Plugin defaults are back where the config had replaced them: grug-far's
    `<localleader>` keys (now with `\e`, `\x`, `\j` / `\k`, `\n` / `\p`,
    `\v`), neo-tree's `P` float preview, `<C-s>`, `<Tab>` and `<C-;>`, and
    fzf-lua's whole stock key set (only `<F1>`–`<F4>` worked before).
    grug-far's `]f` / `[f` stay.
  - The bufferline keys (`<S-h>` / `<S-l>`, which still replace `H` / `L`,
    `<leader>bm`, …) moved into bufferline's spec in `lua/plugins/ui.lua`.
- **Changed defaults:**
  - `'winborder'` is `rounded`, so core hover, signature-help and diagnostic
    floats have borders.
  - Formatting: a filetype with no formatter uses LSP formatting when a
    server offers it, else trims whitespace, and one whose formatter isn't
    installed falls back to LSP. shfmt follows the project's `.editorconfig`.
  - Trim-on-save leaves a file alone when EditorConfig sets
    `trim_trailing_whitespace`.
  - The swap prompt's default button follows the swap: Delete for a clean
    one, Open read-only (with a warning) when the file is newer than the
    swap, otherwise Recover.
  - Big-file mode also turns off regex syntax, ufo and LSP, and treesitter
    even where Neovim's own ftplugins start it (Lua, help, query, markdown).
  - autopairs is active in Vim script. lazydev completion runs only in Lua
    buffers.
  - Telescope loads on first use; bufferline loads at startup.
  - Windows: toggleterm terminals run `pwsh -NoLogo` when PowerShell 7 is
    installed (`'shell'` is unchanged). In the lazygit float, `<Esc>` reaches
    lazygit at once.
- **scoper.nvim:**
  - Telescope backend: "show full path" moved from `<C-p>` (telescope's
    previous-entry key) to `<M-p>`, in insert and normal mode; the path
    appears in the prompt title.
  - With `:ScoperToggle` off, or a scope without includes, Find / Grep /
    Replace search the whole cwd, without excludes.
  - `:ScoperExclude` without an argument prompts for a glob, and invalid
    globs are refused. `:ScoperAdd` warns about a directory that doesn't
    exist.
  - A scope change restarts only this project's clangd. The clangd `cmd` is
    per project, and extra `clangd_cmd()` arguments survive reloads.
  - The default scope gets `default_excludes`. scoper follows `:cd`, but not
    `:lcd` / `:tcd`.

### Fixed

- `<leader>bP` no longer force-deletes unpinned buffers with unsaved
  changes: they stay open, and splits keep their layout.
- Nerd Font icons are back (diagnostic signs, gitsigns deletes, dap-ui,
  neo-tree git symbols, lualine separators). They're `\u{…}` escapes in
  `lua/config/icons.lua` now, so a tool round-trip can't strip them again.
- Sessions: pinned buffers come back pinned, DAP and other tool windows are
  closed before saving, and per-tab buffers return to their tabs.
- Log points stay on disk; the next breakpoint change in another file used
  to erase them.
- `:SwapDelete` finds the swap of a file under your home folder.
- An unreadable swap file (empty or damaged) no longer stops a session
  restore with `E325`. The swap guard deletes an empty one and opens the
  file read-only over any other, with a notice; `:SwapDelete` then removes
  it. With `:SwapGuardToggle` off, the stock prompt is back.
- Windows: terminal-mode `<C-h/j/k/l>` work (they never applied), and
  cppdbg and codelldb run attached (`detached = false`).
- telescope's ui-select registers even when fzf-native failed to build.
- neogen: `<Tab>` jumps through the placeholders after `<leader>cd`.
- No parser downloads at startup without the tree-sitter CLI. A saved fold
  view isn't replayed over a file that changed on disk. LSP log rotation
  keeps `lsp.log.old` when the rename fails.
- Last-position restore skips commit and rebase messages again. Resizing
  equalises splits without firing scope.nvim's tab events.
- `:checkhealth config`: Mason tools aren't reported missing before Mason
  loads, `fdfind` counts as fd, the WindowsApps `python3` stub is flagged,
  and MSVC is found through vswhere.
- `:DiagnosticDump` starts with a "review before sharing" line.
- UI: catppuccin themes bufferline; lualine's git diff comes from gitsigns
  (no extra git jobs), and lualine uses its neo-tree, dap-ui, fzf-lua and
  other extensions.
- scoper.nvim:
  - Exclude globs match only below the project root, so a cwd under e.g.
    `build/` no longer empties the filtered `compile_commands.json`.
  - The fzf-lua, telescope and grug-far pickers honour absolute excludes,
    and apply excludes below includes outside the cwd, as `is_in_scope()`
    and the clangd filter do. grug-far's flags field splits at spaces, so
    a space in an exclude glob shows as `?` (any one character) there.
  - Windows: root-relative `\src`, drive-relative `C:foo` and `\\?\UNC\…`
    paths resolve correctly, and ripgrep and telescope excludes ignore case,
    like the clangd filter.
  - The clangd restart no longer stops a clangd started meanwhile, recovers
    from a failed poll and stays quiet with no clangd running.
  - The filtered compile database is cached by fingerprint; startup reuses
    the last result and refreshes it afterwards.
  - A corrupt state file is kept as a `.corrupt-<time>` copy. fzf-lua grep
    keeps its trailing `-e`. Command completion filters by what you typed.
  - `make lint` covers `plugin/` too, and so does the root `make check`.

### Docs

- README: the 0.12 floor and tree-sitter CLI advice, real install lists
  (formatters, shellcheck, debug adapters), a 0.12 built-ins table, and
  corrected recipes, layout tree, tweaks and testing sections.
- Cheatsheets: instructions that did the opposite of what they said are
  fixed (VS "move line", live-grep ` -- ` globs, diagnostics via
  `<leader>ld` / `]d` instead of `K`), and every key and default above is
  updated.
- Templates: `launch.json.example` is valid JSON for nvim-dap; the two
  clang-format templates produce identical `--dump-config` output; `.clangd`
  applies to C++ files only.
- Tooling: a new `.gitattributes` keeps LF in every checkout.
  `scripts/check-docs.sh` gained guards (scoper commands both ways, plugin
  rows, the version floor, template pairs, health titles, retired terms).
  The pre-commit hook checks the staged content. CI installs a current
  tree-sitter CLI.
- Changelog: dated entries from now on; the older ones are grouped as
  undated, and `docs/CHANGES-archive.md` says it is historical.

## Undated entries (before 2026-10-12), newest first

These predate dated entries and are kept as written, with their headings
moved two levels down. Their dates can't be recovered: the git history
starts at the audited snapshot of 2026-10-12. Still older entries are in
[docs/CHANGES-archive.md](docs/CHANGES-archive.md).

### Robustness pass: degraded environments

Exercised the config in environments that break assumptions: no
`rg`/`fd`/`fzf`/`lazygit` on PATH, no git, offline first start, no
plugins at all, a checkout path containing a space, `NVIM_APPNAME`, a
malformed `compile_commands.json`, a corrupt breakpoint store.

- **A failed lazy.nvim bootstrap no longer breaks startup.** With no
  git on PATH the clone raised `E475 … 'git' is not executable` as a raw
  traceback; a failed clone (offline, proxy) printed the error, waited for
  a key and **exited Neovim** — so a first start without network left no
  editor at all. Now both cases explain what failed ("starting WITHOUT
  plugins"), remove any half-cloned directory, skip the plugin layer and
  keep the core config (options, keymaps, autocmds); the next start
  retries. Verified with no git and with a git that fails like an offline
  machine; in that plugin-less mode the event sweep and core keymaps run
  without errors. New behaviour spec (runs a child Neovim with a fresh
  data dir and a git-less PATH).
- README: the no-make test commands are single lines that run unchanged
  in PowerShell, cmd.exe and POSIX shells (the old one used a bash line
  continuation).
- Checked, already robust: missing rg/fd → telescope names the missing
  tool; missing fzf → fzf-lua says so; missing lazygit → notice;
  malformed compile_commands.json → scoper falls back to plain clangd
  with a message; corrupt breakpoint store → no error on open; all
  suites and `make check` pass from a path with a space; the config
  installs and loads cleanly under `NVIM_APPNAME` (no hard-coded paths).
- Test-harness note: on Neovim 0.11, `vim.system(…, { clear_env = true,
  env = … })` also drops the `env` table; the new spec avoids clear_env.
  The config itself doesn't use clear_env.

---

### Deep pass: side effects on the user's data dir, health cleanups

New angles this time: `lua-language-server --check` over every Lua file
(55 findings, all annotation noise — `pcall(vim.cmd, …)` typed as a
table, busted's `assert.has_no`, duplicate-set in test stubs — except
the one below), the full `:checkhealth` with every plugin loaded, the
all-`<leader>` harness and the event sweep again, Windows code paths
(`.cmd` shims for Mason debug adapters, Scripts\python.exe, path case),
startup time (~50 ms).

- **Test runs wrote into the everyday Neovim package path.** Both test
  harnesses cloned plenary into `stdpath("data")/site/pack/test/start/` —
  a directory your normal Neovim treats as an auto-loaded package, and
  which `:checkhealth lazy` flags ("found existing packages"). Now
  `stdpath("cache")/test-deps/plenary.nvim`, added to 'runtimepath'
  explicitly; scoper's `make clean` and the README follow.
- **The colorscheme created `site/pack/core` at every startup.**
  catppuccin's integration auto-detection calls `vim.pack.get()` on 0.12,
  which creates that directory — leading to a second `:checkhealth lazy`
  warning and a `:checkhealth vim.pack` "lockfile is absent" warning.
  `auto_integrations = false` with the detected set spelled out
  (adds `blink_indent` and `mini`). Colors verified identical to before
  for eight representative groups. Correction to the previous entry:
  neo-tree / render-markdown colors were in fact already applied by that
  auto-detection; they're now explicit.
- **lazy.nvim rocks support off** (`rocks = { enabled = false }`): no
  plugin here is a luarocks rock, and the unused support made
  `:checkhealth lazy` report an ERROR for the missing luarocks.
- **`:DiagnosticDump`**: a log file that can't be seeked (a FIFO, some
  network shares) no longer errors on `nil > n`.

---

### Windows: Mason installs failing on a foreign `tar`

Reported: `Installation failed for Package(name=shellcheck) … tar.EXE:
unrecognized option '--no-same-owner'`, with `tar` resolving to a vendor
shell's copy (`…\ds_shell\…\tar.EXE`). Mason unpacks archives with
`tar --no-same-owner -xvf` (or `gtar` if present) and simply uses the
first `tar` on PATH; tars bundled with other tools (vendor shells, and
Git for Windows' GNU tar, which also misreads `C:\…` as a remote host)
break those installs.

- **`util.windows_tar_shim()`**, called from the Mason spec before
  `mason.setup()`: on Windows, when the first `tar` on PATH isn't
  `%SystemRoot%\System32\tar.exe`, System32's bsdtar is copied once to
  `stdpath("data")/tar-shim/` and that directory is put first on `$PATH`
  for this Neovim and its children. Only `tar` changes (putting System32
  itself first would also swap `find`, `sort`, …). No-op on other OSes,
  when `tar` already is System32's, or on Windows without tar.exe.
  Opt out: `vim.g.windows_tar_shim = false`.
- `:checkhealth config` (Windows) reports which tar Mason will get.
- README troubleshooting row for the error.
- Behaviour spec for the shim logic (forced Windows branch: copied once,
  prepended once, untouched when not needed or opted out). Not run on a
  real Windows machine from here — after updating, `:MasonInstall
  shellcheck` is the check.

---

### Toggle for linked tag editing

- **`<leader>lt` toggles linked tag editing** (Neovim 0.12+, buffers whose
  server supports it, e.g. html). Neovim has no per-buffer switch or
  `is_enabled()` for this feature, so the state is session-wide
  (`vim.g.user_linked_editing`, default on): the toggle applies to every
  supporting client and new clients attach in the chosen state. Verified
  in tmux: OFF → typing in `<span>` left `</span>` alone; ON again →
  `<sYYpan>…</sYYpan>`. keymaps cheatsheet row replaces the earlier note.

---

### Approved improvements: gI, linked editing, color toggle, theme, CI

- **LSP "go to implementation" is `gI`** (was `gi`), so Vim's built-in
  `gi` — resume insert where you last left it — works in LSP buffers
  again. keymaps and vs-to-nvim cheatsheets updated.
- **Linked editing (Neovim 0.12+).** For servers that advertise
  `textDocument/linkedEditingRange` (the html server does), editing an
  opening tag renames its closing tag as you type. Verified in tmux:
  inserting `XX` into `<span>` gave `<sXXpan>…</sXXpan>`. Guarded, so
  0.11.2 attaches exactly as before (checked).
- **Color swatches: `<leader>lc` toggle (0.12+).** Neovim 0.12 already
  highlights LSP document colors by default (verified: cssls → 2 color
  highlights for `#ff0000` / `rgb(…)`); the new buffer-local key turns
  them off/on, only where the server supports document colors.
- **catppuccin: neo-tree and render-markdown integrations** enabled
  (verified: `NeoTreeGitModified` and `RenderMarkdownH1Bg` now get the
  theme's colors).
- **Cheatsheet: Neovim 0.12's built-in selection keys** — `an`/`in`
  (expand/shrink by syntax node, also after an operator) and `]n`/`[n`
  (sibling node) in Visual mode. They were already active; nothing in
  the config maps them.
- **CI actions at their current majors**: checkout v7, setup-node v7,
  cache v6, gh-actions-lua v13, gh-actions-luarocks v6 (all node24;
  action-setup-vim v1 is current). Checked each action.yml: every input
  the workflow passes still exists. Not run on GitHub from here.
- **README: "Neovim 0.12 features deliberately not enabled"** —
  `'autocomplete'` (blink.cmp already covers completion; how to switch)
  and the experimental ui2 (why it's off; one-line command to try it).

---

### Whole-repo pass: stale text, dead options, small gaps

Checked: `make ci` end to end; a hygiene scan of every text file (CRLF,
final newline, trailing whitespace, tabs in Lua: none); shellcheck on
`scripts/check-docs.sh` and the pre-commit hook (clean); the hook itself
in a scratch clone (it blocks a mis-formatted/unparsable staged file);
`clang-tidy --verify-config` on the `.clang-tidy` template (no errors);
`:checkhealth config` (only the expected clang-tidy / cargo warnings);
every `:Command` named in the READMEs; the neo-tree commands the config
maps; getcmdcompltype() for all shell/filter command-line forms on
0.11.2 and 0.12.5; that Neovim's default LSP `K` doesn't shadow ufo's
peek (it only maps when K is unmapped — ours is global, so it stays).

- **trouble.nvim: dead option removed.** `use_diagnostic_signs` is a
  trouble v2 setting; v3 (installed) doesn't have it and ignored it.
- **`]q` / `[q` take a count** (`3]q`), like `:3cnext`, when trouble
  isn't open (verified: `2]q` from entry 1 lands on entry 3).
- **`:DiagnosticDump` also tails `lsp.log.old`.** The log rotation at
  startup moves a large log to `.old`, which after a hang + restart is
  where the relevant lines are; the dump only read the fresh file
  (verified with a marker line).
- **`.luacheckrc`** no longer ignores whitespace warnings (611/612):
  stylua already guarantees clean whitespace, so they could only hide
  slips. Still 0 warnings.
- **Stale text**: `.editorconfig`'s header still called stylua a
  "destructive opt-in" with no format gate, and it and the keymaps
  cheatsheet pointed at the old `lua/config/autocmds.lua`; a leftover
  `_G.__bufferline_user` note in util.lua. The completion comment on the
  shell-command skip now states what was verified (getcmdcompltype()
  covers every form; the pattern is only a second guard).

---

### Cheatsheet and example check

Automated: every `:Command` named in the cheatsheets (69) checked with
every plugin loaded; every `<kbd>` key (432) compared against the real
mappings (the rest reviewed by hand: Vim built-ins, buffer-local LSP /
gitsigns keys, grug-far's localleader keys, atone's and diffview's
in-pane keys — all confirmed in the plugins' sources); every
`:checkhealth` target; every repository path named in the docs; the keys
named in the templates. The worked examples were executed: `gzaiw)`,
`gzaip"`, `gzr"'`, `gzd"`, `gcc`, `gcap`/`gcip`, visual `gc`,
`*` + `cgn` + `.`, `:norm I//`, `:norm 0i//`, `<C-v>…I`, `yyp` — all do
what the docs say.

- **`:TSInstallInfo` doesn't exist** on nvim-treesitter's `main` branch;
  the treesitter card now lists `:TSUninstall` and points to
  `:checkhealth nvim-treesitter` for the parser list.
- **LSP commands on the 0.11.2 floor:** the card presented `:lsp …` as
  the commands and the lspconfig ones as "was". `:lsp` only exists from
  0.12, and on 0.11 nvim-lspconfig still provides `:LspInfo`/`:LspStart`/…
  (verified on both versions); the note now says which to use where.
- `:checkhealth lsp` is the same report as `:checkhealth vim.lsp`
  (verified); the README/card no longer describe them as different, and
  the duplicate row is gone.
- `gcap` also comments the blank line after the paragraph (as a bare
  `--`); the workflows card says so and names `gcip` for the paragraph
  alone.

---

### More debugging runs: completion, snippets, pickers, editing plugins

- **Bug: friendly-snippets were never available.** blink uses
  `snippets.preset = "luasnip"`, so its snippet source only offers what
  LuaSnip holds — and nothing loaded friendly-snippets into LuaSnip:
  `#require("luasnip").get_snippets("lua")` was 0, and the only
  "snippets" in the menu were lua_ls's own. Fix: LuaSnip's config calls
  `require("luasnip.loaders.from_vscode").lazy_load()`, and
  friendly-snippets is now LuaSnip's dependency (as a sibling under blink
  it reached 'runtimepath' after LuaSnip's config ran, so the loader still
  found nothing — verified). After: 24 Lua snippets; in tmux `fori` +
  `<C-y>` expands and `<Tab>` walks the placeholders. New behaviour spec
  (fails on the previous config).
- Checked, working: member completion after a trigger character (`.`
  still triggers although it carries an undo-break mapping), telescope
  find_files / live_grep / help_tags / keymaps / git_files /
  lsp_document_symbols (all return results), fzf-lua files and live_grep,
  LSP rename across a file, `<leader>lh` inlay-hint toggle, grug-far
  actually writing a replacement, mini.align, Comment.nvim `gbc`,
  nvim-autopairs, the which-key popup, flash `s` labels.

Tests: 19 behaviour specs.

---

### Docs: inserting on every line of a mouse selection

A mouse drag starts characterwise Visual mode, where `I` inserts once at
the start of the selection — standard Vim/Neovim behaviour (checked in
`nvim --clean`: only blockwise Visual inserts on every line), not a config
issue; no mapping touches `I` and `'selectmode'` is empty. Behaviour left
unchanged; the alternatives are now documented:

- vs-to-nvim (Selection & multi-edit): drag then `<C-v>` then `I`;
  Alt+drag for a block directly (works via `'mousemodel'` popup_setpos,
  terminal-dependent); keyboard `<C-v>` … `I`; `:norm I…` / `:norm 0i…`
  on any selection.
- keymaps (Visual): a short row pointing there.

---

### Gap check: flows not exercised before

Exercised end to end for the first time: blink completion from lua_ls
(tmux: menu shown, `vim.api.nvim_buf_get_name(buf)` accepted), gitsigns
detecting and staging a hunk, diffview open/close, `:DiagnosticDump`,
`:FormatToggle`/`!`, render-markdown, ufo folds + `K` peek, toggleterm,
`:TodoTrouble`, neo-tree, atone, breakpoints restored after a restart,
and a session save/restore with two tabs and a split (after the helper
refactor).

- **Bug: formatting a visual selection with stylua did nothing.**
  conform passes the offset of the selection's last character as
  `--range-end`, but stylua only reformats statements that end before
  that offset, so a linewise selection never covered its own last
  statement. conform.log showed `--range-end 14` for a 15-character line
  and unchanged output; the stylua CLI formats with 15. The stylua
  `range_args` are overridden with the end offset + 1. Verified: only
  the selected line changes. clang-format's range formatting was already
  correct (checked the same way).
- Not bugs: `]q` from a fresh quickfix list goes to the second entry
  (`:cnext` semantics) and reports "No more items" at the end.
- New behaviour spec (18): visual `<leader>cf` formats only the
  selection.

---

### Cleanup + quality-of-life pass

#### Structure

- `lua/config/autocmds.lua` (885 lines) is now `lua/config/autocmds/`,
  one module per topic, loaded in the original order by `init.lua`:
  `editing`, `bigfile`, `glue`, `folds`, `lsplog`, `swap`. Every
  reference in comments and docs points at the new files.
- The nvim-dap setup body (pause override, signs, `:DapLoadLaunchJSON`,
  adapters, fallback configurations) moved to `lua/config/dap.lua`;
  `lua/plugins/dap.lua` keeps the plugin specs and keymaps (768 → 421).
- `util.is_file_buffer(buf)` is the single "real file buffer" test (buftype
  "", named, not a `scheme://` URI), used by fold views, the LSP attach
  guard and session handling instead of four hand-written checks.
  `util.augroup()` replaces per-file copies.
- The `_G.__bufferline_user` global is gone: ui.lua registers the buffer
  menu as `util.buffer_menu`, which `<leader>bm` opens.
- catppuccin no longer enables its nvim-cmp integration (not installed).

#### Comments

- `options.lua` 305 → 188 lines; the longest comment blocks elsewhere
  (swap guard, treesitter header, undo-break keys, atone, lazydev, LSP-log
  rotation, session filetype fallback) condensed to what the code does and
  why. Comment lines in `lua/` roughly 1,400 → 1,080.

#### Quality of life

- `<A-j>` / `<A-k>` take a count (`3<A-j>`) in normal and visual mode,
  clamped at the file edges.
- `<leader>wc` in the last window says what to do instead of E444.
- Missing treesitter parsers install on first use: opening a filetype
  nvim-treesitter supports but `PARSERS` doesn't list builds its parser in
  the background and then highlights the open buffers (verified with an
  `.ini` file). Opt out: `vim.g.treesitter_auto_install = false`.
- Big-file threshold is `vim.g.big_file_size` (bytes, default 1 MB), read
  at each open.
- Not changed: an inline "diagnostics under the current line" toggle was
  proposed, but `<leader>lv` already does exactly that.

Tests: 2 new behaviour specs (17): counts and edges for line moves,
`<leader>wc` in the last window. All suites pass on 0.12.5 and 0.11.2;
`:SwapDelete`, `:SwapGuardToggle`, `:DapLoadLaunchJSON`, `<leader>bm` and
all four debug adapters re-checked after the moves.

---

### Bug sweep over lua/

Method: `:checkhealth` with every plugin loaded, a harness that fires
all 130 `<leader>` maps on a C++ buffer with clangd attached (prompts
stubbed) and reports errors, an event sweep (opening each filetype,
writing into a new directory, help, terminal, quickfix, tabs, a git
commit buffer, `:wall`, FocusGained, VimResized, a >1 MB file), plus a
read-through.

- **`gr` (references) waited out `timeoutlen` on every press on Neovim
  0.12.** The config deleted the default `grr/grn/gra/gri/grt` maps from
  a fixed list, but 0.12 added `grx` (codelens run), which made `gr` an
  ambiguous prefix again (reported by which-key's health check). The
  defaults are now found and deleted by discovery: every `gr<x>` map
  whose description names a `vim.lsp` function.
- **Language servers attached to virtual buffers.** Opening a C++ diff in
  diffview gave the `diffview://` buffer (buftype "", filetype cpp)
  clangd, which rejected every request: "clangd only supports 'file' URI
  scheme", printed repeatedly. The LspAttach handler now detaches from
  any buffer whose name is a non-`file://` URI.
- **Fold views for virtual buffers.** Such buffers were also eligible
  for mkview/loadview (`E484: Can't open file …/view//diffview:=+…` in
  the sweep). URI-named buffers are excluded.
- **mini.surround advertised visual-mode actions it doesn't have.**
  gzd/gzr/gzh/gzn were registered in visual mode too; mini only maps
  gza/gzf/gzF there, so e.g. `gzd` on a selection fell through to Vim —
  `gz` is no command and the trailing `d` deleted the selection
  (reproduced). Visual stubs now only for gza/gzf/gzF.
- **`<leader>bd` could fail half-way with a Lua traceback** when the
  replacement buffer's load raised (the sweep hit `E325: ATTENTION` from
  a swap-file prompt inside `nvim_win_set_buf`). The window switch is
  now guarded and falls back to `[No Name]`.
- Checked, no problem: the other harness hits were expected behaviour
  (`<leader>wc` in a single window, `<leader>lr` off a symbol, neo-tree's
  own `silent! autocmd! FileExplorer`, and which-key's `<leader>?`, which
  works interactively). Event sweep: no errors; trailing whitespace
  trimmed on write, parent directory created, big-file mode on.
- 4 new behaviour specs (15 total): no `gr<x>` defaults left, visual
  surround stubs, no view file for URI buffers.

---

### scoper.nvim bug sweep

Every module re-read; each bug below was reproduced before the fix.

- **Excludes meant different things in different places.** The pickers
  hand excludes to ripgrep / fd, which treat `build` or `*.o` as "any
  path component, any depth", but `is_in_scope()` — which filters the
  compile_commands.json clangd gets — only matched the whole path. So
  `:ScoperExclude build` hid `src/build/a.c` from `:ScoperFind` yet kept
  it for clangd (reproduced side by side with rg and fd). New
  `Path.match_exclude()` implements the rg/fd (gitignore-style) rules:
  slashless patterns match any component, patterns with `/` match the
  relative path or a parent, a trailing `/` is accepted.
- **Telescope backend excluded too much, and nothing on Windows.**
  Excludes became unanchored Lua patterns, so `build` also hid
  `builder/` and `*.o` hid `x.oo`; and they only matched `/`, while
  telescope shows backslashed paths on Windows. They are now
  component-anchored and match either separator
  (`pickers._glob_to_lua_pats`).
- **Two Neovim instances in one project overwrote each other's scope
  edits.** Each kept the state in memory and the last save won.
  Mutators now re-read the state file first when its mtime changed
  (test fails on the old code: the other instance's include vanished).
- **Every scope edit restarted clangd**, even edits that changed nothing
  clangd sees — e.g. any edit while scoping is OFF (reproduced: client id
  went 2 → 3 for an exclude added while off). Automatic reloads now skip
  the restart when the cmd and the filtered database are unchanged
  (identical content is no longer rewritten either); `:ScoperLspReload`
  still always restarts. Verified step by step: enable/disable and a
  database-changing exclude restart, no-op edits don't.
- **Late timer ticks during a clangd reload** could run after the
  timer was closed (busy main loop) and call `stop()`/`close()` on a
  closing handle and re-attach twice; guarded.
- **Directories with spaces on the command line.** `:ScoperAdd` split
  on every space, but tab completion inserts `my\ dir`, which became
  the two paths `my\` and `dir`. Escaped spaces are now kept (Windows
  `\` separators untouched). The directory picker unescapes what its
  completion inserts, and `:ScoperRemove` completes from the scope's own
  entries instead of the filesystem.
- **Plain-vim grep fallback**: a search with no hits threw E480 as an
  error, and the scope's excludes were ignored (vimgrep can't take
  them). "No matches" is now a message and results are filtered through
  `is_in_scope()`.
- 8 new specs (scoper 77 → 85): split_args escaping, match_exclude,
  telescope pattern anchoring incl. Windows paths, two-instance state.
  README: exclude semantics, the reload rule, escaped spaces,
  two-instance note.

---

### Docs brought up to date with the audit

- **README**
  - Testing: the three suites and what each covers (smoke with lazy
    actually loading, duplicate `<leader>` check across keymaps.lua AND
    lazy `keys`, `behavior_spec.lua`); new make targets (`fmt-check`,
    `format` on both trees); CI now runs stylua and a stable + v0.11.2
    matrix; the hook's stylua gate. Layout tree lists
    `tests/behavior_spec.lua`.
  - Health: fzf < 0.45 warning and the `'exrc'` note.
  - Sessions: the new "started with files" save rule, the suppressed
    directories, and saving while debugging.
  - Install: fzf added to the Windows/macOS lines. On Debian/Ubuntu the
    `apt` Neovim is below the 0.11.2 floor and apt's fzf (0.44) too old
    for some fzf-lua pickers, so both now point at the upstream
    releases. A note that `tree-sitter --version` must work and that
    `make check` matches CI only with stylua 2.5.2.
- **Cheatsheets**
  - keymaps: fzf-lua `<C-x>` (buffers and `:FzfLua tabs`), neo-tree
    buffers view `d`/`bd`, `<leader>dB` cancel rule.
  - debugging: `<Esc>` at the executable prompt cancels; a failed launch
    closes the UI; saving mid-debug keeps the program; Python interpreter
    order; `<leader>de`/`<leader>dw` are n + x (not v).
  - plugins: breakpoint store location (`nvim_checkpoints/`, per cwd),
    `<leader>cf` formats this config too, prettierd / shellcheck,
    neo-tree buffers `d`, format-on-save wording.
  - workflows: `<leader>dB` wording; first-run checklist includes the
    tree-sitter CLI and fzf ≥ 0.45.
- **scoper.nvim README**: Windows case-insensitivity, paths with
  spaces/commas per backend, test coverage, `make fmt-check` / `check`.
- Verified: all 8 cheatsheets parse with balanced tags, every
  `<leader>` key named in the docs exists (the four flagged are
  diffview's own merge-tool keys), `check-docs.sh` passes.

---

### Debugger audit

All four adapters (codelldb, cppdbg, debugpy, bash-debug-adapter) were
exercised against real programs before and after these changes.

- **Bug: saving the session while debugging killed the program being
  debugged.** The session pre-save hook always ran `dap.terminate()` and
  wiped the `[dap-*]` buffers — correct when quitting, but it also runs
  for `:AutoSession save` and when switching sessions. Reproduced: the
  debug session was gone after a manual save. Now it only terminates
  when Neovim is actually exiting (`v:exiting`); a mid-session save just
  closes the dap windows so they stay out of the session file, and
  reopens dap-ui afterwards (`post_save_cmds`). Verified: debuggee still
  running, UI back, no `dap-` names in the saved session; on `:qa` the
  debuggee is still terminated and the next restore is error-free.
- **Bug: `<Esc>` at the "Path to executable" prompt launched anyway.**
  The fallback configs returned the empty string, so cppdbg failed with
  "property 'program' is missing or empty" (and left 5 empty dap-ui
  panels open), codelldb with "'<cwd>' is not a valid executable". Empty
  input or the pre-filled directory now returns `dap.ABORT` ("Run
  aborted"); shared `ask_program()` for all three prompts.
- **Bug: dap-ui panels stayed open after a failed launch/attach.** A
  failing launch ends without a terminated/exited event, so the
  auto-close never ran. The UI now closes on an error reply to
  `launch`/`attach`. Verified with a nonexistent program on cppdbg and
  codelldb: 0 panels left.
- **Bug: `<leader>dB` never offered a hit count.** It called
  persistent-breakpoints' `set_conditional_breakpoint()`, which only
  prompts for a condition (and turns a cancelled prompt into a plain
  breakpoint), although every cheatsheet promised "condition + hit
  count". It now asks for both, cancels when both are empty, and
  persists the result (hit count verified in the store).
- **Python: project virtualenvs are found without activation.** The
  interpreter is picked from `$VIRTUAL_ENV`, then `$CONDA_PREFIX`, then
  `./.venv` / `./venv` in the cwd (uv / poetry / `python -m venv`
  layout, `Scripts\python.exe` on Windows), then PATH.
- **codelldb: 10 s connect budget instead of 3.5 s**
  (`options.max_retries = 40`) for slow cold starts (Windows Defender);
  a normal start (~0.4 s here) is unaffected.
- Comments corrected: persistent-breakpoints stores one file per cwd
  under `nvim_checkpoints/` (not `breakpoints.json`) and has no change
  listener; the disabled `js`/`delve` adapters are explained in one
  block instead of a formatter-mangled column.
- 2 new behaviour specs (prompt cancel → ABORT; `.venv` discovery) —
  12 total.

---

### Path handling audit (cross-platform)

- **Bug: grug-far paths with spaces matched nothing** (`<leader>sf` and
  `:ScoperReplace`). Both quoted such paths with double quotes, but
  grug-far splits its `paths` field on spaces itself and only understands
  a backslash-escaped space; the quotes reached ripgrep as literal
  characters. Verified with the real plugin: `"sp ace/x.txt"` found 0
  matches, `sp\ ace/x.txt` found the file. Both now escape spaces only,
  which leaves Windows `\` separators intact (`scoper.pickers._grug_path`).
- **Bug: `:SwapDelete` missed crash leftovers when `'directory'` contains
  `.`**. In `'directory'`, `.` means "the edited file's directory", but the
  scan used the cwd. Reproduced with `directory=.`, a killed Neovim and the
  cwd elsewhere: before, "no leftover swap"; after, the leftover is listed
  for deletion. `~`/`$VAR` in `'directory'` are now expanded too.
- **Bug (Windows): session suppression never matched most entries.**
  auto-session compares `suppressed_dirs` to `getcwd()` as plain strings,
  and `getcwd()` uses backslashes on Windows. The config converted `%TEMP%`
  to forward slashes and listed `~/Downloads` and `/`, so on Windows only
  `~` itself worked. Entries are now expanded, realpath-resolved (handles
  8.3 short `%TEMP%` names and macOS's `/var → /private/var`), and added
  in both separator styles on Windows (`'shellslash'` flips `getcwd()`),
  plus the system drive root. Linux verified; the Windows branch follows
  auto-session's comparison code but could not be run here.
- **scoper, Windows case-insensitivity.** NTFS ignores case, scoper
  mostly did not:
  - `:ScoperAdd src` after `Src` added a duplicate, and `:ScoperRemove SRC`
    removed nothing — both now compare `Path.key()` (normalized,
    lower-cased on Windows; unchanged elsewhere).
  - Exclude globs are matched case-insensitively on Windows
    (`**/Build/**` now excludes `build/`).
  - Project identity (state file and compile_commands cache) is hashed
    from `Path.key(cwd)`, so `C:\Proj` and `c:\proj` are one project.
    State files written under the old case-sensitive hash are still read
    and migrate on the next save.
- **scoper `:find` fallback: commas in dir names.** The comment said
  commas "can't be represented in 'path'"; they can, escaped with a
  backslash (verified with `findfile()`). `_find_path` now escapes commas
  as well as spaces.
- New tests: 2 pickers specs (comma/space `'path'`, grug-far escaping),
  2 path specs and 2 state specs for the Windows-case rules (scoper
  71 → 77).

---

### Same bug class elsewhere: stock buffer deletes that close windows

Follow-up to the telescope `<M-d>` fix: every other plugin action that
deletes a buffer was checked for the same problem (a stock
`nvim_buf_delete`, which closes every window showing the buffer).

- **Bug: neo-tree buffers view `d` / `bd`** (`<leader>be`). neo-tree's
  stock `buffer_delete` calls `nvim_buf_delete` directly. Reproduced:
  deleting a buffer shown in a split took the layout from 2 windows to 1,
  and on a modified buffer the mapping threw a Lua error
  (`commands.lua:32: Failed`). Both keys now go through
  `delete_buffer_keep_windows`: split kept, dirty buffer skipped with the
  usual message, no error.
- **Bug: `:FzfLua tabs` ctrl-x.** The tabs picker (buffers grouped by
  tab) has its own stock `buf_del`, separate from the buffers picker.
  Reproduced: ctrl-x on a buffer visible in a split left 1 window instead
  of 2. It now shares the buffers picker's action (defined once as
  `fzf_delete_buffers` in finder.lua).
- **`:checkhealth config` warns about fzf older than 0.45.** fzf-lua
  uses fzf's `transform` action; with Ubuntu's packaged fzf 0.44.1,
  `:FzfLua tabs` failed with "unknown action: transform" and never
  opened.
- Checked, no problem: bufferline (close button, `<leader>bJ`, close
  others/left/right — all via `close_command`), telescope's scope
  extension (`<leader>fB`, no delete mapping), scope.nvim's own close
  (not used), the bufferline menu when focus leaves it, every
  `<cmd>…<cr>` keymap target (29 commands exist after loading all
  plugins) and every `require()` literal in the config (45 modules).
- Fixed a comment in keymaps.lua that the formatter had joined into one
  overlong line.
- New behaviour spec for the neo-tree action (10 specs total).

---

### Buffer pickers: one shared delete action, <M-d> made layout-safe

Telescope and fzf-lua both stay (their behaviour differs on purpose),
but their buffer-delete actions are now one function.

- **Bug: telescope's `<M-d>` closed splits.** Telescope binds `<M-d>`
  (insert and normal mode) in its buffers picker to the stock
  `actions.delete_buffer`, which closes every window showing the buffer —
  exactly what the custom `<C-d>` avoids. Reproduced on the previous
  config: `<M-d>` on a buffer visible in a vertical split left 1 window
  instead of 2. `<M-d>` now runs the same safe action as `<C-d>`.
- **New `util.delete_buffers_from_picker(bufs)`** holds the whole
  decision both pickers used to spell out separately: one target → the
  per-buffer delete with its "why not" message; several → the batched
  delete with one summary. Telescope's `<C-d>`/`<M-d>` and fzf-lua's
  `<C-x>` now only map their entries to bufnrs and refresh the list.
  finder.lua shrank from 395 to ~350 lines.
- Behaviour preserved and re-verified in tmux on both pickers: single
  dirty buffer → "Skipped (unsaved changes)"; multi-select → one
  "Deleted N buffer(s); skipped …" summary; a buffer visible in a split
  is deleted without closing the split; the picker stays open with the
  deleted rows removed. One nuance: fzf-lua now counts only entries that
  resolve to a buffer when choosing single vs batched (only reachable
  with non-buffer rows, which its buffers picker doesn't produce).
- 2 new behaviour specs for the shared helper (9 total).

---

### Pass 4: behaviour specs, stylua enforced, prettierd, comment cleanup

#### Tests

- **The "full config" suite had never loaded a single plugin.** The
  runner starts Neovim with `--noplugin`, and lazy.nvim's `setup()`
  returns immediately when `'loadplugins'` is off — so no plugin spec was
  ever parsed, no plugin `keys` reached the duplicate-keymap check, and
  nothing plugin-backed could be tested. `tests/minimal_init.lua` now
  re-enables it for lazy, and a new sanity spec asserts lazy loaded >10
  plugin specs.
- **Duplicate `<leader>` check now covers lazy `keys` specs.** Lazy's own
  stub→real re-registration is tagged and skipped in the raw log; keys
  are compared from lazy's spec table instead. Proven by injecting a
  duplicate between two specs and between keymaps.lua and a spec — both
  fail the test.
- **New `tests/behavior_spec.lua`** (7 specs) for the audit fixes: bulk
  delete of a running terminal, split kept when deleting a buffer shown
  twice, bufferline close on a modified buffer (window and file
  untouched), fold view saved from another tab, `<leader>cf` through
  stylua keeping `-- stylua: ignore` ranges, `<Esc>` sparing hidden
  floats, visual `<A-j>` at the file edge. Run against the pre-audit
  code, 5 of the 7 fail.

#### Formatting: stylua is now enforced

- Both trees are stylua-formatted. Hand-aligned runs (option lists,
  keymap tables, icon maps — 86 ranges) were fenced automatically with
  `-- stylua: ignore start` / `-- stylua: ignore end`, so their columns
  are unchanged. `collapse_simple_statement = "ConditionalOnly"` keeps
  one-line `if … then return end` guards.
- `make check` = luacheck + `stylua --check` in both trees; new
  `make fmt-check`; `make format` formats both trees. CI's lint job
  installs stylua pinned to 2.5.2. The pre-commit hook checks staged Lua
  when stylua is installed.
- Consequently the "never format this config's own files" guard
  (stylua `condition`, `<leader>cf` refusal, `is_config_file`) is gone:
  formatting these files is now the intended behaviour.

#### Other

- `prettierd` is auto-installed. Before, JS/TS/JSON/YAML/Markdown/HTML/
  CSS were routed to prettier but nothing installed it, so they fell
  back to LSP formatting or none. Verified: a messy .ts and .yaml file
  now format.
- auto-session saves when launched with file arguments only if the
  session grew to 2+ file buffers or 2+ tabs, so a quick `nvim foo.c`
  edit never overwrites the project session.
- `:checkhealth config` reports when `'exrc'` is on and how to revoke
  trust.
- Code comments no longer narrate past bugs ("an earlier version…");
  they say what the code does and why. That history lives here.
- Older changelog entries moved to `docs/CHANGES-archive.md`.

Tests: config 5/5 + behaviour 7/7, scoper 71/71; luacheck and
stylua --check clean in both trees.

---

### Audit pass 3: treesitter, every LSP/DAP, scoper end-to-end, startup

With the tree-sitter CLI installed and all 27 parsers built, the parts
that could previously only be read were exercised on Neovim 0.12.5.

#### Fixed

- **bashls produced no diagnostics.** bashls only relays shellcheck,
  which nothing installed. `shellcheck` is now in mason-tool-installer's
  list; a script with an unquoted `$var` and an unclosed `if` went from
  0 diagnostics to 3.
- **Startup: ~82 ms → ~56 ms (no file).** mason-tool-installer's default
  integrations `pcall(require, "mason-lspconfig")` and
  `require("mason-nvim-dap.mappings.source")`, which lazy.nvim turned
  into full plugin loads at startup — defeating both specs' lazy
  triggers. The list uses Mason package names, so the integrations are
  now off. Auto-install verified still working (shfmt removed →
  reinstalled on the next start).
- **`:checkhealth config` now checks `cargo`.** Without it rust_analyzer
  logs "cargo not found" and never attaches (observed).
- **Format-on-save example.** The commented table form would have let
  the LSP fallback reformat this config's own files; the example (and
  the README tweak) now use the function form with `is_config_file()`.
  *(Reverted in Pass 4: the `is_config_file()` guard is gone, because
  formatting this config's own files became the intended behaviour. The
  function form stays.)*
- **`lazy-lock.json` added**, pinning the 56 plugins to the revisions
  tested here; README explains `:Lazy restore` / `:Lazy update`.

#### Verified, no change needed

- Treesitter: highlighting, indentexpr (`o` after `if a:` → 8 spaces),
  `]f`/`[f`, `]a`, `vaf`, neogen docstrings, ufo folds on C++ (lsp with
  treesitter fallback), ts-context-commentstring (`gcc` in JSX →
  `{/* … */}`, in TS → `//`).
- LSP: ts_ls, yamlls, marksman, bashls, jsonls, html, cssls, taplo attach
  and report; pyright/ruff/lua_ls/clangd as before.
- DAP: debugpy, bash-debug-adapter and cppdbg (gdb) each stop at a
  breakpoint; codelldb as before.
- scoper on a real two-directory project: filtered compile_commands
  (1/2 entries), clangd attaches with `--compile-commands-dir` pointing
  at it, find/grep restricted to the scope, quoted rg exclude.
- Every `<leader>` key named in README + cheatsheets (331) exists;
  `<leader>co/ct/cb/ca` are diffview's own merge-tool maps.
- `rhysd/action-setup-vim` accepts `v0.11.2`.
- Startup with a parser set present shows no messages at all.

#### Investigated, left as is

- Opening a C++ file costs ~260 ms more than other types: compiling the
  C++ highlight queries; identical in `nvim --clean`.
- `vim.lsp` is loaded at startup by scoper's setup so clangd is filtered
  from its very first start; ~1.6 ms warm.
- Telescope empty-on-first-open: not reproducible in three attempts.

Not testable here: Rust (no cargo in the sandbox) and Windows.

Tests: config 4/4 and scoper 71/71 on both 0.12.5 and 0.11.2.

---

### Audit pass 2: runtime verification, the "left alone" list, CI floor

Follow-up to the audit below. Everything here was exercised against the
installed plugin set on Neovim 0.12.5, and the test suites also on the
declared 0.11.2 floor.

#### Bugs fixed (reproduced before, verified after)

- **Fold state was only saved for the current window on quit.** The
  mkview autocmd required the leaving buffer to be current. While
  quitting, each window's BufWinLeave fires with some other buffer
  current, so any fold closed in a non-current window (e.g. tab 1 when
  you quit from tab 2) was lost. The save now runs inside the window
  showing the buffer, found across all tabs with `win_findbuf()`
  (`bufwinid()` only searches the current tab). Before: no view file
  written; after: view written, fold closed again on the next launch.
- **`<leader>cf` reformatted this config's own files anyway.** The
  stylua `condition` removed stylua, but `lsp_format = "fallback"` then
  handed the buffer to the language servers. Test: `local    zz   =
  {1,2}` became `local zz = { 1, 2 }`. `<leader>cf` now refuses with a
  message for files inside the config (realpath-resolved, via the shared
  `is_config_file()`). *(Reverted in Pass 4: `<leader>cf` formats this
  config's own files again, now that stylua is enforced on them.)*
- **stylua was running as a second language server on every Lua
  buffer.** It has an lspconfig definition, so mason-lspconfig's
  automatic_enable started it just because Mason had installed it for
  conform. Now excluded (`automatic_enable = { exclude = { "stylua" } }`).
- **First `gcc` of a session bypassed Comment.nvim.** Neovim's default
  `gcc` map is an exact match and beat lazy's `gc` stub, so the plugin
  (and ts-context-commentstring) never loaded on it. `gcc`/`gbc` are
  now lazy keys too.
- **No LSP for buffers without a file.** `:enew` + `:set ft=lua` never
  loaded the LSP stack (only BufReadPre/BufNewFile triggered it).
  `FileType` added; verified lua_ls attaches.
- **scoper: a hand-edited state file with `null` crashed.** JSON null
  decodes to vim.NIL (truthy), which slipped past `x or {}`. Types are
  now checked; new state_spec test fails on the old code.
- **`<Esc>` destroyed smear-cursor's window pool.** It closed every
  non-focusable float, including smear-cursor's pool of hidden floats
  (measured 70–400). Hidden floats and smear-cursor are now skipped.

#### Smaller improvements

- Window zoom: if splits were opened/closed while zoomed, un-zoom now
  equalizes instead of replaying a stale `winrestcmd()` onto the wrong
  windows.
- find_files excludes `.git/` in the fd/rg command itself instead of
  listing it and filtering afterwards.
- incline also loads on BufNewFile.
- The lsp.log rotation requires `vim.lsp.log` directly instead of
  touching `vim.lsp` (another plugin still loads `vim.lsp` at startup,
  so no measurable gain today — but the rotation no longer depends on it).
- `smartindent` removed: ignored wherever an indentexpr exists, and in
  the remaining buffers its C rules misfire (a `#` line jumps to col 0).
- Session rescue never re-lists gitcommit/gitrebase/gittag buffers.
- mini.surround / mini.align point at the `nvim-mini` org (the old URLs
  redirect; the next `:Lazy sync` re-clones — verified).
- Documented: `]a`/`[a` override Neovim 0.11's argument-list maps (kept
  on purpose); why `<C-\>` isn't mapped in terminal mode; auto-session
  only saves when started without file arguments, and drops a tab whose
  only window holds a never-written file.

#### CI

- Both Neovim jobs now run a matrix of `stable` and `v0.11.2` (the
  MIN_NVIM floor), which was previously promised but never tested.
- Node comes from `actions/setup-node`; Ubuntu's `nodejs` apt package
  has no npm and only shadowed the runner's own node.
- The plugin cache key includes `lazy-lock.json` when present.

#### Docs / templates

- README health section lists the tree-sitter CLI (required), curl/wget
  and tar; plugin table uses the `nvim-mini` names.
- launch.json template referred to a nonexistent `<leader>cb`.
- Validated with the real tools: `.clang-format` + example parse
  (clang-format 23), `.clangd` loads (`clangd --check`: 0 errors),
  `.clang-tidy` has no unknown options, launch.json yields 9 configs in
  nvim-dap.

#### Verified working, no change needed

codelldb session (breakpoint, dap-ui, pause without picker, terminate
closes UI); telescope `<C-d>` bulk delete keeping splits; fzf-lua
`<C-x>`; swap guard with two live instances; session restore of
per-tab buffers; pyright hover with ruff's disabled; neo-tree; grug-far;
the whole config on Neovim 0.11.2.

#### Known, not fixed

- Telescope's buffer picker can render an empty list the first time it
  is opened in a session (fine on every later open). Seen in tmux only.
- Startup time could not be measured meaningfully here: without the
  tree-sitter CLI every launch retries 27 parser builds.

Tests: scoper 70 → 71 specs (on 0.12.5 and 0.11.2); config 4/4 on both.

---

### Audit pass: close-path consistency, scoper clangd reload, health accuracy

A full audit against Neovim 0.12.5 with the plugin set installed and
exercised headless and in tmux. Each behavioural fix below was checked by
running the same script against the previous tree and this one.

#### Bugs fixed

- **scoper: clangd reload used a deprecated API and usually didn't
  reconnect.** `vim.lsp.stop_client()` is hard-deprecated on 0.12 (a
  warning on every reload; removed in 0.13) — now `client:stop()`.
  Separately, clangd with a background index took ~3.7 s to shut down
  gracefully in testing, so the 2 s timeout skipped the re-attach and
  left C/C++ buffers with no clangd at all. The reload now force-stops
  any client still alive after the 2 s grace period and waits a further
  1.5 s; it reconnected on every test run afterwards (before: mostly
  "still exiting … skipped re-attach"). The re-attach also re-fires only
  the `nvim.lsp.enable` FileType handlers instead of every FileType
  autocmd (treesitter, ufo, formatoptions, …), and now covers `cuda`.
- **Bufferline Close / close button on a modified buffer.** The menu's
  Close and `close_command` detached the buffer's windows FIRST and then
  called a non-forced delete; with `'confirm'` on that raised a save
  dialog after the layout had already changed (and answering it wrote
  the file). Both now go through `util.delete_buffer_keep_windows`, same
  as `<leader>bd`: dirty buffers are skipped untouched with a
  notification, terminals are forced.
- **Bulk buffer delete and running terminals.** The batched delete never
  forced terminal buffers, which are never `'modified'` but still refuse
  a plain delete (E89). With `'confirm'` on that was one prompt per
  terminal; without it they were reported "failed" after their windows
  had been repointed. Now forced, matching the single-buffer path.
- **`<leader>tg` spawned a new lazygit on every press** (3 presses → 3
  terminals). One Terminal is now reused; it is dropped when lazygit
  exits, and a missing `lazygit` binary gives a message.
- **stylua guard bypassed via the symlink target.** A config opened
  through its real path (the usual dotfiles layout) wasn't recognised as
  "this config". Both sides are now realpath-resolved. *(Reverted in
  Pass 4 together with the guard itself.)*
- **`:SwapDelete` reported failed removals as successful.**
  `vim.uv.fs_unlink` returns `nil, err`; it doesn't throw, so the `pcall`
  never saw a failure.
- **Session restore re-enabled treesitter on big files.** The
  `SessionLoadPost` fallback now honours `b:big_file`.
- **LspDetach cleared highlights in the wrong buffer**
  (`vim.lsp.buf.clear_references()` acts on the current buffer); now
  `vim.lsp.util.buf_clear_references(dev.buf)`.
- **Visual `<A-j>` / `<A-k>` threw E16 at the first/last line.** Now a
  function with edge guards (like the normal-mode pair); the selection
  is kept.
- **Select-mode leaks.** `<leader>la`, `<leader>cf`, `<leader>gs`/`gr`,
  `<leader>dw`/`de`, visual `<leader>sr`, Comment.nvim's `gc`/`gb` and
  mini.surround were mapped in `"v"` (visual + select). In a snippet
  placeholder that made a typed space wait for `timeoutlen` or fire the
  map. Now `"x"`, per the rule already stated in keymaps.lua.
- **scoper: ripgrep excludes weren't shell-quoted** on the fzf-lua path
  (fd's were); a glob with a space split into two arguments.

#### :checkhealth config

- The tree-sitter CLI is now an ERROR-level requirement. nvim-treesitter
  `main` builds every parser with `tree-sitter build`; without it all of
  PARSERS fail (observed), contrary to the old "most work without it".
  `tar` is checked too.
- The minimum Neovim version is read from `vim.g.config_min_nvim`,
  published by init.lua, instead of being restated.

#### Hardening / cleanups

- folding.lua: `get_parser()` returns nil on 0.12 rather than throwing,
  so the old `pcall` was always "ok"; the parser is now tested, and
  `query.get()` (which does throw without a parser) is pcall'd — also in
  treesitter.lua's indentexpr check.
- Removed the config_spec block that read the live keymap table and, as
  its own comment said, could never detect a duplicate.
- Fixed misplaced/stale comments (util.lua function docs,
  completion.lua `opts_extend`, session.lua `session_lens`,
  formatting.lua package count, scoper reload timeout docs).

#### Tests

- scoper: `_rg_exclude` quoting (incl. a real shell round-trip),
  `_reattach` fires only the LSP group, long-path prefix exercised on
  every OS. 65 → 70 specs.
- luacheck clean on both trees; `check-docs.sh` passes.

#### Audit note

An earlier draft of this audit flagged scoper's `\\?\` long-path
pattern as broken. That was a misreading — the pattern is correct and is
unchanged; only the extra cross-OS test was kept.

Files touched: `init.lua`, `lua/config/{autocmds,health,keymaps,util}.lua`,
`lua/plugins/{completion,dap,editor,folding,formatting,git,lsp,search,session,terminal,treesitter,ui}.lua`,
`tests/config_spec.lua`, `scoper.nvim/lua/scoper/{lsp,pickers}.lua`,
`scoper.nvim/tests/{lsp,path,pickers}_spec.lua`, `scoper.nvim/README.md`

---

### Enforcement: doc-sync guards, cross-platform scoper CI, health dir checks

A follow-up to the documentation audit. That audit found several places
where the docs had drifted from the code (files missing from the README
tree, an undocumented keymap, a template pair that had to be re-verified by
hand). Rather than just fix them and hope, this pass turns each class of
drift into an automated guard, extends CI to the OS the config is most
careful about, and adds a couple of robustness checks.

#### Doc-sync guards (scripts/check-docs.sh)

New POSIX-sh script, wired into `make check-docs`, the `lint` CI job, and
the pre-commit hook. Pure grep/sed/diff over files — no Neovim boot — so it
is fast enough to run on every commit; it and the updated pre-commit hook
are shellcheck-clean (`shellcheck -s sh`). Four guards, each the permanent fix
for a real bug the audit turned up:

- **README Layout tree lists every module / plugin / template.** Enumerates
  `lua/config/*.lua`, `lua/plugins/*.lua` and the C++/DAP template files and
  asserts each appears in the tree (matched on the box-drawing lines, so a
  file merely mentioned in prose does not count). Would have caught the
  missing `health.lua`, `explorer.lua` and `clang-tidy.example`.
- **Every source `<leader>` map is documented in keymaps.html.** Strips
  whole-line comments first so prose that mentions a mapping is not taken
  for a binding, and compares only alphabetic suffixes (numeric jumps are
  documented as a single `1…9` range). Would have caught `<leader>cm`.
- **`.clang-tidy` and `clang-tidy.example` carry identical settings.**
  Compares both with comments and blank lines removed. Would have caught
  template drift.
- **Every `:checkhealth config` section is named in the README.** Each
  `h.start(...)` in `health.lua` must appear in the README's health
  description, so a new section can't be added without documenting it.
  Would have caught the Runtime state directories section, added in this
  same pass without (initially) a README mention.

Each guard was tested against a deliberately drifted tree to confirm it
fails with a specific message, and passes once the drift is corrected.

#### CI: scoper specs on Windows too

The workflow was Ubuntu-only, yet the config is heavily Windows-aware —
`scoper/path.lua` alone has drive-letter, UNC and backslash logic that a
Linux runner only ever exercises through `has('win32')` branches. Split
scoper's suite into its own job with an
`os: [ubuntu-latest, windows-latest]` matrix. scoper's harness clones only
plenary (git is preinstalled on the runners) — no full plugin set, no treesitter, no
compiler — so it runs reliably on Windows and now exercises the real path
code on the real OS. The job invokes Neovim directly with `shell: bash`
(one command for both runners; no dependency on GNU make being present on
Windows). The full-config smoke test stays Ubuntu-only — its lazy.nvim
plugin/parser install is too slow and flaky to gate on cross-platform. The
`lint` job also gained the `make check-docs` step.

#### :checkhealth config — runtime state directories

`health.lua` thoroughly checked the external toolchain but never the dirs
Neovim persists state to. Added a section that verifies the swap directory
(`'directory'`) and, when `undofile` is on, the undo directory (`'undodir'`)
are writable — or, since Neovim makes them lazily, that they can be created
under a writable parent. A read-only state dir otherwise fails silently and
far from its cause (a warning on every file open, lost undo history).

#### Fix: whitespace-strip skips read-only / special buffers

The `BufWritePre` trailing-whitespace trimmer guarded binary, diff,
big-file and markdown buffers, but not read-only or special ones — so
writing a `nomodifiable` or `nofile`/help/terminal/quickfix buffer to a
path threw `E21` from its `:substitute`. Added a `modifiable` + non-empty
`buftype` guard, matching the defensive style of the surrounding autocmds.
(Found while capturing `:checkhealth` output during this pass.)

Files touched:

- `scripts/check-docs.sh` (new), `Makefile`, `.githooks/pre-commit`,
  `.github/workflows/ci.yml`, `lua/config/health.lua`,
  `lua/config/autocmds.lua`, `README.md`,
  `docs/cheatsheets/plugins.html`, `docs/cheatsheets/workflows.html`

---

### Documentation sweep: layout tree, template naming, swap-comment re-sync

A pass over the docs for drift after the recent feature work; three fixes,
no behavior change.

- README's Layout tree had fallen behind the filesystem:
  `lua/config/health.lua`, `lua/plugins/explorer.lua` (neo-tree,
  `<leader>e`) and the annotated `clang-tidy` template were all absent.
  Added; every config / plugin / template file is now represented in the
  tree.
- The annotated C++ reference templates are `clang-format.example` and
  `clangd.example` (no leading dot), but the clang-tidy one had shipped as
  `.clang-tidy.example` — hidden and inconsistent with its siblings —
  while `docs/templates/cpp/README.md` already referred to it dot-less.
  Renamed to `clang-tidy.example` so the file matches the convention and
  the doc.
- `options.lua`'s swapfile write-up still described crash-leftover swaps
  as getting Vim's stock prompt; that stopped being true when the concise
  recovery prompt landed (next entry). Re-synced, and it now points at
  `:SwapDelete`.

Files touched:

- `README.md`, `lua/config/options.lua`,
  `docs/templates/cpp/clang-tidy.example` (renamed from
  `.clang-tidy.example`)

---

### Swap-file crash recovery: concise prompt + :SwapDelete

Follow-up to the swap re-enable and the guard toggle. Both changes target
the crash-leftover case, which the guard had deliberately left to Vim's
stock handler.

#### Concise recovery prompt for crash leftovers

When a swap has no live owner (a previous edit session crashed), Vim's
stock handler prints a ~17-line `E325` ATTENTION block plus a six-option
prompt — once per affected file, so opening a handful of crash-leftover
files at once is a wall of text. With the guard ON, the SwapExists handler
now replaces that with a single-line `confirm()` carrying the same real
choices (Recover / Open read-only / Edit anyway / Delete swap / Quit).
Recover is the default; `<Esc>` quits, so an accidental dismiss never edits
or deletes. Guard OFF is unchanged — `v:swapchoice` stays empty and stock
Neovim shows its full prompt, preserving the "off means exactly stock"
contract. A different USER's swap, or an unreadable one, still gets the
stock prompt in both modes *(unreadable: changed on 2026-10-13, see
there)*. `confirm()` is synchronous, which is exactly
what SwapExists needs, and it renders correctly this early (unlike
nvim-notify, which is why the live-owner notice still schedules).

#### :SwapDelete — remove a leftover without hunting its path

New user command. No argument targets the current buffer's swap; an
argument targets an explicit swap-file path, so a leftover can be cleared
without even opening the file it belongs to. Resolving the current
buffer's swap can't lean on `vim.fn.swapname()`: it returns `""` for a
buffer opened OVER an existing swap (Edit-anyway / Open-read-only / Recover
all leave it empty), which is precisely the crash-leftover case. So the
command scans the `directory` swap dirs and matches each swap's RECORDED
file name (`swapinfo().fname`) against the buffer path — naming-scheme
agnostic (handles the `dir//` mangling and `.swo`/`.swn` generations) and
cross-platform. It shows the exact path(s) and what it knows about each,
requires a `confirm()` that defaults to Cancel, and flatly refuses to
delete a swap a DIFFERENT live Nvim is using. This session's own active
swap is left alone in no-argument mode (it's the live crash protection,
not a leftover); an explicit path still deletes it.

Verified end to end against real crash leftovers (`kill -9` mid-edit): the
concise prompt replaces the ATTENTION block, Recover restores the unsaved
line, Delete removes the leftover, `:SwapDelete` finds the leftover via the
fname scan despite an empty `swapname()`, and the explicit-path form clears
one without opening its file. Two bugs surfaced while testing and were
fixed: `complete="file"` made Nvim expand `%` in the argument (swap paths
are all `%`), so it was dropped; and `vim.fn.expand()` on the path had the
same `%` problem, replaced with `vim.fs.normalize`.

Files touched:

- `lua/config/autocmds.lua`, `docs/cheatsheets/plugins.html`, `README.md`

---

Older entries: [docs/CHANGES-archive.md](docs/CHANGES-archive.md)
(historical, undated).
