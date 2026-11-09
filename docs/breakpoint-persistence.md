# Reliable breakpoint persistence

The config uses the maintained `abhi-k9/persistent-breakpoints.nvim` fork. F9 / `<leader>db`, conditional and hit-count
`<leader>dB`, logpoint `<leader>dP`, listing `<leader>dx`, and clearing
`<leader>dX` keep their meanings. Both conditional prompts empty cancels;
an empty logpoint prompt cancels.

## Audit decision and fork assessment

The evaluated persistent-breakpoints pin was
`d1656221836207787b8a7969cc2dc72668c4742a`, also the main head returned by GitHub
during this audit. Upstream was unarchived; its latest commit (2025-03-22)
addresses session loading. No open PRs were returned. Open issues included #28
(initialization/module loading) and #8 (whole-project loading).

The maintenance fork fixes demonstrated storage and lifecycle defects while
retaining the public mapping API. Its `store.lua` and `core.lua` replace unsafe
storage and duplicate mutable state; there are no config-local persistence wrappers.
No new runtime dependency was added. Fork maintenance includes the small enumeration
boundary with nvim-dap and the storage/lifecycle regression suites.

| Finding | Severity | Likelihood and practical impact | Evidence and disposition |
| --- | --- | --- | --- |
| Destination opened with `w+` before encoding | High | Encoding/I/O failures or interruption can lose the previous store | Injected unencodable value: save threw and a valid file became zero bytes. Validate/encode first, write/fsync a sibling, then rename. |
| Decode errors escape initialization | High | Any truncated/malformed store can prevent setup | Invalid JSON reproduced a thrown load. Warn, preserve bytes and block writes to unreadable state. Ordinary debugging remains available. |
| Slash-to-underscore cwd collision | High | Projects such as `/a_b/c` and `/a/b_c` share state | Reproduced identical filenames. Hash canonical cwd and verify root metadata. |
| Editors overwrite stale whole maps | High | Likely with multiple editors of one project; another editor's work disappears | Independent store contexts now demonstrate stale-writer rejection under an exclusive lock. No silent last-writer-wins merge. |
| DirChanged clears through `dap.breakpoints.clear()` | High | During debugging, signs and adapter breakpoints can disagree | Source-confirmed bypass of adapter broadcast. Defer switches during debugging; use public setters/clear. |
| Restore uses low-level placement | Medium | Files loaded during debugging may show markers without notifying the adapter | Public setters now notify sessions; fake-session request recording tests this boundary. |
| Snapshots do not automatically follow edits/renames | Medium | Wrong lines or old filenames after editing | Real sign movement/rename tests; capture tracked files on write/unload/exit and mapped changes. |
| Unchecked write/close results | High, conditional | Disk full, permissions or filesystem failures may appear successful | Source-confirmed risk. Fault tests cover denied reads, partial/failed writes, fsync and rename; no real disk was filled. |
| Session buffers exist before contents load | Medium | Premature/wrong-line restoration | Upstream #24 documents this history. Restore only loaded files, including late arrivals. |

## Lifecycle and debugger contract

The persistence plugin and DAP load on BufReadPost. Setup reads the cwd store once and restores loaded files. BufReadPost,
BufWinEnter and SessionLoadPost reconcile arrivals; auto-session also refreshes
after scope restores hidden buffers. JSON filenames never cause files to open,
and JSON is never executed. Repeated events do not reload an unchanged project.

Mapped changes save immediately. Writes, unload and exit capture moved lines and
renamed loaded buffers in tracked files; unchanged state produces no disk write.
External renames of unopened files cannot be inferred. Persisted fields are
`line`, `condition`, `hitCondition` and `logMessage`; adapter IDs, verification
results and buffer numbers are transient.

Restore/clear use public `dap.set_breakpoint()` / `dap.clear_breakpoints()`.
Enumeration uses one isolated typed but undocumented API, `dap.breakpoints.get()`:
public quickfix lists omit structured fields. Test this contract on DAP updates.
No adapter-specific persistence logic is involved. C/C++, Rust, Python, Bash and
other adapters receive the same fields; support for conditional/hit/log features
still depends on the adapter.

The effective cwd, including local cwd, owns the store; Scoper and launch roots
do not redefine it. Realpath canonicalizes existing roots, without globally
lowercasing case-sensitive volumes. Aliases realpath cannot unify may produce
separate stores. Windows drive/UNC and unusual filenames never enter shell
commands; relative persisted filenames and NUL are rejected.

During any DAP session, cwd switching is deferred with a warning and edits still
belong to the original project. After termination/disconnect, a scheduled refresh
or subsequent buffer/directory event reconciles cwd. Failed saves and unreadable
destinations also prevent destructive project switches.

Raw DAP calls in untracked files remain outside automatic persistence. In tracked
files, DAP UI/raw changes are captured on write/unload/exit: raw calls are not a
guaranteed temporary-breakpoint API. Out-of-range saved lines warn and retain
that file's stored data instead of treating partial restoration as deletion.

## Storage and migration

Storage is `stdpath("data")/nvim_checkpoints/v1-<sha256-root>.json`:

```json
{
  "version": 1,
  "root": "/absolute/canonical/project",
  "breakpoints": {
    "/absolute/source.cpp": [
      {"line": 42, "condition": "x > 0", "hitCondition": ">= 5", "logMessage": "x={x}"}
    ]
  }
}
```

Empty maps/lists may encode as `[]`; both empty representations are accepted.
Absent, empty and explicit clear differ: absent state can import legacy data;
an existing versioned empty store always takes precedence. Unknown schema,
wrong root, malformed fields/lines, relative names, symlink/nonregular files
and files over 4 MiB are rejected.

When no versioned store exists, the cwd-derived legacy JSON is read/validated.
The first successful mutation writes and verifies the new copy. **Legacy bytes
are never rewritten or removed.** A changed legacy source during migration
rejects saving. Old filename collisions cannot be disambiguated: inspect imported
markers when projects had colliding names. Other cwd aliases and custom legacy
`save_dir` overrides require manual review; no speculative scan imports other
projects. The plugin retains `setup({save_dir = ...})` for custom storage. Update old
Lazy overrides to the fork owner; do not install both repositories. Do not mix old/new editors during migration.

For rollback, close editors, back up the checkpoint directory, restore the
previous config/lockfile and run `:Lazy restore`. Legacy originals remain usable.
New edits exist only in versioned files: review and copy the `breakpoints` map
to the appropriate backed-up legacy JSON to retain them. Never blindly overwrite
an ambiguous legacy filename; retain new files until rollback is verified.

## Failure recovery and multiple editors

New directories use POSIX 0700 and files 0600. Existing permissions and Windows
ACLs are not rewritten. Store-file symlinks are rejected; a symlink at the writable
directory blocks saving. Parent directories are trusted user storage, not a
sandbox against a process running as the same OS user.

Saving exclusively creates `<store>.lock`, compares current bytes with this
instance's baseline, writes/fsyncs/closes a unique sibling, then renames over the
destination and verifies readback. There is no delete-old-file fallback on Windows.
Partial writes complete or fail without replacing the previous store.

Conflicts, corruption and permission failures warn and retain unsaved memory.
Later changes/writes/exit retry transient failures. Dirty state is never silently
reloaded or blindly merged with another editor's clear. Manual retry:
`:lua require("persistent-breakpoints.api").store_breakpoints()`.

Before closing with unsaved changes, export them and copy the printed temporary
file to durable storage:

```vim
:lua local s = require("persistent-breakpoints.api").snapshot(); local p = vim.fn.tempname() .. ".breakpoints.json"; assert(vim.fn.writefile({vim.json.encode(s)}, p) == 0); print(p)
```

`snapshot()` returns the map and, as its second value, the owned target filename.
With all relevant editors closed, review/merge recovery data, then restart.
Corrupt files are not automatically deleted or replaced by empty maps: back up,
repair JSON or restore a reviewed backup. Deleting versioned files can expose
older legacy state again; use `<leader>dX` to clear the owned project's state.

Interrupted writers may leave `.lock` / `.tmp-*` siblings. They are never stolen
or imported automatically. Stop all relevant editors, back up and inspect the
directory, then remove only stale lock/temp files. File fsync is performed, but
parent-directory fsync is not: power-loss durability is not guaranteed.
Network shares and Windows antivirus/rename interference require native testing.

## Validation and limitations

Tests use temporary directories, never real user stores. Storage coverage includes
all fields, first run/clear, migration preservation, malformed/truncated JSON,
schema/path validation, Unicode/drive/UNC paths, injected permissions and I/O
failures, partial writes, symlinks, stale writers and stale locks. Lifecycle tests
use real DAP signs/setters for mapped prompts/F9, restart-like reinitialization,
late/session loads, multiple files, renames, switches, clear and adapter notification.

Validation here uses Linux/Neovim 0.12.6. Independent store contexts test concurrency
interleavings, not a two-process Windows stress test. Native Windows/macOS, network
shares, power-cut durability and live debuggees across every adapter are not
certified. Full process restart and actual auto-session restoration remain useful
native manual checks. CI gets fast ordinary specs, no new matrix or debugger
downloads.

Related pins: nvim-dap `cfa2d58f4537aca6ca83e2de1a0d9f1491121264` (also current
upstream head queried), auto-session `02a5588f677970a9bc784115c62bef9e5855499b`,
and the existing DAP UI fork revision in `lazy-lock.json`. Adapter definitions
and launch configuration are unchanged.

## Sources

- [Persistence utilities](https://github.com/Weissle/persistent-breakpoints.nvim/blob/d1656221836207787b8a7969cc2dc72668c4742a/lua/persistent-breakpoints/utils.lua),
  [API/lifecycle](https://github.com/Weissle/persistent-breakpoints.nvim/blob/d1656221836207787b8a7969cc2dc72668c4742a/lua/persistent-breakpoints/api.lua)
  and [setup](https://github.com/Weissle/persistent-breakpoints.nvim/blob/d1656221836207787b8a7969cc2dc72668c4742a/lua/persistent-breakpoints/init.lua).
- [Session issue #24](https://github.com/Weissle/persistent-breakpoints.nvim/issues/24),
  [initialization issue #28](https://github.com/Weissle/persistent-breakpoints.nvim/issues/28),
  [whole-project request #8](https://github.com/Weissle/persistent-breakpoints.nvim/issues/8).
- [DAP API](https://github.com/mfussenegger/nvim-dap/blob/cfa2d58f4537aca6ca83e2de1a0d9f1491121264/doc/dap.txt),
  [public setters/broadcast](https://github.com/mfussenegger/nvim-dap/blob/cfa2d58f4537aca6ca83e2de1a0d9f1491121264/lua/dap.lua)
  and [enumeration contract](https://github.com/mfussenegger/nvim-dap/blob/cfa2d58f4537aca6ca83e2de1a0d9f1491121264/lua/dap/breakpoints.lua).
