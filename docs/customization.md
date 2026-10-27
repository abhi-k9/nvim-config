# Customize this configuration

Create `local.lua` next to `init.lua`. It is ignored by Git and is optional.
Return a Lua table; the configuration reads it before core maps, autocmds, and
plugins are registered. Restart Neovim after changing startup policy.

```lua
return {
  globals = { mapleader = ",", maplocalleader = ";" },
  options = { exrc = false, shiftwidth = 4, spelllang = "en_gb" },
  tools = { servers = { "lua_ls", "pyright", "ruff" } },
  editing = { trim_skip_filetypes = { "markdown", "diff", "text" } },
  plugins = {
    { "nvim-lualine/lualine.nvim", opts = { options = { globalstatus = false } } },
  },
}
```

The file is trusted executable Lua, just like `init.lua`. Keep tokens and machine
paths out of tracked files. Git ignores only the root `local.lua`; arbitrary
new source files still appear in the documentation checks. To use another file,
set `vim.g.config_local_file` to its filename **before** loading `init.lua`.
Set it to `false` to disable local loading. The test harness does this so a
developer's private configuration cannot change the default regression suite.
A missing file uses defaults; a broken file reports an error and uses defaults.

## Load order and override rules

1. Capture explicitly pre-set Neovim options and load `local.lua`.
2. Apply `globals`, then shipped options, then captured options and `options`.
3. Register core maps and autocmds using those effective settings.
4. Import shipped plugin specs, then append `plugins` as ordinary Lazy specs.
5. Configure LSP/DAP defaults, apply their overrides, and activate integrations.

An explicitly pre-set leader or option survives shipped defaults. An `options`
entry wins over a pre-set option. Prefer the returned `globals`/`options` tables
to side effects in `local.lua`; direct option assignments inside that file are
outside the capture/apply contract.

`require("config.settings").get("tools.servers", fallback)` returns the exact
configured value or the fallback when absent. `false`, an empty table, and a
function are meaningful values. Returned tables are copies. Lists replace;
they do not concatenate. Extend a list explicitly when desired. Do not assume
an incomplete dictionary is merged with a caller's fallback dictionary; the
shipped policies read individual leaf settings where that distinction matters.

`plugins` uses Lazy's own merging rules, independently of these setting rules.
Use plugin `opts` and `config` overrides for layout, appearance, keymaps, and
plugin-specific settings; there is no second plugin configuration framework.
To disable a plugin, use a normal spec such as
`{ "karb94/neoscroll.nvim", enabled = false }`.

## Project context and trust

The settings module never searches a project for Lua or executes project files.
Neovim's `exrc`/`:trust` mechanism remains responsible for project configuration.
Set `options.exrc=false` if project-local Lua is unwanted.

Trusted code can register a runtime overlay explicitly:

```lua
require("config.settings").for_project("/work/project-a", {
  search = { root = "project", exclude_dirs = { ".git", "generated" } },
  editing = { trim_whitespace = false },
})
```

Overlays match the **global** working directory and its descendants, most
specific last. Dictionaries merge, lists replace, and changing global directory
removes the previous project's runtime overlay. This models one active project.
An `:lcd`/`:tcd` changes invocation cwd without changing project identity. It
does not activate a different project overlay. Startup settings such as leaders,
plugin specs, tool lists, theme, and session adapter selection need a restart;
registering a later overlay does not undo already-installed behavior.
Scoper modes and database candidates are plugin setup settings; after changing
them at runtime, call its explicit `setup()`/`patch()` API. Its shared project
root resolver and the documented invocation-time search/debug roots remain
dynamic.

`project.root` may be a path or `function(ctx)` returning a path. The context
contains `cwd` (global directory), `filename`, and `bufnr`. Relative paths resolve
against the global directory. Paths preserve literal `$`, `%`, `#`, and POSIX
backslashes; only a leading `~` is expanded.
The standalone `scoper.project.root` callback instead receives the global cwd
string, following Scoper's own API; the shared resolver adapts that fallback.
On Windows use fully qualified drive/UNC paths. Drive-relative `C:folder` roots
are rejected; `\folder` uses the global cwd's drive and requires an explicit
fully qualified path when that cwd is on a UNC share.

Commands choose their context at invocation through
`require("config.settings").resolve(intent)`:

| Intent | Root |
| --- | --- |
| `"cwd"` | Current window/tab directory, including `:lcd`/`:tcd` |
| `"project"` | `project.root`, then `scoper.project.root`, then global cwd |
| `"file"` | Current file's parent; unnamed/URI buffers use invocation cwd |
| `"scope"` | Loaded Scoper project root; project root before Scoper loads |
| Path or `function(ctx)` | Explicit root resolved against global cwd |

This resolver does not change third-party cwd contracts automatically. See the
feature guides for supported boundaries.

## Feature guides and inspection

- [Tool selection, executables, LSP and offline completeness](tooling-configuration.md)
- [Scoper state, matching and persistence](scoper-core-notes.md)
- [Scoper compilation databases and clangd modes](scoper-integration-notes.md)
- [Search, selector, explorer and sessions](search-session-configuration.md)
- [Debug adapters, launch files and terminals](debug-terminal-configuration.md)
- [Editing, UI and retention](editing-ui-configuration.md)
- [Verification environment, acceptance cases and limits](generalization-verification.md)

Inspect one effective value with
`:lua vim.print(require("config.settings").get("search.root", "cwd"))`.
`:lua vim.print(require("config.settings").info())` shows the local source path
and registered project roots, without dumping arbitrary settings or secrets.
Use `:checkhealth config` for tool readiness, `:ScoperStatus` for scope state,
and the Scoper integration guide for compilation status. `:DiagnosticDump`
still requires review before sharing: paths, messages, and log tails can contain
sensitive data.

Existing `vim.g` controls (large files, health reminders, swap/tar safeguards,
parser auto-install) remain supported; put them under `globals` in `local.lua`.
No version policy changes: use `:Lazy update`/`:Lazy restore` for plugins,
Mason's update commands for selected tools, and the explicit CI action updater
for immutable action pins.

Upstream contracts checked for this implementation:
[Neovim project trust](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/options.txt),
[Lazy spec merging](https://lazy.folke.io/spec), and
[clangd database selection/compiler execution flags](https://github.com/llvm/llvm-project/blob/main/clang-tools-extra/clangd/tool/ClangdMain.cpp).
The feature guides link additional backend contracts and state their limits.
