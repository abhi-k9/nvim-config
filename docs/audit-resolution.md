# Audit finding resolution

> Historical follow-up snapshot, last updated at `bb172db` (2026-10-23).
> File/test counts, timings and resolved behavior below belong to that batch.
> Consult the [README](../README.md) and feature guides for current behavior;
> subsequent revisions and their validation appear in [CHANGES.md](../CHANGES.md).

This follow-up addresses the unresolved findings in the
[first audit](audit-2026-10-21.md) and
[expanded audit](audit-followup-2026-10-22.md), starting from `d82a7f4`.
Their original observations and test counts remain historical evidence.
This records that batch's resulting behavior and verification limits, rather than
claiming exhaustive branch coverage or an audit of every upstream dependency.

## Findings addressed

| Area | Result | Evidence |
| --- | --- | --- |
| Concurrent Scoper state saves | Cooperating writers serialize comparison and atomic publication with owned directory locks. A conflicting save is refused, preserving disk state and local edits until explicit reload. Dead owners can be recovered; live/unknown locks are retained. Content comparison also detects equal-timestamp edits and deletions. | `state_concurrency_spec.lua`: two real Neovim writers synchronized before save, dead-owner process exit, thrown-write cleanup, stale direct saves, external edits/reset. Existing state/read-error/migration specs pass. |
| Compilation cache publication | Filtered objects are addressed by their content hash; metadata is an advisory pointer. Different source generations cannot overwrite each other's output objects. Source changes during work or result delivery get one retry, then a reported fallback. Warm hits check timestamps, size and identity. | `lsp_spec.lua`: reversed completion, delivery changes, bounded retries, same-size corruption and malformed metadata, plus existing native worker/filter/reload tests. Cache-name and failure regressions retained. |
| Toggleterm literal cwd | Configured shell mappings and lazygit pass `dir = "."` through the public API. New jobs use the active literal cwd; existing jobs retain their cwd. | `terminal_literal_cwd_spec.lua`: real shell output for global/window-local `$NAME` directories, reopening a running terminal, all configured shell mappings. |
| Diffview exact-file history | Current-file, working-copy and selected-line mappings refuse names whose glob/pathspec/backslash interpretation could change the target. The warning points to repository history. Ordinary paths retain the backend's existing command handling. | `history_literal_paths_spec.lua`: all mappings, visual ranges, ordinary special characters through the actual pinned Git adapter's expansion boundary, and ambiguous names refused before backend invocation. |
| Windows DAP spawning | Use Mason's native C++ executables, debugpy's venv interpreter and the Bash adapter's Node script; honor a configured Mason root. Avoid sending `.cmd` files directly to `uv.spawn`. | Five controlled adapter-selection tests, preserved Python transport specs, plus `tests/fixtures/windows_dap_spawn.lua` in native Windows CI. The fixture starts real native images/Python/Node with spaces, shell characters and Unicode in paths/argv. |
| Windows offline Python launchers | Rebase bounded, verified unsigned distlib PE/shebang/ZIP launchers using exact builder-root provenance. Preserve the native image and embedded script, refreshing an existing PE checksum. Unsupported known Python overlays remain unchanged and cause an explicit incomplete-install error. | Portable format/provenance/CRC/custom/signed-image tests and an actual bundled distlib launcher parser probe. Windows CI copies a real venv, removes the builder, relocates its launcher and executes it with literal argv; ImageHlp independently checks its checksum. Archive defenses remain covered on all three OSes. |
| Swap cleanup window | Recheck file identity after final header decoding and owner checks, immediately before unlink, in both cleanup commands. | Two regressions replace recovery data during final header decoding; the new data survives. Existing dirty/live/foreign-host/link/confirmation tests pass. |
| CI action references | Full immutable commit pins, with deliberate update-track comments. A manual updater resolves all pins before atomic replacement; failures/concurrent edits retain the workflow. | `make check-actions`: offline pin checks and 14 updater regressions. Existing job/step timeouts, read-only token permissions and credential persistence restrictions remain. |

## Verification environment

Local checks use Neovim **0.12.6**, installed locked plugin sources, isolated
config/data/state/cache/log directories, actual ripgrep and POSIX shell processes,
and disposable Python fixtures. The complete local gate is `make ci`: lint,
formatting, document consistency, action pins/updater, host specs, standalone
Scoper specs and offline-seed tests.

The local result is **590 executed tests**: 250 host configuration, 274 Scoper,
52 offline-seed and 14 action-updater tests. The Scoper harness additionally
reports its native Windows API case as pending on Linux; Python skips its native
Windows launcher execution case. Neither skip is counted as local execution.

Native CI has seven jobs: lint/documentation, full configuration on Ubuntu,
Scoper on Ubuntu/Windows, and offline seed on Ubuntu/Windows/macOS. The Windows
Scoper job also runs the DAP spawning fixture. Native results must be read from
the completed jobs of the Actions run for the pushed revision; local forced
Windows branches alone do not establish native execution. Full debugger sessions
are a separate boundary from successful adapter process spawning.

A disposable performance probe with **10,000 entries / 18.9 MB** measured about
**983 ms** for initial synchronous filtering and **0.21 ms** mean over 20 warm
lookups. Each warm lookup read only one **530-byte metadata file**, with stat
checks for the databases. These are observations on this environment, not timing
guarantees; automatic reloads still filter in a separate Neovim process.

## Retained limits and deliberate restrictions

- **Restricted replacement remains refused.** Pinned grug-far exposes no durable
  per-instance cwd for deferred searches/writes. Restoring that capability needs
  a supported upstream API or another backend. Direct unscoped replacement remains
  available. Scoper's Telescope search refuses directories the backend would
  expand into a different path; postfiltering wrong-directory results would still
  miss legitimate files. Raw plugin commands retain their upstream semantics.
- **Portable unlink is not compare-and-delete.** A path can still change between
  the last stat and unlink. The narrowed swap window is documented, not claimed
  eliminated. Renaming arbitrary active swaps into quarantine would add other
  recovery risks and was not introduced.
- **State locking coordinates cooperating editors.** External programs that
  ignore the lock can race publication. PID reuse can conservatively retain a
  dead lock; inspect it only after confirming no writer is active. Local edits
  after a conflict require preserving/copying before explicit reload, not an
  automatic merge with ambiguous deletion semantics.
- **Cache freshness uses filesystem identity.** Arbitrary edits that preserve
  every recorded stat field are outside the warm-hit contract. Outputs are
  verified by digest on publication/reuse. Old objects are retained so active
  clangd processes do not lose their database; close editors before manually
  removing `stdpath("cache")/scoper` to reclaim space. No automatic GC was added.
- **Virtual environments are not generally portable.** Signed/custom launchers,
  unsupported overlays, incompatible Python versions and native package ABI
  dependencies may require offline reinstall/rebuild at the final destination.
  Relocation support is limited to recognized layouts; it does not execute seed
  metadata as repair instructions.
- **Action pins cover action source.** Action-downloaded tools, runner images,
  Mason packages and parser versions retain their independent update policies.
  No transitive vulnerability scan or fully reproducible toolchain is claimed.
  See the README for deliberate action updates and changing major versions.
- **Remaining platform evidence gaps:** full MSVC/PDB/GDB sessions, remote
  gdbserver, Python PID injection/reverse transports against real targets, and
  physical clipboard/font/GUI behavior. Controlled transport tests preserve
  behavior; they do not substitute for all those environments. Arbitrary future
  dependency versions are outside the verified revision.

## File coverage reconciliation

The historical ledger accounts for 144 files. Twelve additions before this
follow-up bring the baseline to 156; ten additions here bring the final inventory
to **166 tracked files**. Existing files retain the review evidence in that
ledger, with changed code reviewed and tested as described above. The additional
files are accounted for below; file coverage does not imply 100% behavior or
security coverage.

| File added after the historical ledger | Review/verification |
| --- | --- |
| `docs/ci-troubleshooting.md` | Historical CI reproduction, native run, timeout and source evidence retained. |
| `docs/limited-environments.md` | Missing-tool integration and reminder behavior compared with supported defaults and specs. |
| `lua/config/health_reminder.lua` | Cadence, persistence, interactive gating and clock/lease recovery; reminder regressions retained. |
| `lua/config/tooling.lua` | Runtime/download/build prerequisite gates, bounded probes and skip reporting; complete/minimal toolsets covered. |
| `scoper.nvim/lua/scoper/windows.lua` | UTF-8/UTF-16 conversion, bounded Windows API allocation and failure returns; native short-path/Unicode CI case. |
| `scoper.nvim/tests/run.lua` | Shared sequential harness and nonzero initialization exits; host and standalone CI entrypoint. |
| `scoper.nvim/tests/short_paths_spec.lua` | Controlled aliases and native Windows filesystem/Unicode cases. |
| `scripts/ci-run.py` | Bounded escaped annotations, streamed output and process status; existing failure/Unicode/signal probes retained. |
| `tests/config_runtime_spec.lua` | Cold plugin install runtime discovery regression. |
| `tests/health_reminder_spec.lua` | Reminder timing, persistence, clock corrections and concurrency recovery. |
| `tests/test_runner_spec.lua` | Initialization errors exit promptly in child Neovim. |
| `tests/tooling_spec.lua` | Missing/available runtimes, native builds and supported automatic installation. |
| `scoper.nvim/tests/fixtures/state_writer.lua` | Real editor save barrier and abrupt writer exit; isolated shared data root. |
| `scoper.nvim/tests/state_concurrency_spec.lua` | Native cooperating writers plus content/conflict/error regressions. |
| `scripts/update-ci-actions.py` | Explicit ref resolution, input validation, offline checks and all-or-nothing file update. |
| `tests/ci_actions_test.py` | Network-free pin policy, update, failure, syntax and concurrent-edit regressions. |
| `tests/dap_windows_adapters_spec.lua` | Controlled platform selection, native/runtime paths, custom Mason root and Unix behavior. |
| `tests/fixtures/windows_dap_spawn.lua` | Native Windows libuv spawn contract and literal Python/Node argv; bounded child processes and cleanup. |
| `tests/history_literal_paths_spec.lua` | Exact-file mapping safety, adapter expansion, ordinary history and visual selection. |
| `tests/scoper_telescope_spec.lua` | Actual pinned Telescope/ripgrep entry filtering and path-expansion refusal. |
| `tests/terminal_literal_cwd_spec.lua` | Actual shell cwd, local cwd and persistent terminal behavior. |
| `docs/audit-resolution.md` | Finding dispositions, evidence boundaries and file inventory reconciled. |

## Online corroboration

Retrieved upstream source was compared with the implementation and regressions.
The environment blocked direct access to some documentation domains; their public
GitHub source mirrors were read instead.

- [GitHub secure-use guidance](https://github.com/github/docs/blob/main/content/actions/reference/security/secure-use.md): full commit pins and their supply-chain scope; guidance also distinguishes transitive workflow locking.
- [Python venv portability](https://github.com/python/cpython/blob/3.12/Doc/library/venv.rst): absolute interpreter paths and general non-portability.
- [Distlib script generation](https://github.com/pypa/distlib/blob/master/distlib/scripts.py): native launcher + UTF-8 shebang + appended `__main__.py` ZIP layout.
- [Microsoft PE format](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/Debug/pe-format.md) and [PE checksum reference](https://github.com/erocarrera/pefile/blob/master/pefile.py): checksums cover the full file and differ from signatures. Native Windows ImageHlp verifies recalculated launcher checksums.
- [Libuv process options](https://github.com/libuv/libuv/blob/v1.x/docs/src/process.rst): Windows `CreateProcess` argument handling.
- Mason registry layouts: [cpptools](https://github.com/mason-org/mason-registry/blob/main/packages/cpptools/package.yaml), [codelldb](https://github.com/mason-org/mason-registry/blob/main/packages/codelldb/package.yaml), [debugpy](https://github.com/mason-org/mason-registry/blob/main/packages/debugpy/package.yaml), [Bash adapter](https://github.com/mason-org/mason-registry/blob/main/packages/bash-debug-adapter/package.yaml).
- [Pinned Telescope file/grep implementation](https://github.com/nvim-telescope/telescope.nvim/blob/40aedd8a68c78a656a10a8d62d80c54af59420fb/lua/telescope/builtin/__files.lua): option resolution, public entry maker and additional arguments, and directory expansion.
- [Pinned Toggleterm](https://github.com/akinsho/toggleterm.nvim/blob/9a88eae817ef395952e08650b3283726786fb5fb/lua/toggleterm/terminal.lua): directory expansion and terminal spawning.
- [Pinned Diffview Git adapter](https://github.com/dlyongemallo/diffview-plus.nvim/blob/2a2d89a07f5d5d3cef7f542b99c3e28050ca205c/lua/diffview/vcs/adapters/git/init.lua): pathspec expansion and selected-line history handling.
