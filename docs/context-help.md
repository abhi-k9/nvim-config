# Find help inside a workflow

Start with **F1**. Pickers and supported panels open their native key reference.
In other Normal-mode buffers, F1 or `<leader>?` shows local mappings through
which-key. Empty contexts or missing which-key fall back to Neovim help.
Press Space and wait to discover leader groups; `<leader>fk` searches mappings,
`<leader>fc` searches commands and `<leader>fh` searches help topics.

References describe the active context: a Diffview merge layout has different
actions from its file-history panel. Help stays with the plugin rather than a
second hand-maintained list in the configuration.

## Read a guide or inspect the workspace

`<leader>h` / `:ConfigHelp [topic]` reads the existing Markdown guides in a
read-only floating window. With no topic, choose from a menu; Tab completion
also supports direct commands. Topics are `quickstart`, `navigation`, `buffers`,
`workspace`, `debugging`, `help`, `tools`, `install`, `migration` and `customization`.
`/` searches the document, `b` returns to topics, and `q` / Esc closes the reader.
The source document stays untouched. References skip FileType provisioning, so
reading a guide does not install parsers or start a language server for it.

`<leader>wi` / `:WorkspaceInfo` compares cwd scopes, visible Neo-tree roots,
Scoper's scope/build state, attached language-server roots and debugger context.
Its footer offers `r` to refresh the original source window and `h` for the
directory guide. `q` / Esc closes only that report. Plugins are queried only
when loaded; missing/unsupported APIs and resolver failures are reported.
The report does not change roots, start a debug session or load optional plugins.

These commands work in a minimal editor. A failed optional selector falls back
to the quick-start reader; `:ConfigHelp debugging` bypasses selection entirely.
If the docs folder is absent, restore it or use `:help`. Debug launch selection
has a separate guard: a failed selector never chooses a launch automatically and suggests
`:DapLaunchInfo`, which needs no picker.

## Pickers, panels and reports

| Feature / entry point | Help / hints | Return to work |
| --- | --- | --- |
| Files, buffers, grep, symbols, diagnostics and sessions (Telescope) | F1 in either picker mode; `g?` / `?` in Normal mode; Ctrl-/ or Ctrl-_ while typing. Buffer pickers advertise mark/close keys. | F1 again or another action dismisses the overlay. Esc closes the picker. Query/selection stay intact. |
| fzf-lua pickers, including Scoper searches | Native F1 help; previews retain their own function keys. | F1 toggles help; Esc closes the picker. |
| Neo-tree files, buffers and Git-status views | F1, `g?` or `?`; native help reflects the source. `<leader>be` switches buffers/files. | Esc cancels help. Pressing an action key in help runs that tree action. `<leader>e` toggles the tree. |
| Trouble diagnostics, TODO and quickfix lists | F1, `g?` or `?`. | Native help shows close keys; `q` in the main list closes that list. |
| Diffview diffs, merge layouts, file/history panels, history options and worktree overview | F1 or `g?` opens native help for that context. Existing help hints remain enabled. | `q` / Esc closes help; `<leader>gD` closes Diffview. |
| Atone undo tree and diff pane (`<leader>u`) | F1, `g?` or `?` opens the native action reference. | `q` / Esc / Ctrl-c closes help only. In the tree, `q` / Ctrl-c closes Atone panes; Esc retains its native action. Enter **reverts file contents** to the selected undo node. |
| Buffer action menu (`<leader>bm`) | Each action has a name; the footer advertises close keys. | `q` / Esc closes the menu; Enter or a numbered action performs the selected operation. |
| Debug launch details (`<leader>dI`) | Read program/cwd, adapter command status and provider; `/` searches. | `q` / Esc closes the report; no session starts. |
| Debug value preview (`<leader>dw`) | Its footer advertises close keys. | `q` / Esc closes only that native value float, preserving code windows. |
| Mason (`<leader>cm`) | `g?` opens full native help; Normal-mode F1 lists local mappings. | Use the native help/close keys shown there. |
| Lazy (`:Lazy`) | `?` opens native help; Normal-mode F1 lists local mappings. | Native `?` toggles help; `q` closes Lazy. |
| grug-far replacement (`<leader>sr`) | Normal-mode `g?` opens native help; F1 lists local mappings. | `q` / Esc closes help. Fields remain editable; replacement is a separate action. |
| Scoper status (`:ScoperShow`) | Footer advertises `q` / Esc. Named close mappings appear in the config's F1 / `<leader>?` reference. | `q` / Esc closes the read-only report. The footer works in standalone Scoper without which-key. |
| Scoper remove/delete selectors | Telescope: F1 / Normal-mode `g?`, Tab/Enter hints and named actions. fzf: native F1, named confirmation and Ctrl-a toggle-all. | Tab marks; Enter confirms. The plain fallback uses its `(done)` row rather than a picker help overlay. |
| Code actions, session selection and other `vim.ui.select` dialogs | The selected Telescope/fzf UI inherits native help. | Follow that selector's accept/cancel controls. Native selectors have no added F1 popup. |

Telescope's native help is a compact, current-mode overlay. Long lists can be
clipped on small terminals; use mapping/help search for a larger reference.
An extension with its own title/layout can override the default F1 border hint.
Help still applies unless that picker supplies its own mapping.

## Editing, debugging and external programs

These workflows already have useful discovery paths. They do not need a new
input-mode F1 handler or custom help window.

| Workflow | Discovery path | Useful distinction |
| --- | --- | --- |
| Attached LSP actions and Git hunks | Normal-mode F1 / `<leader>?` lists attached mappings; Space-l / Space-g opens leader hints. `:checkhealth vim.lsp` and `:Gitsigns` completion inspect availability. | Mappings and server/tool capabilities are separate. |
| Completion and snippets | Ctrl-n/Ctrl-p opens/selects; Ctrl-y accepts; Ctrl-e dismisses. Ctrl-space shows the menu or toggles documentation; Ctrl-b/Ctrl-f scroll visible documentation. See `:help blink-cmp.txt`. | Enter inserts a newline; Tab primarily jumps snippets/falls back to indentation. F1 is not captured globally in Insert mode. |
| Debugger panes | F1 / `<leader>?` in Normal mode lists the focused element's mappings; Space-d shows debugger commands. See the [debugger guide](debug-terminal-configuration.md). | DAP UI has no native help-page action. Expand/open/edit/remove actions differ by element. |
| Debug REPL | Type `.help` at its prompt for native commands; `:help dap.repl.open()` describes the API. | REPL command help is separate from debugger-pane keymaps. |
| Terminal | Esc-Esc enters terminal Normal mode, then F1 / `<leader>?` lists local mappings. See `:help terminal-input`. | Running programs receive their own input. Their `--help`, `help`, `man` or `?` commands depend on the program. |
| Lazygit (`<leader>gg`) | Use lazygit's own `?` keybinding menu. | External program configuration/version controls that help; Neovim does not intercept its key. |
| Alignment (`ga` / `gA`) | Use `gA` for preview and wait for mini.align's helper status; `:help MiniAlign-modifiers-builtin` lists modifiers. | This character-input workflow gets no injected global help chord. |
| Jump labels / structural jumps | Flash's labels guide selection; Esc cancels. See `:help flash.nvim.txt` and global mapping search. | F1 is not an extra character-input handler inside Flash. |
| Fold preview | `K` peeks a closed fold; otherwise it requests hover or native keyword help. See `:help ufo.txt`. | A fold preview and LSP hover are different contexts. |
| Quickfix/location lists | `:help quickfix`, or F1 / `<leader>?` for existing local mappings. Trouble provides the richer mapped list UI. | The ordinary list gets no new custom help page. |
| Formatters and optional tools | `:ConformInfo`, `:checkhealth config` and command completion show configured/available integrations. | Inspection does not imply every optional tool is installed. |

## Portability and customization

F1 may require Fn+F1 on macOS, and terminal/system shortcuts can intercept it.
Use the native alternatives above. Ctrl-Shift-? is not required: legacy terminals
can encode it as Backspace/Delete. Literal `?` and `g?` remain normal text in
search prompts; new generic discovery mappings apply only in Normal mode.

Buffer-local plugin bindings take precedence over generic F1. Local Lazy `opts`
overrides remain authoritative. Diffview's F1 actions reuse the locked plugin's
native help callbacks, retaining each layout's target; Atone uses its documented
help-key lists. Scoper's native picker references work without this host config.
There is no global plugin dispatcher or per-keystroke help rendering.
