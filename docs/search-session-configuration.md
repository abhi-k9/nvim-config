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
directory names**, not globs or arbitrary paths. Empty lists disable these
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

Search/replace has a deliberate API boundary. The pinned grug-far version
normalizes even absolute path prefills relative to whichever window is current
and starts deferred work against the current directory. A different resolved
`replace_root` is therefore refused with a message. Change directory explicitly
before opening the replacement UI. Current-file replacement keeps its existing
saved-file and literal-path checks. Common search visibility fields do not
silently rewrite replacement flags; configure grug-far's normal options instead.

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

By default home, Downloads, temporary directories and the filesystem root are
suppressed. `sessions.suppressed_dirs` replaces this list; `{}` clears it.
Configured paths are literal except leading `~`, resolve relative to the global
working directory, and retain realpath/native-separator handling. Supply absolute
paths when registering preferences for several projects.

`sessions.suppress=function(ctx) return ... end` adds an automatic save/restore
veto. It receives the current `cwd` and the backend's display `session_name`.
Return exactly `true` to suppress; keep this predicate pure. It does not block
explicit manual save/restore. The automatic save check runs before the backend's
panel cleanup, so a suppressed save leaves the visible debugger layout intact.
`config.session` owns one idempotent wrapper around the public `save_session`
boundary; its detach operation restores the prior function only while it still
owns that function. Automatic restore uses the backend's supported pre-restore
hook. Explicit saves retain all debugger/explorer cleanup and scope serialization.

When launched with file arguments, automatic saving defaults to a minimum of
two real listed file buffers **or** two tabs. `sessions.min_files` and `min_tabs`
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
