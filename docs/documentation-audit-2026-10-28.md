# Documentation and comment audit — 2026-10-28

Baseline: `e3218ac`. The review accounted for all **202 tracked baseline files**,
including **37 documentation/template files**, runtime comments, test comments,
script docstrings/help and repository metadata. This report adds one file.
Ignored machine-local settings and downloaded dependency trees are outside that
inventory; dependency sources were consulted to verify specific public contracts.

## Corrections and expanded explanations

| Area | Corrections and useful context |
| --- | --- |
| Installation and partial environments | Distinguish the audited bundle from GitHub source archives, required editor/bootstrap tools from optional development tools, supported build discovery from guaranteed availability, and per-language readiness from a universal startup prerequisite. |
| Updates and CI | Plugin update checks do not apply updates. Recover a known-good lockfile before `:Lazy restore` when undoing an update that rewrote it. Clarify immutable action pins versus separately downloaded tools, one run per batch push versus separate push events, native-platform bounds and controlled parser provisioning in tests. |
| Local configuration and trust | `exrc` is off by default; explicit pre-set options survive. Explain returned settings versus executable side effects, project overlay matching versus registration lifetime, and the difference between trust approval and a sandbox. |
| Debugger workflows | Launch files are read when selecting a new configuration, not on every active Continue/RunLast. Explain CodeLLDB command/evaluation REPL versus debuggee stdin, client-dependent external terminals, symbol lookup tradeoffs, expression modes and post-exit UI limits. Remove global ptrace-disable and broad antivirus-exclusion recipes from current guidance. |
| C/C++ examples | Correct clangd user/project precedence, compilation-database discovery and header command inference. Explain clang-tidy diagnostic scope/version-dependent wildcard checks, formatter semantic caveats and physical-line suppression. Correct the annotated `FullyQualifiedNamespaces` value to an empty list. |
| Scoper | Document the current store/pipeline ownership, immutable source databases, empty-scope behavior, asynchronous selectors, inherited clangd arguments, worker/fallback boundaries and Windows case-sensitivity assumptions. |
| Search and sessions | Explain backend-dependent fuzzy syntax and filename formatting, captured scope queries, invocation cwd versus project/session identity, nil automatic-save callback names, backend expansion of suppression entries and executable session files. |
| Editing and UI | Correct clipboard/Insert-mode behavior, Visual Studio shortcuts, Neogen defaults, bufferline pin ordinals, zoom restoration, fold/cursor restoration and split equalization. Add actionable format-on-save and fold/split explanations. |
| State and diagnostics | Use actual `stdpath()`/option values for cleanup, explain the data lost by each reset, retain recovery distinctions and narrow concurrent-cleanup claims. Clarify log rotation, diagnostic privacy, process snapshots and the limits of heuristic redaction. |
| Historical evidence | Preserve original observations, metrics and timestamps. Add explicit snapshot notices and correction notes where an old technical explanation could otherwise be reused as current advice. |

The maintained entry points are the [README](../README.md),
[customization guide](customization.md) and its linked feature guides. Historical
audits and changelogs explain past work; they are not installation instructions
or a live count of tests, files or supported dependency versions.

## Coverage reconciliation

The following non-overlapping assignments reconcile to the baseline inventory.
Each included unchanged files as well as files requiring corrections.

| Review area | Baseline files |
| --- | ---: |
| Tooling, installation, CI, scripts and related tests | 37 |
| Scoper implementation, tests and guides | 46 |
| Debugger/terminal files and historical reports | 23 |
| Editing/UI, keymaps and swap guidance | 23 |
| LSP, completion and C/C++ templates | 18 |
| Search, sessions, history and state guidance | 21 |
| README, customization, settings/utilities, metadata and remaining test comments | 34 |
| **Total** | **202** |

## Behavior defect exposed by the review

Scoper captured scope membership before refreshing an external save. The first
search after another editor changed the active scope could therefore use stale
roots or reject a root that was no longer selected. A first replacement request
could also miss a newly saved restriction.

The fix refreshes `State.context()` before reading membership. Two regressions
failed before the fix and pass afterward: first-search freshness, including a
formerly missing root, and first-replacement restriction enforcement. Existing
open pickers still retain their captured scope; this does not introduce live
mutation of an already open result set.

Other changes are explanatory text/help and the corrected documentation-template
value. Plugin/tool pins and the configuration's defaults remain unchanged.

## Verification and limits

- `make ci` passed on Neovim **0.12.6** in the isolated Linux environment:
  **756 executed tests** (690 Lua, 52 offline-seed, 14 action-updater), with two
  Lua cases pending and one Python case skipped for native Windows behavior.
  Lint, formatting, documentation guards and immutable-action checks passed.
- All 47 changed Lua files compiled. Stripped LuaJIT bytecode was unchanged in
  the 45 files containing comment-only edits; differences were confined to the
  Scoper refresh fix and its regression file. Python syntax/structure was
  unchanged apart from docstrings and two CLI-help strings.
- The pinned nvim-dap loader parsed all nine active launch examples. Current
  Markdown examples passed syntax checks: 22 Lua snippets, one JSON field block
  in its documented object context, and 34 shell snippets. Syntax checking does
  not execute setup, cleanup or project-specific commands.
- All 94 local Markdown/HTML references and fragments were checked across 31
  files. All 110 distinct public GitHub targets returned HTTP 200, and selected technical claims
  were compared with the referenced source and locked dependencies. A successful
  HTTP response does not establish the accuracy of every upstream statement.
- C/C++ template checks included clangd configuration parsing and focused
  diagnostic/suppression probes. Selected state-cleanup examples were exercised
  against disposable Unix data. PowerShell examples were reviewed, not executed
  locally; native CI is a separate platform gate.

This is complete coverage of the repository's documented/commented surfaces at
the baseline, not proof of every behavior, configuration or upstream dependency.
Historical experiments were not all rerun. Native Windows/macOS interactive
debugging, terminal encodings, physical clipboard/font behavior and arbitrary
project/toolchain combinations still require their own environment checks.

## Corroboration

Relevant sources include the locked implementations and:

- [Neovim 0.12.6 documentation](https://github.com/neovim/neovim/tree/v0.12.6/runtime/doc), including trust, terminal input and process-wait behavior.
- [CodeLLDB 1.12.3 manual](https://github.com/vadimcn/codelldb/blob/v1.12.3/MANUAL.md) and [LLDB on-demand symbol tradeoffs](https://github.com/llvm/llvm-project/blob/llvmorg-22.1.8/lldb/docs/use/ondemand.rst).
- [Clangd compilation-database selection](https://github.com/llvm/llvm-project/blob/llvmorg-22.1.8/clang-tools-extra/clangd/GlobalCompilationDatabase.cpp) and [configuration schema](https://github.com/llvm/llvm-project/blob/llvmorg-22.1.8/clang-tools-extra/clangd/ConfigFragment.h).
- [Clang-tidy user manual](https://github.com/llvm/llvm-project/blob/llvmorg-22.1.8/clang-tools-extra/docs/clang-tidy/index.rst) and [clang-format style options](https://github.com/llvm/llvm-project/blob/llvmorg-22.1.8/clang/docs/ClangFormatStyleOptions.rst).
- [Microsoft's Visual Studio shortcut reference](https://github.com/MicrosoftDocs/visualstudio-docs/blob/main/docs/ide/default-keyboard-shortcuts-in-visual-studio.md).
- [Linux Yama attach policy](https://github.com/torvalds/linux/blob/v6.12/Documentation/admin-guide/LSM/Yama.rst).
