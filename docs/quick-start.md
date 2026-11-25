# Everyday workflows

`<leader>` means Space. Press `<leader>ff` as three keys in sequence. Unless a
step says otherwise, press Esc to enter Normal mode first. Finish `:` commands
with Enter. [Installation instructions](workflows/install-update-uninstall.md)

## First session

1. In your project directory, run `nvim .`. If your build needs an SDK shell,
   start Neovim from that shell. On first launch, let plugin installation finish.
2. Press Space, f, f. Type part of a filename and press Enter to open it.
3. Press `i` to edit and Esc when finished. Ctrl-s saves, `u` undoes and Ctrl-r redoes.
4. Put the cursor on a symbol. With a language server attached, `gd` jumps to
   its definition. Ctrl-o takes you back.
5. Use `:wa` to save all edited files and `:qa` to quit.

## Discover actions inside a feature

Press Space and wait for the shortcut menu. In a picker, Neo-tree or Trouble,
F1 shows the keys for that view. In Mason and grug-far, use `g?`. Open
`:ConfigHelp` for the guides or `<leader>fk` to search mappings. [Context help](context-help.md)

## Find files, text and symbols

| Task | Keys |
| --- | --- |
| Find files / grep project text | `<leader>ff` / `<leader>fg` (grep needs ripgrep) |
| Recent files / buffers in this tab / buffers in all tabs | `<leader>fr` / `<leader>fb` / `<leader>fB` |
| Toggle the file tree / reveal the current file | `<leader>e` / `<leader>E` |
| Switch the tree between open buffers and files | `<leader>be` |
| Find references / symbols in this file / workspace symbols | `gr` / `<leader>fs` / `<leader>fS` |
| Search jumps / edits in this file / edits across loaded files | `<leader>fj` / `<leader>fC` / `<leader>fE` |
| Search in the current file | `/text`, then Enter. Use `n` / `N` for next / previous. |

In the references panel, Enter opens a result and keeps the list. Press `o` to
open the result and close the list. From the file window, use
`:Trouble lsp_references close` to dismiss the list while keeping the file open.

To switch projects, use `:cd /path/to/project` (Windows example
`:cd C:/work/OtherProject`). Use `:WorkspaceInfo` if the tree, picker or clangd
seems to be using a different root. [Directory scopes](search-session-configuration.md#changing-directories-after-startup)

## Edit and review

- **Completion** — Ctrl-n / Ctrl-p select a candidate in Insert mode. Ctrl-y
  accepts it and Ctrl-e dismisses it.
- **Code actions** — `<leader>lr` renames a symbol, `<leader>la` lists code
  actions and `<leader>cf` formats the file or selection.
- **Diagnostics** — `]d` / `[d` visit the next / previous diagnostic. Toggle
  the workspace list with `<leader>xx`; press `q` in the panel to close it.
- **Replace text** — `<leader>sf` searches the current saved file;
  `<leader>sr` searches the replacement root. Review the paths and preview,
  then press `\r` in grug-far's Normal mode to apply.
- **Compare undo states** — Open `<leader>u`, highlight the first state and
  press `=`. Move to the second state to preview the diff. Enter restores it.
- **Git** — `]h` / `[h` visit hunks. `<leader>gp` previews a hunk and
  `<leader>gs` stages it. `<leader>tg` opens LazyGit when installed.

## Build and debug

Open a horizontal terminal with `<leader>th` and run your normal build command.
For a configured CMake project, for example, run `cmake --build out/debug`
using your own build directory. Esc twice enters Terminal-Normal mode; `i`
resumes shell input.

1. Build with debug information. Adapt the [launch template](templates/dap/launch.json.example)
   in your project's `.vscode/launch.json`, including the executable and cwd.
2. Check the launch file with `<leader>dL`. In a source file, press F9 on an
   executable line and F5 to choose a configuration and start debugging.
3. F10 steps over, F11 steps into and F5 continues. Use `<leader>dt` to stop.

For adapter setup, program input or slow CodeLLDB launches, see
[debugging and terminals](debug-terminal-configuration.md).

## Keep a useful layout and resume work

- **Split** the focused window with `<leader>wv` or `<leader>ws`. Ctrl-h/j/k/l move between windows.
- **Close** the current buffer with `<leader>bd` to keep the split. To close
  several, open `<leader>fb`, mark rows with Tab and press Ctrl-d. Unsaved buffers are skipped.
- **Resume** a project with `nvim .`. To save a session explicitly use
  `<leader>wS`; `<leader>wf` picks a saved session. Save edited files first.
  Sessions restore layout and file names. [Session settings](search-session-configuration.md#sessions-and-global-buffers)

## Scope a large project

Run `:ScoperNew working`, then `:ScoperAdd src include` and
`:ScoperExclude **/generated/**`, substituting paths from your project.
Check `:ScoperStatus`; if it is off, use `:ScoperToggle`. Use `:ScoperFind`
and `:ScoperGrep` for scoped searches. Ordinary finders keep their own search
rules. [Scoper settings](scoper-project-config.md)

If a feature is missing, start with `:checkhealth config`. For an unattached
language server use `:checkhealth vim.lsp`; for a failed debug launch use
`:DapShowLog`. [Missing tools](limited-environments.md) · [All guides](README.md)
