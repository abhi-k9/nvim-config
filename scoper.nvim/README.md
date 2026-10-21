# scoper.nvim

Scope your searches (and clangd indexing) to a subset of a project's
directories. Built for monorepos and large C/C++ codebases.

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

For clangd users: a filtered `compile_commands.json` is written to the
cache and clangd is restarted against it, cutting cold-start indexing on
big projects in proportion to how much you've scoped down.

## Install (lazy.nvim)

Requires Neovim 0.12 or later.

Local plugin:

```lua
{
  dir = "~/projects/scoper.nvim",
  config = function()
    require("scoper").setup({
      lsp = {
        clangd = true,              -- auto-rebuild compile_commands.json
        -- Base flags scoper launches clangd with (it prepends its own
        -- --compile-commands-dir on top when applicable). Optional —
        -- shown here with the defaults. Pass your own list to REPLACE
        -- them wholesale; lists are not merged element-by-element.
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

Published:

```lua
{ "you/scoper.nvim", config = true }
```

## Commands

Most commands accept either a list of arguments on the command line
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
| `:ScoperAdd [path...]` | Add dir(s) to active scope (`~` and `$VARS` are expanded). A path that isn't an existing directory is added with a warning. No args → interactive picker (loop). |
| `:ScoperRemove [path...]` | Remove one or more dirs. No args → multi-select picker of current includes. |
| `:ScoperExclude [glob]` | Add a deny pattern (e.g. `**/dist/**`); the whole argument is one glob. A glob `vim.glob` can't parse is refused with a warning. No args → prompt. |
| `:ScoperRemoveExclude [glob]` | Remove a deny pattern. No args → multi-select picker of current excludes. |
| `:ScoperClear` | Empty includes of active scope (excludes kept). |
| `:ScoperShow` | Floating panel: includes + excludes of active scope. |

### Scope management

| Command | What |
|---|---|
| `:ScoperNew [name]` | Create a new scope and switch to it. Names may contain letters, digits, `.`, `-`, `_` only — they become directory components in the clangd cache, so `/`, `\`, `:`, `*` etc. are rejected with an error. |
| `:ScoperUse [name]` | Switch active scope. No args → picker. |
| `:ScoperDelete [name...]` | Delete one or more scopes. No args → multi-select picker. |
| `:ScoperScopes` | List all scopes for this project. |

### Toggle / status

| Command | What |
|---|---|
| `:ScoperToggle` | Enable / disable scoping. When disabled, everything is in scope (see below). |
| `:ScoperStatus` | Echo `Scoper: ON · scope="foo" · N include · M exclude`. |

### Search within scope

| Command | What |
|---|---|
| `:ScoperFind` | Fuzzy-find files across **all** the scope's directories (fzf-lua → telescope → :find fallback). |
| `:ScoperGrep [query]` | Live grep across **all** the scope's directories (fzf-lua → telescope → :vimgrep fallback). |
| `:ScoperReplace` | Project-wide search/replace via grug-far, scoped. |
| `:ScoperTogglePicker` | Switch the backend of `:ScoperFind` / `:ScoperGrep` between fzf-lua and telescope (sets `vim.g.scoper_picker`). |

While scoping is off, or the active scope has no includes, these commands
search the whole cwd without the scope's excludes. All three backends
apply the excludes; the plain `:find` fallback opens the first match the
excludes don't hide.

`:ScoperFind` follows directory links below the scope's dirs, so a link to
a folder outside them is searched too, on both fzf-lua and telescope. To
keep to the dirs themselves, set `vim.g.scoper_follow_links = false`; the
plain `:find` fallback always follows links. `:ScoperGrep` and
`:ScoperReplace` never follow them (ripgrep's default).

On the telescope
backend, `<M-p>` (insert and normal mode) shows the highlighted entry's
full path in the prompt title without closing the picker.

### LSP

| Command | What |
|---|---|
| `:ScoperLspReload` | Re-filter compile_commands.json + restart clangd (always). |

With `lsp.clangd = true`, scope edits reload clangd automatically, but
only when something clangd sees changed — a different
`--compile-commands-dir` or a different filtered database. Edits that
filter to the same entries, or any edit while scoping is off, leave the
running clangd (and its warm index) alone, and automatic reloads say
nothing when no clangd of the project is running.

## How it decides what's "in scope"

A path is in scope iff:

1. It lies under at least one `include` directory, **or** matches an
   include glob, **and**
2. It does not match any `exclude` glob.

Excludes follow ripgrep's (gitignore-style) semantics in the pickers, the
clangd filter and `is_in_scope()`:

- a pattern without `/` (`build`, `*.o`, `node_modules`) matches any
  path component at any depth, so it excludes a directory of that name
  with everything below it (`build` does not touch `builder/`);
- a pattern with `/` (`src/gen`, `**/gen/**`) matches the path relative
  to the cwd, or any of its parent directories;
- a trailing `/` (`build/`) is accepted;
- a leading `/` (`/build`) anchors the pattern at the cwd;
- a pattern with a drive or an absolute path (`C:/proj/vendor/**`)
  matches the absolute path.

Patterns never see the folders above the cwd: with the project in
`D:/build/proj`, `**/build/**` excludes only `build` folders inside it.
Below an include outside the cwd they match relative to that include,
so they don't see the folders above it either. The search tools list
paths relative to the cwd, but by their full path below an include
outside it, so the pickers rewrite the patterns for them: an absolute
one relative to the cwd or to the include it lies in, the others
anchored at each include outside the cwd as well. Where they still
differ (besides fd's letter case, below):

- The pickers drop an absolute pattern that lies neither in the cwd nor
  in an include, or that has a wildcard above them (`C:/**/vendor/**`).
  On Unix they read it as anchored at the cwd and each include instead,
  like `/build`.
- fd, which `:ScoperFind` uses only when ripgrep isn't installed, gets
  the patterns as written.

Glob includes (`:ScoperAdd **/*.proto`) filter the clangd database and
`is_in_scope()`; the pickers search the include *directories* only, so
they refuse a scope that has nothing but glob includes.

Special cases:

- If scoping is **off** (`:ScoperToggle`), everything is in scope.
- If the active scope's `include` list is **empty**, everything is in
  scope (so you can't accidentally hide every file by enabling Scoper
  before adding anything).
- Paths are compared after normalization: forward slashes, no trailing
  slashes, no `\\?\` or `\\.\` prefix. On Windows comparisons are
  **case-insensitive** (NTFS is): `:ScoperAdd src` after `Src` is a
  duplicate, `:ScoperRemove SRC` removes it, `**/Build/**` excludes
  `build/` (ripgrep runs with `--glob-case-insensitive`, telescope's
  patterns ignore case too), and `C:\Proj` / `c:\proj` are the same
  project (older state files saved under the case-sensitive key are
  still read). The one exception is fd, which `:ScoperFind` on the
  fzf-lua backend uses only when ripgrep isn't installed: it matches
  excludes case-sensitively.
- Scope dirs containing spaces work everywhere: `:ScoperFind`'s ripgrep
  / fd excludes are shell-quoted, `:ScoperReplace` escapes spaces the way
  grug-far expects (`my\ dir`), and the plain-vim `:find` fallback
  escapes spaces and commas in its search path. grug-far's *flags* field
  splits at whitespace and has no quoting. An exclude glob with whitespace
  therefore can't reach it unchanged, so `:ScoperReplace` refuses to
  open; write the glob with `?` for the space. A dir with a space that
  ends up inside an exclude glob (below an include outside the cwd) shows
  the space as `?`, which matches any one character.

## Multiple scopes per project

The state file is keyed by cwd (two Neovim instances in the same project
share it; each re-reads it before changing anything, so neither drops the
other's edits), but inside it lives a *dict* of named scopes plus a
pointer to which one is active:

```
{
  active  = "frontend",
  enabled = true,
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

`:ScoperFind`, `:ScoperGrep`, `:ScoperReplace`, and the clangd
`--compile-commands-dir` filtering all key off the active scope, so a
single `:ScoperUse` switches your whole workspace context.

A few things worth knowing:

- **The active scope is persisted, not session-local.** Quit and reopen
  the project later — you come back into whichever scope was last
  active. If you want a different default each session you'd have to
  `:ScoperUse <name>` on enter; usually the sticky default is what you
  want.
- **The project is the global cwd.** Scoper follows `:cd` (which is
  also what session plugins use); a window or tab directory (`:lcd`,
  `:tcd`, `'autochdir'`) doesn't switch projects, and nothing is saved
  into another project's state from there.
- **One active scope per project, period.** Two nvim instances in the
  same project share the same *state file* — but not live memory.
  There is no file watcher: instance B picks up instance A's changes
  only when B next changes the scope itself (it re-reads the file
  first) or on a `:cd`. Until then B's statusline, pickers and clangd
  filter keep using what B loaded. They also share the filtered
  compile_commands cache for a given scope name, so divergent
  *contents* under the same name can make the cache flip-flop between
  the two versions as each instance rebuilds it. If you genuinely need
  two scopes "live" at once, use two nvim instances in two different
  cwds.
- **Only simultaneous saves race.** Saves are atomic (a crash can never
  corrupt the store), and every change re-reads the file first, so an
  edit saved earlier by another instance is kept. Two saves in the
  same instant still race: the later one wins.
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
vim.keymap.set("n", s .. "r", "<cmd>ScoperReplace<cr>",{ desc = "Scope replace" })
```

Lualine component:

```lua
sections = {
  lualine_x = { require("scoper").lualine, "encoding", ... },
}
```

## clangd integration

When `lsp.clangd = true` in setup, every scope change triggers:

1. Locate `compile_commands.json` (cwd, `./build`, `./out`, `./cmake-build-*`)
2. Filter entries where `entry.file` is in the active scope
3. Write filtered JSON to
   `stdpath("cache")/scoper/<project-hash>/<scope>/compile_commands.json`
4. Update `vim.lsp.config("clangd", { cmd = ... --compile-commands-dir=... })`
5. Restart this project's running clangd clients

**Cold start included.** `setup()` runs steps 1–4 once immediately
(no step 5 — no client exists yet), so a persisted, enabled scope
filters the *very first* index of the session. When
`compile_commands.json` changed since the filtered copy was made (a
CMake re-run), startup uses the previous filtered copy, and when there
is none yet (first use of a scope) the unfiltered database; the refresh
runs right after startup instead of delaying it, and clangd is restarted
then only if the filtered database really changed. `:cd` to another
project also re-applies the integration for that project's persisted
scope.

**Other projects are left alone.** `vim.lsp.config` is global, so the
installed `cmd` is a function that decides per client: a clangd started
for a root outside this project gets the plain `clangd_args`, without
this project's `--compile-commands-dir`, and step 5 restarts only the
clients whose root is inside the project (or contains it). The function
always uses the newest cmd, so a clangd started any other way later
(`:lsp restart`, a new buffer) gets the current scope too. While
`clangd` isn't on `PATH`, a plain list is installed instead, which
`vim.lsp.enable()` skips quietly; the first C/C++ buffer opened once
clangd is there (for example after mason.nvim has loaded) switches to
the function.

Steps 1–3 are cached: an unchanged `compile_commands.json` and scope
skip them. When they do run, scope edits and `:ScoperLspReload` do steps
2–3 in a background `nvim --clean --headless` process, so a big database
(10k entries: ~300 ms) doesn't freeze the editor. Only
`require("scoper").clangd_cmd()`, which must return a ready cmd, filters
in Neovim itself.

The restart in step 5 is **asynchronous**: the old clients get a
graceful shutdown that turns into a forced one after 2 s (clangd with a
busy background index often needs longer), and scoper polls (50 ms
libuv timer) for those clients to exit before re-firing the LSP
`FileType` handlers to attach the new ones, so the UI stays responsive
throughout. A clangd that starts in the meantime already has the new
cmd and is left running. Only if a stopped client still hasn't exited
1.5 s after the forced stop is the re-attach skipped (starting a fresh
clangd alongside a live one would mean two clients indexing the same
project) and a warning tells you to run `:ScoperLspReload`. A reload
requested while one is already in flight is queued and replayed
exactly once when the in-flight pass finishes — the last scope change
always wins, never gets dropped.

When the scope is **off** (`:ScoperToggle`), or the active include list
is empty, or the JSON couldn't be parsed, steps 2–3 are skipped. Step
4 then installs a cmd whose `--compile-commands-dir` points at the
*unfiltered* directory we located in step 1 (i.e. wherever the real
`compile_commands.json` lives). Step 5 still restarts running clients,
so the swap takes effect in the same Neovim session.

Why "always explicit" rather than dropping the flag in the unscoped
case: clangd's own discovery walks up from the source file and also
honours a project-level `.clangd` file's
`CompileFlags.CompilationDatabase` setting. If those two disagree
with where the database actually lives (e.g. `.clangd` says `build/`
but the file is at the root, or vice versa), clangd silently falls
back to fixed ad-hoc flags and every project include becomes a "file
not found" error. Passing `--compile-commands-dir` overrides the
`.clangd` setting and removes that whole class of failure. If
scoper can't locate `compile_commands.json` in any of its candidate
directories, only then is the flag omitted and clangd's discovery
takes over.

The baseline clangd flags come from `setup()`'s `lsp.clangd_args`
(defaults: `--background-index`, `--clang-tidy`,
`--completion-style=detailed`, `--header-insertion=iwyu`) and are
applied in both modes, so the only effective difference between
scoped and unscoped operation is which directory
`--compile-commands-dir` points at — the filtered scoper cache vs.
the project's own directory. Override `clangd_args` to change
tidy/completion behaviour for both modes at once.

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
from `clangd_args` if you'd rather not run tidy in-editor.

### Header files and the C++ standard

`compile_commands.json` lists only source TUs (`.cpp`), never headers.
To parse a header, clangd borrows compile flags from a source file that
`#include`s it. With filtering ON, the scoped database may not contain
that sibling `.cpp` (it's only kept if its `file` is in the active
scope), so clangd can't find a donor TU and falls back to a DEFAULT
language standard — old enough that modern C++ in a header reports
spurious errors like "... is a C++NN extension" or a C++98-era "no
member named ...". This is inherent to filtering, not a bug, and it's
independent of how your headers and sources are laid out (an `include/`
vs `src/` split doesn't change it — clangd matches by which TU includes
the header, not by directory adjacency).

Fix it with a project-level **`.clangd`** at your repo root (NOT in your
Neovim config — clangd discovers it by walking up from the edited file):

```yaml
If:
  PathMatch: .*\.(cc|cpp|cxx|h|hh|hpp|hxx)
CompileFlags:
  Add: [-std=c++20]   # set to your project's standard
```

`Add` flags apply to every parse, including the orphan-header fallback,
so this pins the standard regardless of scope or which sibling TU is
present. The `If` block keeps a C++ standard off C sources; drop `h`
from the list if your `.h` headers are C. After adding it, force a
re-index (`:ScoperToggle` off then on, or clear the
`stdpath("cache")/scoper/...` directory) so clangd rebuilds with the
fallback in effect. Alternatively, keep the offending header's
sibling `.cpp` in scope (`:ScoperAdd <src-dir>`), or `:ScoperToggle` the
LSP filtering off so clangd reads the full unfiltered database.

If you'd rather wire it manually:

```lua
-- in your clangd setup
local cmd = require("scoper").clangd_cmd({ "--query-driver=/usr/bin/clang*" })
vim.lsp.config("clangd", { cmd = cmd })
```

`clangd_cmd` is guaranteed to return a usable cmd in every state
(scoped, unscoped-with-located-CC.json, or unconfigured), so this
pattern is safe to call unconditionally. Extra args passed to it are
remembered: later reloads (scope edits, `:ScoperLspReload`) keep them
until a call that passes a new list. The `:messages` notification
after each reload tells you which case applied — either
`N/M entries kept → /scoper/cache/path` (filtered), or
`<reason>; clangd pointed at /project/dir` (unscoped but explicit),
or `<reason>; clangd will use built-in discovery` (no CC.json found).

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
| Filtered compile_commands | `stdpath("cache")/scoper/<hash>/<scope>/` |

`<hash>` is the first 16 hex digits of the sha256 of the project path
(lower-cased on Windows). A state file that can't be parsed is kept
next to it as `<hash>.json.corrupt-<time>` before Scoper starts over.

Both directories are safe to delete; Scoper rebuilds on next launch.

## Events

Scoper fires a `User ScoperChanged` autocmd whenever the active scope or
its contents change. Use it to react in your own config:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ScoperChanged",
  callback = function() require("lualine").refresh() end,
})
```

## Limitations

- Symlinks are matched logically (not resolved). If you want resolved
  matching, normalize through `vim.uv.fs_realpath` before adding.
- `:ScoperReplace` requires grug-far.nvim; `:ScoperFind` / `:ScoperGrep`
  use a plain-vim fallback if no picker plugin is installed.
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
busted-style runner, one Neovim process per spec file. The Windows-only
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
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
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
- `lsp_spec`: the compile_commands filter and its cache, the three
  clangd modes, remembered extra args, the per-project cmd, and the
  restart (only this project's clients, the exit poll, the guard,
  queued reloads, automatic skips) against fake clients.
- `pickers_spec`: the scope context (scoping off means the whole cwd),
  the options passed to stub fzf-lua and telescope modules, shell and
  grug-far quoting, the telescope pattern translation, the rewriting of
  absolute excludes and of those of includes outside the cwd, and the
  plain-vim grep filter.
- `commands_spec` sources `plugin/scoper.lua` (the runner starts with
  `--noplugin`) and runs the commands and their completion;
  `init_spec` covers `setup()` and which directory changes it follows.

Not covered: `ui.lua`, and real fzf-lua, telescope and clangd
processes; those are checked by hand.
