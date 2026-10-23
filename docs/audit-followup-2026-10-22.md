# Expanded repository audit — 2026-10-22

This continues [the first audit](audit-2026-10-21.md) from commit `01842c4`.
The inventory covered all **107 tracked baseline files**, including the plugin
specifications, custom callbacks, bundled Scoper implementation, test harnesses,
CI, scripts, templates, and documentation. New helpers and regression tests are
included in the coverage ledger below. Neovim **0.12.6** was used throughout.

The dependency lockfile was retained. This audit changes configuration behavior
and tests; it does not upgrade plugins, tools, or parsers. Plugin upgrades remain
available through `:Lazy update`, with `:Lazy restore` returning to the committed
lockfile. Mason tools and Treesitter parsers have their separate update commands.

## Verified changes

Each implementation group has a failing baseline reproduction and a passing
regression or native integration check. Related corrections share a focused
commit. Independent review also challenged the changes themselves: it caught
in-flight Scoper cancellation, silent external-state refresh, and application-name
assumptions in a new test fixture. Those corrections are included in the final
implementation and tests.

| Area | Confirmed behavior before correction | Result and reproducible check |
| --- | --- | --- |
| Scoper delayed selections | A pending remove/add/exclude/name picker could modify a different project or active scope after a context switch. | Snapshot and revalidate the relevant context; cancel stale actions. External state refresh emits its change event. `scoper.nvim/tests/context_spec.lua`. |
| Scoper plain multiselect | An actual item named `(done)` was indistinguishable from the finish row. | Use the selection index. `scoper.nvim/tests/ui_spec.lua`. |
| LSP attachment | A special-buffer transition while clangd initialized could leave a virtual buffer attached and produce invalid-URI requests. | Reject special buffers in `LspAttach`, retaining ordinary unnamed buffers. Native asynchronous clangd reproduction plus `tests/lsp_lifecycle_spec.lua`. |
| LSP capabilities | Background attachment and linked-editing toggles queried dynamic capabilities against the current window's buffer. | Pass the event/client-attached buffer explicitly. Native per-buffer registration regressions in `tests/lsp_lifecycle_spec.lua`. |
| Telescope clipboard paths | A display-relative filename could resolve against the caller's cwd instead of the picker's cwd. | Prefer actual entry paths and use picker-relative resolution. `tests/navigation_paths_spec.lua`. |
| Current-file replacement | The pinned Grug backend expanded literal `$NAME` in a filename, potentially targeting another existing file. | Refuse paths the backend cannot preserve literally. Real backend reproduction and `tests/search_literal_paths_spec.lua`. |
| Shared debugger UI | Ending one of two real debugpy sessions hid the surviving session's controls. | Account for live root and child sessions, including terminate completion and launch errors. `tests/dap_ui_lifecycle_spec.lua`. |
| Session saves and debugger panels | Saving opened intentionally hidden panels, discarded post-mortem panels, or changed layout subsets/tabs. | Snapshot visible layouts without loading an unused debugger; restore the same subset in reverse layout order and retain focus. Native two-tab regression in `tests/session_ui_visibility_spec.lua`. |
| Buffer menu splits | Split actions divided a focused sidebar or terminal instead of the file area. | Route through the existing normal-file-window helper. `tests/buffer_menu_split_spec.lua`. |
| Buffer deletion | Replacement-buffer hooks could close snapshot windows or wipe later deletion targets, causing invalid-ID errors. | Revalidate windows and buffers after hooks; retain edits introduced during replacement. `tests/buffer_lifecycle_spec.lua`. |
| Prose undo mappings | Markdown punctuation mappings remained after changing the buffer to code. | Remove only owned mappings on leaving prose; preserve user replacements. `tests/prose_undo_spec.lua`. |
| Window zoom | Exchanging splits preserved the ID set but changed the window-number order used by saved resize commands. | Compare the ordered split layout before restoring sizes. `tests/zoom_layout_spec.lua`. |
| Test dependency bootstrap | An interrupted cache skipped installation; concurrent suites could delete each other's partial clone; initialization failures could leave a headless runner waiting. | Share a staged installer, validate module/runtime markers, publish complete clones, clean only owned staging, and exit promptly with cache-remediation guidance. `tests/test_dependency_spec.lua`, including custom application names. |
| Core-dump template | The old CodeLLDB example loaded a core and then launched a fresh process over it. | Use documented custom target creation and disable process creation with attach. An actual ELF core retained its saved line/value instead of outputting a fresh program result. |
| Parser installation | A deduplicated JavaScript installation attached its initiating filetype but missed pending JSX aliases. | Attach every loaded buffer resolving to the installed parser language. `tests/treesitter_install_alias_spec.lua`. |
| Large-file context parsing | Stopping highlighting did not stop Treesitter context from independently parsing excluded buffers. | Use the context plugin's documented attachment predicate. Real parser checks in `tests/treesitter_context_bigfile_spec.lua`. |
| Explorer startup | Starting on an absolute directory outside cwd opened the wrong tree root; reloading could reuse stale argv. | Capture the entered directory and pass it explicitly to the deferred open. `tests/explorer_directory_spec.lua`. |
| Diagnostic log reads | A FIFO blocked indefinitely; a long single line disappeared; an unbounded read could exceed the intended tail size. | Reject nonregular files, open nonblocking where supported, recheck the FD, and perform one bounded read. `tests/diagnostic_tail_spec.lua`. |
| Diagnostic write failures | Actual mkdir/write exceptions escaped the intended failure notification. | Catch exceptions and return failure; recognize dangling filename collisions with lstat. `tests/diagnostic_tail_spec.lua`. |
| Health path checks | Regular-file obstacles appeared writable, `/` appeared unset, and escaped commas were misparsed. | Share the native option decoder and validate each existing ancestor's type. `tests/health_paths_spec.lua`; existing swap regressions retained. |
| Grug file navigation | Empty matching source lines made later source text resemble result headers. | Navigate actual result-path highlight annotations. Real ripgrep cases in `tests/search_file_navigation_spec.lua`. |
| Scoper integration lifecycle | Disabling integration left listeners/debounces, scheduled initial work, pending reloads, or in-flight results able to restart clangd. | Tear down owned hooks, track timer identity and generations through filtering/restart polling, and retain explicit manual requests. `scoper.nvim/tests/lsp_lifecycle_spec.lua` and `lsp_inflight_spec.lua`. |
| Asynchronous LSP formatting | A delayed native response overwrote newer typing or raised errors after buffer deletion. | Guard changedtick, URI, buffer lifecycle, detach, supersession, and timeout; apply sequential server results to the explicit buffer with negotiated offsets. `tests/lsp_format_race_spec.lua`. |
| Adapter crashes | A transport failure without DAP exit events left empty panels open. | Use the session close hook, schedule UI work, and recheck ownership/preferences. Actual owned-adapter termination plus `tests/dap_ui_lifecycle_spec.lua`. |
| Python socket attach | A newly spawned stdio adapter waited indefinitely while the target's `debugpy.listen()` already owned a different adapter. | Connect directly to the existing socket adapter; preserve executable launch/PID/reverse-listen modes. Native socket attach and `tests/dap_python_adapter_spec.lua`. |
| Compilation-cache failures | A cache directory blocked by a file escaped the command's usable-fallback contract. | Return a failure result and finish asynchronous work once without starting a doomed worker. `scoper.nvim/tests/cache_failure_spec.lua`. |
| Scoper persistence | Read/stat/backup/mkdir failures could throw or permit defaults to overwrite state that could not be inspected. Special-file reads could block. | Preserve unread data, block unsafe saves until successful reload, retain session changes, and reject nonregular state paths. `scoper.nvim/tests/state_io_spec.lua`. |
| Fold-view freshness | Whole-second timestamps missed a newer source rewrite within the same second. | Compare seconds and nanoseconds. `tests/fold_view_freshness_spec.lua`. |
| View cleanup | The janitor removed unrelated old files from configurable `viewdir`. | Prune only native encoded view names; test real default and numbered `:mkview` output. `tests/view_janitor_spec.lua`. |
| Large-to-small reread | A previously scheduled large-file shutdown stopped the newly attached small-file parser. | Recheck the live large-file marker at both deferred boundaries. `tests/bigfile_reread_spec.lua`. |
| Session filetype recovery | Rescue detection ran filetype plugins on special and URI buffers. | Restrict recovery to ordinary files. `tests/session_filetype_rescue_spec.lua`. |
| Outside-project glob scopes | Relative excludes also matched ancestors above a glob include's literal root. | Anchor excludes below the complete literal ancestor and require the full include match. `scoper.nvim/tests/glob_roots_spec.lua`. |
| Escape popup cleanup | A close hook could invalidate a later popup in the window snapshot. | Revalidate before reading window configuration. Native window-hook cases in `tests/escape_float_lifecycle_spec.lua`. |
| Portable scope caches | Long names failed Unix component limits; DOS device names and trailing dots were invalid Windows cache components. | Encode only nonportable cache components, preserving logical names and existing ordinary cache paths. `scoper.nvim/tests/cache_names_spec.lua`. |
| UNC glob patterns | Neovim's glob compiler rejected the empty first segment of an explicit `//server/share` pattern. | Compile one separator away and enforce the original UNC subject boundary. `scoper.nvim/tests/unc_globs_spec.lua`; Windows string rules on Linux. |
| First language-server startup | Mason could enable a server before user settings and Blink capabilities were configured. | Make the automatic-enable layer depend on completed server configuration. Real first LuaLS/clangd startup plus `tests/lsp_initialization_spec.lua`. |

Documentation also now describes startup LSP-log rotation, cleanup of the retained
generation, and the correct Unix state locations for undo, swap, and views.

## Architecture and safety decisions

The asynchronous formatting helper is intentionally limited to LSP formatting.
Routing through the pinned Conform implementation avoided stale text edits but
still raised an autocmd-deletion error after a real buffer wipe. The small local
helper supplies the required lifecycle guards without replacing upstream APIs.
Its cancellation state is invalidated before calling cancellation hooks, and it
handles synchronous in-process replies as well as delayed external servers.

DAP UI visibility has no equivalent public getter. Session saves therefore use
guarded pinned visibility state and public restore operations; absent or changed
private state degrades without an exception. The existing private scope.nvim
persistence coupling remains guarded as in the first audit.

The current-file Grug restriction and the earlier restricted `:ScoperReplace`
restriction remain deliberate. The pinned backend lacks the literal-path and
durable per-instance cwd guarantees those operations require. Broadening a write
target silently would be worse than reporting the unsupported operation clearly.

## Test environment and results

Reusable installed dependencies were kept at their locked revisions. Each worker
used separate configuration/data/state/cache/log roots beneath
`/workspace/nvim-audit-followup/`; only installed dependency subdirectories were
shared or copied. Mutable Scoper state, sessions, views, logs, test fixtures, and
temporary Git repositories were isolated. Native debugger tests terminated only
their own processes. Online corroboration used verified HTTPS.

`make ci` passed with **496 tests**: **196 configuration**, **256 Scoper**,
and **44 Python** tests, with zero failures or errors. This is **150 additional
passing regressions** beyond the first audit's 346. Both Lua trees pass Luacheck
and StyLua; documentation guards and ShellCheck pass.

The startup smoke passed Lua LSP initialization/hover, native Treesitter parsing,
real StyLua formatting, local Scoper, and native fzf loading. All **54 configured
plugins** load without errors. All **53 locked plugin checkouts** match the
unchanged lockfile (SHA-256
`60c75712834aa4d6a841fd531ba85e33e24f902edfb77495600be3c708d0d289`).
The actual offline completeness check reports no pending downloads.

Independent review reran **60 focused cases** successfully, including its own
reproductions of the issues it returned for correction. A limited full-file
credential/conflict scan found no recognized private-key blocks, GitHub tokens,
AWS access keys, or unresolved merge markers. This scan is not a guarantee that
arbitrary sensitive prose can be identified automatically.

The cloud evidence is retained under `/workspace/nvim-audit-followup/`: root
combined logs in `root/logs/`, independent results in `independent-review.md`,
and per-function ledgers in `core-lifecycle/coverage.md`,
`debugger/FINDINGS.md`, `editor-navigation/COVERAGE.md`,
`lsp-format/FINDINGS.md`, `ui-folding/coverage.md`, and
`scoper-model/coverage-ledger.md`.
Tracked tests provide the durable reproductions; one-off process fixtures and
large installed dependencies remain outside the repository.

Additional native checks covered:

- Python launch, breakpoint/evaluate/step/continue, run-to-cursor, restart/pause,
  socket attach, simultaneous sessions, and unexpected adapter termination.
- CodeLLDB launch/step, PID attach and nonterminating detach, plus real ELF core
  generation and inspection; Bash adapter breakpoint/evaluate/step/continue.
  cppdbg initialization and its missing-GDB failure/cleanup path also ran.
- Real clangd virtual-buffer initialization, negotiated UTF-16 formatting, and
  first-client configuration; LuaLS/LazyDev types and Blink completion.
- Eighteen formatter filetypes plus a UTF-8 StyLua selection; real parser aliases,
  context policy, textobjects, Neogen/LuaSnip generation, and UFO providers.
- Neo-tree directory startup, Telescope entry generation, real ripgrep/Grug
  results, Gitsigns partial staging, terminal lifecycle, Trouble count routing,
  native menu geometry, multi-tab DAP layouts, themes, statusline, and undo UI.
- Both concise and annotated C++ template sets with actual clangd/clang-format
  configuration parsing; all eight HTML cheatsheets' local links/anchors and
  Markdown local targets. No scripts are embedded in the HTML files.

Some tests control callback timing or filesystem failure responses to make races
deterministic. Native processes and actual buffer/window/file operations separately
corroborate those findings. That distinction matters: forced Windows path-string
cases are not native Windows execution.

## Remaining limitations and findings

This is the historical finding list for that audit revision. Later fixes and
current verification boundaries are tracked in [audit-resolution.md](audit-resolution.md).

1. **Toggleterm literal cwd expansion:** its pinned implementation expands an
   already absolute directory with `vim.fn.expand`. A project literally named
   `$NAME` can open a shell or lazygit in a sibling expanded directory when the
   environment variable exists. A real terminal `pwd` reproduced this. There is
   no public literal-cwd mode; no private adapter or temporary path alias was
   added. Use a project path without that expansion syntax until upstream
   supports it.
2. **Diffview current-file history:** Git pathspec wildcards can broaden the
   read-only history selection (`file[ab].lua` can include `filea.lua`); the pinned
   adapter also normalizes literal POSIX backslashes. A Git-only literal-magic
   workaround would change Mercurial behavior and still miss backslashes. Actual
   Git/path-adapter checks confirmed the limit; no write/injection issue was
   reproduced.
3. **Prior audit debt remains:** direct Windows `.cmd` adapter spawning and
   Windows native Python-launcher relocation need native Windows verification;
   simultaneous Scoper state saves remain last-writer-wins; cache writers sharing
   a scope fingerprint can race source generations; final swap stat/unlink is not
   an atomic compare-and-delete. The first report explains these boundaries.
4. CI actions/tools still follow their configured moving releases, and production
   Mason/parser versions are independently updateable. The unchanged plugin
   lockfile makes plugin restoration reproducible, not every downloaded tool.
5. No native Windows/macOS host, physical clipboard/font/GUI, remote gdbserver,
   MSVC/PDB run, or full GDB-backed session was available. Python PID injection
   and reverse-listen transports were source-reviewed and preserved by transport
   regressions, not exercised against real targets. Headless checks cannot assess
   animation/font quality. Arbitrary future upstream versions are outside this
   audit's evidence. Scoper's external-state refresh also depends on filesystem
   timestamps; equal/coarse timestamps and logical symlink aliases are not a
   transactional cross-process synchronization mechanism.

Previously suspected issues that did **not** reproduce were excluded: one-letter
URI grammar cleanup (Neovim treats it as a filesystem/drive form), default dump
permissions (actually 0600), the ordinary small-to-large parser reread, Trouble
count handling, and Diffview Ex-metacharacter argument injection. Historical
changelog claims were structurally scanned, not re-proven as current behavior.

## Online corroboration

The following official documentation and exact pinned sources explain the
observed behavior. Copies and reproduction logs are retained in the test workspace;
failed fetches were not used as evidence.

- Neovim 0.12.6: [window/buffer API](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/api.txt),
  [native functions](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/vimfn.txt),
  [LSP API and async formatting warning](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/lsp.txt),
  [native formatting implementation](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/lsp/buf.lua),
  [luv filesystem API](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/luvref.txt),
  [view/application paths](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/starting.txt),
  [native view encoding](https://github.com/neovim/neovim/blob/v0.12.6/src/nvim/ex_session.c#L1107),
  [undo breaks](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/insert.txt),
  [environment expansion](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/fs.lua#L696).
- Debugger lifecycle: [pinned nvim-dap session/on_close](https://github.com/mfussenegger/nvim-dap/blob/cfa2d58f4537aca6ca83e2de1a0d9f1491121264/lua/dap/session.lua),
  [DAP requests/events](https://github.com/microsoft/debug-adapter-protocol/blob/main/specification.md),
  [CodeLLDB 1.12.3 core/launch manual](https://github.com/vadimcn/codelldb/blob/v1.12.3/MANUAL.md),
  [debugpy 1.8.22 adapter attachment](https://github.com/microsoft/debugpy/blob/v1.8.22/src/debugpy/adapter/clients.py),
  [Bash adapter dependencies](https://github.com/rogalmic/vscode-bash-debug/blob/master/README.md),
  [cpptools schema](https://github.com/microsoft/vscode-cpptools/blob/main/Extension/package.json).
- UI and parsers: [pinned DAP UI layout ordering](https://github.com/rcarriga/nvim-dap-ui/blob/cc9dd33aade7f20bae414d0cba163bc60d4d4b43/lua/dapui/init.lua#L285),
  [layout visibility](https://github.com/rcarriga/nvim-dap-ui/blob/cc9dd33aade7f20bae414d0cba163bc60d4d4b43/lua/dapui/windows/layout.lua#L156),
  [JavaScript/JSX parser aliases](https://github.com/nvim-treesitter/nvim-treesitter/blob/1a4f47b03dfe92d28de7d5654c67327ef008c9e6/plugin/filetypes.lua#L26),
  [context attachment contract](https://github.com/nvim-treesitter/nvim-treesitter-context/blob/8decd73460d26ef0a0befb745d022dd1fc2c38b8/README.md#L389),
  [context's independent parsing](https://github.com/nvim-treesitter/nvim-treesitter-context/blob/8decd73460d26ef0a0befb745d022dd1fc2c38b8/lua/treesitter-context/context.lua#L233).
- Navigation and literal paths: [Telescope entry metadata](https://github.com/nvim-telescope/telescope.nvim/blob/40aedd8a68c78a656a10a8d62d80c54af59420fb/lua/telescope/make_entry.lua),
  [Grug path normalization](https://github.com/MagicDuck/grug-far.nvim/blob/11595bf747edc270bce2069d1020502ad4ae56cf/lua/grug-far/utils.lua#L614),
  [Grug result annotations](https://github.com/MagicDuck/grug-far.nvim/blob/11595bf747edc270bce2069d1020502ad4ae56cf/lua/grug-far/render/resultsList.lua#L111),
  [Neo-tree directory handling](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/d5b8a12b74683ddaefa519ce66a097610672859f/lua/neo-tree/command/init.lua#L206),
  [Toggleterm cwd expansion](https://github.com/akinsho/toggleterm.nvim/blob/9a88eae817ef395952e08650b3283726786fb5fb/lua/toggleterm/terminal.lua#L185),
  [Diffview pathspec handling](https://github.com/dlyongemallo/diffview-plus.nvim/blob/2a2d89a07f5d5d3cef7f542b99c3e28050ca205c/lua/diffview/vcs/adapters/git/init.lua#L158),
  [Git pathspec/literal semantics](https://github.com/git/git/blob/v2.43.0/Documentation/glossary-content.txt#L358).
- Startup ordering: [pinned Mason automatic enable](https://github.com/mason-org/mason-lspconfig.nvim/blob/e17625cdc8c2650787467398e02c5d63a2cde966/lua/mason-lspconfig/features/automatic_enable.lua),
  [Neovim immediate enable behavior](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/lsp.lua),
  [pinned Lazy dependency contract](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/doc/lazy.nvim.txt).
- Glob/portability rules: [Neovim glob compiler](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/glob.lua),
  [Windows file naming rules](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file).
- Test installation: [Git clone destination rules](https://github.com/git/git/blob/master/Documentation/git-clone.adoc),
  [libuv filesystem/rename API](https://github.com/libuv/libuv/blob/v1.x/docs/src/fs.rst).

## File coverage ledger

This historical ledger enumerates all **144 files at that audit revision** (107 baseline files and 37 additions). Static review, controlled regressions, native integration, and retained prior-audit coverage are identified separately. External dependencies themselves are outside the tracked-file inventory. Later additions are accounted for in [audit-resolution.md](audit-resolution.md).

| File | Review and verification |
| --- | --- |
| `.editorconfig` | Every rule/override reviewed for scope, platform line endings and tool semantics; relevant formatter/linter gates executed. |
| `.gitattributes` | Every rule/override reviewed for scope, platform line endings and tool semantics; relevant formatter/linter gates executed. |
| `.githooks/pre-commit` | NUL-separated staged paths, staged blobs, per-tree configs, pipe/error propagation and doc gate reviewed. Hook regressions and ShellCheck. |
| `.github/workflows/ci.yml` | Every job/matrix/cache/action/input/tool acquisition and token/credential setting rereviewed; retained prior official action-source evidence. Local equivalent gates; remote CI not run. |
| `.luacheckrc` | Every rule/override reviewed for scope, platform line endings and tool semantics; relevant formatter/linter gates executed. |
| `CHANGES.md` | Historical material: full-file structural/credential/conflict and local-link scans; current behavior claims checked in maintained docs, historical claims not re-proven. |
| `Makefile` | Every target, dependency, tool override, runner and cleanup command reviewed. CI-equivalent targets executed; shared dependency bootstrap corrected. |
| `README.md` | Current architecture/tool/update/test/path documentation rereviewed; inventory/key/command/plugin guards and local link checks. |
| `docs/CHANGES-archive.md` | Historical material: full-file structural/credential/conflict and local-link scans; current behavior claims checked in maintained docs, historical claims not re-proven. |
| `docs/audit-2026-10-21.md` | Prior findings/evidence/limits retained as historical baseline; all referenced regression suites rerun. Not rewritten as new findings. |
| `docs/audit-followup-2026-10-22.md` | Audit synthesis, evidence boundaries, official references and complete inventory reconciliation; final documentation/link gates. |
| `docs/cheatsheets/clang-settings-reference.html` | HTML/content structure and embedded-code surfaces scanned; no scripts; all local links/anchors checked. Current command/plugin/template consistency guards and runtime integrations. |
| `docs/cheatsheets/clang-tools.html` | HTML/content structure and embedded-code surfaces scanned; no scripts; all local links/anchors checked. Current command/plugin/template consistency guards and runtime integrations. |
| `docs/cheatsheets/cpp-diagnostics.html` | HTML/content structure and embedded-code surfaces scanned; no scripts; all local links/anchors checked. Current command/plugin/template consistency guards and runtime integrations. |
| `docs/cheatsheets/debugging.html` | HTML/content structure and embedded-code surfaces scanned; no scripts; all local links/anchors checked. Current command/plugin/template consistency guards and runtime integrations. |
| `docs/cheatsheets/keymaps.html` | HTML/content structure and embedded-code surfaces scanned; no scripts; all local links/anchors checked. Current command/plugin/template consistency guards and runtime integrations. |
| `docs/cheatsheets/plugins.html` | HTML/content structure and embedded-code surfaces scanned; no scripts; all local links/anchors checked. Current command/plugin/template consistency guards and runtime integrations. |
| `docs/cheatsheets/vs-to-nvim.html` | HTML/content structure and embedded-code surfaces scanned; no scripts; all local links/anchors checked. Current command/plugin/template consistency guards and runtime integrations. |
| `docs/cheatsheets/workflows.html` | HTML/content structure and embedded-code surfaces scanned; no scripts; all local links/anchors checked. Current command/plugin/template consistency guards and runtime integrations. |
| `docs/templates/cpp/.clang-format` | Template options/comments and concise/annotated parity reviewed. Both template sets parsed by actual clangd; clang-format comparison; official LLVM semantics retained. |
| `docs/templates/cpp/.clang-tidy` | Template options/comments and concise/annotated parity reviewed. Both template sets parsed by actual clangd; clang-format comparison; official LLVM semantics retained. |
| `docs/templates/cpp/.clangd` | Template options/comments and concise/annotated parity reviewed. Both template sets parsed by actual clangd; clang-format comparison; official LLVM semantics retained. |
| `docs/templates/cpp/README.md` | Template options/comments and concise/annotated parity reviewed. Both template sets parsed by actual clangd; clang-format comparison; official LLVM semantics retained. |
| `docs/templates/cpp/clang-format.example` | Template options/comments and concise/annotated parity reviewed. Both template sets parsed by actual clangd; clang-format comparison; official LLVM semantics retained. |
| `docs/templates/cpp/clang-tidy.example` | Template options/comments and concise/annotated parity reviewed. Both template sets parsed by actual clangd; clang-format comparison; official LLVM semantics retained. |
| `docs/templates/cpp/clangd.example` | Template options/comments and concise/annotated parity reviewed. Both template sets parsed by actual clangd; clang-format comparison; official LLVM semantics retained. |
| `docs/templates/dap/launch.json.example` | Every active/commented configuration reviewed; all nine active JSONC configs parsed by pinned DAP loader. Actual core example corrected/tested. |
| `docs/workflows/install-update-uninstall.md` | Every install/update/rollback/uninstall recipe and platform path rereviewed; corrected Unix state locations; local link checks. |
| `docs/workflows/offline-install.md` | Trust/checksum/platform/lock/extraction/rollback/relocation guidance compared with helper and hostile-seed tests; native Windows limits explicit. |
| `docs/workflows/state-files.md` | Undo/ShaDa/session/breakpoint/log cleanup guidance rereviewed; actual rotation/path behavior corroborates corrections. |
| `docs/workflows/swap-files.md` | Recovery/cleanup/ownership guidance cross-checked against retained first-audit logic and rerun swap regressions; local links. |
| `init.lua` | Ancient-safe minimum-version failure branch and every load-order dependency rereviewed. Real 0.12.6 startup/config suite. |
| `lazy-lock.json` | Every configured plugin/lock relationship checked; byte-for-byte baseline comparison and installed Git revision verification. |
| `lua/config/autocmds/bigfile.lua` | Threshold/swap transitions/cheapeners/FileType/deferred stop. Native large-to-small race and small-to-large control. |
| `lua/config/autocmds/editing.lua` | Every callback: yank/position/resize/trim/format/panel/commit/mkdir/checktime. Source review and retained behavior regressions. |
| `lua/config/autocmds/folds.lua` | View encoding/eligibility/save/load/cursor/freshness/pruning. Native timestamps and real default/numbered view artifacts. |
| `lua/config/autocmds/glue.lua` | Deferred session detection and loaded-only LuaSnip cleanup. Native ordinary/special/URI buffer rescue tests. |
| `lua/config/autocmds/init.lua` | All require/load ordering and augroup lifecycle premises. Real startup and combined regressions. |
| `lua/config/autocmds/lsplog.lua` | Threshold/stat/rename/notification/logger-open ordering. Actual 21 MiB rotation and retained-generation replacement. |
| `lua/config/autocmds/swap.lua` | Retained first-audit recovery/ownership/revalidation review; shared decoder extraction rechecked. All cleanup/directory regressions rerun. |
| `lua/config/dap.lua` | Every adapter, fallback, interpreter resolver, prompt, sign, pause and launch-loader branch. Real Linux adapter matrix; Windows limits explicit. |
| `lua/config/diagnostics.lua` | All report sections, recursive redaction, bounded log FD reads, filename collision and write failure paths. Native FIFO/long-line/failure regressions. |
| `lua/config/health.lua` | Every prerequisite/version/state-path/Python/MSVC branch. Actual path-obstacle/root/escaping tests; Windows/MSVC source review. |
| `lua/config/icons.lua` | All glyph keys/consumers and fresh severity mappings. Native statusline/bufferline integration; physical font rendering excluded. |
| `lua/config/keymaps.lua` | Every mapping/callback; Escape, deletion, save, zoom, prose, diagnostics and terminal behavior. Native window/prose/zoom regressions. |
| `lua/config/lazy.lua` | Lock resolution, staged bootstrap, publication/failure branches, manager setup and update policy rereviewed. Bootstrap/concurrency regressions rerun. |
| `lua/config/lsp_format.lua` | Every cancellation/request/response/timeout/lifecycle branch. Independent review; UTF-16, stale edits, wipe, focus and synchronous replies. |
| `lua/config/options.lua` | Every option and load-order premise; native trust, swap/undo/session/view and completion settings. Config suite; platform/UI limits apply. |
| `lua/config/util.lua` | Replacement selection; single/bulk buffer deletion and hooks; native option decoder; URI eligibility; Windows tar shim. Native deletion/health/swap regressions; Windows shim source review. |
| `lua/plugins/atone.lua` | Commands/setup/undo integration. Actual open/close on an edited buffer. |
| `lua/plugins/colorscheme.lua` | Startup priority, background/flavor, styles/integration identifiers. Actual light/dark themes and statusline refresh. |
| `lua/plugins/completion.lua` | Blink/LuaSnip source/key/capability/snippet and commandline routing. Real native command parser/completion; async source APIs reviewed. |
| `lua/plugins/dap.lua` | Every flow/breakpoint/stack/UI/virtual-text/persistence mapping and listener reviewed. Real adapter/multisession/crash flows; independent lifecycle regressions. |
| `lua/plugins/editor.lua` | Every editor integration callback and option. Native TSX comments, surround/align, animated scrolling/window-switch cleanup; API review. |
| `lua/plugins/explorer.lua` | Every tree option/key/custom callback and startup/reload timing. Real outside-directory startup plus deferred cwd regressions. |
| `lua/plugins/finder.lua` | All Telescope/fzf options, mappings, selection/path/delete/picker UI APIs. Real entries and clipboard-path tests; physical clipboard excluded. |
| `lua/plugins/folding.lua` | Provider cache/fallbacks, special/large exclusion, peek/hover/native K, Unicode truncation. Native providers and narrow-width probes. |
| `lua/plugins/formatting.lua` | All formatter lists/options/conditions/selection/toggle hooks and Mason lists. Real external formatting across 18 filetypes plus UTF-8 selection. |
| `lua/plugins/git.lua` | All Gitsigns/Diffview maps, visual staging and command argument handling. Real odd-filename partial staging and pathspec checks; residual documented. |
| `lua/plugins/lazydev.lua` | Library word-gating/runtime/dependency configuration. Actual LuaLS/LazyDev types and Blink module completion. |
| `lua/plugins/lsp.lua` | Every server/diagnostic/mapping/capability/attach/detach hook and setup dependency. Native clangd/LuaLS plus lifecycle/format/startup regressions. |
| `lua/plugins/neogen.lua` | Generate command/key, Doxygen conventions, dependency/snippet APIs. Native C parser to Neogen to LuaSnip expansion. |
| `lua/plugins/scoper.lua` | Checkout-relative local plugin, eager setup, clangd/query-driver flags and platform executable resolution. Real checkout loading; Windows source review. |
| `lua/plugins/search.lua` | Current-file target validation/escaping and result navigation hooks. Real backend normalization and ripgrep header tests. |
| `lua/plugins/session.lua` | All suppressions/save/quit/restore/scope rescue and debugger visibility/tab callbacks. Native subset/multi-tab tests and prior scope regressions. |
| `lua/plugins/terminal.lua` | All toggles/caches/exit/scheduling/escape/cwd/lazygit callbacks. Real terminal lifecycle and owned fake-lazygit process; cwd expansion residual. |
| `lua/plugins/treesitter.lua` | Every parser/install/task/cooldown/attach/textobject/context callback and option. Native aliases/context/textobjects; controlled installer races. |
| `lua/plugins/trouble.lua` | Every mode/key, count-aware next/previous and fallback/error behavior. Actual open quickfix view and counted movement. |
| `lua/plugins/ui.lua` | Every statusline/bufferline/menu/Incline/Fidget callback and option. Native panel geometry, themes/diagnostics, menu and rendering probes. |
| `lua/plugins/which-key.lua` | Every prefix/schema/key callback and lifecycle. Actual local popup after VimEnter. |
| `scoper.nvim/.luacheckrc` | Every rule/override reviewed for scope, platform line endings and tool semantics; relevant formatter/linter gates executed. |
| `scoper.nvim/Makefile` | Every target, dependency, tool override, runner and cleanup command reviewed. CI-equivalent targets executed; shared dependency bootstrap corrected. |
| `scoper.nvim/README.md` | Public API/commands/path/glob/backend/state/compiler/test documentation cross-checked against source and existing regression coverage. |
| `scoper.nvim/lua/scoper/cdb.lua` | Database schema/path/filter/digest/output/meta publication rereview. Native cache-obstacle regression and existing worker/filter tests. |
| `scoper.nvim/lua/scoper/cdb_worker.lua` | Worker isolation, job/result encoding and failure reporting rereview. Existing real background-process regressions rerun. |
| `scoper.nvim/lua/scoper/init.lua` | Configuration/setup and every public operation/deferred callback. Project/scope cancellation and LSP lifecycle regressions. |
| `scoper.nvim/lua/scoper/lsp.lua` | Compilation discovery/cache/spawn/worker/restart/root/reattach/lifecycle rereview. All existing regressions plus cache errors/names/generation tests. |
| `scoper.nvim/lua/scoper/path.lua` | Normalization/drive/UNC/key/relative/glob compilation/exclude semantics. Full path regressions plus UNC string-rule cases; no native Windows I/O claim. |
| `scoper.nvim/lua/scoper/pickers.lua` | Every context/anchor/glob translator/backend/find/grep/replace callback rereviewed. Existing real rg/plain search/escaping/confinement regressions rerun; unsupported glob and scoped-write limits retained. |
| `scoper.nvim/lua/scoper/state.lua` | Schema/defaults/migration/read/backup/save/sync/context, every mutator and matcher. I/O/context/outside-glob regressions; concurrent-save debt retained. |
| `scoper.nvim/lua/scoper/ui.lua` | All backend detection, directory selection/input/multi-select/presentation branches. Sentinel regression and retained plain-picker tests. |
| `scoper.nvim/lua/scoper/util.lua` | Argument splitting/backend preference/hash/atomic publication. All existing utility tests rerun; state/cache failure integration. |
| `scoper.nvim/plugin/scoper.lua` | Every command dispatcher, nargs/completion and status callback. Command tests plus context/name/path integration. |
| `scoper.nvim/stylua.toml` | Every rule/override reviewed for scope, platform line endings and tool semantics; relevant formatter/linter gates executed. |
| `scoper.nvim/tests/bootstrap.lua` | Runner/runtime isolation, real-config load and shared staged dependency publication reviewed. Child-process failures, incomplete/concurrent caches and custom app name tested. |
| `scoper.nvim/tests/cache_failure_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/cache_names_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/commands_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `scoper.nvim/tests/context_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/glob_roots_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/init_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `scoper.nvim/tests/lsp_inflight_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/lsp_lifecycle_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/lsp_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `scoper.nvim/tests/minimal_init.lua` | Runner/runtime isolation, real-config load and shared staged dependency publication reviewed. Child-process failures, incomplete/concurrent caches and custom app name tested. |
| `scoper.nvim/tests/path_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `scoper.nvim/tests/pickers_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `scoper.nvim/tests/state_io_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/state_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `scoper.nvim/tests/ui_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/unc_globs_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `scoper.nvim/tests/util_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `scripts/check-docs.sh` | All inventory/keymap/command/plugin/version/template/health/API guards reviewed and executed. ShellCheck; shell failure behavior reviewed. |
| `scripts/offline-seed-check.lua` | Plugin/tool/parser completeness collection and fail-closed report/exit paths. Actual installed-data completeness and Python runner tests. |
| `scripts/offline-seed.py` | Whole archive/checksum/schema/link/extraction/promotion/rollback/venv/launcher code rereviewed; unchanged first-audit security tests rerun. Platform debt retained. |
| `stylua.toml` | Every rule/override reviewed for scope, platform line endings and tool semantics; relevant formatter/linter gates executed. |
| `tests/behavior_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/bigfile_reread_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/bootstrap_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/buffer_lifecycle_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/buffer_menu_split_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/config_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/dap_python_adapter_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/dap_ui_lifecycle_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/diagnostic_tail_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/escape_float_lifecycle_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/explorer_directory_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/fixtures/lsp_initialization.lua` | Actual Lazy dependency startup with controlled Mason enable boundary; asserts user settings and Blink capabilities before first-server activation. Fresh child-process regression. |
| `tests/fold_view_freshness_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/health_paths_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/hooks_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/local_plugin_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/lsp_format_race_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/lsp_initialization_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/lsp_lifecycle_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/minimal_init.lua` | Runner/runtime isolation, real-config load and shared staged dependency publication reviewed. Child-process failures, incomplete/concurrent caches and custom app name tested. |
| `tests/navigation_paths_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/offline_seed_test.py` | Hostile archive, checksum/lock/platform, rollback, metadata/launcher and completeness tests rereviewed and rerun; real filesystem and controlled subprocess failures. |
| `tests/prose_undo_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/search_file_navigation_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/search_literal_paths_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/search_scope_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/session_dap_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/session_filetype_rescue_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/session_scope_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/session_ui_visibility_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/swap_cleanup_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/swap_directory_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/test_dependency_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/treesitter_context_bigfile_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/treesitter_install_alias_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/treesitter_install_spec.lua` | Existing regression source/intent retained from first audit; rerun under native 0.12.6, including prior safety/robustness cases. |
| `tests/view_janitor_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
| `tests/zoom_layout_spec.lua` | New regression: source/fixture isolation and intended failing behavior reviewed; executed under native 0.12.6 in final suite. |
