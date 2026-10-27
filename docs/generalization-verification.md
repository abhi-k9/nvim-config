# Configuration generalization verification

The implementation follows the approved separation of machine settings,
project identity, search membership, build selection and optional clangd policy.
Existing workflows retain their defaults except the documented Windows shell
inheritance and removal of inferred compiler-execution trust. See
[customization](customization.md) for migration and the feature guide index.

## Test environment

Local verification uses Neovim **0.12.6** on Linux with isolated XDG
config/data/state/cache directories and the locked plugin sources. The default
harness disables private `local.lua` loading and automatic parser provisioning.
Installer tests use controlled process/package APIs; representative startup
tests create their own override file and load the actual configuration/plugins.
Native file/search/shell tests use disposable files and real subprocesses.

Run all required checks from the repository root:

```sh
make ci
```

This includes luacheck/StyLua on both trees, documentation synchronization,
immutable-action checks, full configuration/Scoper suites, offline-seed tests
and action-updater tests. Individual Lua specs can be selected, for example:

```sh
nvim --headless --noplugin -u NONE -l scoper.nvim/tests/run.lua tests/settings_spec.lua
cd scoper.nvim
nvim --headless --noplugin -u NONE -l tests/run.lua tests/lsp_modes_spec.lua
```

The completed local run passed **734 executable tests**: 339 full-configuration,
329 Scoper, 52 offline-seed and 14 action-updater tests. Three platform-specific
cases were pending/skipped on Linux. Lint, formatting, documentation guards and
the immutable-action check passed. Native CI remains the platform-specific gate
described below; these counts do not imply full UI/debugger coverage on every OS.

## Contracts exercised

| Area | Verified behavior |
| --- | --- |
| Override lifecycle | Real local-file startup precedes maps/options/plugin opts; false, empty lists, callbacks and pre-set options survive; project parent replacement and leaf reads agree. |
| Tools | Pins/conditions/alias identities agree across readiness, health and seeds; actual installer callbacks reject conflicts before setup; unavailable requested tools remain incomplete. |
| Compiler ownership | Global project changes reconcile owned `CC` before another process starts; local-directory changes and intervening external edits preserve ownership. |
| First LSP activation | Completion/server settings and final clangd argv/environment are present at Mason's activation boundary; reconciling Scoper does not reload scope state. |
| Scoper state | Legacy/newer schemas, immutable snapshots, revisions/events, explicit reload, conflicting writers, failed I/O and unsaved project switching. |
| Scope queries | Directory/file/glob roots, exact predicates, outside roots, symlinks and real Telescope/ripgrep/fzf parsing; native fallbacks retain membership. |
| Compilation pipeline | Explicit/external/ambiguous/custom-named sources, immutable output, source replacement, no-op suppression, inherited argv/environment and owned configuration disposal. |
| Asynchronous changes | Strict first attachment, bounded timeout, worker failure, concurrent waiters, scope/build changes during preparation, and project changes during graceful client exit. |
| Debug/terminals | First/repeated setup, adapter opt-outs, actual custom launch provider, late project overlays, stock-provider delegation, Python transports, shell resolution and project lazygit handles. |
| Search/sessions | Literal directory boundaries, invocation roots, selectors/explorer opt-outs, manual sessions, global buffers, and automatic veto before debugger/scope cleanup. |
| Editing/UI/retention | Background-buffer trimming and EditorConfig precedence, owned prose maps, stock-theme/no-icons/reduced-motion whole startup, conservative configurable cleanup. |

The review found and fixed additional integration gaps before the batch push:
stranded startup waiters, stale commands during restart polling, selected-source
copy starvation, late debug-provider overrides, automatic-save layout changes,
compiler environment leakage and parser opt-out/version-validation mismatches.

## Platform coverage and limits

CI runs the full config on Linux; Scoper on Linux and native Windows; and seed
tests on Linux, Windows and macOS. The Windows job additionally runs real native
DAP spawning plus drive/UNC/root-path checks. Linux tests that simulate Windows
API selection do not replace those native checks. Full UI startup and every
debugger/toolchain combination are not exercised on every OS.

These are regression checks for the documented contracts, not a claim that all
possible configurations or external tools have been exhaustively tested. Custom
callbacks and native plugin overrides remain trusted executable configuration.
Third-party cwd/discovery boundaries are described in the feature guides.
Restricted replacement, automatic concurrent state merging, simultaneous
per-tab Scoper projects, and automatic cache garbage collection remain outside
this implementation. Header-only scopes can legitimately retain zero compilation
entries; no compiler standard or header/source relationship is invented.

The feature guides link the upstream Neovim, clangd, Lazy, Mason and backend
contracts used to check the design. In particular, project configuration remains
Neovim trust-gated and `query_drivers` is an explicit permission for clangd to
execute matching compiler programs.
