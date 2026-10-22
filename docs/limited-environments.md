# Using the config without a full development environment

Neovim 0.12+ and Git are enough to obtain and run the plugin configuration.
No separate Lua, LuaRocks, or Rust installation is required. Plugin cloning still
needs network access, or a prepared offline seed. A Nerd Font affects glyphs,
not whether the editor works.

Automatic tool installation remains enabled when prerequisites are available.
The config checks the prerequisites for its configured packages before queuing
installs or native builds. It records unsupported work for `:checkhealth config`
instead of generating a popup for every failed attempt.

| Missing prerequisite | Behavior |
| --- | --- |
| Node | Skip npm-based servers/formatters and the Bash debug adapter. Installed Node-based language servers are also excluded from automatic activation. |
| npm | Skip npm-based installation; an already-installed server can still run with Node. |
| Cargo or rustc | Skip rust-analyzer installation and automatic activation. Lua completion does not require Rust. |
| Python 3 with `venv` and `ensurepip` | Skip automatic installation of clang-format and debugpy. Windows Store aliases and partial Python installs are rejected. Debian/Ubuntu may need `python3-venv`. |
| curl/wget, or Windows PowerShell | Skip Mason installs that cannot download packages. |
| unzip, tar, or gzip | Skip the configured Mason packages that need that archive format. Windows ZIP extraction uses PowerShell. |
| Treesitter CLI, C compiler, curl, or tar | Skip automatic parser installation/update. Existing parsers still work; other filetypes retain Vim's basic syntax highlighting. |
| Native Telescope build chain | Skip the native sorter build. Telescope's Lua sorter remains available; an existing native artifact can still load. |
| Blink download/checksum utility | Use the Lua fuzzy matcher quietly. With those utilities available, keep the normal prebuilt Rust matcher and its failure reporting. |

On Windows, parser compilation recognizes MSVC Build Tools through `vswhere`,
even when `cl.exe` is absent from PATH. Telescope's Windows Makefile specifically
needs GCC; CMake can use MSVC. The MSVC and Python probes have 1.5-second bounds
and cache their results within the editor process.

## Reporting and recovery

Run `:checkhealth config` to see the **Optional tooling skipped on this machine**
section alongside the existing system-tool checks. Health checks still flag
missing prerequisites and invalid versions. These reports describe available
integrations; missing optional components do not mean basic editing is broken.

Install the relevant prerequisites, then restart Neovim to restore automatic
installation/activation. `:Mason` and `:MasonInstall <package>` remain available
for explicit installation; `:TSInstall <language>` can be used directly too.
The explicit commands retain their normal errors when prerequisites are absent.
For a previously skipped Telescope native sorter, run
`:Lazy build telescope-fzf-native.nvim` after adding its build tools.

No global notification or diagnostic filter was added. Compiler failures,
network failures with download tools present, broken servers, formatter failures,
and errors from an explicitly requested feature remain visible. Missing ripgrep,
fzf, a debugger, or lazygit can still prevent the corresponding command from
working; the health report identifies those tools. This policy avoids predictable
automatic failures rather than promising that every external feature works
without its dependencies.

## Verification

A disposable Linux environment used Neovim 0.12.6 with only `git` and `sh` on
PATH, installed plugin sources, and isolated config/data/cache/state directories.
There was no Rust, Lua executable, LuaRocks, Node/npm, Python, C compiler,
Treesitter CLI, make, ripgrep, or fzf. Opening Lua, Rust, Python, Markdown, C++,
and JavaScript buffers before the change produced nine Mason installation
errors and Blink binary download/checksum warnings.

The same startup after the change produced **zero notifications and zero
messages**. A second environment with no cached Mason registry also started
quietly. Explicit health checks retained the skipped-install, runtime, parser,
sorter, and completion-fallback reasons.

Regression specs cover missing and complete toolsets, already-installed Node
servers without npm, Windows Store Python aliases, incomplete Python installs,
per-package installer conditions, native sorter fallback, compiler-free parser
startup/first use, MSVC discovery, and automatic-enable exclusions/allowlists.
Windows prerequisite behavior is tested at the executable/process API boundary;
the reduced-PATH integration runs were on Linux.

`make ci` passed **521 tests** locally: 216 configuration, 261 portable Scoper,
and 44 Python tests. One additional Windows API test is skipped on Linux.
Lint, formatting, and documentation checks passed as well.

## Upstream implementation references

- [Mason package metadata and installer prerequisites](https://github.com/mason-org/mason-registry/tree/main/packages).
- [Mason Python virtual-environment creation](https://github.com/mason-org/mason.nvim/blob/2a6940af80375532e5e9e7c1f2fc6319a1b7a69d/lua/mason-core/installer/managers/pypi.lua).
- [Mason tool installer per-package conditions](https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim/blob/443f1ef8b5e6bf47045cb2217b6f748a223cf7dc/lua/mason-tool-installer/init.lua).
- [Treesitter source download and compilation](https://github.com/nvim-treesitter/nvim-treesitter/blob/1a4f47b03dfe92d28de7d5654c67327ef008c9e6/lua/nvim-treesitter/install.lua).
- [Blink native/Lua matcher choices](https://github.com/Saghen/blink.cmp/blob/78336bc89ee5365633bcf754d93df01678b5c08f/lua/blink/cmp/config/fuzzy.lua).
- [Telescope native sorter Makefile](https://github.com/nvim-telescope/telescope-fzf-native.nvim/blob/b25b749b9db64d375d782094e2b9dce53ad53a40/Makefile).
