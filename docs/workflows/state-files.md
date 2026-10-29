# State files: undo history, ShaDa, sessions, logs

Besides swap files ([swap-files.md](swap-files.md)), Neovim and this
config keep a few things between runs. Most remain until you remove them;
the LSP log has startup rotation and fold views have an exit-time janitor.
This page explains what each one holds and what removing it loses.
For "something is stale, reset it", see README → Clearing caches instead.

| What | Windows | Linux, macOS | Losing it costs |
|---|---|---|---|
| Undo history | `%LOCALAPPDATA%\nvim-data\undo\` | `~/.local/state/nvim/undo/` | undo past the last restart |
| ShaDa | `%LOCALAPPDATA%\nvim-data\shada\` | `~/.local/state/nvim/shada/` | marks, registers, command and search history, recent files |
| Sessions | `%LOCALAPPDATA%\nvim-data\sessions\` | `~/.local/share/nvim/sessions/` | the window layout restored per project |
| Breakpoints | `%LOCALAPPDATA%\nvim-data\nvim_checkpoints\` | `~/.local/share/nvim/nvim_checkpoints/` | saved DAP breakpoints |
| Fold views | `%LOCALAPPDATA%\nvim-data\view\` | `~/.local/state/nvim/view/` | saved fold state |
| Logs | `%LOCALAPPDATA%\nvim-data\*.log` | `~/.local/state/nvim/*.log` | troubleshooting evidence |

These are default locations. XDG directory overrides and `NVIM_APPNAME` can
change them, including side-by-side installations. To print the actual folders:

```vim
:echo stdpath('state') .. "\n" .. stdpath('data') .. "\n" .. stdpath('log')
```

For the shell maintenance commands below, resolve the state directory using the
same executable and environment as your usual Neovim. Quit all interactive
instances first. These helper invocations skip your configuration and ShaDa:

```powershell
$nvimState = & nvim --headless -u NONE -i NONE --cmd 'lua io.write(vim.fn.stdpath([[state]]))' --cmd quit
$nvimState
```

```sh
nvim_state=$(nvim --headless -u NONE -i NONE --cmd 'lua io.write(vim.fn.stdpath([[state]]))' --cmd quit)
printf '%s\n' "$nvim_state"
```

Check the printed/resolved value before deleting anything. If you override native
options, inspect `:set undodir? viewdir? shadafile?` as well: those options can
move individual files outside the standard state tree.

## Undo history

`undofile` is on. Eligible ordinary file writes keep undo history under
`undodir`, normally the undo folder above, with the full file path encoded in
the name. Undo files of renamed, deleted or long-untouched files remain until
removed; there is no automatic undo janitor. Removing one loses that file's
persistent undo history, not the source file. A running editor may write the
history back, so do cleanup after quitting. Undo files can retain earlier source
text, including text already removed from the saved file.

Delete undo files older than 90 days:

```powershell
# Windows (PowerShell)
Get-ChildItem -LiteralPath (Join-Path $nvimState 'undo') -File |
  Where-Object LastWriteTime -lt (Get-Date).AddDays(-90) |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName }
```

```sh
# Linux / macOS
find "${nvim_state:?Resolve the Neovim state directory first}/undo" -type f -mtime +90 -delete
```

To browse a file's undo tree (including edits from earlier sessions):
`<leader>u`.

## ShaDa (marks, registers, history)

Neovim writes `shada/main.shada` when it quits. Two problems come up:

- **"E138: All main.shada.tmp.X files exist, cannot write ShaDa file"**
  on quit. Earlier Neovims that were killed while writing left temporary
  files behind. Quit every Neovim, then delete only the temporary files:

  ```powershell
  Get-ChildItem -LiteralPath (Join-Path $nvimState 'shada') -Filter 'main.shada.tmp.*' -File |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName }
  ```

  ```sh
  rm -f "${nvim_state:?Resolve the Neovim state directory first}/shada/main.shada.tmp."*
  ```

- **Stale marks, registers or recent files.** Inside Neovim, `:delmarks!`
  clears the current buffer's marks/changelist except A–Z and 0–9;
  `:delmarks A-Z0-9` clears those file marks. `:wshada!` rewrites the file
  from the current in-memory state, without merging the older file. This is
  a mark cleanup, not a register/history reset. For a full reset, quit every
  Neovim using this state tree and delete `shada/main.shada`. Other running
  instances can otherwise repopulate it on exit.

## Sessions

By default auto-session saves a `.vim` file named after the editor's global cwd
when Neovim quits, and restores it for a bare `nvim` or single-directory launch.
Home, Downloads, configured temp paths and the filesystem root are suppressed
by default; their subdirectories are not automatically suppressed. File-argument
launches skip automatic restore and save only after reaching the configured
file/tab thresholds. Manual names and local policy can change these rules;
see [session policy](../search-session-configuration.md#sessions-and-global-buffers).

Sessions keep file names, window/tab layout and selected local state, not unsaved
contents or running terminals/debuggees. They are executable Vim scripts, so do
not restore a session file from an untrusted source. Save files and keep recovery
data independently of sessions.

- Current project: `<leader>wD` or `:AutoSession delete`.
  Deleting the active session also disables auto-saving for the rest of that
  Neovim instance, so it is not immediately recreated on exit.
- Other projects: `<leader>wf` lists the saved sessions; `<CR>` loads the
  highlighted one, `<C-d>` deletes it.
- Projects that no longer exist: delete their files from the sessions
  folder. Each file name contains the project path, so they are easy to
  spot. A `<name>.vim.diffview.json` next to a session belongs to it
  (diffview+ keeps the views that were open there); delete it together
  with the `.vim` file.

A stale session can often be repaired by deleting just that session and saving
a clean layout. Deleting it does not fix a missing plugin or restore a deleted
source file. Keep useful sidecars and inspect the original error first.

## Breakpoints

persistent-breakpoints.nvim keeps one JSON file per project in
`nvim_checkpoints`, keyed by its own current-cwd contract. Inside a project,
`<leader>dX` clears in-memory breakpoints and writes an empty breakpoint map to
the current cwd's JSON file; it does not remove every project's saved file.
Delete JSON files of projects you no longer need while no instance is using them.
A separate debugger root or `launch.json` path does not relocate this storage.

## Other saved state

- Fold views live under `viewdir` and contain folds only in this config.
  The exit-time janitor removes recognized views older than 90 days by default;
  `retention.views_days` changes or disables it. Removing a view loses saved folds.
- Scoper project scopes and build selections live under `stdpath('data')/scoper/`.
  They are user selections, not disposable parser caches; see
  [Scoper state](../scoper-core-notes.md) before resetting them.
- Atone marks use `stdpath('data')/atone_marks.json`; Diffview reviewed-file
  selections use `stdpath('data')/diffview_selections.json`. Removing these loses
  the plugin's saved marks/selections, not source files.
- `stdpath('state')/tooling-reminder` records the last optional-tool reminder.
  Removing it makes the next eligible check due again; it does not repair tools.

## Logs

- `lsp.log` is Neovim's client log, including server messages according to its
  log level. At startup this config
  attempts to rotate logs larger than 20 MiB to `lsp.log.old`, replacing the
  previous generation. It can still grow during a long running session;
  rotation may also fail if another process holds the file open. Its path:
  `:lua =vim.lsp.log.get_filename()`. Delete or empty it, and remove
  `lsp.log.old` if unwanted, while no Neovim runs.
- `mason.log` and others: same treatment.
- `diagnostic_*.txt` files are `:DiagnosticDump` snapshots in
  `stdpath('log')`. Keep the ones you attached to a report; the rest can
  go. Review a snapshot before sharing: paths, messages and the LSP log tail
  can include project data. `:DiagnosticDump!` additionally includes unredacted
  DAP configuration.

The startup log threshold is configurable through `retention.log_max_bytes` in
the ignored root `local.lua`; `false` disables rotation. The view janitor's
default 90-day cutoff is separately configurable through `retention.views_days`.
See [retention preferences](../editing-ui-configuration.md#retention) for the
ownership safeguards and cross-editor limits.

```powershell
# Windows: quit every Neovim first
$nvimLogs = & nvim --headless -u NONE -i NONE --cmd 'lua io.write(vim.fn.stdpath([[log]]))' --cmd quit
Get-ChildItem -LiteralPath $nvimLogs -File |
  Where-Object { $_.Name -like '*.log' -or $_.Name -eq 'lsp.log.old' -or $_.Name -like 'diagnostic_*.txt' } |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName }
```

```sh
# Linux / macOS: quit every Neovim first
nvim_logs=$(nvim --headless -u NONE -i NONE --cmd 'lua io.write(vim.fn.stdpath([[log]]))' --cmd quit)
rm -f "${nvim_logs:?Resolve the Neovim log directory first}"/*.log "$nvim_logs"/lsp.log.old "$nvim_logs"/diagnostic_*.txt
```

## A periodic tidy-up

Every few months, or before moving to a new machine:

1. `:SwapClean`, and recover anything it keeps for unsaved changes.
2. Trim undo files older than 90 days (above).
3. Delete sessions and breakpoint files of projects that are gone.
4. Quit Neovim and delete the logs.

Copying your setup to another machine: copy the config folder only.
Plugins reinstall when online; eligible Mason packages and parsers install only
when their platform/runtime/compiler prerequisites are available. Use an offline
seed where networking is unavailable. State files carry absolute paths and are
rarely useful elsewhere (sessions and
breakpoints point at paths that may not exist there).
