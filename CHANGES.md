# Changelog

Newest first. Entries record their own revision's behavior and evidence; later
changes can supersede earlier defaults or instructions. Use the README and
feature guides for current operation. New entries use one `## YYYY-MM-DD — <title>` heading per
change, with `### Fixed` / `### Changed` / `### Docs` subsections. An item
that a later change undid is marked *(Reverted in …)* where it appears.

## 2026-11-09 — Adopt the Bufferline maintenance-fork integration

### Changed

- Pin `abhi-k9/bufferline.nvim` in the spec and lockfile.
- Use public `is_pinned(bufnr)` inside the existing checked close boundary.
  Safe deletion, visibility filtering and keymaps remain in the config.
- Replace the local diagnostic getter adapter with the fork's exact-count cache
  option, preserving the existing cache setting and indicator format.
- Reapply saved pins after scope restoration/reconciliation so hidden buffers
  created after SessionLoadPost receive their saved membership.

### Docs

- Record the exact pin, adapter removal, legacy-session caveat, validation and
  publication/adoption/rollback sequence in the Bufferline migration document.

## 2026-11-08 — Guard Bufferline compatibility boundaries

### Fixed

- Isolate private pin inspection behind a checked boundary. Close-unpinned now
  refuses unknown pin state or tabpage-mode IDs and ignores stale rendered
  buffers hidden by tab scoping. Shared safe deletion still protects edits.
- Treat an unavailable diagnostic-cache getter as an optional optimization
  failure: warn once and let Bufferline configure its native behavior.
- Add focused compatibility regressions without introducing a runtime dependency
  or changing the configured tabline plugin, keys or session ownership.

## 2026-11-08 — Use the DAP UI fork and retire the local controls adapter

### Changed

- Source DAP UI from `abhi-k9/nvim-dap-ui` on `master`, locking the reviewed
  revision `a53a500ed3bb0c7974966c6478edb1a82af0fb19`. It fixes control-handler
  accumulation, repeated-setup listener ownership and floating-window callbacks.
- Remove the temporary controls module, its setup hook, opt-out setting and
  adapter-specific tests. Keep the independent layout-width guard and the manual
  native lifecycle regression, now checking the plugin's own control group.
- Document migration with `:Lazy restore nvim-dap-ui`, explicit fork updates and
  eventual return to upstream. No fork source changes are included in this repo.

## 2026-11-07 — Bound DAP toolbar callbacks with a removable local adapter

*(Reverted in 2026-11-08: superseded by the DAP UI fork's native lifecycle fix;
the native regression check is retained.)*

### Fixed

- Replace only the DAP UI control lifecycle in memory, preserving upstream
  button rendering/actions and the independent fixed-column layout guard.
  Keep one handler set across reopens and rebind after buffer replacement;
  discard deferred work after teardown and preserve later user overrides.
- Skip missing/incompatible plugin APIs or already active native controls.
  Add `debug.controls_lifecycle_fix = false` as a startup opt-out, document
  the upstream defect and removal procedure, and leave plugin sources untouched.
- Cover lifecycle ownership and opt-out with focused regressions. Strengthen
  the existing manual native check to require stable control-handler counts,
  visible buttons and successful buffer recreation, without expanding push CI.

## 2026-11-07 — Add opt-in native smoke and short lifecycle checks

### Changed

- Add a disposable-config runner with a real embedded UI, locked plugin
  preparation, optional 25-cycle stress checks and external process deadlines.
  Exercise picker/explorer workflows, scope session restoration, Bufferline
  diagnostic counts and debugger sidebar widths without installing language tools.
- Check window/buffer and config-owned callback stability; report total callback
  and heap deltas separately. Record observed upstream DAP control callback growth
  as follow-up evidence rather than claiming an absence of dependency leaks.
- Add manual Windows/macOS jobs with separate concurrency, dedicated plugin caches,
  a 45-second check limit and a six-minute job limit. Manual dispatch skips the
  ordinary regression suites; push/PR runs skip these new jobs. Document local
  execution and the test-only MessagePack transport.

## 2026-11-07 — Keep breakpoint lists usable without Trouble

### Fixed

- Let `<leader>dx` fall back to native quickfix when Trouble is missing or its
  command fails. Reuse nvim-dap's exported list, retain failure details and
  report empty breakpoint lists without opening a new pane.
- Cover missing, failing and available Trouble plus empty lists using real DAP
  breakpoints and native quickfix windows. Document navigation and close keys.

## 2026-11-07 — Cancel formatter requests invalidated during dispatch

### Fixed

- Cancel a request whose ID arrives after a synchronous `LspRequest` hook has
  renamed the buffer or started a replacement format. Previously its reply was
  discarded, but the server missed the cancellation and could waste work.
- Preserve the replacement request and existing synchronous-response handling.
  Reproduce both cases through Neovim's native client request method and
  document the LSP-only formatter's cancellation and stale-edit behavior.

## 2026-11-07 — Keep diagnostic snapshots usable around optional-plugin failures

### Fixed

- Inspect only loaded DAP and Lazy modules. A diagnostic dump no longer
  activates an unused debugger while reporting that it has no active session.
- Capture debugger/plugin-inventory inspection failures within their sections
  and continue writing the rest of the report, including the bounded log tails.
  Add activation/failure regressions and document this inspection behavior.

## 2026-11-07 — Keep queued buffer-menu actions in their original context

### Fixed

- Capture the source window/tab after closing an earlier menu. Revalidate the
  target buffer and source before deferred actions and after window-entry hooks.
  Stale selections now report cancellation instead of raising E86 or opening a
  split in another tab; action failures retain an actionable warning.
- Preserve the existing file-pane selection for sidebar invocations. Cover
  deleted targets and tab switches, and explain how to retry from the intended tab.

## 2026-11-07 — Discard obsolete explorer startup callbacks

### Fixed

- Bind a deferred directory open to its source buffer, window and tab. Preserve
  the captured directory across cwd changes, but cancel after a tab switch,
  replaced/renamed buffer, moved/closed window or disabled automatic opening.
- Report optional explorer failures without an uncaught scheduled callback.
  Add tab-switch and buffer-replacement regressions and document explicit reopening.

## 2026-11-07 — Restore tab buffer groups through a local literal-path bridge

### Fixed

- Replace the config's calls to scope.nvim's filename-concatenating session
  loader with a local bridge using `bufadd()`. Restore hidden names literally,
  validate the entire saved group structure before changing visibility and
  reject results if buffer-creation hooks change the session or tabs.
- Retain the existing JSON shape, restore groups by visual tab order, coalesce
  duplicate names and reset process-local tab handles. Missing scope.nvim skips
  group restoration and clears stale group metadata on the next save.

### Changed

- Capture current listed buffers without unlist/relist events; index existing
  names once during restore. Stop the autosave eligibility scan at the required
  file count and skip it when that criterion is disabled.

### Docs

- Document compatibility, recovery and the local ownership boundary, with pinned
  upstream and Neovim API references. Add literal filename, invalid metadata,
  nested-tab and missing-plugin regressions plus a plugin-free fixture reused by
  the existing native Windows CI job. No dependency or plugin-source changes.

## 2026-11-07 — Keep debugger session cleanup safe under nested close hooks

### Fixed

- Recheck window and buffer validity while removing transient debugger panels
  from a saved layout. A `WinClosed` hook can synchronously close a later panel
  in the snapshot; cleanup now continues instead of raising an invalid-window
  error. Reproduce that sequence with real windows and document the behavior.

## 2026-11-07 — Leave virtual save paths to their providers

### Fixed

- Skip automatic parent-directory creation for URI schemes containing `+`, `-`
  or `.`, such as `git+ssh://` and `provider-name://`. Previously those writes
  attempted to create local directories named after the virtual path.
- Preserve local write destinations and Windows drive paths. Add regressions
  and explain filesystem versus virtual writes in the editing guide.

## 2026-11-07 — Recover safely from non-object Scoper state

### Fixed

- Treat JSON arrays as corrupt state roots instead of mixing numeric keys into
  the project object and failing later saves. Reuse the existing backup and
  save-blocking recovery path. Empty objects remain valid and receive defaults.
- Verify empty/nonempty array backups, subsequent mutation/save/reload and empty
  object handling. Document the object-root contract and failed-backup behavior.

## 2026-11-07 — Report Scoper automatic database-discovery overflow

### Fixed

- Return an explicit-path recommendation when automatic discovery exceeds its
  256-candidate budget, matching the existing 4,096-entry scan limit instead of
  throwing a configuration assertion. Keep explicit candidate-list validation.
- Verify the exact 256-candidate boundary and explicit-path selection in a
  workspace with excess build directories. Document both limits and the bypass.

## 2026-11-07 — Check Ruff's platform-specific extraction prerequisites

### Fixed

- Require ZIP extraction through PowerShell for Ruff on Windows instead of tar;
  retain tar for Linux/macOS and ShellCheck's different Windows asset. Verify
  both platform branches and document the Mason registry source contracts.

## 2026-11-07 — Validate Python aliases and bound health version probes

### Fixed

- Accept working Store-installed Python for Mason instead of rejecting every
  interpreter in the Windows alias directory. Keep bounded venv/ensurepip probes
  and cached results; uninstalled shortcuts fail without opening the Store.
- Resolve debugger PATH interpreters, skip unusable Windows aliases with a
  cached bounded version probe, and try the other canonical name. Preserve
  explicit/activated/project interpreters and explain how to fix a missing one.
- Bound each health version command to 1.5 seconds, accept stderr version output,
  and continue reporting after timeouts or spawn failures. Follow Windows case
  rules when explaining an unusable Store alias.

### Docs

- Document interpreter precedence, probe bounds/cache behavior and the
  distinction between working aliases and uninstalled shortcuts. Corroborate
  that behavior with Microsoft's Python FAQ and add targeted regressions.

## 2026-11-06 — Harden window context, literal paths and preview preparation

### Fixed

- Open configured launch files without Ex expansion of `%`, `#` or other literal
  filename characters. Accept valid relative POSIX image names containing a colon,
  while rejecting ambiguous Windows drive-relative names with a useful message.
- Resolve source-window cwd explicitly: Neovim's `nvim_win_call` can change window
  context while plain `getcwd()` still reads the process directory. Correct the
  shared root resolver, inactive/cross-tab workspace reports and DAP selection
  guards. Return to the source window before checking relative adapter commands
  and launching; recheck context after window-entry autocommands.
- Start the image preparation deadline before terminal detection and snapshot
  I/O. Handle stalled stages, rejected copy submissions and exceptions in deferred
  callbacks. Give each request its own job/timer/snapshot lifecycle so cancelled
  operations clean up without interfering with a newer preview.

### Docs

- Explain the source-window directory contract, literal launch paths and shared
  image deadline. Correct the image guide's lockfile restore claim: Lazy follows
  the file on disk rather than recovering Git's version. Clarify fork versus
  protected-branch publishing and add image commands to the plugin cheatsheet.
- Add targeted regressions and a plugin-free cross-tab window-context fixture,
  also exercised by the existing native Windows CI job. Keep physical-terminal
  image verification limits documented in the image guide.

## 2026-11-06 — Document publishing deliberate plugin updates

### Docs

- Add commands to review, test and commit only `lazy-lock.json`, then publish
  the new shared pins. Include the branch/CI route for limited machines and
  separate recovery recipes for local edits blocking a pull and an existing
  merge/rebase conflict. Link the workflow from the README's version policy.

## 2026-11-06 — Add optional local-image previews

### Changed

- Add `:ImageOpen [path]` with an opt-in, on-demand Snacks image renderer and a
  system-viewer fallback; `:ImageOpen!` explicitly requests the system viewer.
  Keep document/file interception, remote downloads, maths/diagrams and the other
  Snacks UI features disabled. Pin only the new dependency; explicit updates
  retain the existing Lazy workflow.
- Preserve source buffers and literal filenames. Decode private temporary
  snapshots to avoid stale path-based image caches, clean them on close/failure,
  cancel superseded requests, bound conversion time and discard stale callbacks.
  Add scoped `q` / Esc / `e` hints and useful missing-tool/API/opener messages.
- Use native platform openers with literal argv, including shell-free Windows
  file opening, and distinguish ImageMagick from Windows' disk `convert.exe`.
  Expose opt-in state and dependencies in `:checkhealth config` without loading
  the renderer or issuing startup warnings for the default disabled feature.
- Cover fallback, cancellation, filenames, cache freshness, decoding failure and
  actual graphics-protocol output with fixtures. Reuse native Windows CI for the
  plugin-free image command/path check; no extra workflow runs or jobs.

### Docs

- Add [image preview setup and platform limits](docs/image-previews.md), available
  through `:ConfigHelp images`, and link it from the daily-use/customization/help
  guides and README. Document dependency installation and remaining physical
  terminal/file-association verification.

## 2026-11-05 — Make workspace, guide and debug workflows easier to discover

### Changed

- Add `<leader>h` / `:ConfigHelp [topic]` to read maintained guides inside Neovim,
  with completion, topic selection, search and scoped close keys. References
  skip FileType provisioning and remain usable without optional plugins.
- Add `<leader>wi` / `:WorkspaceInfo` to compare cwd scopes, visible tree roots,
  Scoper/build state, attached LSP roots and debugging context. Refresh retains
  the original source window; missing status APIs and resolver errors are isolated.
- Show program/cwd and adapter command presence in the local launch chooser.
  Add `:DapLaunch`, `:DapLaunchInfo` and `:DapEditLaunch`, with `<leader>da` and
  `<leader>dI` shortcuts. Preserve native configuration values, dynamic launch
  evaluation, existing-session Continue, Run Last and Restart. Cancel stale
  discovery/selection, handle unavailable integrations and never auto-launch on
  selector failure. No plugin source, dependency or lockfile changes.
- Use close-buffer labels consistently and name discard-changes actions. Add
  recovery commands to common buffer, formatter and launch failures. Buffer
  menus and native debugger value previews show scoped `q` / Esc close hints;
  Esc also closes Atone help without restoring an undo node.

### Docs

- Update the quick start, context-help/directory/debugger/migration guides,
  README and cheatsheets with new workflows, close/delete/quit terminology,
  inspection limits and missing-plugin recovery.

## 2026-11-05 — Extend native help to undo, diff and scope workflows

### Changed

- Add F1 to Atone's native tree/diff help while preserving `?` / `g?`.
- Reuse Diffview's existing help callbacks for F1 in every native help context,
  including merge layouts, file/history/options panels and worktree overview.
  Each context retains its own mappings; no default table is mutated.
- Add close hints and named mappings to Scoper's read-only report. Give native
  multi-selection actions readable labels, mark/confirm hints and Telescope
  help aliases, including standalone Scoper searches without host configuration.

### Docs

- Add a [context-help guide](docs/context-help.md) covering the other feature
  families: LSP/Git, completion, debugger panes/REPL, terminals/lazygit,
  alignment, jump labels, folds, quickfix, selectors and tool inspection.
- Link it from the README, quick start, debugger guide and cheatsheets. Distinguish
  native help from local mapping lists and external-program input; document that
  Neo-tree's help can execute actions, with Esc as its cancel key.

## 2026-11-05 — Expose live context help and safe buffer actions

### Changed

- Add native F1 help to Telescope, Neo-tree and Trouble, plus Normal-mode `g?`
  aliases. Retain native help keys and fzf-lua's existing F1. Normal-mode F1
  elsewhere shares the which-key local-mapping reference, falling back to
  Neovim help for empty contexts or missing which-key.
- Advertise picker help and buffer mark/close keys in result titles. Give custom
  actions readable live descriptions without a separate help renderer/manual.
  Literal prompt input and terminal input retain their existing bindings.
- Share safe Ctrl-d/Alt-d closing and mark actions across both buffer-picker
  modes and the all-tabs Scope picker, preserving its native cross-tab opening.
  Keep skipped, unlisted buffers from other tabs visible after a close attempt.

### Docs

- Document help entry points, mode/terminal limits, multi-buffer closing and
  native reference behavior in the quick start, migration guide and cheatsheets.

## 2026-11-05 — Toggle Neo-tree buffers and filesystem views

### Changed

- Make repeated `<leader>be` switch the visible tree between buffers and files.
  Derive state from Neo-tree instead of keeping a second toggle flag; preserve
  native roots/position and avoid automatic reveal changing the remembered root.
- Catch unavailable modules and source-switch errors without adding cwd, Scoper
  or project-root coupling. Verify actual source/root behavior and focused
  regressions for windows, tabs, closed trees and dependency failure.

## 2026-11-05 — Cache Bufferline diagnostic counts locally

### Changed

- Cache native diagnostic counts per buffer/namespace in a local adapter;
  refresh changed buffers instead of scanning the workspace on every redraw.
  Poll enabled state per group so toggles remain live without diagnostic events.
- Preserve native insert/replace update policy and severity indicators; delegate
  other providers and restore only the owned getter during disposal. Keep the
  original Bufferline source and lockfile unchanged. Disable the adapter with
  `ui.bufferline_diagnostic_cache = false` in `local.lua`.
- In a 20-buffer Linux fixture, 10,000-diagnostic aggregation fell from about
  12.86 ms to 0.006 ms per warmed redraw; 100 unchanged renders made zero native
  diagnostic reads instead of 100. Record methods and limits in the
  [responsiveness review](https://github.com/abhi-k9/nvim-config/blob/f29b83e101b6a13e0d050bdf7e7a8fb4c3c9eb84/docs/performance-review-2026-11-04.md#follow-up-local-bufferline-cache--2026-11-05).

## 2026-11-04 — Stage CI Neovim installs on the destination filesystem

### Fixed

- Set Linux setup's temporary directory to the resolved home directory for the
  pinned Neovim action. A runner with `/tmp` on another filesystem failed its
  extraction-to-installation rename with `EXDEV`, before executing tests.
- Keep the override scoped to Neovim setup and retain the immutable action pin.
  Document the source-confirmed cause and the separate Windows fixture correction
  in [CI troubleshooting](https://github.com/abhi-k9/nvim-config/blob/f29b83e101b6a13e0d050bdf7e7a8fb4c3c9eb84/docs/ci-troubleshooting.md#installer-filesystem-mismatch--2026-11-04).

## 2026-11-04 — Normalize the database-resolution test fixture on Windows

### Fixed

- Normalize the new test fixture's temporary root before constructing expected
  paths and clangd arguments. Native Windows CI exposed comparisons between raw
  backslash/uppercase-drive temp paths and Scoper's normalized paths; production
  path handling remains unchanged.

## 2026-11-04 — Record the responsiveness review

### Docs

- Record measured settings, Scoper and fold-restoration improvements, callback
  checks, upstream sources and platform limits in the
  [responsiveness review](https://github.com/abhi-k9/nvim-config/blob/f29b83e101b6a13e0d050bdf7e7a8fb4c3c9eb84/docs/performance-review-2026-11-04.md).
- Explain why forcing asynchronous Neo-tree scans was deferred after a stale
  navigation race, and retain bufferline diagnostic aggregation and restart
  polling as measured follow-up opportunities.

## 2026-11-04 — Reject obsolete synchronous filter output

### Fixed

- Compare a cold synchronous filter's captured project/scope/build context with
  the context after filtering. Retry once when it changed; if it keeps changing,
  return no obsolete filtered directory. Previously an external resolver change
  could pair old output with the new selection in status. Reuse the post-work
  resolution so stable preparation keeps the same discovery count.
- Verify successful build switches and bounded repeated changes with real
  filtered output, alongside the existing failed-preparation fallback case.

## 2026-11-04 — Share Scoper discovery within an operation

### Changed

- Resolve a database once per status read or warm command preparation, passing
  the selection explicitly instead of keeping mutable selection scratch state.
  Independent operations still discover external changes and invoke resolvers;
  cold filtering retains its later resolution and asynchronous obsolete-result
  checks remain intact.
- On a Linux fixture with 4,000 immediate entries, status discovery fell from two
  scans to one (about 4.1–4.8 ms to 1.9 ms); selected command preparation fell from
  three to one (about 6.2 ms to 2.0 ms). Add regressions for new/removed databases,
  resolver changes, warm reuse and cold fallback selection changes.

## 2026-11-04 — Skip source checks when no saved fold view exists

### Changed

- Return after a missing saved view instead of also checking the source file on
  buffer entry and the first idle reassertion. Existing saved views retain their
  subsecond freshness checks and cursor-preserving restoration.
- A 100-entry event probe eliminated 200 source-file stat calls while keeping
  all 200 saved-view checks, avoiding extra I/O on first visits and network paths.

## 2026-11-04 — Avoid path work for machine-only settings

### Changed

- Skip working-directory resolution on settings reads when no trusted project
  overlays are registered. Later registration and directory changes still take
  effect immediately; no settings or directory cache is introduced.
- A Neovim 0.12.6 Linux microbenchmark of 100,000 scalar reads fell from about
  439 ms to 38 ms, eliminating 200,000 cwd lookups. This isolates getter overhead,
  not total startup or interactive latency; ordinary startup has far fewer reads.

## 2026-11-04 — Explain directory switching and diagnostics panel controls

### Docs

- Document `:cd`, `:tcd`, `:lcd` and Neo-tree's tab-local root navigation, with
  the effects on Scoper, searches, language servers, debugging, terminals and
  sessions. Add quick-start instructions and migration-guide cross-references.
- Explain Trouble toggle/close/jump controls, focused-window `:q` behavior and
  the diagnostics statusline label in the guides and cheatsheets.
- Clarify full selected database behavior with scope filtering off, independently
  of disabling clangd integration or waiting for a usable project index.

## 2026-11-04 — Improve Telescope typing and prompt rendering

### Fixed

- Replace the growing-history `smart` path formatter with width-based truncation.
  Result redraws no longer compare each label with previously displayed paths;
  complete matching/opening paths and native fuzzy sorting are preserved.
- Disable smear-cursor overlays in Telescope prompt buffers, keeping the native
  input caret and ordinary editor animation. Prompt text is not trimmed or altered.

### Docs

- Explain picker rendering costs, the native caret, complete-path access and the
  existing fzf/Scoper alternatives for very large file lists.

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

Earlier undated release notes are available in the Git history of this file.
