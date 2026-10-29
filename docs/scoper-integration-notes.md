# Scoper and compilation databases

Scoper's named search scopes, project root, selected compilation database and
clangd integration are independent choices. Scope paths are relative to the
loaded project root. Selecting Debug versus Release does not change search
includes; changing an include does not choose a different build. Scoper never
runs a generator, merges build configurations or modifies the source database.

## Configure the integration

The bundled configuration keeps its existing automatic filtered integration.
Use the ignored checkout-root `local.lua` for machine preferences:

```lua
return {
  project = {
    root = function(ctx)
      return vim.fs.root(ctx.cwd, { ".git", "CMakeLists.txt" }) or ctx.cwd
    end,
  },
  scoper = {
    lsp = {
      mode = "selected",
      -- Optional: explicit argv. Otherwise an existing clangd argv is inherited,
      -- with { "clangd" } as the fallback.
      cmd = { "/opt/llvm/bin/clangd", "--log=error" },
      -- Base flags remain separate from compiler-execution trust.
      clangd_args = { "--background-index", "--clang-tidy" },
      query_drivers = { "/opt/toolchain/bin/aarch64-linux-gnu-g++" },
    },
    compilation_database = { path = "out/debug/compile_commands.json" },
  },
}
```

Direct plugin users pass the `scoper` table to `require("scoper").setup()`.
`project.root` there is a path or `function(cwd)`; the host's top-level
`project.root` receives the richer settings context shown above. The host shares
its project resolver with Scoper when no Scoper-specific root is supplied.

| `lsp.mode` | Command/database behavior | Automatic integration |
| --- | --- | --- |
| `"disabled"` | Releases owned configuration; manual reload does nothing. | Off |
| `"native"` | Leaves existing clangd configuration and its native database discovery untouched. | Off |
| `"selected"` | Points clangd at the selected complete database; search scope has no effect. | On |
| `"filtered"` | Uses an immutable filtered copy while scope is enabled and includes are nonempty; otherwise uses the selected full database. | On |

With no explicit mode, legacy `lsp.clangd=true` means automatic filtered
integration. `lsp.clangd=false` keeps automatic integration off, while explicit
`:ScoperLspReload` and `clangd_cmd()` remain available for compatibility. This
legacy manual behavior differs from the explicit `"disabled"` mode.

`lsp.clangd_args`, `extra_args` and `query_drivers` append to an inherited or
explicit argv. Selecting a database replaces an existing
`--compile-commands-dir=...` flag; unrelated flags stay intact. `cmd_env`,
`cmd_cwd`, detached behavior and other server configuration remain intact. A
custom function-valued `cmd` can remain entirely under user ownership through
native/disabled mode; selected/filtered integration requires explicit argv.

The appended defaults can repeat flags already in inherited argv. Set
`clangd_args = {}` when the existing command should supply all base flags, or
provide a replacement list deliberately. List replacement affects that option,
not the inherited command itself. A managed compilation-directory argument takes
precedence over `.clangd`'s `CompileFlags.CompilationDatabase` search setting;
other `.clangd` configuration, including added compiler flags, still applies.

`query_drivers` is an execution whitelist: clangd may execute matching compilers
to discover system headers. The host no longer grants inferred prefix globs or
hard-coded MSYS paths. List trusted exact paths, or intentionally chosen globs.
Compilers do not need this permission merely to appear in a database.

## Choose the source database

Resolution order is the persisted explicit build selection (if any), then a
configured resolver/path, then candidates:

```lua
compilation_database = {
  -- A file or directory; relative paths resolve against the project root.
  path = "/external/build/debug/commands.json",
  -- Alternatively, an ordered priority list ({} disables discovery):
  -- candidates = { "out/debug", "generated/cdb/compile_commands.json" },
  -- Alternatively, a main-editor callback returning a path or false:
  -- resolver = function(snapshot) return choose_build(snapshot.root) end,
}
```

Callbacks receive copied revisioned state; they should be cheap and stable for
the same project/build selection. They execute in the editor, never in workers.
A resolver returning `false`, or `path=false`, disables source selection. A
missing explicit file is reported without silently falling back to another
configuration. There is no automatic recursive scan. Built-in candidates are
`compile_commands.json`, `build/compile_commands.json`,
`out/compile_commands.json`, and sorted immediate `cmake-build-*` directories.
Discovery checks at most 4,096 immediate entries and accepts at most 256 explicit
candidates. An explicit ordered list establishes priority. New explicit modes
refuse ambiguous default discovery; legacy boolean integration retains its
previous first-match priority. Set a path to resolve ambiguity.

clangd accepts a directory containing `compile_commands.json`. If a selected
source has another filename, Scoper publishes a full immutable copy named
`compile_commands.json` in its cache; its entries stay unchanged. Filtering preserves each kept
entry's original arguments, command, directory and other fields, including
relative-file semantics. An include containing only headers can produce zero
translation units; status reports the kept/total counts. Scoper invents no
compiler standard or header-to-source relationship.

`:ScoperDatabase {path}` selects a build independently of the named scope;
`:ScoperDatabase!` clears that persisted selection and restores configured
resolution. See [state and scope contracts](scoper-core-notes.md) for persistence
conflicts and the project-state schema.

## Refresh, startup and ownership

The adapter watches the selected source's parent directory to notice atomic
replacement. Changes are debounced (`lsp.debounce_ms=500` by default).
`FocusGained` compares file identity/timestamps as a fallback for unavailable
watchers. `lsp.watch=false` disables the filesystem watcher while retaining that
focus check. `:ScoperLspReload` is always available in selected/filtered and legacy
manual modes. It intentionally requests a restart; automatic reloads avoid one
when output and argv are unchanged. Scoper restarts only the active project's
clangd clients and preserves its existing graceful-exit/duplicate-client guards.

The default `lsp.startup="fallback"` starts immediately with an intact previous
filtered output, or the full selected database on a cold cache miss, then refreshes
in a worker. A source with a custom filename needs a cache copy first; until it
is ready, fallback startup retains native discovery and reports that condition
instead of pointing clangd at a directory containing a differently named file. Status distinguishes pending versus ready output. For strict first
attachment use:

```lua
lsp = { mode = "filtered", startup = "prepare", prepare_timeout_ms = 5000 }
```

This gates `vim.lsp.enable()` through its asynchronous root callback while
preparing the filtered database. The same `startup="prepare"` policy is supported
in selected mode and waits for a required full copy, or immediately accepts a
canonical selected database. Concurrent buffers share preparation. Scope/build
changes retry preparation within the original timeout budget. The editor
stays responsive. If preparation fails, times out, or has no usable filtered
output, the buffer stays unattached and reports the reason; retry with
`:ScoperLspReload` after correcting it. This strict policy never falls back to
expensive synchronous filtering on worker startup failure. Ordinary compatibility
reloads can instead filter in the main editor after a worker failure and warn
once; that fallback can pause the UI on a large database. A timed-out worker may still
finish its immutable cache object for a later retry. Native/manual client start
APIs that bypass `vim.lsp.enable()` are outside this startup gate's contract.

`setup()` disposes old automatic listeners/watchers before configuring the new
integration. The host also reconciles final `lsp.servers.clangd` options before
activation through `require("scoper.lsp").reconfigure()`, without reloading scope
state. Disposal restores command/root providers only while they still
match Scoper's owned values, preserving later user replacements. Global cwd,
project, scope revision and build-selection checks prevent obsolete asynchronous
results from restarting a new context's clients. Those checks remain active
through graceful-exit polling, before any buffer is reattached. Old immutable cache objects are
retained because another editor may still read them; close relevant editors
before manually removing `stdpath("cache")/scoper`.

## Inspect and verify

`require("scoper").status_snapshot().lsp` (or
`require("scoper.lsp").status()`) returns a copy with mode, selected source and
provenance, freshness, reason, kept/total counts, worker outcome/timing, startup
state and effective argv. `:ScoperShow` and `:DiagnosticDump` present this public
state. Status snapshots are safe to modify without changing live integration.

Targeted tests cover explicit/external/nested/ambiguous builds, arbitrary source
filenames, unchanged original entries, inherited argv/environment, compiler trust,
source replacement/focus refresh, ownership restoration, prepare completion and
timeout. Existing tests cover malformed/changing sources, immutable publication,
relative compilation entries, cache integrity, asynchronous races and selective
restart behavior.

Primary interface references:

- [clangd compilation databases](https://clangd.llvm.org/compilation-database.html)
- [clangd compile-command design](https://clangd.llvm.org/design/compile-commands)
- [clangd system headers and query-driver trust](https://clangd.llvm.org/guides/system-headers)
- [Neovim asynchronous LSP roots](https://neovim.io/doc/user/lsp.html#lsp-root_dir())
- [libuv filesystem-event caveats](https://docs.libuv.org/en/v1.x/fs_event.html)
