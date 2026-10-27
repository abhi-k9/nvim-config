# scoper.nvim

Scope searches to selected directories, files or globs. Optionally select a
compilation database for clangd, with or without filtering it. Built for
monorepos and large C/C++ codebases.

## Idea

You're working in `repo/services/api/` for the next three days. You don't
want `<leader>fg` to grep through `repo/legacy/`, `repo/vendor/`, and
`repo/third-party/`. With Scoper:

```vim
:ScoperNew api
:ScoperAdd services/api/ shared/proto/
:ScoperExclude **/node_modules/**
:ScoperToggle
:ScoperGrep TODO
```

Now `:ScoperGrep` and `:ScoperFind` only touch the in-scope dirs. Your
existing `<leader>ff` / `<leader>fg` are untouched — Scoper deliberately
provides separate commands.

For clangd users, `filtered` mode writes an immutable scoped database to the
cache and refreshes this project's clients. `selected` mode uses the complete
chosen build; `native` leaves clangd's own discovery under your control. Search
scopes and build selection remain independent.

## Install (lazy.nvim)

Requires Neovim 0.12 or later.

Local plugin:

```lua
{
  dir = "~/projects/scoper.nvim",
  config = function()
    require("scoper").setup({
      lsp = {
        mode = "filtered",            -- opt in to managed filtered integration
        -- Base flags scoper launches clangd with (it prepends its own
        -- --compile-commands-dir on top when applicable). Optional —
        -- shown here with the defaults. Pass your own list to REPLACE
        -- this list wholesale; lists are not merged element-by-element.
        -- Existing server argv is inherited unless lsp.cmd is supplied.
        clangd_args = {
          "--background-index",
          "--clang-tidy",
          "--completion-style=detailed",
          "--header-insertion=iwyu",
        },
      },
      default_excludes = {            -- every new scope starts with these
        "**/node_modules/**",
        "**/.git/**",
        "**/target/**",
      },
    })
  end,
}
```

## Commands

Scope membership/management commands accept a list of arguments on the command line
(whitespace-separated; a directory containing spaces is written
`my\ dir`, which is what tab completion inserts) or
zero arguments to open an interactive selector. Selectors come in
three shapes:

- **Multi-select picker** — `:ScoperRemove`, `:ScoperDelete`. Choose
  any subset of an enumerable list. Backend-dependent:
  - *fzf-lua*: `<Tab>` toggles a row, `<C-a>` toggles all, `<CR>`
    confirms the selection (or just the highlighted row if you didn't
    toggle anything).
  - *telescope*: `<Tab>` / `<S-Tab>` toggle rows; `<CR>` confirms the
    toggle set, or the highlighted row if none were toggled.
  - *plain `vim.ui.select` fallback* (no picker plugin loaded): a
    loop appears with a `(done)` sentinel as the first option — pick
    one item, the picker re-opens with that item removed and the
    running count in the prompt, repeat until you select `(done)` or
    hit `<Esc>` to commit whatever you've collected so far.
- **Free-form text loop** — `:ScoperAdd`. Arbitrary directories can't
  be enumerated up front, so this is iterative text input rather than
  a picker. Each `<CR>` adds the typed path and re-prompts with the
  parent pre-filled; empty input ends. Uses Vim-native
  `completion = "dir"` for `<Tab>` directory completion.
- **Single-pick** — `:ScoperUse` (single-select picker over scope
  names; exactly one scope is active at a time) and `:ScoperNew`
  (free-form text input for the new scope's name).

### Scope membership

| Command | What |
|---|---|
| `:ScoperAdd [path...]` | Add directories, files or globs (`~` and `$VARS` expand). Missing paths remain selected with a warning. No args → interactive directory-input loop. |
| `:ScoperRemove [path...]` | Remove include paths/globs. No args → multi-select picker of current includes. |
| `:ScoperExclude [glob]` | Add a deny pattern (e.g. `**/dist/**`); the whole argument is one glob. A glob `vim.glob` can't parse is refused with a warning. No args → prompt. |
| `:ScoperRemoveExclude [glob]` | Remove a deny pattern. No args → multi-select picker of current excludes. |
| `:ScoperClear` | Empty includes of active scope (excludes kept). |
| `:ScoperShow` | Panel: scope, project/revision, persistence and selected/effective database status. |

### Scope management

| Command | What |
|---|---|
| `:ScoperNew [name]` | Create a new scope and switch to it. Names may contain letters, digits, `.`, `-`, `_` only — they become directory components in the clangd cache, so `/`, `\`, `:`, `*` etc. are rejected with an error. |
| `:ScoperUse [name]` | Switch active scope. No args → picker. |
| `:ScoperDelete [name...]` | Delete one or more scopes. No args → multi-select picker. |
| `:ScoperScopes` | List all scopes for this project. |
| `:ScoperReload[!]` | Reload saved state; `!` explicitly discards unsaved local edits. |

### Toggle / status

| Command | What |
|---|---|
| `:ScoperToggle` | Enable / disable scoping. When disabled, everything is in scope (see below). |
| `:ScoperStatus` | Echo `Scoper: ON · scope="foo" · N include · M exclude`. |

### Search within scope

| Command | What |
|---|---|
| `:ScoperFind` | Fuzzy-find files within **all** active include paths/globs (fzf-lua → telescope → :find fallback). |
| `:ScoperGrep [query]` | Live grep within **all** active include paths/globs (fzf-lua → telescope → :vimgrep fallback). |
| `:ScoperReplace` | Open ordinary grug-far only when scoping is unrestricted; restricted replacement is refused. |
| `:ScoperTogglePicker` | Switch the backend of `:ScoperFind` / `:ScoperGrep` between fzf-lua and telescope (sets `vim.g.scoper_picker`). |

While scoping is off, or the active scope has no includes, these commands
search without the scope's excludes. Find and grep use the loaded project
root; unrestricted replacement retains grug-far's ordinary current-directory
behavior. All three find/grep backends apply the excludes; the plain `:find`
fallback opens the first match the excludes don't hide.

**Scoped replacement is unavailable with the pinned grug-far backend.** Its
deferred searches and file writes resolve relative paths using the window
that is current when each operation runs. Switching windows can therefore
change exclusion matching or file destinations even if its result window
has a project-local directory. The backend exposes no durable per-instance
working-directory API, so `:ScoperReplace` refuses an active restricted
scope before opening it. Use `:ScoperGrep` to inspect the scope. Direct
`:GrugFar` remains available for explicitly unscoped replacement.

`:ScoperFind` follows directory links below the scope's dirs, so a link to
a folder outside them is searched too, on both fzf-lua and telescope. To
keep to the dirs themselves, set `vim.g.scoper_follow_links = false`; the
plain `:find` fallback always follows links. `:ScoperGrep` does not follow
them by default (ripgrep's default).

On the telescope
backend, `<M-p>` (insert and normal mode) shows the highlighted entry's
full path in the prompt title without closing the picker.
Parsed Telescope entries use the same captured scope matcher as clangd,
including brace alternatives and negated character classes. If Telescope
would expand a supplied directory into another path (for example `$NAME`),
Scoper refuses that search with a warning.

### LSP and build selection

| Command | What |
|---|---|
| `:ScoperDatabase [path]` | Select a project-wide build database independently of named scopes; no argument shows status. |
| `:ScoperDatabase!` | Clear the saved selection and return to configured resolution. |
| `:ScoperLspReload` | Explicitly refresh/restart in selected, filtered or legacy manual mode. |

With automatic selected/filtered integration, scope or selected-source changes
refresh the effective input. An unchanged output/argv leaves warm clangd clients
running. Explicit reload requests a restart. Automatic reloads stay quiet when
this project's clangd is not running.

## How it decides what's "in scope"

A path is in scope when it lies under an included directory, is an included
file, or matches an include glob, and no exclude matches it. All picker adapters
and the compilation-database filter use a captured shared matcher.

Excludes use gitignore-style component and glob semantics:

- Without `/`, `build`, `*.o` or `node_modules` matches a component at any
  depth and its descendants; `build` does not hide `builder`.
- With `/`, `src/gen` or `**/gen/**` matches relative to the loaded project,
  including parent-directory matches. A leading `/` anchors at that root.
- A trailing `/` is accepted; an absolute drive/path pattern matches absolute
  paths. For includes outside the project, relative excludes use the include's
  directory or a glob's deepest literal ancestor.

Folders above the project are not matched by a relative exclude. With a project
at `D:/build/proj`, `**/build/**` excludes `build` folders inside that project.

File includes and glob-only scopes work with find and grep. Search roots are
existing literal files/directories or a glob's deepest literal ancestor; the
exact matcher filters results within those roots. A restricted query with no
usable root is refused instead of silently searching the whole project.

Special cases:

- Disabled scoping means everything is in scope.
- An empty include list also means everything is in scope, and excludes are
  ignored. For a whole-project scope with exclusions, include `.` explicitly.
- Path comparison normalizes separators/device prefixes and is case-insensitive
  on Windows. Native short-name aliases are expanded for comparison. Directory
  symlinks retain their logical spelling; following them is a backend policy.
- Paths with spaces are supported. Picker paths remain literal; a backend that
  would expand a literal path into another location is refused.

The [state and scope guide](../docs/scoper-core-notes.md) documents the shared
query representation, project resolver, snapshots and compatibility boundaries.

## Multiple scopes per project

The state file is keyed by the loaded project root. Cooperating editors refresh
saved changes before a mutation and refuse conflicting publications, preserving
unsaved local changes. Its named scopes and selected build are separate:

```
{
  schema_version = 1,
  active  = "frontend",
  enabled = true,
  database_path = "/external/build/compile_commands.json",
  scopes  = {
    frontend = { include = {...}, exclude = {...} },
    backend  = { include = {...}, exclude = {...} },
    tests    = { include = {...}, exclude = {...} },
  }
}
```

So per project you can keep as many scopes as you want; one is active at
a time, and switching is cheap. The typical monorepo setup:

```vim
:cd ~/work/monorepo

:ScoperNew frontend
:ScoperAdd apps/web packages/ui
:ScoperExclude **/dist/**

:ScoperNew backend
:ScoperAdd services packages/shared
:ScoperExclude **/__pycache__/**

:ScoperUse frontend     " telescope/grep/clangd all filter to web/ui
" ... work for a while ...
:ScoperUse backend      " clangd auto-reloads (debounced) against the new scope
```

`:ScoperFind`, `:ScoperGrep`, and the clangd
`--compile-commands-dir` filtering all key off the active scope, so a
single `:ScoperUse` switches search membership and, in filtered mode, the clangd
filter. It keeps the selected build unchanged.

State behavior:

- **The active scope is persisted, not session-local.** Quit and reopen
  the project later — you come back into whichever scope was last
  active. If you want a different default each session you'd have to
  `:ScoperUse <name>` on enter; usually the sticky default is what you
  want.
- **The default project is the global cwd.** Scoper follows `:cd`;
  `project.root` can instead provide a fixed path or resolver. A window/tab
  directory (`:lcd`, `:tcd`, `'autochdir'`) does not switch projects. Relative
  includes and saved state stay attached to the loaded project.
- **One active project/scope per editor.** Two editors in the same
  project share a state file, not live memory. There is no state-file watcher:
  another editor's saved changes are read before a mutation or context capture,
  or by `:ScoperReload`, unless this editor has unsaved changes. Filtered
  databases are isolated by project, scope, source selection and loaded
  include/exclude lists, so divergent instances do not overwrite each other's
  clangd input. The state file itself is still shared.
- **Conflicting saves are refused.** Changes refresh the saved contents
  first, including equal-timestamp edits and deletions. Saves use an owned
  per-project directory lock and compare the contents read with the contents
  on disk before atomic publication. A stale save preserves the other editor's
  file and your local edits. `:ScoperReload` refuses to discard them; copy or
  reconcile them, then explicitly use `:ScoperReload!` to replace local state.
  Ordinary I/O failures can be retried with `require("scoper.state").save()`.
  Switching projects retains unsaved state in this editor and restores it on
  return. Quitting still loses unsaved state. Dead-owner locks are
  recovered; live or unrecognized locks are retained with an error.
  External programs that ignore the lock are outside this serialization.
- **`default_excludes` seed new scopes only.** They apply to scopes
  created with `:ScoperNew` and to the `default` scope of a project
  that has no state file yet. Scopes that already exist on disk keep
  the excludes they have; edit them with `:ScoperExclude` /
  `:ScoperRemoveExclude` (or delete and recreate the scope) if you
  want them updated.

## Suggested keymaps

> If you're reading this inside the bundled Neovim config: `<leader>S`
> is free there today, but check `:checkhealth which-key` after adding
> a prefix — the host config owns `<leader>s` (grug-far search/replace)
> and single-key flash motions live on `s`/`S` in visual mode, so a
> slow-typed chord behaves best with a prefix registered as a
> which-key group.

```lua
local s = "<leader>S"   -- pick your own prefix
vim.keymap.set("n", s .. "t", "<cmd>ScoperToggle<cr>", { desc = "Scope toggle" })
vim.keymap.set("n", s .. "a", "<cmd>ScoperAdd<cr>",    { desc = "Scope add dir" })
vim.keymap.set("n", s .. "x", "<cmd>ScoperExclude<cr>",{ desc = "Scope exclude" })
vim.keymap.set("n", s .. "s", "<cmd>ScoperShow<cr>",   { desc = "Scope show" })
vim.keymap.set("n", s .. "u", "<cmd>ScoperUse<cr>",    { desc = "Scope use" })
vim.keymap.set("n", s .. "n", "<cmd>ScoperNew<cr>",    { desc = "Scope new" })
vim.keymap.set("n", s .. "f", "<cmd>ScoperFind<cr>",   { desc = "Scope find" })
vim.keymap.set("n", s .. "g", "<cmd>ScoperGrep<cr>",   { desc = "Scope grep" })
vim.keymap.set("n", s .. "r", "<cmd>ScoperReplace<cr>",{ desc = "Scope replace (availability checked)" })
```

Lualine component:

```lua
sections = {
  lualine_x = { require("scoper").lualine, "encoding", ... },
}
```

## clangd integration

The integration is optional in standalone Scoper. The bundled host retains its
existing automatic filtered behavior. Select an explicit mode in `setup()`:

| `lsp.mode` | Behavior |
| --- | --- |
| `"disabled"` | Release owned configuration; no automatic or manual reload. |
| `"native"` | Keep clangd's existing configuration and native database discovery. |
| `"selected"` | Use the complete selected database, independently of search scope. |
| `"filtered"` | Use an immutable scoped copy while scoping is active; otherwise use the selected complete database. |

If mode is absent, legacy `lsp.clangd=true` maps to automatic filtered integration;
`false` disables automatic integration while preserving explicit manual reloads.
An explicit disabled mode is stricter than that legacy boolean.

Select arbitrary nested/external databases through `compilation_database.path`,
a main-editor resolver or ordered candidates, or persist a selection with
`:ScoperDatabase`. No build generator is run and Debug/Release databases are never
merged automatically. Explicit modes refuse ambiguous default discovery; choose
a path or an ordered candidate list to express priority.

Managed modes preserve inherited or explicit clangd argv and server environment.
Scoper only replaces the compilation-directory flag when selecting an input.
Native mode preserves the user's existing `.clangd`/upward discovery behavior.
`lsp.query_drivers` is a compiler execution whitelist; use trusted exact paths or
intentionally chosen globs. The host no longer infers broad permissions from a
compiler prefix or grants hard-coded MSYS paths.

Filtering and reloads run in a background editor. The default
`lsp.startup="fallback"` uses a previous filtered object or the selected full
input on a cold miss, then refreshes asynchronously. For a filtered first
attachment, `startup="prepare"` provides a bounded asynchronous startup gate;
a failure or timeout leaves the buffer unattached with a reported reason.
Parent-directory watching notices source-database atomic replacement, with a
cheap `FocusGained` check as fallback. Source-only changes can therefore refresh
without editing the scope. Automatic semantic no-ops suppress restarts.

Other projects' clients remain untouched. Restarting retains graceful-shutdown,
exit-poll and duplicate-client guards; obsolete project/scope/build work cannot
restart a newly selected context. Setup disposes owned listeners/watchers and
restores command/root providers only while Scoper still owns them.

Outputs are immutable content-addressed cache objects. Source changes during
preparation are retried once, then reported. Metadata checks establish freshness,
not protection against deliberate metadata-preserving tampering. Close editors
using the cache before deleting it; automatic cross-editor cache deletion is not
performed.

See the [integration guide](../docs/scoper-integration-notes.md) for full mode
and compatibility tables, source precedence/limits, query-driver trust,
startup/refresh policy, ownership and public status fields. This README's
remaining sections describe clangd behavior that filtering cannot generalize
away.

### clang-tidy checks

Because the baseline flags include `--clang-tidy`, clangd runs
clang-tidy live and reads a project-root **`.clang-tidy`** (YAML,
discovered by walking up from the edited file — not in your Neovim
config). Use it to choose the modern-C++ / bug-catching check families
and tune naming or member-init style; clangd surfaces the results as
diagnostics and code-action fix-its. A note on the interactive case:
clangd ignores `.clang-tidy`'s `WarningsAsErrors` for editor
diagnostics (that key only affects the standalone `clang-tidy` CLI /
CI), and unknown/removed check-option keys are silently dropped, so
keep options current with your clangd version. Remove `--clang-tidy`
from `clangd_args` and any inherited/custom argv to disable tidy in-editor.

### Header files and the C++ standard

Compilation databases usually list source translation units, rather than
headers. clangd borrows a known including file's command or infers a command
from a similar source filename. Filtering may remove those donors. A scope
containing only `include/` can keep zero translation units even though its
headers are searchable. The fallback command can then lack include paths,
defines or the intended C++ standard. The resulting diagnostics do not mean
Scoper should invent compiler flags or infer which source file you meant.

Prefer including the relevant source units or use `mode="selected"` to retain
the complete build database while keeping searches restricted. If a fallback
standard is appropriate for the whole project, set it explicitly in a
project-level **`.clangd`**, discovered from the edited file. This example uses
C++20; replace it with the project's actual standard:

```yaml
If:
  PathMatch: .*\.(cc|cpp|cxx|h|hh|hpp|hxx)
CompileFlags:
  Add: [-std=c++20]   # set to your project's standard
```

`Add` affects all matching commands, including full-database entries, so choose
this policy deliberately if builds use different standards. The `If` block
keeps a C++ standard off C sources; drop `h` if `.h` headers are C. Use
`:ScoperLspReload` to request a restart after changing project policy if needed.
Do not remove cache objects while active editors may still read them.

### Manual compatibility API

Existing callers can still build a command explicitly:

```lua
local cmd, info = require("scoper").clangd_cmd({ "--log=error" })
vim.lsp.config("clangd", { cmd = cmd })
```

`clangd_cmd(extra_args)` returns argv, a readable explanation and change status.
Extra args are remembered until another explicit list replaces them. This
legacy API can synchronously prepare a missing filtered database because it must
return ready argv. Prefer managed setup/startup for responsive cold preparation;
`startup="prepare"` gates `vim.lsp.enable()` rather than arbitrary manual client
starts. The safe header handling and trusted compiler paths remain the caller's
responsibility.

## Cross-platform notes

- Windows backslashes, drive-letter casing, and the `\\?\` / `\\.\`
  device prefixes (also `\\?\UNC\server\share`) are all normalized
  internally.
- UNC paths (`\\server\share\foo`) are kept as-is after normalization
  (become `//server/share/foo` internally).
- On Windows a root-relative path (`\src`) means that folder on the
  drive (or share) of the project, and a drive-relative one (`D:src`)
  is resolved against the project on the same drive, or against that
  drive's current directory.
- Tilde (`~/foo`) is expanded relative to the user's home.
- Relative include paths are stored relative to the project directory.
  The state file is named by a hash of the project's absolute path, so
  it belongs to one checkout on one machine and can't be shared through
  git.

## Data location

| Thing | Path |
|---|---|
| Per-project state | `stdpath("data")/scoper/<hash>.json` |
| Filtered compile_commands | `stdpath("cache")/scoper/<hash>/<scope>/<scope-hash>/objects/<digest>/` |

`<hash>` is the first 16 hex digits of the sha256 of the project path
(lower-cased on Windows). A state file that can't be parsed is kept
next to it as `<hash>.json.corrupt-<time>` before Scoper starts over.
`<scope-hash>` is a 32-hex prefix of a fingerprint including layout version,
project identity, selected source, mode and include/exclude lists. Old objects
are retained while another editor may still read them; remove old cache layouts
only after closing relevant editors.

State files carry schema version 1. Unversioned files migrate on save; newer
unsupported schemas block saves instead of being overwritten.

Deleting the state directory resets saved scopes and the saved build selection.
Deleting the cache directory after closing its editors only removes rebuildable
filtered databases.

## Events

Scoper fires `User ScoperChanged` on accepted state/project changes, even when
a change applies only to the session because saving failed. Its `args.data`
contains `root`, `scope`, monotonic `revision`, `database`, `reason`, `changed`
fields and structured `persistence`. Use it to react in your own config:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ScoperChanged",
  callback = function(args)
    -- args.data.persistence.persisted reports publication success.
    require("lualine").refresh()
  end,
})
```

`require("scoper").snapshot()` and `status_snapshot()` return isolated copies.
Use supported mutators and capture revisions for delayed work; legacy mutable
accessors do not track direct writes. See the [state guide](../docs/scoper-core-notes.md)
for field/return contracts and explicit conflict recovery.

## Limitations

- Symlinks are matched logically (not resolved). If you want resolved
  matching, normalize through `vim.uv.fs_realpath` before adding.
- Native Windows 8.3 aliases are expanded for comparisons, so a short cwd
  and long buffer filename still identify the same scope. Stored project
  identity and scope names retain their existing form.
- `:ScoperReplace` refuses an active restricted scope because grug-far
  cannot preserve its working directory through deferred operations and
  window changes. Unrestricted replacement requires grug-far.nvim.
  `:ScoperFind` / `:ScoperGrep` use a plain-vim fallback if no picker
  plugin is installed.
- On the fzf-lua backend, `:ScoperFind` runs ripgrep itself over every
  scope directory (fd through fzf-lua's `search_paths` when ripgrep
  isn't installed), and `:ScoperGrep` uses `search_paths`, which needs a
  fzf-lua from mid-2024 or later. On the telescope backend (or
  `vim.g.scoper_picker = "telescope"`) this works regardless of version
  via `search_dirs`.
- LSP integration is clangd-only for now; nothing else has the
  `--compile-commands-dir` style external index config.

## Testing

Unit tests live under `tests/` and use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s
busted-style runner, one Neovim process per spec file, run sequentially. The Windows-only
rules (case-insensitive paths, device prefixes, root- and
drive-relative paths) run on every OS by forcing the Windows branch.
CI (the host config's `test-scoper` job) runs them on Ubuntu and
Windows.

```bash
make test      # plenary specs (clones plenary into stdpath('cache')/test-deps on first run)
make lint      # luacheck lua/ plugin/ tests/
make format    # stylua in place (aligned blocks are fenced with
               #   -- stylua: ignore start / -- stylua: ignore end)
make fmt-check # stylua --check (no writes)
make check     # lint + fmt-check (what CI runs)
make clean     # delete the cloned test dependencies
```

Or, without make, the raw command for running tests:

```bash
nvim --headless --noplugin -u NONE -l tests/run.lua
```

Static-analysis tools:

| Tool | Purpose | Install |
|---|---|---|
| luacheck | unused locals, accidental globals, typos | `luarocks install luacheck` |
| stylua   | code formatting | `cargo install stylua` (or download release) |

### What's covered

- `path_spec`: normalization (trailing slashes, drive casing, device
  prefixes, `.`/`..`), `is_absolute`, `absolute` (root- and
  drive-relative paths), `is_under` (including the `/foo` vs `/foobar`
  segment boundary), `relative`, `match_glob` and its cache, exclude
  matching (never above the search root) and glob validation.
- `state_spec`: includes and excludes (missing directories, invalid
  globs, `$VARS`), scopes and the fallback when the active one goes,
  `default_excludes`, `is_in_scope`, save/load including corrupt files
  and failed saves, two instances on one state file, and the project
  root under `:lcd` and `:cd`.
- `lsp_spec`: the compile_commands filter and its cache, legacy behavior,
  remembered extra args, the per-project cmd, and the
  restart (only this project's clients, the exit poll, the guard,
  queued reloads, automatic skips) against fake clients.
- `pickers_spec`: the scope context (scoping off means the whole cwd),
  the options passed to stub fzf-lua and telescope modules, shell quoting,
  refusal of restricted replacement, captured Telescope entry filtering,
  the rewriting of
  absolute excludes and of those of includes outside the cwd, and the
  plain-vim grep filter.
- `state_contract_spec` covers isolated snapshots, revisioned events, schema
  migration/refusal, unsaved recovery across projects and deterministic setup.
  `scope_query_spec` covers shared file/glob queries and exact predicates.
- `commands_spec` sources `plugin/scoper.lua` (the runner starts with
  `--noplugin`) and runs the commands and their completion;
  `init_spec` covers `setup()` and which directory changes it follows.

`state_concurrency_spec` starts two real editors at a save barrier and tests
dead-owner recovery. The host config's `tests/scoper_telescope_spec.lua` runs
the actual pinned Telescope and ripgrep. Standalone specs still use controlled
picker modules and LSP clients; a full native debugger/clangd matrix is not
covered by this suite.
