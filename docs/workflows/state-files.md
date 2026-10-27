# State files: undo history, ShaDa, sessions, logs

Besides swap files ([swap-files.md](swap-files.md)), Neovim and this
config keep a few things between runs. Most remain until you remove them;
the LSP log has startup rotation as described below. This page says what each one holds, where it
lives on each OS, and how to trim it without losing what you want to keep.
For "something is stale, reset it", see README → Clearing caches instead.

| What | Windows | Linux, macOS | Losing it costs |
|---|---|---|---|
| Undo history | `%LOCALAPPDATA%\nvim-data\undo\` | `~/.local/state/nvim/undo/` | undo past the last restart |
| ShaDa | `%LOCALAPPDATA%\nvim-data\shada\` | `~/.local/state/nvim/shada/` | marks, registers, command and search history, recent files |
| Sessions | `%LOCALAPPDATA%\nvim-data\sessions\` | `~/.local/share/nvim/sessions/` | the window layout restored per project |
| Breakpoints | `%LOCALAPPDATA%\nvim-data\nvim_checkpoints\` | `~/.local/share/nvim/nvim_checkpoints/` | saved DAP breakpoints |
| Logs | `%LOCALAPPDATA%\nvim-data\*.log` | `~/.local/state/nvim/*.log` | nothing you need |

On Linux and macOS, `$XDG_STATE_HOME` / `$XDG_DATA_HOME` replace
`~/.local/state` / `~/.local/share` when set, and `NVIM_APPNAME` replaces
`nvim`. To print the folders on any machine:

```vim
:echo stdpath('state') .. "\n" .. stdpath('data') .. "\n" .. stdpath('log')
```

## Undo history

`undofile` is on, so every file you save gets an undo file in the undo
folder (named like a swap: the full path with `%` for separators). Undo
files of renamed, deleted or long-untouched files stay forever. Deleting
any of them is safe at any time; you only lose the older undo steps of
those files.

Delete undo files older than 90 days:

```powershell
# Windows (PowerShell)
Get-ChildItem "$env:LOCALAPPDATA\nvim-data\undo" -File |
  Where-Object LastWriteTime -lt (Get-Date).AddDays(-90) | Remove-Item
```

```sh
# Linux / macOS
find "${XDG_STATE_HOME:-$HOME/.local/state}/nvim/undo" -type f -mtime +90 -delete
```

To browse a file's undo tree (including edits from earlier sessions):
`<leader>u`.

## ShaDa (marks, registers, history)

Neovim writes `shada/main.shada` when it quits. Two problems come up:

- **"E138: All main.shada.tmp.X files exist, cannot write ShaDa file"**
  on quit. Earlier Neovims that were killed while writing left temporary
  files behind. Quit every Neovim, then delete only the temporary files:

  ```powershell
  Remove-Item "$env:LOCALAPPDATA\nvim-data\shada\main.shada.tmp.*"
  ```

  ```sh
  rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/nvim/shada/main.shada.tmp."*
  ```

- **Stale marks, registers or recent files.** Inside Neovim, `:delmarks!`
  drops the current buffer's lowercase marks and `:delmarks A-Z0-9` the
  file marks; `:wshada!` then rewrites the file without what you deleted.
  For a full reset, quit every Neovim and delete `main.shada`.

## Sessions

auto-session saves one `.vim` file per project directory (named after the
encoded path) when Neovim quits, and restores it when you start `nvim`
without file arguments in that directory.

- Current project: `<leader>wD` or `:AutoSession delete`.
- Other projects: `<leader>wf` lists the saved sessions; `<CR>` loads the
  highlighted one, `<C-d>` deletes it.
- Projects that no longer exist: delete their files from the sessions
  folder. Each file name contains the project path, so they are easy to
  spot. A `<name>.vim.diffview.json` next to a session belongs to it
  (diffview+ keeps the views that were open there); delete it together
  with the `.vim` file.

A session that restores into errors (a deleted file, a plugin window that
no longer exists) is fixed by deleting that one session, not the folder.

## Breakpoints

persistent-breakpoints.nvim keeps one JSON file per project in
`nvim_checkpoints`. Inside a project, `<leader>dX` clears all of them
(on disk too); delete the JSON files of projects you no longer have.

## Logs

- `lsp.log` is appended to by every language server. At startup this config
  attempts to rotate logs larger than 20 MiB to `lsp.log.old`, replacing the
  previous generation. It can still grow during a long running session;
  rotation may also fail if another process holds the file open. Its path:
  `:lua =vim.lsp.log.get_filename()`. Delete or empty it, and remove
  `lsp.log.old` if unwanted, while no Neovim runs.
- `mason.log` and others: same treatment.
- `diagnostic_*.txt` files are `:DiagnosticDump` snapshots in
  `stdpath('log')`. Keep the ones you attached to a report; the rest can
  go.

The startup log threshold is configurable through `retention.log_max_bytes` in
the ignored root `local.lua`; `false` disables rotation. The view janitor's
default 90-day cutoff is separately configurable through `retention.views_days`.
See [retention preferences](../editing-ui-configuration.md#retention) for the
ownership safeguards and cross-editor limits.

```powershell
# Windows: quit every Neovim first
Remove-Item "$env:LOCALAPPDATA\nvim-data\*.log", "$env:LOCALAPPDATA\nvim-data\lsp.log.old", "$env:LOCALAPPDATA\nvim-data\diagnostic_*.txt" -ErrorAction SilentlyContinue
```

```sh
# Linux / macOS: quit every Neovim first
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}"/nvim/*.log "${XDG_STATE_HOME:-$HOME/.local/state}"/nvim/lsp.log.old "${XDG_STATE_HOME:-$HOME/.local/state}"/nvim/diagnostic_*.txt
```

## A periodic tidy-up

Every few months, or before moving to a new machine:

1. `:SwapClean`, and recover anything it keeps for unsaved changes.
2. Trim undo files older than 90 days (above).
3. Delete sessions and breakpoint files of projects that are gone.
4. Quit Neovim and delete the logs.

Copying your setup to another machine: copy the config folder only.
Plugins, Mason packages and parsers reinstall on the first start; state
files carry absolute paths and are rarely useful elsewhere (sessions and
breakpoints point at paths that may not exist there).
