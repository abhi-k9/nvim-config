# Reliable breakpoint persistence

The config uses the maintained `abhi-k9/persistent-breakpoints.nvim` fork. F9 / `<leader>db`, conditional and hit-count
`<leader>dB`, logpoint `<leader>dP`, listing `<leader>dx`, and clearing
`<leader>dX` keep their meanings. Both conditional prompts empty cancels;
an empty logpoint prompt cancels.

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

Conditional breakpoints, hit counts and logpoints require support from the
selected debug adapter.

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

If a clear fails, live breakpoints stay active. Retry the clear after resolving the
storage error. Project names containing literal environment references such as
`$PROJECT` now get their own store. If an older version expanded the name,
inspect the old project's snapshot before moving any breakpoints. Its store may
also contain breakpoints from the directory with the expanded name.

If another editor saved first, keep the editor with the rejected save open.
Run `:PBExport <file>` there and choose an unused filename in an existing
backup directory. Use Tab to complete paths with spaces. Wait for the success
message before quitting. If the export fails, choose another path and retry.
The command leaves both the shared store and your pending edits intact.

The exported JSON contains the file-to-breakpoints map. After closing both
editors, back up the winning store and compare its `breakpoints` field with
the export to reconcile the changes.

Corrupt files are not automatically deleted or replaced by empty maps: back up,
repair JSON or restore a reviewed backup. Deleting versioned files can expose
older legacy state again; use `<leader>dX` to clear the owned project's state.

Interrupted writers may leave `.lock` / `.tmp-*` siblings. They are never stolen
or imported automatically. Stop all relevant editors, back up and inspect the
directory, then remove only stale lock/temp files. File fsync is performed, but
parent-directory fsync is not: power-loss durability is not guaranteed.
Network shares and Windows antivirus/rename interference require native testing.
