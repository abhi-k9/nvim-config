# Per-project Scoper configuration

Place `.scoper.json` in Scoper's configured project root. By default this is the
**global working directory**, not necessarily the Git root. Scoper reads exactly
that file: it does not walk parents or execute project-local Lua.

## Quick start

Run `:ScoperConfigExport` to create an indented JSON file from current settings
and scopes. Review it before committing it to your project. This file is optional;
projects without it keep their existing behavior.

```json
{
  "version": 1,
  "settings": {
    "default_excludes": ["**/build/**", "**/vendor/**"],
    "picker": "auto",
    "compilation_database": { "path": "build/compile_commands.json" },
    "lsp": { "mode": "filtered", "startup": "prepare", "watch": true }
  },
  "scopes": {
    "cpp": { "include": ["**/*.{cpp,hpp}"], "exclude": ["**/generated/**"] }
  },
  "active": "cpp",
  "enabled": true
}
```

Paths resolve against the configured root; `/` works on Windows too. Scope
patterns use [globs](glob-cheatsheet.md). Empty includes admit everything before
applying exclusions. JSON requires double quotes and does not support comments.

## Commands and ownership

| Command | Effect |
| --- | --- |
| `:ScoperConfigExport` | Create `.scoper.json`; refuse to overwrite an existing file. |
| `:ScoperConfigExport!` | Explicitly replace an existing regular config file. |
| `:ScoperConfigReload` | Read settings again; retain current scope definitions and selections. |
| `:ScoperConfigReload!` | Also apply configured scope definitions, active scope and enabled state. |
| `:ScoperReload` | Reload the separate saved personal state, as before. |

Settings load at setup, when the configured root changes, and on explicit config
reload. Editing the file does not trigger a watcher. Ordinary Scoper commands
still save only personal state under `stdpath("data")/scoper/`; they never rewrite
`.scoper.json`.

Reloading a changed database selection in `selected` or `filtered` mode also
restarts affected running clangd clients with the updated command. Updating the
launch settings alone would only affect future clients.

Configured scopes seed a root without saved state. Existing saved scopes win.
Reload with `!` replaces matching named definitions but retains unmentioned local
scopes; `active` and `enabled` change only if present in the file. Unsaved local
changes block this explicit import. Save/recover them first. Import failures
retain the in-memory state and report the persistence error.

A locally selected `:ScoperDatabase` still takes priority over the configured
build path. Use `:ScoperDatabase!` to clear that selection. Export includes the
current selection, made root-relative when inside the project.

## Precedence and supported settings

Settings merge in this order, later values winning:

1. Scoper's built-in defaults.
2. Host/user `setup()` options (including this configuration's `local.lua`).
3. `.scoper.json` `settings`.
4. Trusted `project_config.overrides` supplied through `setup()`/`local.lua`.

Dictionaries merge; arrays replace, including empty arrays. `default_excludes`
seeds newly created scopes; a scope's explicit `exclude` list replaces it.
Omitted scope includes default to empty. Without `active`, a new project's
`default` scope wins if present, otherwise the first sorted name.

Allowed JSON settings are:

- `default_excludes`: array of glob strings.
- `picker`: `auto`, `fzf`, or `telescope`. A manual `g:scoper_picker` override wins.
- `compilation_database`: `path` (string or `false`) and `candidates` (array,
  maximum 256). Existing database resolution rules still apply.
- `lsp`: `mode` (`disabled`, `native`, `selected`, `filtered`), `startup`
  (`fallback`, `prepare`), `watch` (boolean), `debounce_ms` and
  `prepare_timeout_ms` (integer milliseconds, 1–600000).

Executables, arbitrary clangd arguments, `query_drivers`, root resolvers and Lua
callbacks belong in trusted local setup, and are rejected in project JSON.
Export omits those machine-specific values. An existing local database resolver
still has its normal precedence over a configured path.

To ignore project files entirely, set `scoper.project_config.enabled = false`
in your host settings. To enforce a personal preference while retaining project
settings, use, for example, `scoper.project_config.overrides.picker = "telescope"`.
`setup()` replaces the local base options; `patch()` updates that base without
copying a project's settings into the next root's configuration.

## Failure handling

Files are limited to 1 MiB and must be regular files, not symlinks. Unknown
fields, invalid types/globs and unsupported versions reject the whole document.
Reads compare file identity, size and modification metadata before and after
reading. If a concurrent edit or replacement is detected, reload is rejected;
finish saving the file and run `:ScoperConfigReload` again.
Explicit reload leaves the working configuration intact on validation failure;
setup/root changes use that root's last valid document in this editor, or host
defaults if none exists. Saved scope data is not deleted. Inspect file status
with `:lua vim.print(require('scoper').project_config_status)`.

Exports publish complete JSON from a temporary file in the same directory.
Non-overwriting export uses a hard link for race-safe creation; on filesystems
without hard-link support it reports an error. Explicit `Export!` uses atomic
rename and is last-writer-wins. Both clean up temporary files after reported
failures. No automatic migration or background rewriting is performed.

The lifecycle, precedence, validation and export regression tests run in temporary
roots. Native Windows filesystem behavior still requires platform verification.
