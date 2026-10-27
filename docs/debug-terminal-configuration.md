# Debugger and terminal customization

Put machine preferences in the optional, untracked `local.lua` at the config
root. It returns a table. Normal Lazy plugin overrides remain available for
layouts, key mappings and plugin options; these policies cover behavior that
needs coordination before an adapter or terminal starts.

```lua
return {
  debug = {
    root = "project",
    launch_file = ".vscode/launch.json",
    pause_pick_thread = true,
    auto_open_ui = false,
    codelldb_terminal = "integrated",
    codelldb_init_commands = {},
    python = function(root)
      return vim.fs.joinpath(root, ".venv", "bin", "python")
    end,
  },
  terminal = {
    lazygit_per_project = true,
  },
}
```

On Windows the example interpreter would normally be
`vim.fs.joinpath(root, ".venv", "Scripts", "python.exe")`. An explicit path is
used as given; this resolver does not install an interpreter or activate a shell.

## Debug defaults and extension points

| Setting | Shipped behavior |
| --- | --- |
| `debug.root` | `"cwd"`: current window/tab/global cwd at invocation. Also accepts `"project"`, `"scope"`, `"file"`, an explicit path or the shared root callback. |
| `debug.launch_file` | `".vscode/launch.json"`, relative to the resolved debug root. Absolute/home-relative paths are accepted; environment variables stay literal. A function receives `(root, bufnr)` and returns a path or `false`; `false` disables launch-file discovery. |
| `debug.pause_pick_thread` | `false`, unless `vim.g.dap_pause_pick_thread` is already set. `:DapTogglePausePicker` still toggles the live preference. |
| `debug.fallbacks` | `true`: add C/C++/Rust, Python and shell examples without replacing existing user configurations. `false` removes only this module's generated examples. |
| `debug.adapters` | Native nvim-dap adapter definitions/functions keyed by type. Existing adapters survive unless explicitly overridden. A `false` entry disables that adapter and omits its generated fallbacks. |
| `debug.configurations` | Exact per-filetype configuration lists, applied after defaults. An empty list or `false` disables that filetype's configurations. |
| `debug.mimode` | `"lldb"` on macOS, `"gdb"` elsewhere, for cppdbg fallback configurations. |
| `debug.codelldb_terminal` | `"console"`, for the codelldb launch fallback. |
| `debug.codelldb_init_commands` | `{ "settings set target.preload-symbols false" }`; replace with an empty list to omit this tuning. |
| `debug.python` | Interpreter path or function `(root) -> path` for the Python fallback's **debuggee**. Otherwise prefer the activated virtualenv/Conda environment, then project `.venv`/`venv`, then PATH. |
| `debug.mason_root` | Use Mason's final configured installation root, falling back to the normal data directory. |
| `debug.configure` | Optional final callback `(dap)` after adapters and configurations have been applied, before a debug command starts. |
| `debug.auto_open_ui` | `true`. Setting it to `false` suppresses automatic opening; manual UI commands still work. |
| `debug.auto_close_ui` | `true`, unless `vim.g.dap_autoclose_ui` was already set. Closing still respects other live debug sessions. |

Pre-set pause/auto-close globals win so existing configuration keeps working.
Set the corresponding settings before DAP loads. Changing the global later also
changes the live toggle. Repeated `require("config.dap").setup()` preserves user
adapters/configurations and avoids stacking pause wrappers or generated fallbacks.
An explicit per-filetype configuration list replaces the entire list, including
generated defaults. Callbacks may run again on repeated setup and should be
idempotent.

To use an adapter outside Mason, supply its native definition. Commands are
executable paths and arguments remain separate list elements:

```lua
return {
  debug = {
    adapters = {
      codelldb = {
        type = "server",
        port = "${port}",
        executable = {
          command = "/opt/debug tools/codelldb",
          args = { "--port", "${port}" },
        },
      },
    },
  },
}
```

Changing `debug.python` changes the program's interpreter, not debugpy's adapter
runtime. Override `debug.adapters.python` to select a different adapter runtime.
The shipped adapter keeps Python socket attach separate from launch, PID attach
and reverse-listen transports. Windows defaults still spawn native adapter images
and argv directly rather than passing Mason's `.cmd` shims to libuv.

The actual nvim-dap launch provider and `:DapLoadLaunchJSON` use the same root
and source. The command validates/previews; it does not append duplicate entries.
Custom roots bind `${workspaceFolder}` and `${workspaceFolderBasename}` to that
root, including configurations with VS Code input prompts. Other variables and
inputs remain nvim-dap's responsibility. The wrapper resolves effective root/source
settings on every invocation, including trusted project overlays registered after
DAP loads. With no override it delegates to the previous provider, preserving
nvim-dap's normal cwd discovery. Leaving a project restores that behavior without
running setup again. If user code replaces the provider after this module installs
it, repeated setup preserves that later provider; its owner then controls launch
discovery.

Persistent breakpoints use their plugin's cwd contract. A debug-root override
does not relocate breakpoint persistence or third-party session files. Launch
files and Lua callbacks are executable/debugging inputs: use trusted project
files and review adapter commands before launching them.

## Fixed window widths during debugging

The locked DAP UI closes its default left sidebar before the bottom console
strip. Neovim can give that sidebar's 40 columns plus its separator to adjacent
Neo-tree, even with `winfixwidth` enabled. Repeated sessions would grow a
32-column tree to 73, 114, 155 and 196 columns.

The config protects independent fixed-width columns around each DAP UI open,
close and toggle call. Protection uses Neovim's `winfixwidth` option and split
layout, with no plugin-name or filetype list. Neo-tree already sets this option;
other sidebar plugins can participate by setting it on their windows. Run
`:setlocal winfixwidth` in a sidebar to opt in, or `:setlocal nowinfixwidth` to
let that window resize freely. A stack of fixed windows in one column is also
protected. A bottom/top panel sharing its width with a flexible editor follows
that editor's width instead of constraining the entire column.
Compound grids made entirely of fixed windows, with further side-by-side splits
inside the column, retain Neovim's native sizing; restoring their individual
widths can impose conflicting constraints on the shared outer column.

The guard captures live widths per operation, including windows in other tabs,
then restores both unwanted growth and shrinkage. A manual resize between calls
is preserved; there is no fixed 32-column reset or stored session target. Neovim
can clamp restoration on narrow screens, and the next operation uses the actual
width available. It cannot guarantee every preferred width when the screen is
too small for all panels.

DAP UI's own windows are excluded by their layout-owned window IDs, including
custom elements with arbitrary filetypes. DAP UI retains control of its panel
sizes and reset behavior. Floating/external windows, closed/replaced windows and
ordinary flexible editing splits are not width targets. The same protection
applies when session saving temporarily closes the debugger panels.

After updating and restarting, undo any width growth already accumulated by
focusing Neo-tree and running `:vertical resize 32` once (or your preferred
width). Subsequent debugger cycles retain that choice when space permits.

## Shell and lazygit policies

`terminal.shell` now inherits `vim.o.shell` by default on every platform. This
is an intentional change on Windows: installed PowerShell no longer silently
takes precedence over configured cmd. To retain the previous preference, set
`terminal.shell = "legacy"`; it chooses `pwsh -NoLogo` on Windows when available,
otherwise the configured shell. A nonempty string or a zero-argument function
returning a string selects a shell explicitly. A resolver returning `nil` inherits
the configured shell. This is Toggleterm's shell interface, so a string with
shell arguments follows that plugin's parsing rules.

Normal terminal mappings launch in the literal active cwd. Existing terminal
jobs retain their original directory when reopened after a project switch.
The default lazygit policy keeps one process for the session. With
`terminal.lazygit_per_project = true`, each resolved project root gets a separate
handle; returning to a project toggles its existing process. Each process starts
in the active cwd at its first invocation. A project switch never terminates
an earlier process, and quitting lazygit drops only that process's handle.

Neogen annotation conventions remain ordinary plugin options. For example,
return a Lazy override under `plugins` for `"danymat/neogen"` with
`opts.languages.python.template.annotation_convention = "google_docstrings"`.
No additional configuration wrapper is needed for that plugin.

## Verification

`tests/debug_policy_spec.lua` covers pre-set choices, repeated setup, adapter
disablement, exact lists, custom launch discovery, workspace substitution,
callable input configurations and provider ownership. `tests/debug_activation_spec.lua`
checks overrides before the real Lazy/DAP activation. Existing Python transport
and Windows adapter tests remain in place. `tests/terminal_policy_spec.lua`
covers inherited/resolved shells and session/project lazygit handles; real-shell
literal-cwd regressions remain in `tests/terminal_literal_cwd_spec.lua`.

References: [nvim-dap configurations and providers](https://github.com/mfussenegger/nvim-dap/blob/master/doc/dap.txt),
[nvim-dap VS Code launch support](https://github.com/mfussenegger/nvim-dap/blob/master/lua/dap/ext/vscode.lua),
and [Toggleterm configuration](https://github.com/akinsho/toggleterm.nvim#setup).
