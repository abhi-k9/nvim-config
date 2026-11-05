# Search, selection and session policy

Put machine preferences in the ignored root `local.lua` and return a table.
These examples use the shared settings loader described in
[local configuration](customization.md). Ordinary Lazy `plugins` overrides
remain available for advanced backend options and appearance.

```lua
return {
  project = { root = function(ctx) return ctx.cwd end },
  search = {
    find_root = "project",
    grep_root = "cwd",
    replace_root = "cwd",
    hidden = true,
    respect_gitignore = true,
    follow_links = false,
    exclude_dirs = { ".git", "node_modules", ".cache" },
    explorer = { respect_gitignore = false },
  },
  selector = { provider = "native" },
  explorer = { auto_open = false },
  sessions = {
    auto_save = false,
    auto_restore = false,
    suppressed_dirs = {},
    min_files = 2,
    min_tabs = 2,
    global_buffers = true,
  },
}
```

## Roots and visibility

The config-owned Telescope and fzf file/grep mappings resolve their roots when
invoked. `search.root` defaults to `"cwd"`; `find_root`, `grep_root` and
`replace_root` override it independently. Accepted root intents are:

| Value | Meaning |
| --- | --- |
| `"cwd"` | Active window/tab working directory, including `:lcd` and `:tcd`. |
| `"project"` | `project.root`, or the editor's global working directory. |
| `"scope"` | Loaded Scoper project root, falling back to the project root. This does not apply the scope's include/exclude filter. |
| `"file"` | Current file's parent; unnamed/URI buffers fall back to the current working directory. |
| A path or `function(ctx)` | Explicit path/resolver; relative results resolve against the global working directory. The context contains `cwd`, `filename` and `bufnr`. |

`project.root` is an explicit string or callback; the config does not guess a
repository root by scanning arbitrary parent markers. Root resolution does not
change process cwd. Invoking backend commands directly, such as `:Telescope`,
continues to use that backend's own options.

Visibility fields are `hidden`, `respect_gitignore`, `follow_links` and
`exclude_dirs`. `exclude_dirs` is a replacement list of **literal single
directory names** for file/grep searches, not globs or arbitrary paths. Empty lists disable these
extra exclusions. Matching respects directory boundaries: excluding `.git` and
`node_modules` retains `vendor.git` and `my_node_modules`. Invalid names containing
separators or line breaks are ignored. Source flags and parsed-entry filtering
are both used where supported. Backend leaves under `search.telescope`,
`search.fzf` or `search.explorer` override the common leaves.

The shipped backend defaults retain their intended differences:

| Backend | Hidden | Gitignored | Extra excluded names |
| --- | --- | --- | --- |
| Telescope files | Shown | Hidden | `.git`, `node_modules` |
| Telescope grep | Hidden | Hidden | `.git`, `node_modules` |
| fzf files | Shown | Hidden | `.git`, `.jj` |
| fzf grep | Hidden | Hidden | `.git`, `.jj` |
| Neo-tree | Shown | Shown | `.DS_Store`, `thumbs.db`, `node_modules` |

Link following defaults off for these config-owned ordinary file/grep commands.
Neo-tree's filesystem traversal and search/replace retain their own backend
semantics; the common setting does not promise to change either one. Neo-tree
visibility options and `explorer.auto_open` are read during plugin initialization.
For Neo-tree, `exclude_dirs` supplies `hide_by_name`: it hides matching files as
well as directories. These are filtered entries, not `never_show` entries, so
Neo-tree's `H` toggle can reveal them. They do not limit replacement operations.

Extended fzf file-finder operators require fzf or Telescope's optional
native fzf extension. If the native build is unavailable, Telescope keeps its
Lua sorter; basic finding works, but fzf-specific operators are not guaranteed.
Scoper's native `:find` fallback uses Vim patterns rather than the fuzzy syntax.

Search/replace has a deliberate API boundary. The pinned grug-far version
normalizes even absolute path prefills relative to whichever window is current
and starts deferred work against the current directory. A different resolved
`replace_root` is therefore refused with a message. Change directory explicitly
before opening the replacement UI. Current-file replacement keeps its existing
saved-file and literal-path checks. Common search visibility fields do not
silently rewrite replacement flags; configure grug-far's normal options instead.

## Changing directories after startup

Use `:cd` to switch the global working directory after `nvim .`. For example:

```vim
:cd C:/work/OtherProject
:pwd
```

On Linux/macOS, substitute the actual directory, such as `/home/me/project` or
`/Users/me/project`. Use Vim filename completion/escaping for paths with spaces.
`:cd ..` moves up and `:cd -` returns to the previous directory.

| Operation | Directory scope | Scoper project with shipped defaults |
| --- | --- | --- |
| `:cd PATH` | Global; clears local cwd for the current window and tab | Switches to that directory's saved state/build selection |
| `:tcd PATH` | Current tab; clears the current window's local cwd | Unchanged |
| `:lcd PATH` | Current window | Unchanged |
| Neo-tree `.` / Backspace | Set selected directory as tree root / navigate up; sidebar cwd is tab-local | Unchanged |

Window-local cwd overrides tab-local cwd, which overrides global cwd. Other
tabs/windows can retain their own local directories after a global change.
`:pwd` shows the active directory; `:verbose pwd` identifies its scope.
`:lua print(vim.fn.getcwd(-1, -1))` prints global cwd, and `:ScoperShow` shows
Scoper's actual project/database state.

`<leader>wi` / `:WorkspaceInfo` collects these distinctions in a read-only report:
source file, window/tab/global cwd, configured project root, visible current-tab
Neo-tree source/root, Scoper scope ON/OFF, explicit build selection and resolved
clangd database/preparation status, attached LSP roots, and debugging context.
Debug context includes the next launch root/file and the active session's name,
type, program and cwd; environment/argument tables are not dumped.

Press `r` to refresh the original source window, `h` to read this guide, or
`q` / Esc to close just the report. An unavailable plugin/API is named instead
of failing the whole report. Closed trees' saved roots are deliberately not
queried: asking Neo-tree for fresh state could create it. The report never
requires optional plugin modules, changes cwd, starts a debugger or prepares a
database. Trusted configured root/launch-file resolvers and loaded Scoper status
discovery run on demand, so custom callbacks should remain suitable for inspection.
Use `:ScoperShow` and `:checkhealth config` for deeper state and tooling details.

With default root policies, the components respond as follows:

| Component | Effect of changing global cwd |
| --- | --- |
| Neo-tree | Its bound filesystem tree follows the directory change. Tree navigation can itself set a tab-local cwd, as above. |
| Scoper | Loads the new project's saved scope/build state and reconciles automatic clangd integration. A subdirectory is a separate project unless a root resolver keeps the enclosing project fixed. |
| Telescope/fzf file and grep mappings | New pickers resolve the active cwd at invocation. Reopen an existing picker after switching. |
| Language servers | Discover roots independently for files. A cwd change does not turn an existing client into a client for another project; old buffers can retain old clients. |
| Debugger | Newly selected launches use the new default debug root/launch file. Active sessions and Run Last retain their captured configuration. |
| Terminal/lazygit | New jobs start at invocation cwd. Existing jobs retain their cwd/environment; the default lazygit handle is reused across projects. |
| Sessions | A directory change does not automatically save one layout and restore another: auto-session's `cwd_change_handling` is off by default. Existing buffers/windows remain. |

These are defaults, not a universal root override. `project.root`,
`scoper.project.root`, search/debug root settings and ordinary plugin overrides
can alter the applicable policy. A tree root, an LSP root and a selected build
database remain separate choices.

For an unrelated project, save edits and explicitly save the old session first
if you want its layout preserved (`<leader>wS`). Select a saved session with
`<leader>wf` when a layout switch is intended. Starting another Neovim process
from the new project's prepared shell also keeps project/environment ownership
separate; changing cwd cannot import a new shell's SDK/setup variables.

## Picker responsiveness

Telescope uses width-based path truncation for displayed results. Its `smart`
path formatter compares entries against a growing history of displayed paths;
that work can slow redraws as you browse, even with a healthy native fzf sorter.
Truncation changes only the label: matching, opening and `<C-y>` path copying
still use the original complete path. Normal Lazy `opts.defaults.path_display`
overrides remain available, but enabling `smart` restores that cost.

Cursor animation is disabled in Telescope's prompt so typing uses the real
cursor instead of additional animated overlays. A native insertion caret after
the final character is expected; it is not an extra space in the query. Literal
spaces that you type retain their normal matching semantics.

For a very large repository, `<leader>Ff` offers the existing external fzf file
picker when `fzf` is installed. Or use `:ScoperFind` for a deliberately bounded
working set. `:checkhealth telescope` checks the optional native sorter; a healthy
sorter does not remove result-formatting, preview or UI rendering costs.

## Context help and buffer actions

F1 opens Telescope's native live keymap overlay from either picker mode; `g?`
also opens it from picker Normal mode. Native `?` (Normal) and Ctrl-/ / Ctrl-_
(Insert) remain available. The overlay lists mappings for the current mode,
leaves focus in the prompt and does not alter the query or selection. F1 again
or the next picker action dismisses it. Long lists can be clipped by the native
overlay on small terminals; this is a quick reference, not a scrollable manual.

The results border advertises F1. Buffers pickers show the mark/close hints too:
Tab/Shift-Tab mark or unmark a row and move; Ctrl-d or Alt-d closes the marked
set, or the highlighted row when none is marked. Both picker modes use the same
safe close action. Unsaved rows stay visible, including unlisted buffers owned
by other tabs; successful closes preserve editor windows and refresh the list.

`<leader>fB` explicitly shares these actions and hints with Scope's all-tabs
picker while retaining its cross-tab Enter behavior and Ctrl-w action. This
extension is a separate picker and does not automatically inherit ordinary
Telescope buffers-picker configuration.

fzf-lua already provides native F1 help; its Ctrl-x buffer-close action now has a
readable description there. Native help is generated on demand from registered
mappings, with no per-keystroke help rendering or duplicate manual to maintain.

Neo-tree's F1 / `g?` / `?` show its native keymaps. `<leader>be` toggles its visible
buffers/filesystem source in the current tab, preferring the focused tree if more
than one exists. Switching back preserves the remembered filesystem root and
window placement; it does not reveal an unrelated current file or change the
global working directory. With no visible tree, the mapping opens buffers view.
There is no separate config-owned source flag, project-root resolver or Scoper
dependency. Missing Neo-tree modules or command failures produce a warning.

F1 in Normal mode elsewhere uses the existing which-key local-mapping reference;
native buffer-local F1 mappings take precedence. No new Insert/terminal-mode
binding intercepts terminal input. Mason and grug-far retain `g?`, Lazy retains
`?`, and `<leader>?` remains an alternate local-key reference.

## Scoper picker queries

Scoper searches use the loaded Scoper project root, independently of ordinary
search-root settings. A captured `scoper.scope.query` provides bounded literal
search roots plus the exact inclusion/exclusion predicate used by compilation
database filtering. Includes may be existing directories, individual files or
Neovim glob patterns. A glob searches from its deepest complete literal ancestor
and accepts only matching entries. A scope with no existing roots is refused.

Telescope filters parsed entries. fzf filters raw file/grep rows before decorating
them and keeps the captured predicate in the editor (`multiprocess=false`) for
restricted queries. Native `:find` and `:vimgrep` fallbacks handle individual files
and filter final results. Without ripgrep, individual-file finding uses the
native fallback because fd accepts directory roots. Picker results keep the scope
captured when the picker opened; editing a scope does not mutate an open picker.

For compatibility, disabled scoping or an empty include list searches everything
and ignores the scope's excludes. The existing `g:scoper_follow_links` policy
remains independent and defaults on. Restricted replacement remains refused:
grug-far cannot retain the required per-instance directory and scope contract.

## Selector and explorer ownership

`selector.provider` defaults to `"telescope"`. `"fzf"` registers fzf-lua on the
first selection request, falling back to the prior selector when the `fzf`
executable is unavailable. `"native"` or `false` leaves `vim.ui.select` alone.
This decision is made before installing the lazy selection hook; a later manual
Telescope load does not install its selection extension for another provider.

`explorer.auto_open=false` disables the config-owned startup directory hook.
Explorer toggle/reveal mappings remain available. `ui.icons=false` uses ASCII
explorer markers and disables file-icon decoration in the owned Telescope/fzf
pickers. Third-party layouts can still be customized with normal plugin options.

## Sessions and global buffers

`sessions.auto_save` and `auto_restore` default to `true`. Set both to `false`
for manual sessions; `:AutoSession save`, `restore`, `search` and `delete` still
work. Auto-session continues to name sessions by its own cwd contract; ordinary
search and Scoper root policies do not rename sessions.

By default the exact home, Downloads, configured temporary directory paths and
filesystem root are suppressed. Their subdirectories are not automatically
suppressed. `sessions.suppressed_dirs` replaces this list; `{}` clears it.
The config resolves entries relative to the global working directory, expands a
leading `~`, and prepares realpath/native-separator variants. Supply absolute
paths when registering preferences for several projects. The backend then applies
its own environment/glob expansion and matching: this is not an end-to-end literal
path interface. Use `sessions.suppress` for explicit comparisons when a path
contains `$NAME`, `*`, `?` or other expansion characters.

`sessions.suppress=function(ctx) return ... end` adds an automatic save/restore
veto. It receives the current window/tab `cwd` and a `session_name` when one is
available. A normal cwd-based autosave passes `nil` for the name; automatic
restore supplies the backend's display name. Use `cwd` for ordinary directory
checks and handle an absent name explicitly. Return exactly `true` to suppress;
keep this predicate pure. It does not block
explicit manual save/restore. The automatic save check runs before the backend's
ignored-filetype cleanup and the config's debugger cleanup, so a suppressed save
leaves the visible debugger layout intact.
`config.session` owns one idempotent wrapper around the public `save_session`
boundary; its detach operation restores the prior function only while it still
owns that function. Automatic restore uses the backend's supported pre-restore
hook. Explicit saves retain all debugger/explorer cleanup and scope serialization.

Sessions store file names and layout, not unsaved buffer contents or a running
debuggee. Save edits or retain swap recovery before quitting; session files are
not a content backup. Session files are executable Vim scripts, so restore only
files you trust. Session naming uses auto-session's global-cwd contract, even
when a search or the suppression predicate observes a window-local directory.

When launched with file arguments, automatic saving defaults to a minimum of
two listed ordinary named file buffers (including new files) **or** two tabs.
`sessions.min_files` and `min_tabs`
change these thresholds; each accepts a positive number or `false` to disable
that side of the condition. Both `false` prevent file-argument autosaves.
Normal directory launches retain auto-session's own automatic save rules.

`sessions.global_buffers=true` disables scope.nvim at startup and skips the
scope-specific save/restore adapter. Shared buffers remain visible across tabs;
the all-tabs buffer picker falls back to the ordinary buffer picker. Existing
tab-scoped session metadata is ignored rather than applied as a global buffer
map. Change this setting before startup and restart Neovim. The DAP panel/layout
save protections and dirty-buffer protections remain in effect in either mode.

## Verification

`tests/search_policy_spec.lua` checks literal exclusion boundaries with real
ripgrep, dynamic roots, false/empty values, selector/explorer hooks, manual
sessions, thresholds and global-buffer guards. `tests/scoper_telescope_spec.lua`
uses real Telescope jobs for file/glob includes. Scoper's
`tests/picker_query_spec.lua` verifies native results and captured fzf predicates;
the existing picker suite covers cwd confinement, quoting and replacement refusal.

Backend contracts were checked against the installed locked sources:
[Telescope](https://github.com/nvim-telescope/telescope.nvim),
[fzf-lua](https://github.com/ibhagwan/fzf-lua),
[Neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim),
[auto-session](https://github.com/rmagatti/auto-session), and
[grug-far](https://github.com/MagicDuck/grug-far.nvim).
The pinned [session path matcher](https://github.com/rmagatti/auto-session/blob/02a5588f677970a9bc784115c62bef9e5855499b/lua/auto-session/lib.lua#L615),
[native fzf syntax](https://github.com/nvim-telescope/telescope-fzf-native.nvim/blob/b25b749b9db64d375d782094e2b9dce53ad53a40/README.md), and
[fzf filename-first formatter](https://github.com/ibhagwan/fzf-lua/blob/d9725e6446b82ed38186686fe9d4f9826a98c269/lua/fzf-lua/defaults.lua#L385)
explain the matching boundaries described above.
