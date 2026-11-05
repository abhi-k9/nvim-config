# Quick start: everyday workflows

This guide uses the shipped mappings. `<leader>` means **Space**, pressed before
the following letters: `<leader>ff` is Space, f, f in sequence. `<C-s>` means
hold Ctrl and press s. Unless stated otherwise, press **Esc** to enter Normal
mode before using a mapping. `:` commands finish with Enter.

For installation, use the [platform instructions](workflows/install-update-uninstall.md).
For an IDE-oriented introduction, use the [Visual Studio migration guide](visual-studio-migration.md).
Keep this guide for daily tasks and the [keymap sheet](cheatsheets/keymaps.html)
for the larger reference.

## First session

1. Open a terminal in your project directory and run `nvim`. If your build needs
   an SDK/setup environment, prepare that shell **before** starting Neovim.
   Let plugin installation finish on a new setup. Optional development tools can
   be absent; `:checkhealth config` explains missing capabilities.
2. Press Space, f, f; type part of a filename; choose a result and press Enter.
   In this picker, Ctrl-j/Ctrl-k move the selection and Esc closes it.
3. Press `i` to insert text, then Esc to return to Normal mode. `u` undoes;
   Ctrl-r redoes. Save with Ctrl-s or `:w`. Ctrl-s also saves from Insert mode
   and leaves you in Normal mode.
4. Put the cursor on a symbol and press `gd` to find its definition. Ctrl-o
   returns to the previous jump. These language features need an attached server.
5. Use `:wa` to write all file buffers, then `:qa` to quit. Unsaved changes can
   block quitting; inspect them rather than adding `!` just to dismiss the error.

Press Space and wait for the which-key menu whenever you forget a mapping.
`<leader>fk` searches mappings; `<leader>fh` searches help; `:pwd` shows the
active directory. Launching here sets the initial directory context; opening a
file does not import a Visual Studio solution or select a build configuration.

## Discover actions inside a feature

Press **F1** in Telescope, fzf-lua, Neo-tree or Trouble for that feature's live
key reference. Telescope's result border reminds you of F1; its buffer picker
also shows the mark/close keys. Help reflects the active mappings, including
our custom actions.

| Context | Other help keys |
| --- | --- |
| Telescope | `g?` or `?` in its Normal mode; Ctrl-/ (often Ctrl-_) while typing. |
| Neo-tree / Trouble | `g?` or `?` inside the panel. |
| Mason / grug-far | `g?` opens the native help page. |
| Lazy | `?` opens its native help page. |
| Other buffers | F1 in Normal mode, or `<leader>?`, lists local mappings through which-key; with no local mappings or no which-key, it opens Neovim help. |

Telescope's reference is a compact overlay for the current picker mode, not a
scrollable manual. Press F1 again, or perform an action, to dismiss it and keep
your query. Literal `?` and `g?` still type normally in search prompts.
On a Mac, F1 may require Fn+F1; terminal/system shortcuts can intercept function
keys. Use the alternate keys above. Ctrl-Shift-? is deliberately not required
because some terminals encode it as Backspace/Delete.

`<leader>be` opens Neo-tree's buffers view; press it again to return to its
remembered filesystem view. A closed tree starts in buffers view. This changes
the view without selecting a new project root. If Neo-tree is unavailable, the
mapping reports that condition without throwing an error.

## Change the working directory

After `nvim .`, use `:cd /path/to/project` (Windows: `:cd C:/work/OtherProject`),
then `:pwd` to check it. `:cd ..` goes up; `:cd -` returns to the previous cwd.
With the shipped defaults, this moves Scoper's project and newly opened ordinary
searches together. Prefer the repository root: changing to a subdirectory also
changes Scoper's project identity unless you configured a project-root resolver.

Neo-tree's `.` sets the selected directory as its root and Backspace navigates
up, but its sidebar uses **tab-local** cwd by default. This can move ordinary
searches while Scoper stays at the global cwd. Use `:cd` for a project-wide
switch. See [directory scopes and plugin behavior](search-session-configuration.md#changing-directories-after-startup)
for `:tcd`, `:lcd`, sessions, terminals, language servers and debug launches.

## Find files, text and symbols

| Task | Keys | What to expect |
| --- | --- | --- |
| Find a file | `<leader>ff` | Fuzzy filename picker under the configured search root; current cwd by default. |
| Find text across files | `<leader>fg` | Live grep; needs ripgrep. |
| Search the current file | `/text`, Enter, then `n` / `N` | Next / previous match; Esc clears highlighting. |
| Recent files / open buffers | `<leader>fr` / `<leader>fb` | Buffer picker shows this tab's buffers by default; `<leader>fB` reaches all tabs. |
| Show / reveal in the file tree | `<leader>e` / `<leader>E` | Toggle Neo-tree / reveal the current file. |
| Definition / references | `gd` / `gr` | Definition lookup / focused Trouble references panel. |
| Symbols in this file / workspace | `<leader>fs` / `<leader>fS` | Ask the language server for symbols. |
| Jump back / forward | Ctrl-o / Ctrl-i | Neovim's jump history. |

The uppercase `<leader>F...` family offers fzf-lua alternatives when `fzf` is
installed. You only need to learn one finder initially. Ordinary `ff` / `fg`
do not acquire Scoper's membership filter just because a scope is selected.

## Edit, inspect and format

In Insert mode, Ctrl-n/Ctrl-p open and navigate completion; Ctrl-y accepts,
Ctrl-e dismisses. Enter inserts a newline rather than accepting a candidate;
Tab handles snippet jumps/fallback indentation. Selection is not acceptance.

| Task | Keys | Notes |
| --- | --- | --- |
| Rename a symbol / request a code action | `<leader>lr` / `<leader>la` | Semantic operations depend on the server and project configuration. |
| Inspect a symbol | `K` | Hover when not peeking a closed fold. |
| Format the buffer or a Visual selection | `<leader>cf` | Conform uses available configured formatters, with LSP fallback. |
| Format through LSP | `<leader>lf` | Whole-buffer request; requires server formatting support. |
| Show a line diagnostic | `<leader>ld` | Diagnostic details in a float. |
| Next / previous diagnostic | `]d` / `[d` | Jump and inspect. |
| Diagnostics list | `<leader>xx` | Trouble workspace diagnostics; `<leader>xX` limits to this buffer. |
| Comment code | `gcc`, or select with `V` then `gc` | Current line / selected lines, using the filetype's comment syntax. |

Formatting on save is off. Trailing-whitespace cleanup is a separate save
policy. To opt into format-on-save, use the
[local.lua recipe](tooling-configuration.md#opt-into-format-on-save).
After a rename or code action, inspect the changed files and save the intended
edits (`:wa` writes all file buffers). `:ls` helps find buffers marked modified.
For system clipboard copying, select text and type `"+y`; paste in Normal mode
with `"+p`. This requires a working clipboard provider; plain `y` / `p` use
Neovim's registers by default.

To close the diagnostics panel, press `<leader>xx` again from any window, or
`q` while focused inside Trouble. `:Trouble diagnostics close` closes it
explicitly. Enter jumps to an item and leaves the panel open; `o` jumps and
closes it. `:q` closes whichever window currently has focus, which may be your
file window after a jump. The statusline's `Diagnostics` label identifies the
Trouble panel; it is not a separate editing mode.

## Replace text with a preview

1. Use `<leader>sf` for the current saved file, or `<leader>sr` for the current
   replacement root. `<leader>sw` prefills the word under the cursor.
2. Edit the Search / Replace fields in grug-far. Inspect the file paths, matches
   and replacement preview; narrow the file/path inputs as needed.
3. In that buffer's Normal mode, press `\r` to apply replacements. Backslash is
   the shipped local leader. `g?` shows grug-far's own mappings.
4. Review the resulting diff before committing. Semantic rename uses
   `<leader>lr`; a text replacement does not understand symbol identity.

Scoper-restricted replacement is refused rather than silently replacing outside
the scope. Ordinary replacement has its own cwd/backend contract; see
[search boundaries](search-session-configuration.md#roots-and-visibility).

## Build, run and test

Use your project's existing build/test commands. `<leader>th` opens a horizontal
terminal; `<leader>tt` opens a floating terminal. For an **already configured
CMake project** whose build directory is `out/debug`, for example:

```sh
cmake --build out/debug --config Debug
ctest --test-dir out/debug -C Debug --output-on-failure
```

Substitute your actual build directory and configuration. These commands do not
configure the project or create tests. For MSBuild, use a prepared developer
environment and your normal solution/project command; the
[migration guide](visual-studio-migration.md#build-run-and-test) explains the boundary.
Scoper does not run builds or synchronize Debug/Release with the debugger.

Inside a terminal, press Esc twice to enter Terminal-Normal mode; `i` resumes
input. Esc twice followed by Ctrl-\ toggles the floating terminal. An existing
terminal job keeps its shell environment and original cwd when reopened.

## Debug a compiled program

1. Build an executable with debug information using your normal build system.
2. Copy/adapt the [launch template](templates/dap/launch.json.example) into the
   project's `.vscode/launch.json`. Select the correct adapter and set `program`,
   `cwd`, arguments and environment for that actual build.
3. Use `<leader>dL` to validate/preview configurations without launching.
4. Set a breakpoint with F9, then F5 to choose/start a launch configuration.
   F10 steps over, F11 steps into, `<leader>dO` steps out, and F6 pauses.
5. Inspect variables/stack in DAP UI; `<leader>de` evaluates an expression and
   `<leader>du` toggles the panels. `<leader>dt` terminates the session.

Without a launch file, a generated fallback can prompt for an executable. It
does not build it. F5 during a live session continues that session; stop it and
select a new configuration to pick up edited launch settings. CodeLLDB's console
is a debugger REPL, not an interactive stdin terminal. See the
[debugger guide](debug-terminal-configuration.md#selecting-a-launch-and-choosing-program-inputoutput)
for input/output choices and the optional slow-launch symbol settings.

## Review and commit changes

In a Git worktree, `]h` / `[h` move between hunks, `<leader>gp` previews a hunk,
and `<leader>gs` stages one. `<leader>gd` opens the Diffview review;
`<leader>gD` closes it. `<leader>tg` opens lazygit when it is installed on PATH.
Commit/push there or in your normal terminal workflow. Save the edited file
before comparing its on-disk state in external Git tools.

## Keep a useful layout and resume work

Focus a code window first: `<leader>wv` / `<leader>ws` split the current window
vertically/horizontally, including a sidebar if that has focus. Ctrl-h/j/k/l move
between windows, `<leader>wm` toggles zoom, and `<leader>wc` closes a window.
A buffer is the open document; a window is a view of it. `<leader>bd` closes a
buffer while preserving splits and refuses unsaved changes. Closing a terminal
buffer can stop its running job.

To close a chosen set, open `<leader>fb` (this tab) or `<leader>fB` (all tabs),
mark rows with Tab/Shift-Tab, then press Ctrl-d or Alt-d. The action works in
both picker modes, keeps the picker and editor splits open, and skips unsaved
buffers. F1 lists the actual actions; `<leader>bP` closes unpinned buffers and
`<leader>bm` offers **Close others**.

Sessions normally save/restore eligible cwd-based work. `<leader>wS` saves,
`<leader>wf` selects a saved session, and `<leader>wr` restores one. Save files
first: sessions retain names/layout, not unsaved contents or running programs.
Quick single-file launches and suppressed directories have different automatic
save rules; see [session policy](search-session-configuration.md#sessions-and-global-buffers).

## Optional: focus a large codebase with Scoper

Create a named working set, using directories that exist in your project:

```vim
:ScoperNew working
:ScoperAdd src include
:ScoperExclude **/generated/**
:ScoperStatus
:ScoperFind
```

Use `:ScoperUse working` to return to an existing set. Check status and use
`:ScoperToggle` only if scoping is disabled. `:ScoperGrep` searches its text.
To select a build database independently, use
`:ScoperDatabase out/debug/compile_commands.json` with your real path. That
does not generate the database, select the launch executable or build anything.
The shipped clangd mode can filter its database by scope; see the
[Scoper guide](scoper-integration-notes.md) before tuning that policy.

## When something is missing

| Symptom | First check |
| --- | --- |
| A shortcut seems to type text | Esc, then retry in Normal mode; press Space and wait for which-key. |
| No completion, definition or rename | `:checkhealth vim.lsp`; check the attached server and, for C/C++, the compilation database. |
| No formatter or tool | `:checkhealth config`, `:Mason`, `:ConformInfo`; selected tools still need supported prerequisites. |
| A debugger cannot start | Check adapter installation, `program`/`cwd`, and build symbols; `<leader>dL` checks JSON, not executable readiness. |
| A file is absent from search | Check cwd, ignore/visibility policy and whether this is an ordinary or Scoper picker. |

For a limited machine, read [optional-tool behavior](limited-environments.md).
Put persistent preferences in the ignored root `local.lua`, using
[customization](customization.md); avoid editing tracked plugin specs for normal
machine-specific settings. For crashes/recovery, use the
[swap guide](workflows/swap-files.md); a session file cannot replace recovery data.
