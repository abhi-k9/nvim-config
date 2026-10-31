# Visual Studio to Neovim: migration and feature reference

This guide maps a Visual Studio desktop workflow to this configuration, with
particular attention to C/C++. Start with the quick start, then look up features
as you need them. It describes shipped defaults; `local.lua` overrides can change
keys and behavior. The [Visual Studio shortcut cheatsheet](cheatsheets/vs-to-nvim.html)
is the compact side-by-side reference, and the [general quick start](quick-start.md)
is a shorter introduction for any language.

Visual Studio shortcut references assume the General keyboard profile; language
profiles, versions and personal bindings can differ. Microsoft's
[shortcut reference](https://github.com/MicrosoftDocs/visualstudio-docs/blob/main/docs/ide/default-keyboard-shortcuts-in-visual-studio.md)
helps identify the original command when your binding is different.

Jump to: [quick start](#quick-start-your-first-working-session),
[project model](#the-project-model-you-are-moving-to),
[editing/refactoring](#editing-completion-and-refactoring),
[C++ setup](#c-project-setup), [build/run/test](#build-run-and-test),
[debugging](#debugging), [Git/sessions](#git-sessions-and-recovery), or
[troubleshooting](#when-a-familiar-feature-does-not-work).

## Quick start: your first working session

1. **Open your normal development shell in the project root.** On Windows, use
   the Developer Command Prompt/PowerShell or company-provided environment you
   normally build from. If setup opens a child shell, launch Neovim *inside that
   configured shell*. Run `nvim` there. Opening a directory in the file tree does
   not by itself establish the editor's project cwd.
2. **Check readiness.** Run `:checkhealth config`; inspect `:Mason` if a selected
   server or adapter is missing. Missing optional tools do not prevent basic
   editing. Installation details are in the [README](../README.md#prerequisites).
3. **Find a source file.** Press `Space`, `f`, `f`, type part of its name, then
   Enter. `Space f g` searches file contents; `Space e` toggles the file tree.
4. **Make and save an edit.** Press `i`, type, then Escape to return to Normal
   mode. Ctrl+S saves a file; when used in Insert mode it also leaves Insert.
   `:w` saves and `:q` closes a window/quits when it is the last one.
5. **Navigate semantically.** With the language server attached, put the cursor
   on a symbol and use `gd` for definition, `gr` for references, `K` for hover
   when not peeking a closed fold, and Ctrl+O to return. For C++, first ensure
   clangd has the correct compilation database; see [C++ setup](#c-project-setup).
6. **Build with your existing command.** `Space t h` opens a horizontal shell.
   Run the same build/test script you use outside the editor. This config does
   not infer a startup project or build a solution when you press F5.
7. **Debug a built executable.** Copy the [launch template](templates/dap/launch.json.example)
   to the project's `.vscode/launch.json`, keep the configuration you need, and
   edit its executable, arguments and cwd. `Space d L` validates/previews it;
   F9 sets a breakpoint and F5 selects a launch. See [debugging](#debugging).
8. **Review and resume.** `Space g d` opens Git diff review. Save important edits,
   then use `:confirm qall` to quit with unsaved-change prompts. Sessions can
   restore layouts later, but they do not replace saving file contents.

You can stop after step 4 and use the editor productively. Navigation, building
and debugging have their own tool prerequisites; they need not all be configured
at once.

## How to read the keys

| Notation | What to press |
| --- | --- |
| `<leader>ff` | Space, then `f`, then `f`, in sequence |
| `<C-s>` | Hold Ctrl and press S |
| `<A-j>` | Hold Alt and press J; terminal forwarding must support it |
| `gd` | `g`, then lowercase `d`, in Normal mode |
| `gD` | `g`, then uppercase `D` |
| `:Command` | Type colon, the command, then Enter |

Normal mode interprets keys as commands. Insert mode types text. Visual mode
selects text (`v` for characters, `V` for lines); Escape returns to Normal mode.
Most mappings in this guide are Normal-mode mappings unless stated otherwise.
`Space` and a short wait opens which-key; `Space f k` searches mappings and
`Space f c` searches commands. `:Tutor` teaches the editing model without requiring
you to learn the entire plugin set first.

Use the portable leader mapping when a function-key chord does not arrive at
Neovim. Modified keys depend on terminal/multiplexer encoding. See the
[terminal notes](../README.md#terminal--multiplexer-notes).

## The project model you are moving to

Visual Studio coordinates solution membership, build configurations, IntelliSense
and the startup project. Here, those decisions belong to separate components:

| Visual Studio concept | Here | What it controls |
| --- | --- | --- |
| Solution/project files | Your existing build system and files on disk | `.sln`/`.vcxproj` are not imported into an IDE project model automatically |
| Working directory | `:pwd`; change global cwd with `:cd` | Default ordinary searches, launch discovery and session identity depend on cwd |
| IntelliSense project | Attached language server and its root/configuration | Semantic navigation, completion, diagnostics and refactoring |
| Active configuration/platform | Your build command and selected compilation database | Compiler defines/includes/flags seen by clangd; choosing a database does not run a build |
| Find in Files scope | Ordinary search root/visibility, or a named Scoper scope | Which paths a search considers |
| Startup project/debug settings | Selected DAP configuration | Executable, arguments, runtime cwd, environment and adapter |
| Document tabs | Buffers shown in bufferline | Loaded file contents; a buffer can appear in several windows |
| Window layout | Splits inside a Neovim tab page | Views of buffers; a tab page is a layout, not a document |

Start with one Neovim process per independent project. Scoper has one active
project per editor, and matching `local.lua` project overlays use global cwd.
`:lcd` and `:tcd` change invocation cwd locally without switching Scoper's project
or activating another overlay. Separate tabs do not create independent Scoper
project instances.

Ordinary `Space f f` / `Space f g` searches do not automatically become Scoper
searches. An LSP root is also not a guarantee that grep, terminals, sessions and
debugging share that root. Configure the supported root policies when needed;
see [customization](customization.md#project-context-and-trust) and
[search/session policy](search-session-configuration.md).

## Files, buffers and windows

| Familiar action | This configuration |
| --- | --- |
| Go to File / Ctrl+T | `<leader>ff`; `<leader>Ff` uses the fzf-lua alternative |
| Recent files | `<leader>fr` |
| Open documents list | `<leader>fb` for the current tab; `<leader>fB` for all buffers |
| Solution Explorer | `<leader>e` toggles Neo-tree; `<leader>E` reveals the current file |
| Next/previous document | `Shift+L` / `Shift+H` in Normal mode |
| Pin a document | `<leader>bp`; pinning can reorder the display |
| Close document, keep layout | `<leader>bd`; unsaved buffers are skipped |
| Save / Save All | `<C-s>` / `<leader>W` |
| Split editor vertically/horizontally | `<leader>wv` / `<leader>ws`; focus a code window first |
| Move between splits | `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` |
| Close the focused split | `<leader>wc` |
| Temporarily maximize a split | `<leader>wm`; press again to restore while the layout is unchanged |

Closing a buffer differs from closing a window. `<leader>bd` redirects windows
showing that buffer before deleting it; a terminal buffer close can stop its job.
`<leader>bD` explicitly force-deletes and can discard edits. Prefer the ordinary
close until you have reviewed unsaved work.

Use `:tabnew` for another layout and `gt` / `gT` to change tab pages. By default,
scope.nvim presents buffers per tab. The same file is still one buffer, so edits
in one view appear in every view. Opening a tab is not an independent copy of a
solution, process environment or debug session.

## Editing, completion and refactoring

### Start with a small editing vocabulary

| Task | Keys |
| --- | --- |
| Insert before cursor / new line below | `i` / `o`, then Escape when finished |
| Change the current word | `ciw`, type replacement, Escape |
| Change text inside parentheses/quotes | `ci)` / `ci"` |
| Delete/copy/paste a line | `dd` / `yy` / `p` |
| Undo/redo | `u` / `<C-r>` |
| Repeat the last change | `.` |
| Comment the current line | `gcc` |
| Comment selected lines | `V`, select lines, then `gc` |
| Move line/selected lines | `<A-j>` / `<A-k>` in Normal/Visual mode |
| Surround a word with parentheses | `gzaiw)` |
| Remove surrounding quotes | `gzd"` |
| Generate a function's documentation comment | `<leader>cd` where Neogen supports the filetype/parser |
| Browse retained undo branches | `<leader>u` opens Atone |

Deletion and copying use Vim registers. This config leaves the unnamed register
separate from the system clipboard. To copy outside the editor, select text and
use `"+y`; use `"+p` in Normal mode to paste from the system clipboard. In Insert
mode, `<C-r>+` inserts that register. These need a working clipboard provider;
check `:checkhealth vim.provider`. Insert-mode Ctrl+C leaves Insert and Ctrl+V
quotes the next key; they are not Visual Studio's copy/paste commands here.

### IntelliSense-style completion

Blink combines language-server, snippet, path and buffer-word suggestions. In
Insert mode, `<C-n>` / `<C-p>` opens or moves through completion; `<C-y>` accepts
and `<C-e>` dismisses. Enter normally inserts a newline; Tab is for snippet
movement, not a universal completion-accept key. LuaSnip handles supported snippet
placeholders with Tab/Shift+Tab; language-server signatures appear while typing
arguments, and `<leader>lk` requests signature help in Normal mode.

Buffer-word completion can work while a language server is absent. Semantic
completion requires a running server and correct project settings. Installing a
language-server binary alone does not prove it attached to this buffer.

### Semantic navigation and changes

| Visual Studio feature | Here | Boundary |
| --- | --- | --- |
| Go to Definition (F12) | `gd` | LSP/server knowledge of the symbol |
| Go to Declaration (Ctrl+F12 in General profile) | `gD` | Distinct results depend on the language server |
| Go to Implementation | `gI` | Uppercase I; `gi` keeps Vim's resume-Insert behavior |
| Go to Type Definition | `gy` | Server capability |
| Find All References | `gr` | Trouble reference list; press again to close |
| File/workspace symbol navigation | `<leader>fs` / `<leader>fS` | Server-provided symbols, not a filename search |
| Quick Info | `K` | Peeks a closed fold first, then hover; it is not Peek Definition |
| Rename symbol | `<leader>lr` | Workspace edits produced by the server |
| Quick Actions/refactoring | `<leader>la` in Normal/Visual mode | Only actions offered by this server/context |
| Format Document | `<leader>cf` or `<leader>lf` | Conform versus LSP; see below |

For a rename, place the cursor on the symbol, invoke `<leader>lr`, enter the new
name, then review the modified buffers and Git diff before saving. A semantic
rename is different from replacing matching text. Visual Studio refactorings
such as particular extract/move/generate operations are not guaranteed by the
presence of a Code Action menu.

### Formatting and folds

`<leader>cf` runs Conform's configured external formatter, with LSP fallback;
Visual mode requests a range where supported. `<leader>lf` formats the buffer
through LSP. A project's `.clang-format` or formatter-specific configuration
controls style; mismatched formatter versions can produce different output.
Format-on-save is off. The [opt-in recipe](tooling-configuration.md#opt-into-format-on-save)
adds it and honors `:FormatToggle` / `:FormatToggle!`. Core trailing-whitespace
cleanup is a separate save policy and can also be affected by EditorConfig.

Use `za` to toggle the fold under the cursor, `zM` to close all folds and `zR`
to open all. Fold ranges use available providers, while open/closed state is
persisted separately per file. After edits or a slow provider, restoration need
not reproduce every earlier fold; see [fold persistence](editing-ui-configuration.md#fold-persistence-and-split-sizing).

## Search, replacement and large projects

`/pattern` searches the current buffer; `n` / `N` moves through matches. Use
`<leader>fg` for live project text search, `<leader>fw` for the current word and
`<leader>f/` for a fuzzy search in the current buffer. These are different match
engines; do not assume a fuzzy-finder operator is a regex or a literal path.

For text replacement, open `<leader>sr`, fill Search/Replace and any path/glob
constraints, review matches, then use the grug-far buffer's local action
`\r` to replace (default localleader is backslash). `g?` shows its local help.
`<leader>sf` starts with the current saved file, and `<leader>sw` prefills the word
under the cursor. Replacement can affect many files; save/review the relevant
buffers and inspect the resulting diff. Backend path-expansion checks can refuse
some filenames or a different requested root rather than target another path.

For a large tree, use Scoper's explicit commands:

```vim
:ScoperNew subsystem
:ScoperAdd src/ include/
:ScoperExclude **/generated/**
:ScoperShow
:ScoperFind
:ScoperGrep
```

Replace those example paths with your own. `:ScoperNew` creates and selects a
named scope. Includes can be directories, files or globs; `:ScoperFind` and
`:ScoperGrep` use the captured membership. Disabled scoping or **an empty include
list is unrestricted**, so excluding paths alone is insufficient: include `.`
when you mean the project minus exclusions. Restricted Scoper replacement is
refused by the current backend contract.

Scoper's default clangd integration can also filter a selected compilation
database, but that is separate from ordinary file/grep search. Scope membership
does not prevent you opening a file, and is not a security boundary. See
[scope/state contracts](scoper-core-notes.md) and
[compilation-database modes](scoper-integration-notes.md).

## C++ project setup

### Give clangd the build's real commands

Accurate defines, include directories, language modes and target flags come from
`compile_commands.json`. Opening a `.sln` or `.vcxproj` does not automatically
provide that information to clangd. A compilation database usually lists source
translation units; clangd can infer a header's command from a source file. A
header-only scope can therefore contain no compilation entries.

For a project already using CMake, reuse its documented presets/generator. If it
supports Ninja, this is one possible Debug setup (Ninja and a compiler must be
available; run it in an initialized developer environment on Windows):

```sh
cmake -S . -B out/debug -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build out/debug
```

The export option is supported by CMake's Ninja/Makefile generators, not its
Visual Studio generator. For a genuinely MSBuild-only project, use a maintained
project-approved compilation-database exporter or a database supplied by the
build team. Do not assume changing a generator or copying a few include paths
reproduces the original project semantics.

Select the result explicitly when needed:

```vim
:ScoperDatabase out/debug/compile_commands.json
:ScoperLspReload
```

`:ScoperDatabase` without a path reports status; `:ScoperDatabase!` clears the
saved selection. Debug/Release and platform databases are separate build choices.
Selecting one does not rebuild code, change search includes or choose the
debugger's executable. Use Scoper mode `selected` to keep the complete selected
database independent of search scope, or `filtered` when scope filtering is
intended; configuration examples are in the [integration guide](scoper-integration-notes.md).

When clangd reports missing headers or wrong types, check its actual compilation
command and selected database before adding global flags. Keep compiler/SDK
versions and generated headers consistent with your build. `query_drivers` is an
explicit permission for clangd to execute matching compilers, not a generic way
to fix every SDK issue; allow only trusted paths needed by your toolchain.

### Error List and code analysis

| Task | Keys/command |
| --- | --- |
| Next/previous diagnostic | `]d` / `[d` |
| Workspace diagnostic list | `<leader>xx` |
| Current-buffer diagnostic list | `<leader>xX` |
| Diagnostic picker | `<leader>fd` |
| Quickfix/build-output list | `<leader>xq`; `]q` / `[q` moves Trouble/quickfix entries |
| Check attached LSP clients | `:checkhealth vim.lsp` |
| Check external formatter choice | `:ConformInfo` |

Clangd diagnostics are not the authoritative build result. Clangd uses a Clang
frontend even when the project's compiler is MSVC or GCC; supported diagnostics,
extensions and refactorings can differ. Its integrated clang-tidy checks and the
standalone `clang-tidy` command also have different configuration boundaries.
Use the [C++ template guide](templates/cpp/README.md) and
[diagnostic reference](cheatsheets/cpp-diagnostics.html) for placement, suppression
and version-specific settings.

## Build, run and test

Use your repository's commands, including its environment setup, selected target,
configuration and test filters. For example, if these names exist in your project:

| Project type | Example command, run in a suitable shell |
| --- | --- |
| Existing Visual Studio solution | `msbuild MySolution.sln /m /p:Configuration=Debug /p:Platform=x64` |
| Configured CMake build | `cmake --build out/debug --config Debug` |
| CTest project | `ctest --test-dir out/debug -C Debug --output-on-failure` |
| Python tests | `python -m pytest` using the project's environment |
| Rust project | `cargo test` |

There is no configured Build Solution shortcut, automatic `.sln` target selector
or Test Explorer. F5 starts/continues a debugger; it does not run those build
commands or a VS Code `preLaunchTask`. Run tests in the terminal, apply their
documented filters, and use the output/exit status as usual.

`<leader>th` opens a horizontal terminal; `<leader>tt` opens a float. From terminal
input mode, press Escape twice (or `<C-\><C-n>`) to return to Normal mode, then
use normal window navigation or a terminal toggle. `exit` ends the shell; hiding
the window can leave its process running. New terminal jobs start at invocation
cwd; reopening one retains that job's old cwd.

If you want navigable build errors, configure Neovim's `makeprg` and `errorformat`
for the real command/output, then use `:make` and the quickfix list. The stock
`:make` path is synchronous; test the parser rather than assuming arbitrary
MSBuild/compiler output will populate useful entries automatically.

Environment setup in a child shell cannot modify the already running parent
Neovim, language servers or debugger adapters. For a company setup script that
opens a new configured shell, start Neovim there. Restart existing tools after
changing their environment; opening another terminal panel alone does not update
the editor process's environment.

## Debugging

### Map the startup project to a launch configuration

The adapters supplied by this config include CodeLLDB and cppdbg for native code,
debugpy for Python, and a Bash adapter. CodeLLDB bundles LLDB; cppdbg needs its
appropriate external debugger. A binary with usable debug information and the
adapter's platform support are still required.

Create `.vscode/launch.json` under the resolved debug root. This is nvim-dap's
VS Code-style configuration input; Visual Studio project debugging properties
are not imported automatically. Here is a native example; `out/debug/app` is an
example output path, not a path the config creates:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Native Debug",
      "type": "codelldb",
      "request": "launch",
      "program": "${workspaceFolder}/out/debug/app",
      "cwd": "${workspaceFolder}",
      "args": [],
      "stopOnEntry": false,
      "terminal": "console",
      "windows": {
        "program": "${workspaceFolder}/out/debug/app.exe"
      }
    }
  ]
}
```

Replace the program path and choose the runtime cwd your application needs for
assets/configuration. CodeLLDB's `env` is an object; cppdbg uses different fields.
The [annotated launch template](templates/dap/launch.json.example) covers those
differences, OS overrides, PID attach, Python and core dumps. For repeated slow
native launches, its optional [symbol-loading settings](debug-terminal-configuration.md#codelldb-symbol-loading-for-slow-launches)
can help, with documented breakpoint/type-lookup tradeoffs.

`terminal: "console"` puts output in the debugger console, but that REPL accepts
debugger commands/expressions, not interactive program stdin. Choose `integrated`
when a terminal is needed and verify the behavior on your platform. External
terminal launching needs client configuration; see the
[input/output guide](debug-terminal-configuration.md#selecting-a-launch-and-choosing-program-inputoutput).

### Day-to-day debugger controls

| Action | Keys |
| --- | --- |
| Start/select configuration or Continue | F5 / `<leader>dc` |
| Pause | F6 / `<leader>dp` |
| Toggle persistent breakpoint | F9 / `<leader>db` |
| Conditional/hit-count breakpoint | `<leader>dB` |
| Log point | `<leader>dP` |
| Step over / into / out | F10 / F11 / `<leader>dO` |
| Run to cursor | `<leader>dC` |
| Terminate / Restart | `<leader>dt` / `<leader>dR` |
| Toggle debug panels / REPL | `<leader>du` / `<leader>dr` |
| Inspect expression / hover value | `<leader>de` / `<leader>dw` in Normal/Visual mode |
| Up/down stack frames | `<leader>dk` / `<leader>dj` |
| List / clear persisted breakpoints | `<leader>dx` / `<leader>dX` |
| Exception breakpoint filters | `<leader>dE`, when supported by the adapter |

The UI supplies scopes, stack, breakpoints, watches and console views. Use their
local help/menus when entering expressions. CodeLLDB's default simple evaluator
does not treat every expression as native C++: native function calls need its
`/nat` evaluator where supported. Function evaluation can execute code and alter
the debuggee; start with ordinary variable inspection. The
[debugging cheatsheet](cheatsheets/debugging.html) covers evaluators, watches,
LLDB commands and watchpoints in detail.

Finish an active session and select a new configuration after editing
`launch.json`. Continue resumes the active session; Run Last (`<leader>dl`) and
Restart reuse its existing configuration. `<leader>dL` validates/previews without
launching. For PID attach, use the template or select the generated CodeLLDB
attach fallback; access rights and OS attach policy still apply.

Breakpoints can persist across editor starts, but a session file cannot restore
a running debuggee. Keeping panels visible after exit also does not preserve a
live target for new evaluations. MSVC-specific Edit and Continue, debugger visualizers,
diagnostic tools and every PDB scenario are not promised by choosing a DAP adapter.
Test the real compiler/runtime/adapter combination before relying on parity with
Visual Studio.

## Git, sessions and recovery

For a small change, use `]h` / `[h` to visit hunks, `<leader>gp` to preview and
`<leader>gs` to stage/toggle a hunk. `<leader>gd` opens Diffview; `<leader>gD`
closes it. `<leader>gh` shows current-file history, `<leader>gH` repository history,
and `<leader>tg` opens lazygit when that executable is installed. Gitsigns reset
actions discard working-tree changes; review before using `<leader>gr` or
`<leader>gR`. Committing and pushing remain explicit Git/lazygit actions.

Default sessions use directory identity. `<leader>wS` saves, `<leader>wr` restores,
and `<leader>wf` searches saved sessions. Automatic saving/restoring has guards
for suppressed directories and short file-argument edits; see
[session policy](search-session-configuration.md). Sessions are executable Vim
scripts describing files/layouts, not backups of every buffer's contents.

Use `u` / `<C-r>` or `<leader>u` for retained undo history. For a crash, read
[swap recovery](workflows/swap-files.md) before deleting swap files; cleanup,
undo history, session deletion and Git reset lose different kinds of data.
[State-file guidance](workflows/state-files.md) explains paths and retention.

## Customize gradually and recognize the boundaries

Put local preferences in the ignored `local.lua` beside `init.lua`; use normal
Lazy overrides under `plugins` for plugin-specific changes. For example:

```lua
return {
  ui = { reduced_motion = true },
  terminal = { lazygit_per_project = true },
  sessions = { auto_restore = false },
}
```

Restart after changing startup policy. Tool lists replace defaults rather than
append. The [customization guide](customization.md) explains extension, trusted
project overlays and root intents. Project-local Lua discovery (`exrc`) is off
by default; opt in deliberately and review code before trusting it.

| Visual Studio capability | What to expect here |
| --- | --- |
| C#/VB IntelliSense and managed debugging | Not supplied by the shipped native/Python/Bash setup; requires separate LSP/adapter configuration |
| Designers, XAML/WinForms visual editing, profilers and enterprise test tooling | No built-in replacement in this config; keep suitable external tools available |
| Solution/project property pages | Edit the actual build system and select matching analysis/debug inputs |
| Shared environment and target selection across every subsystem | Explicit root/build/launch policies; a scope or tab does not synchronize them all |
| VS extensions such as ReSharper or Visual Assist | Some actions overlap LSP/plugins; their complete feature sets and semantics are not implied |

## When a familiar feature does not work

| Symptom | First checks |
| --- | --- |
| Keys type letters instead of acting | Escape to Normal mode; confirm the actual mapping with `<leader>fk` |
| Ctrl/function-key chord behaves differently | Try the leader equivalent; check terminal/multiplexer encoding |
| Semantic navigation/completion is absent | `:checkhealth vim.lsp`, `:Mason`, filetype and project root; other languages can work independently |
| C++ diagnostics disagree with the build | Actual clangd command, selected compilation database, SDK/toolset and generated files |
| Search misses files | Cwd/root policy, gitignore/hidden settings and whether ordinary or Scoper search was invoked |
| F5 launches the wrong binary or uses old settings | Build first; verify program/cwd and finish/reselect after launch-file edits |
| Debuggee waits for input | Console output is not an interactive stdin terminal; review terminal selection |
| A tool cannot find company setup variables | Start Neovim from the initialized parent shell; restart tools after environment changes |

Use `:messages`, the relevant health report, and `:ConformInfo` / `:MasonLog` for
the failing layer. `:DiagnosticDump` can collect broader state, but inspect its
paths, messages and log tails before sharing it. The [general quick start](quick-start.md)
and [feature-guide index](customization.md#feature-guides-and-inspection) provide
the next steps without changing the entire configuration at once.
