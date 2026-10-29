# Scoper project, scope and state contracts

Scoper keeps three choices separate: the project that owns saved state, a named
search scope, and the compilation database selected for that project. Changing
the scope does not select a different build. The clangd integration mode is a
fourth, optional policy; see [Scoper integration](scoper-integration-notes.md).

## Project identity and configuration

Without an override, the project is the **global** working directory (`:cd`).
Window-local and tab-local directories (`:lcd`, `:tcd`) do not move the project,
state file or filtered database cache. Scoper has one active project per editor;
different tabs do not get simultaneous project instances.

Use a fixed root or an explicit resolver if the project differs from `:cd`:

```lua
require("scoper").setup({
  project = {
    root = function(global_cwd)
      return vim.fs.root(global_cwd, { ".git", "CMakeLists.txt" }) or global_cwd
    end,
  },
})
```

`project.root` accepts a path string or `function(global_cwd)`. Relative paths
resolve against that global directory. A resolver returning `nil`, `false` or
an empty string uses the global directory. Resolvers run in the main editor;
workers receive captured serializable inputs. Scoper does not discover or
execute project-local Lua configuration.

`setup(options)` resolves configuration from stable shipped defaults on every
call. Dictionary options merge; lists, including `{}`, replace. A second setup
does not inherit a previous call's custom lists. Existing in-memory state for
the same project is retained; new `default_excludes` apply to future scopes,
not existing ones. `patch(options)` explicitly layers options over the effective
configuration, then performs the same lifecycle reconfiguration. Neither is a
state-recovery command.

Inspect `require("scoper").config` for effective configuration and
`require("scoper").status_snapshot()` for a copied runtime status. Use
`:ScoperShow` for a readable panel containing project, revision, persistence and
database information.

## Search membership

Includes accept directories, individual files and globs. For example:

```vim
:ScoperAdd src/ include/public.h tests/**/*.cpp
:ScoperExclude **/generated/**
:ScoperToggle
```

Command-line paths with spaces use Vim escaping (`my\ dir`). Includes added by
the user expand `~` and environment variables, are stored relative to the
project when possible, and are deduplicated by path identity. Missing paths
remain selected with a warning, so a generated directory can appear later.
Excludes remain glob strings; invalid patterns are refused. Excludes match
project-relative paths for includes inside the project. For an outside include,
relative excludes use that include's directory or a glob's deepest literal
ancestor. Symlinks retain their logical spelling; they are not canonicalized to
their target. Backend link-following policy remains a separate choice.

For compatibility, **disabled scoping or an empty include list is unrestricted**,
and excludes are not applied in that state. An exclude-only scope does not mean
"the whole project minus these paths". Add `.` if that is the intended scope.

The shared `scoper.scope` module is stateless:

```lua
local Scope = require("scoper.scope")
local matches = Scope.compile({ include = { "src/**/*.c" }, exclude = {} }, root)
local query = Scope.query({ include = { "src/**/*.c" }, exclude = {} }, root, true)
```

`compile()` captures an exact `matches(path)` predicate. `query()` returns:

| Field | Meaning |
| --- | --- |
| `restricted` | Whether the scope imposes include/exclude restrictions. |
| `roots` | Existing file/directory search roots; `nil` for unrestricted queries. |
| `matches`, `in_scope` | The same captured exact membership predicate. |
| `excludes` | A copy of active excludes; empty for unrestricted queries. |
| `missing` | Includes without an existing literal search root. |

`compile()` evaluates the supplied definition directly; an empty include list
matches nothing there. `query()` applies Scoper's compatibility policy first,
so a disabled or empty scope returns an unrestricted predicate and no roots.
Use `query()` when implementing a search adapter that must honor that policy.

A file contributes its own path. A glob contributes its deepest complete literal
ancestor; glob expansion never triggers an unbounded discovery walk. Search
adapters apply the exact predicate as well as the bounded roots. A restricted
query with no usable roots is refused instead of silently searching the whole
project. The CDB filter uses the same matcher. `State.active_dirs()` remains a
directory-only compatibility accessor; new adapters use `State.query()`.

Search roots bound where a backend looks, but a glob's literal ancestor can
contain out-of-scope files. Exact filtering constrains returned results, not
filesystem access by the search tool. Scoping is a selection policy rather
than an access-control boundary.

## Snapshots, revisions and events

`require("scoper").snapshot()` returns a deep-copied view:

```lua
{
  root = "/project",
  scope = "default",
  revision = 12,
  enabled = true,
  definition = { include = { "src" }, exclude = {} },
  database = "/build/compile_commands.json", -- nil when not selected in state
  result = { applied = true, persisted = true, reason = "saved" },
  unsaved = false,
}
```

Mutating this snapshot cannot change live state. `scoper.state.context()` supplies
the comparison identity (`root`, `scope`, `revision`, `database`) for delayed
operations. Revision increases monotonically for accepted changes and project
loads, including changes to a scope that keeps the same name. Scope-sensitive
management selectors cancel if their captured revision changes while they are
open. Search pickers instead retain the exact query captured when opened;
changing the active scope does not retarget an already-open picker.

The existing `User ScoperChanged` event has `args.data` containing:

- `root`, `scope`, `revision`, `database`: the new context;
- `reason`: for example `scope`, `enabled`, `database`, `load`, `refresh` or
  `restore_unsaved`;
- `changed`: the affected categories (`scope`, `enabled`, `database`, `project`);
- `persistence`: a copied result with `applied`, `persisted`, `reason`, optional
  `error`.

Consumers should capture snapshots and use supported mutators. The old mutable
`State.state`, `active_scope()` and `scope(name)` accessors remain for compatibility;
direct writes through them do not participate in revision tracking and are not
the supported integration API. Existing `build_matcher()` delegates to the
stateless matcher.

## Persistence and conflict recovery

The `store.lua` module owns the schema, legacy migration, corruption backups,
writer lock, content comparison and atomic publication. `state.lua` owns active
selection, revisions and notifications. A saved state includes
`schema_version = 1`. Files without a version migrate on their next successful
save. An unsupported schema is never overwritten; Scoper uses session defaults
and reports `unsupported_schema` until an explicit reload can read supported
data. Keep the original file or upgrade Scoper instead of deleting unfamiliar
fields to force a save.

Mutators preserve their legacy count/boolean returns and add a result at the
end. For example, `State.add_paths()` returns `count, missing, result`,
`remove_paths()` returns `count, result`, and `new_scope()` returns
`accepted, error, result`. `clear_active()`, `set_enabled()`, `toggle()` and
`set_database()` return a result directly. `State.save()` remains
`saved, result`. With explicit arguments, public
`scoper.add/remove/exclude/remove_exclude/new/use/clear/toggle/select_database`
return the result; batch `delete` returns `{ deleted, errors, outcomes }` with
each named result. No-argument selector forms are asynchronous and return `nil`
before a choice is made; use the resulting state event or invoke an explicit
mutator when the caller needs a synchronous outcome.

| Result | Meaning |
| --- | --- |
| `applied=true, persisted=true, reason="saved"` | The in-memory change was saved. |
| `applied=true, persisted=false, reason="conflict"` | The other writer's state is intact; this editor retains its changes. |
| `applied=true, persisted=false, reason="io_error"` | The change is session-local; fix the cause and retry saving. |
| `reason="unsupported_schema"` | The store uses an unsupported schema and saves are blocked. |
| `applied=false, reason="unchanged"` | A count-based mutation did not change the scope. |
| `applied=false, reason="invalid"/"exists"/"missing_scope"/"last_scope"` | The request was refused. |
| `applied=false, reason="unsaved"` | Reload would discard local changes. |

`persisted` reports the operation's publication state; `snapshot.unsaved` reports
whether this editor currently has unsaved state. Outcomes are structured so
callers do not need to parse notification text. A failed save still emits the
change event: the accepted local scope can immediately affect search and clangd.

Cooperating editors serialize compare-and-publish using an owner-marked lock.
A stale write is refused rather than merging scopes automatically. Changes that
another editor saved are refreshed before the next mutation, provided this
editor has no unsaved changes. Failed local publications are never replaced by
an automatic refresh. Find, grep and replace also refresh before capturing their
first query, so new roots and replacement restrictions apply on the next call.
Unsaved state is retained in memory when switching projects
and restored on return with its original store baseline. This protects changes
within the running editor; an editor exit still loses unsaved session state.

Use the recovery commands deliberately:

```vim
:ScoperReload       " Re-read saved state; refuses unsaved local changes
:ScoperReload!      " Discard local changes and re-read saved state
```

The equivalent API is `require("scoper").reload({ force = true })`. Reload acts
on the active loaded project and does not reconfigure plugins. Retrying
`require("scoper.state").save()` after an ordinary I/O failure can persist local
changes; a conflict requires an explicit reload and reconciliation. `State.load()`
is retained as a lower-level, unconditional compatibility operation; callers
that need discard protection should use `reload()`.

## Selecting a build

```vim
:ScoperDatabase /external/build/compile_commands.json
:ScoperDatabase           " Show selection and integration status
:ScoperDatabase!          " Clear the saved selection
```

The path is project-wide and persists independently of the named scope. A missing
database may be selected before a build generates it. Clearing selection returns
to the configured resolver/candidates; it does not delete source or cache files.
See [Scoper integration](scoper-integration-notes.md) for selection precedence,
modes, source refresh and compiler-execution trust.

## Verification

The regression suite covers legacy state I/O and simultaneous native writers,
snapshot isolation, revisions/events, explicit reload, newer-schema refusal,
failed-save project switching, setup versus patch semantics, file/glob query
plans, outside roots and logical symlinks. From `scoper.nvim/`:

```sh
nvim --headless --noplugin -u NONE -l tests/run.lua tests/state_contract_spec.lua
nvim --headless --noplugin -u NONE -l tests/run.lua tests/scope_query_spec.lua
```

For Neovim's directory and event behavior, see
[`getcwd()`](https://neovim.io/doc/user/builtin.html#getcwd()),
[`DirChanged`](https://neovim.io/doc/user/autocmd.html#DirChanged) and
[`nvim_exec_autocmds()`](https://neovim.io/doc/user/api.html#nvim_exec_autocmds()).
