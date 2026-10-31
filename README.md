# Neovim Configuration

A well-commented Neovim configuration for **Neovim ≥ 0.12.0** — the floor
that nvim-treesitter's `main` branch needs. A guard at the top of `init.lua`
(`MIN_NVIM`) checks it at startup, and `make check-docs` fails if this
README, the health check or CI name a different floor. Use these default config
folders when no `XDG_CONFIG_HOME` or `NVIM_APPNAME` override is set:

| OS              | Config parent         | Config folder              |
|-----------------|-----------------------|----------------------------|
| Linux / macOS   | `~/.config/`          | `~/.config/nvim/`          |
| Windows (PS)    | `$env:LOCALAPPDATA\`  | `$env:LOCALAPPDATA\nvim\`  |

You can also clone the repository directly into the **Config folder** above.
Pass that destination explicitly to `git clone` to avoid a nested `nvim-config/`.
Git accepts an existing destination only when it is empty, including hidden files.
The original audited zip contains a top-level `nvim/` folder and can be extracted
into the parent above. GitHub source archives usually contain `nvim-config-main/`
instead: move/rename that directory so `init.lua` is directly inside the config
folder. Inspect an archive's layout before extracting it over an existing config.
Commands for cloning, backing up an existing config, extracting, updating to a
new zip, trying it next to another config, and uninstalling, per OS:
[docs/workflows/install-update-uninstall.md](docs/workflows/install-update-uninstall.md).

The first `nvim` launch will bootstrap [lazy.nvim](https://github.com/folke/lazy.nvim)
and install the enabled plugin set. Wait for installation to finish before
relaunching; downloads and supported native builds can take several minutes.

For daily use, start with the [workflow quick start](docs/quick-start.md).
Coming from Visual Studio? The [migration and feature guide](docs/visual-studio-migration.md)
has its own quick start, IDE-to-Neovim feature mappings, build/debug recipes and
the boundaries to know before replacing an established workflow.

## Prerequisites

The editor works with a partial development environment. Optional installs and
native builds are skipped when their prerequisites are missing; details stay in
`:checkhealth config`. Existing parsers, editing, snippets, and Lua completion
remain usable. Install missing prerequisites and restart to enable automatic
installation again. You do **not** need a separate Lua, LuaRocks, or Rust
installation to run the config or edit Lua.

### Required

| Tool                  | Why                                                                  |
|-----------------------|----------------------------------------------------------------------|
| **Neovim ≥ 0.12.0**   | nvim-treesitter's `main` branch requires it. Checked at startup by the guard in `init.lua`; Neovim 0.12.6 is used for local verification. |
| **git**               | Online plugin bootstrap and explicit updates. Lazy checks for updates periodically; it does not automatically apply them. A prepared offline seed supports offline startup. |

### For automatic parser builds

Existing and Neovim-bundled parsers work without these. Missing parsers use Vim's
basic syntax highlighting until their build prerequisites are installed.

| Tool | Why |
| --- | --- |
| **tree-sitter CLI ≥ 0.26.1** | nvim-treesitter (`main`) builds parsers with it. See [Installing the tree-sitter CLI](#installing-the-tree-sitter-cli) below. Existing compatible and Neovim-bundled parsers remain usable without it. |
| **`tar` and `curl`**  | Parser source download/extraction. Recent Windows versions provide them; minimal Linux/macOS installations may need packages. Check availability instead of assuming it. |
| **A C compiler**      | Each parser is compiled to a `.so`/`.dll`. On Windows the CLI can discover installed MSVC C++ Build Tools; to select LLVM, install it and set `CC=clang`. Build failures can also involve SDKs, downloads or incompatible grammar/tool versions; inspect the actual error. |

### Installing the tree-sitter CLI

[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter#requirements) compiles every grammar with the `tree-sitter` executable. You need **0.26.1 or newer** on your `PATH`. Its README asks for a package-manager install, `cargo`, or a [release binary](https://github.com/tree-sitter/tree-sitter/releases) — **not npm**.

Use the first option that works on your machine:

1. **Package manager** (simplest when the version is new enough — check with `tree-sitter --version`):

   | OS | Install |
   |----|---------|
   | Windows ([scoop](https://scoop.sh)) | `scoop install tree-sitter` |
   | macOS / Linux ([Homebrew](https://brew.sh)) | `brew install tree-sitter` |
   | Arch Linux | `sudo pacman -S tree-sitter` |

   Many Debian/Ubuntu repos still ship an older CLI; use cargo or a release binary instead.

2. **Rust / cargo** (cross-platform; install [rustup](https://rustup.rs) first — distro `cargo` packages are often too old to build the CLI):

   ```sh
   cargo install --locked tree-sitter-cli
   ```

   The binary is named `tree-sitter`. Cargo puts it in `~/.cargo/bin` (Windows: `%USERPROFILE%\.cargo\bin`); add that directory to `PATH` if `tree-sitter` isn't found yet.

3. **Prebuilt binary** from <https://github.com/tree-sitter/tree-sitter/releases> (no Rust toolchain needed for the CLI itself):

   - Pick the asset for your OS/CPU (`tree-sitter-windows-x64.zip`, `tree-sitter-macos-arm64.gz`, `tree-sitter-linux-x64.gz`, …).
   - Unzip or gunzip it and place `tree-sitter` (or `tree-sitter.exe` on Windows) in a folder that's on your `PATH`.

**Avoid the npm `tree-sitter-cli` package.** nvim-treesitter advises against it; `:checkhealth config` warns when `exepath('tree-sitter')` points under `node_modules`, or when the version is below 0.26.1.

### Recommended

| Tool        | Used by                                                                 |
|-------------|-------------------------------------------------------------------------|
| `ripgrep`   | `<leader>fg` (live grep), grug-far, scoper                              |
| A Nerd Font | Icons in bufferline / lualine / telescope / neo-tree. Get one from <https://www.nerdfonts.com> and set it as your terminal font. |
| `fd` / `fdfind` | Alternative file-listing backend when ripgrep is unavailable. The configured file finders prefer `rg --files`. |
| `node` + `npm` | Many LSP servers (`ts_ls`, `pyright`, `bashls`, `jsonls`, `yamlls`, `html`/`cssls`) and `prettierd` are JS-based. Automatic installs need both; existing servers only need Node. |
| `python` / `python3` with `venv`/`ensurepip` | Mason installs `clang-format` and `debugpy` from PyPI. On Debian/Ubuntu, also install `python3-venv`. Store aliases on Windows are skipped. |
| `cargo` / `rustup`   | Rust toolchain itself — `rust_analyzer` ships via Mason, but `rustfmt` and `cargo` come from rustup. Blink can use a prebuilt fuzzy matcher or its Lua fallback without Cargo. |
| `lazygit`   | `<leader>tg` floating lazygit terminal                                  |
| `make` or `cmake` | Builds `telescope-fzf-native` with a C toolchain. The Makefile uses `cc` on Unix, **`gcc`** on Windows (MinGW); CMake also supports MSVC. With no suitable build chain the build is skipped and Telescope uses its Lua sorter. `make` also runs the test suite. |
| `gdb` or an appropriate LLDB/MI debugger | Needed for the corresponding cppdbg workflow. The separately installed CodeLLDB adapter bundles LLDB, so it does not require a system `gdb`/`lldb`. |

#### Per-language quick guide

Tools for richer language support are listed below; basic editing does not
require them. Automatic installation depends on the selected tools and their
prerequisites, and each language can work independently of the others.

| Language | Required runtime  | Auto-installed via Mason            | DAP adapter (Mason)       |
|----------|-------------------|-------------------------------------|---------------------------|
| C / C++  | A compiler/SDK to build; a debugger matching the chosen adapter | `clangd` (LSP), `clang-format` (formatter) | `cppdbg`, `codelldb` |
| Rust     | `rustup` (gets you `cargo`, `rustfmt`) | `rust_analyzer` (LSP) — `rustfmt` comes from rustup, not Mason | `codelldb` |
| Python   | `python` (Windows) / `python3` | `pyright` (LSP: types), `ruff` (LSP: lint + import sort, AND conform formatter) | `debugpy`     |
| Lua      | (none — Neovim ships its own) | `lua_ls` (LSP), `stylua` (formatter) | (no DAP)         |
| Bash     | `bash`            | `bashls` (LSP), `shfmt` (formatter) | `bashdb`                  |
| Scheme   | a Scheme implementation to run programs | Treesitter highlighting; no LSP/formatter configured | (none configured) |
| Batch    | Windows cmd to run scripts | No LSP, formatter or parser configured | (none configured) |
| JS / TS  | `node` + `npm`    | `ts_ls` (LSP); `prettierd` (formatter) | (none configured; add an adapter and configuration) |
| Go       | Go toolchain     | `gopls` is optional: select it in `tools.servers` | (none configured) |
| Markdown | (none)            | `marksman` (LSP); `prettierd` (formatter) | (no DAP)         |

The `mason-tool-installer` spec in `lua/plugins/formatting.lua` installs
`stylua`, `clang-format`, `shfmt`, `prettierd` and `shellcheck` (provides bashls's
ShellCheck lint diagnostics), plus the four debug adapters `debugpy`,
`codelldb`, `cpptools` and `bash-debug-adapter`. `ruff` and `taplo` arrive
with their language servers (mason-lspconfig's list in
`lua/plugins/lsp.lua`), and `rustfmt` rides along with the rustup
toolchain and is found on `PATH`. For other tools, use the server/package
selection in `local.lua` or run `:MasonInstall <name>` once. Installing a package
alone does not define an LSP configuration, formatter mapping or debug adapter.

### Optional

| Tool       | What for                                                |
|------------|---------------------------------------------------------|
| `bat`      | Prettier file previews in fzf-lua. (Default is `builtin` for cross-platform safety; switch in `lua/plugins/finder.lua` if you install bat.) |
| `luacheck` | Lint Lua files (`make lint`).                           |
| `stylua`   | Lua formatter; `make format` / `make check` (enforced in CI with the latest release). |
| `procdump` | Windows-only; dumps a frozen nvim process for triage.   |

### Per-platform install recipes

These are the fastest paths I know on each OS to get the **required** tools and the most-loved recommendations. Adjust to taste.

**Windows** (using [scoop](https://scoop.sh)):

```powershell
scoop bucket add main
scoop install neovim git tree-sitter ripgrep fd fzf nodejs lazygit make mingw
# C compiler for treesitter parsers, only if you don't have the MSVC Build Tools:
#   scoop install llvm
#   [Environment]::SetEnvironmentVariable('CC', 'clang', 'User')   # then open a new terminal
# Optional extras:
scoop install bat stylua luarocks gdb
luarocks install luacheck

# Then install a Nerd Font (one-off):
scoop bucket add nerd-fonts
scoop install nerd-fonts/JetBrainsMono-NF
```

`mingw` provides `gcc` for telescope-fzf-native's Makefile. Without a supported
Make toolchain, the spec can select CMake when available; there is no need to
uninstall Make used by other projects. Treesitter parsers are compiled
by the MSVC Build Tools (Visual Studio Build Tools, "Desktop development
with C++"), which are found automatically; with LLVM instead, `CC=clang`
must be set.

**macOS** (using Homebrew):

```sh
brew install neovim git tree-sitter ripgrep fd fzf node lazygit
brew install --cask font-jetbrains-mono-nerd-font
# Optional extras:
brew install bat stylua luacheck
# CodeLLDB bundles LLDB; Xcode Command Line Tools also provide an lldb executable.
```

Whatever the OS: run `tree-sitter --version` (must be **0.26.1+**); see
[Installing the tree-sitter CLI](#installing-the-tree-sitter-cli) if it
fails. Keep stylua current (`:MasonToolsUpdate`): CI uses the latest
release, and an older one may format some lines differently.

Xcode Command Line Tools provide the C compiler (`xcode-select --install` if you haven't already).

**Linux** (Debian/Ubuntu, adapt to your package manager):

```sh
sudo apt install git build-essential curl ripgrep fd-find nodejs npm
# Install lazygit separately if your distribution/release does not package it:
#   https://github.com/jesseduffield/lazygit#installation
# A clipboard tool, so "+y / "+p reach the system clipboard:
sudo apt install xclip          # X11; on Wayland: sudo apt install wl-clipboard
# Neovim and fzf: the distro packages are too old on Debian/Ubuntu
# (Neovim below this config's 0.12.0 floor; Ubuntu 24.04's fzf 0.44 can't
# run some fzf-lua pickers). Use the upstream releases instead:
#   https://github.com/neovim/neovim/releases  (tarball or AppImage)
#   https://github.com/junegunn/fzf/releases   (single binary → ~/.local/bin)
# tree-sitter CLI: see "Installing the tree-sitter CLI" (often cargo or a
# release binary on Debian/Ubuntu — the apt package is usually too old).
# Optional extras:
sudo apt install bat gdb luarocks
cargo install stylua --locked
sudo luarocks install luacheck

# Nerd Font: download a release from the GitHub releases page of
# whichever Nerd Font you prefer and drop the .ttf files into
# ~/.local/share/fonts/, then `fc-cache -fv`.
```

`fd` is often called `fdfind` on Debian-based distributions. The config recognizes
both executable names; an interactive shell alias is not needed and would not
affect Neovim's subprocess lookup anyway.

## Customization

Create an optional, Git-ignored `local.lua` next to `init.lua` to override
leaders/options, selected tools, Scoper, search/debug roots, sessions, editing
policies and UI behavior. It loads before maps and plugins. Keep shipped files
unchanged and use normal Lazy specs for plugin-specific overrides.
See [docs/customization.md](docs/customization.md) for examples, load order,
list/false semantics, trusted project overlays, inspection and feature guides.

Scoper keeps search scope, selected build database and clangd mode separate.
The existing automatic filtered behavior remains the default; explicit
`disabled`, `native`, `selected` and `filtered` modes are documented in
[docs/scoper-integration-notes.md](docs/scoper-integration-notes.md).
`:ScoperDatabase` selects a build independently of scope, and `:ScoperReload`
reloads saved state (`!` explicitly discards unsaved session changes).

## Layout

```
nvim/
├── init.lua                  Entry point
├── lua/
│   ├── config/
│   │   ├── settings.lua      early machine settings, trusted overlays and root intents
│   │   ├── search.lua        literal visibility policies and backend root resolution
│   │   ├── session.lua       automatic-save veto before layout/scope cleanup
│   │   ├── tool_intent.lua   selected package identities, pins and intentional opt-outs
│   │   ├── options.lua       vim.opt settings
│   │   ├── keymaps.lua       Global keymaps
│   │   ├── autocmds/         Autocommands, one module per topic
│   │   │   ├── init.lua          loads the modules below, in order
│   │   │   ├── editing.lua       yank flash, last position, trim, mkdir, …
│   │   │   ├── bigfile.lua       big-file mode
│   │   │   ├── glue.lua          small plugin glue (filetype after session restore, LuaSnip cleanup)
│   │   │   ├── folds.lua         fold persistence (view files)
│   │   │   ├── lsplog.lua        LSP log rotation
│   │   │   └── swap.lua          swap guard, :SwapGuardToggle, :SwapDelete
│   │   ├── dap.lua           nvim-dap setup: adapters, fallback configs, signs
│   │   ├── dap_ui_layout.lua  preserve fixed columns across debugger layout changes
│   │   ├── diagnostics.lua   :DiagnosticDump (hang triage)
│   │   ├── lsp_format.lua    asynchronous LSP formatting with buffer lifecycle guards
│   │   ├── health.lua        :checkhealth config (external toolchain check)
│   │   ├── health_reminder.lua  persisted, configurable monthly tooling review prompt
│   │   ├── tooling.lua       optional tool prerequisites and quiet fallbacks
│   │   ├── util.lua          Shared helpers (buffer delete, file-buffer test, augroup)
│   │   ├── icons.lua         Shared diagnostic glyphs
│   │   └── lazy.lua          Bootstrap lazy.nvim
│   └── plugins/              One file per "category" of plugins
│       ├── colorscheme.lua   catppuccin
│       ├── atone.lua          undo-tree visualizer (atone.nvim)
│       ├── ui.lua            lualine, bufferline, scope (per-tab bufs), incline, devicons, fidget
│       ├── editor.lua        autopairs, flash, neoscroll,
│       │                     smear-cursor, blink.indent, mini.surround,
│       │                     mini.align, todo-comments, render-markdown
│       ├── lazydev.lua       lua_ls library feeding for editing this config
│       ├── which-key.lua     Leader-key popup
│       ├── treesitter.lua    treesitter + context + textobjects
│       ├── lsp.lua           lspconfig + mason + mason-lspconfig (pyright + ruff for Python)
│       ├── completion.lua    blink.cmp (+ LuaSnip, + lazydev source)
│       ├── formatting.lua   conform.nvim + mason-tool-installer (formatter installs)
│       ├── git.lua           gitsigns, diffview+
│       ├── explorer.lua      neo-tree file explorer (<leader>e)
│       ├── finder.lua        telescope + fzf-lua
│       ├── terminal.lua      toggleterm
│       ├── dap.lua           nvim-dap + dap-ui + virtual-text + persistent-breakpoints
│       ├── trouble.lua       trouble.nvim
│       ├── folding.lua       nvim-ufo
│       ├── session.lua       auto-session
│       ├── search.lua        grug-far
│       ├── neogen.lua        doc-comment scaffolding (doxygen, luadoc, …)
│       └── scoper.lua        local spec for bundled scoper.nvim
├── tests/                    plenary specs: config smoke + leader maps, behaviour
│   ├── settings_spec.lua      local values, project isolation and option precedence
│   ├── settings_startup_spec.lua  real local-file startup and plugin overrides
│   ├── debug_policy_spec.lua  idempotent adapters and custom launch providers
│   ├── debug_activation_spec.lua  overrides before first debugger activation
│   ├── terminal_policy_spec.lua  inherited shells and per-project lazygit
│   ├── tool_intent_spec.lua  disabled/pinned tools and strict offline requirements
│   ├── health_tool_intent_spec.lua  selected versus intentionally disabled tools
│   ├── editing_policy_spec.lua  trim/comment/prose/window policies
│   ├── retention_policy_spec.lua  configured view cleanup and log rotation
│   ├── ui_policy_spec.lua    stock-theme/no-icons/reduced-motion startup
│   ├── search_policy_spec.lua  literal visibility, selector and session settings
│   ├── minimal_init.lua
│   ├── config_spec.lua
│   ├── bootstrap_spec.lua     locked first-boot plugin manager
│   ├── test_runner_spec.lua   prompt failure exits from the Lua test runner
│   ├── config_runtime_spec.lua  checkout discovery after a cold plugin install
│   ├── lsp_initialization_spec.lua  first-client settings and capabilities
│   ├── fixtures/
│   │   ├── settings_startup.lua  controlled real machine-local startup profile
│   │   ├── lsp_initialization.lua  real Lazy startup with controlled Mason boundary
│   │   └── windows_dap_spawn.lua  native Windows adapter process and argv checks
│   ├── escape_float_lifecycle_spec.lua  popup closure under reentrant window hooks
│   ├── session_filetype_rescue_spec.lua  session filetype rescue on ordinary files
│   ├── bigfile_reread_spec.lua  large-to-small reread callback invalidation
│   ├── view_janitor_spec.lua  preserve unrelated files during view cleanup
│   ├── fold_view_freshness_spec.lua  subsecond saved-view freshness
│   ├── dap_python_adapter_spec.lua  Python launch and socket attach transports
│   ├── dap_windows_adapters_spec.lua  native Mason adapter selection
│   ├── terminal_literal_cwd_spec.lua  real terminal cwd and persistence
│   ├── history_literal_paths_spec.lua  exact-file history guards
│   ├── scoper_telescope_spec.lua  real Telescope and ripgrep scope filtering
│   ├── ci_actions_test.py     immutable pin guard and explicit updater tests
│   ├── lsp_format_race_spec.lua  delayed formatting and buffer lifecycle races
│   ├── search_file_navigation_spec.lua  Grug result header navigation
│   ├── health_paths_spec.lua  state path types and native option decoding
│   ├── health_reminder_spec.lua  reminder cadence, persistence, and recovery
│   ├── tooling_spec.lua       missing runtimes, native builds, and supported installs
│   ├── diagnostic_tail_spec.lua  bounded regular-file log reads and I/O failures
│   ├── explorer_directory_spec.lua  directory startup and reload behavior
│   ├── treesitter_context_bigfile_spec.lua  large-file context parser exclusion
│   ├── treesitter_install_alias_spec.lua  shared-parser filetype aliases
│   ├── test_dependency_spec.lua  isolated concurrent test dependency installs
│   ├── zoom_layout_spec.lua  ordered window layout changes while zoomed
│   ├── prose_undo_spec.lua  prose mapping cleanup after filetype changes
│   ├── buffer_lifecycle_spec.lua  buffer deletion under reentrant autocmds
│   ├── buffer_menu_split_spec.lua  buffer menu splits from file windows
│   ├── session_ui_visibility_spec.lua  preserve visible debugger layouts on save
│   ├── dap_ui_lifecycle_spec.lua  shared debugger UI across sessions
│   ├── dap_sidebar_width_spec.lua  generic fixed columns, real debugger layouts and Neo-tree
│   ├── search_literal_paths_spec.lua  literal environment-like file names
│   ├── navigation_paths_spec.lua  Telescope picker-relative clipboard paths
│   ├── lsp_lifecycle_spec.lua  LSP attachment and per-buffer capabilities
│   ├── hooks_spec.lua         staged-path and Git failure handling
│   ├── behavior_spec.lua
│   ├── search_scope_spec.lua  current-file replacement confinement
│   ├── local_plugin_spec.lua  checkout-relative bundled plugin loading
│   ├── treesitter_install_spec.lua  failed parser installation cooldown
│   ├── swap_cleanup_spec.lua  swap revalidation across cleanup prompts
│   ├── swap_directory_spec.lua  native escaped swap-directory parsing
│   ├── session_scope_spec.lua  tab scope persistence after moving tabs
│   ├── session_dap_spec.lua    preserve normal files with debugger-like names
│   └── offline_seed_test.py  Python tests for scripts/offline-seed.py (make test-seed)
├── docs/                     Human-facing docs (not loaded by nvim)
│   ├── quick-start.md         common daily workflows and first-session essentials
│   ├── visual-studio-migration.md  Visual Studio migration, quick start and feature reference
│   ├── customization.md       local override lifecycle, trust and feature guide index
│   ├── generalization-verification.md  test environment, acceptance cases and platform limits
│   ├── documentation-audit-2026-10-28.md  documentation/comment coverage, corrections and evidence
│   ├── tooling-configuration.md  selected languages, executable discovery and offline intent
│   ├── scoper-core-notes.md   scope model, revisions, schema and persistence outcomes
│   ├── scoper-integration-notes.md  build selection, clangd modes, startup and source refresh
│   ├── search-session-configuration.md  roots, visibility, selectors and persistence policies
│   ├── debug-terminal-configuration.md  adapters, launch files, shells and lazygit
│   ├── editing-ui-configuration.md  content editing, themes, motion, icons and retention
│   ├── audit-2026-10-21.md     findings, regressions, sources, and limits
│   ├── audit-followup-2026-10-22.md  expanded audit and complete file coverage
│   ├── audit-resolution.md    unresolved findings, verification and retained limits
│   ├── ci-troubleshooting.md  cold-start hangs, platform paths, execution limits
│   ├── limited-environments.md  optional tool policy and minimal-machine verification
│   ├── CHANGES-archive.md    older changelog entries
│   ├── cheatsheets/          Open these in any browser
│   │   ├── keymaps.html              All bindings, grouped by prefix
│   │   ├── plugins.html              Per-plugin commands & features
│   │   ├── workflows.html            Common multi-step recipes
│   │   ├── debugging.html            nvim-dap + codelldb: REPL, evaluators, /py, watchpoints
│   │   ├── vs-to-nvim.html           Visual Studio → this config (for VS expats)
│   │   ├── cpp-diagnostics.html      Suppressing clang-format/clang-tidy/clangd warnings
│   │   ├── clang-tools.html          clangd vs clang-format vs clang-tidy — concepts
│   │   └── clang-settings-reference.html  Exact values in the shipped clang templates
│   ├── workflows/            Longer step-by-step guides (Windows, Linux, macOS)
│   │   ├── swap-files.md             Swap collisions, crash recovery, :SwapClean, cleanup
│   │   ├── state-files.md            Undo history, ShaDa, sessions, logs: where, trim, reset
│   │   ├── install-update-uninstall.md  Extract, try side by side, update, roll back, remove
│   │   └── offline-install.md        Installing on a machine without internet (offline seed)
│   └── templates/            Files you COPY into a project (not the nvim config)
│       ├── cpp/                       → your C++ project root
│       │   ├── .clang-format          ready-to-copy formatter style
│       │   ├── .clang-tidy            ready-to-copy linter config
│       │   ├── .clangd                ready-to-copy LSP config (-std pin for C++ files)
│       │   ├── clang-format.example   annotated reference version
│       │   ├── clang-tidy.example     annotated reference version
│       │   ├── clangd.example         annotated reference version
│       │   └── README.md              placement & which-file-to-use
│       └── dap/                       → your project's .vscode/
│           └── launch.json.example    nvim-dap debug configurations
├── .editorconfig             portable whitespace/charset baseline (all editors)
├── .gitattributes            LF line endings in every checkout (stylua + sh need them)
├── .gitignore               machine-local settings stay untracked
├── .luacheckrc               luacheck config
├── stylua.toml               stylua config
├── .githooks/                tracked git hooks (pre-commit → luacheck + stylua + doc-sync)
├── .github/workflows/ci.yml  CI: luacheck, stylua, doc-sync, specs (nvim stable; scoper also on Windows)
├── Makefile                  test / lint / fmt-check / check / check-docs / format / all / ci / hooks
├── scripts/
│   ├── check-docs.sh             doc-sync guards: tree, keymaps, commands, plugins, version floor, templates, health
│   ├── ci-run.py                 stream CI output and annotate bounded failure details
│   ├── update-ci-actions.py       explicitly refresh immutable action pins
│   ├── offline-seed.py           pack / install plugins + Mason tools + parsers for an offline machine
│   └── offline-seed-check.lua    what this install would still download (used by offline-seed.py)
├── CHANGES.md                changelog (recent entries, newest first)
├── lazy-lock.json            plugin commit pins (`:Lazy restore` / `:Lazy update`)
├── scoper.nvim/              Bundled local plugin (loaded via `dir=`)
│   └── tests/                scoper's own unit tests
└── README.md
```

## Notable extras beyond a minimum setup

A minimal LSP+treesitter config gets you syntax highlighting and `gd`,
but the day-to-day experience leans heavily on a few small additions.
Each is documented in its file and easy to remove if you don't want it.

| Plugin                            | Why                                                          | File              |
|-----------------------------------|--------------------------------------------------------------|-------------------|
| `saghen/blink.cmp`                | Completion engine. LSP without one is half-useful.           | `completion.lua`  |
| `mason-org/mason-lspconfig.nvim`  | Standard glue between Mason and lspconfig.                   | `lsp.lua`         |
| `j-hui/fidget.nvim`               | LSP progress spinner ("indexing…"); invisible-and-essential. | `ui.lua`          |
| `tiagovla/scope.nvim`             | Per-tab buffer scoping — each tab shows only its own buffers (VS-Code-style). Composes with bufferline. | `ui.lua`          |
| `nvim-mini/mini.surround`         | `gzaiw"`, `gzrb)`, etc. — surround verbs on the `gz` prefix (moved off `s`, which flash owns — keeps flash jumps delay-free). | `editor.lua`      |
| `nvim-mini/mini.align`            | `ga=` column-aligns selected lines on a delimiter.           | `editor.lua`      |
| `folke/todo-comments.nvim`        | Highlight + jump between `TODO` / `FIXME` / `NOTE`.          | `editor.lua`      |
| `JoosepAlviste/nvim-ts-context-commentstring` | Right comment style in JSX/Vue/Astro.            | `editor.lua`      |
| `Weissle/persistent-breakpoints.nvim` | DAP breakpoints survive `:qa` and persist per-file.      | `dap.lua`         |
| `theHamsta/nvim-dap-virtual-text`  | Inline variable values at end-of-line while stopped (VS-style inline values). | `dap.lua`         |
| `danymat/neogen`                  | `<leader>cd` to scaffold a doc-comment for the function under the cursor (doxygen for C/C++, conventional style for other langs). | `neogen.lua`      |
| `XXiaoA/atone.nvim`               | `<leader>u` opens a visual undo-tree pane with TreeSitter-highlighted diff preview and persistent node marks. | `atone.lua`       |
| `folke/lazydev.nvim`              | Real completion + hover for the whole `vim.*` API and `require`d plugin modules while editing this config; feeds lua_ls on demand. | `lazydev.lua`     |
| `MeanderingProgrammer/render-markdown.nvim` | In-buffer rendering of Markdown (headings, bullets, code blocks, tables). `:RenderMarkdown toggle`. | `editor.lua`      |

To disable one locally, add `{ "owner/repository", enabled = false }` under
`plugins` in `local.lua`. `:Lazy clean` can remove disabled plugin checkouts.

## Keymap conventions

`<Space>` is leader. Hold it and `which-key` will pop up the rest.

| Prefix         | Theme                                    |
|----------------|------------------------------------------|
| `<leader>b`    | buffer                                   |
| `<leader>c`    | code (format, Mason, swap args, doc-gen, context jump) |
| `<leader>d`    | debug (DAP)                              |
| `<leader>f`    | find — Telescope pickers                 |
| `<leader>F`    | find — fzf-lua pickers                   |
| `<leader>g`    | git (gitsigns + diffview+)               |
| `<leader>l`    | LSP (rename, format, diagnostics, signature) |
| `<leader>s`    | search / replace (grug-far)              |
| `<leader>t`    | terminal (toggleterm, lazygit)           |
| `<leader>w`    | window + session (pure prefix)           |
| `<leader>x`    | diagnostics / trouble                    |
| `<leader>?`    | show buffer-local keymaps                |

Save lives on **`<C-s>`** (works in normal, insert, and visual mode) so
`<leader>w` can stay a pure prefix — chording `<leader>w` no longer
incurs the which-key disambiguation delay. `<leader>W` still saves all.
`<C-s>` is guarded on `buftype`, so in a non-file buffer (neo-tree,
Trouble, a terminal, …) it's a silent no-op instead of an `E382` error.

A few standalone motions worth knowing right away:

- `s` / `S`  — flash jump (`s` + one char, then the label; `S` treesitter node picker; surround lives on `gz` so `s` stays delay-free)
- `gza` / `gzd` / `gzr` — surround add / delete / replace (mini.surround)
- `<A-j>` / `<A-k>` — move the current line (normal) or the selected lines (visual) down / up, re-indented (visual `J` stays join-lines)
- `gcc` / `gc{motion}` / `gc` (visual) — toggle comment (Neovim's built-in commenting, `:h commenting`)
- `]h` / `[h` — next / prev git hunk
- `]d` / `[d` — next / prev diagnostic (Neovim's built-in maps; the config opens the diagnostic float after each jump)
- `]f` / `[f` — next / prev function (treesitter)
- `]k` / `[k` — next / prev class (treesitter; `]c`/`[c` are left to Vim's diff-mode)
- `gd` / `gr` — go to definition (direct jump) / references (opens the Trouble panel)
- `K` — peek a closed fold, else LSP hover, else Vim's own `K` ('keywordprg')
- `<C-\>` — toggle floating terminal
- `<C-o>` / `<C-i>` — jumplist back / forward (browser-style stack: a new jump after `<C-o>` discards the forward entries; see `jumpoptions` in options.lua)

## First-time setup checklist

Start with the required editor/plugin prerequisites, then enable the optional
features you need. A missing language tool is not a reason to abandon setup.

1. **Check Neovim and Git**, then check optional tools for your workflows in a
   fresh shell. Run these commands separately in your platform's shell:
   ```
   nvim --version       # ≥ 0.12.0
   git --version
   tree-sitter --version   # ≥ 0.26.1, and not the npm package
   tar --version        # optional parser-build prerequisite
   curl --version       # optional parser-build prerequisite
   cc --version         # or clang --version; on Windows the MSVC Build Tools needn't be on PATH
   rg --version         # ripgrep (recommended)
   fd --version         # (recommended)
   ```
   Neovim/Git are needed for a fresh online install. Missing parser/build or
   language prerequisites skip the corresponding optional installs; review
   `:checkhealth config` and the [limited-environment guide](docs/limited-environments.md).

2. **Clone this repository into the config folder**, or extract the zip into
   its parent folder (table at the top; per-platform commands and existing-folder
   backup steps in
   [docs/workflows/install-update-uninstall.md](docs/workflows/install-update-uninstall.md)).
   Move an existing config aside first. No internet on this machine? Install an offline seed built elsewhere
   instead of steps 3–7: [docs/workflows/offline-install.md](docs/workflows/offline-install.md).

3. **Launch `nvim`.** lazy.nvim installs itself and enabled plugins. Wait for
   those operations to complete; network speed and supported native builds
   determine how long a fresh install takes.

4. **Quit and relaunch.** Some plugins finalize on the second boot.

5. **Run `:checkhealth config`**, then relevant plugin health checks. Missing
   optional tools are reported even when startup continues quietly. Check font
   rendering separately in your terminal; a Nerd Font is not an executable that
   this health check can install or verify.

6. **Let supported parser installs finish.** With auto-install enabled and its
   prerequisites available, the configured parser list installs in the background.
   Read build errors before retrying `:TSInstall <lang>`; downloads, SDKs and
   grammar/tool compatibility matter as well as the compiler. `:TSUpdate` updates
   installed parsers. Existing compatible parsers work without a build toolchain.

7. **Run `:Mason`** to inspect selected LSP servers, formatters and DAP adapters.
   Check prerequisite skips in `:checkhealth config` before retrying a package
   with `:MasonInstall <name>`; a manual install still needs its prerequisites.

8. **Open a Lua file** and confirm completion + `gd` (go-to-definition)
   work when `lua_ls` is selected and installed. This checks Lua support; other
   languages have independent servers, runtimes and project-root requirements.

### Stuck during setup?

- Mason package failing to install → open `:MasonLog` for the actual
  error. Most failures are missing-toolchain (no `go`, no `node`, no C
  compiler) or network/proxy issues.
- Plugin reports an error you don't recognize → inspect task errors in `:Lazy`
  and `:messages`; `<CR>` on a plugin shows its branch, commit and directory.
  `:Lazy log` shows recent Git updates/commits, not a general error log. If a
  plugin has the wrong revision, see the version/reset guidance below.
- A parser build fails with `Lock file '…tree-sitter…\lock\<lang>-….lock'
  appears stale` → Neovim was closed while that parser compiled (gitcommit
  can be slow). Close other parser installers and confirm the lock's owner is
  gone before removing that specific lock at the path printed in the error;
  cache roots vary by platform and environment. Then retry `:TSInstall <lang>`.
- Treesitter parsers won't compile → inspect prerequisites and the build error.
  `:checkhealth config` checks the compiler and CLI
  (it flags an npm or pre-0.26.1 CLI); then `:TSInstall <lang>`
  retries. On Windows the MSVC Build Tools are found automatically;
  with LLVM instead, `CC=clang` must be set.
- LSP server not attaching → `:checkhealth vim.lsp` shows the per-buffer
  status. If it shows "no clients", confirm the server is in Mason's
  installed list (`:Mason`).
- Everything else → `:DiagnosticDump` writes configuration/runtime details and
  an LSP log tail to `stdpath('log')`. Review paths, messages and logs for private
  data before sharing a report.

## Common tweaks

- **Change colorscheme**: set `ui.colorscheme = "habamax"` (or another
  installed theme) in `local.lua`. Use a Catppuccin Lazy `opts` override for
  its flavour. See [editing/UI policies](docs/editing-ui-configuration.md).
- **Format on save** (off by default): add a Conform Lazy override with
  `event = { "BufWritePre" }` and a `format_on_save` callback; see the
  [complete local.lua recipe](docs/tooling-configuration.md#opt-into-format-on-save).
  Its callback honors `:FormatToggle` / `:FormatToggle!`;
  `editing.trim_whitespace` separately controls core trimming.
- **Big-file threshold**: files larger than `vim.g.big_file_size` bytes
  (default 1 MB) open in big-file mode: no treesitter, regex syntax, swap,
  folding (ufo included) or LSP, and no whitespace trim on save.
  Set it in your own config or live: `:let g:big_file_size = 5000000`.
- **Treesitter parsers on demand**: opening a filetype whose parser isn't
  installed builds it in the background (needs the tree-sitter CLI; once
  you install its CLI, compiler, curl, and tar, the next buffer starts the build).
  A failed build is retried after 5 minutes at the earliest.
  `vim.g.treesitter_auto_install = false` turns that off.
- **Plugin versions**: the committed `lazy-lock.json` records the tested plugin
  revisions. `:Lazy update` moves them forward and rewrites that file.
  `:Lazy restore` uses the lockfile currently on disk; it does not recover an
  older lockfile from Git. To undo an update, restore your desired lockfile from
  Git or a backup first, then run `:Lazy restore`. See the
  [rollback steps](docs/workflows/install-update-uninstall.md#roll-back).
  CI's plugin cache is keyed on the lockfile.
- **Tooling health reminder**: an informational prompt appears on first
  interactive use, then every 30 days when you start or refocus Neovim.
  Set `globals.tooling_reminder_days = 7` in `local.lua` for weekly
  reminders, or `0` to disable them. The timestamp persists in Neovim's state
  directory across restarts. The reminder always points to `:checkhealth config`,
  including when no skipped tooling was recorded during startup.
- **Choose LSPs/parsers**: set `tools.servers` / `tools.parsers` in `local.lua`;
  lists replace the defaults, and `{}` disables config-owned provisioning.
  See [tool selection](docs/tooling-configuration.md) for extension, pins,
  auto-enable policy and prerequisite handling. `:TSInstall <lang>` remains manual.
- **Disable smear-cursor / neoscroll**: set `ui.reduced_motion = true` in
  `local.lua`, or disable either plugin through a normal Lazy override.
- **Re-enable implicit system clipboard**: by default this config keeps
  Vim's unnamed register separate from `"+"` so `dd` / `cc` / `x` don't
  clobber the OS clipboard — at the cost of needing `"+y` / `"+p` for
  clipboard access. To restore the convenient-but-leaky `clipboard =
  "unnamedplus"` behaviour, set `options.clipboard = "unnamedplus"` in
  `local.lua`.
- **Per-project Lua (`exrc`)**: **off by default**; explicitly pre-set options
  survive. To opt in, set `options.exrc = true` in `local.lua`. Neovim then uses
  its `:trust` mechanism for `.nvim.lua` / `.nvimrc` / `.exrc` discovery, including
  ancestor directories. Trusted files execute with the editor's full access;
  approve only code you have reviewed. `:trust ++remove` revokes the current
  file's trust. For project behavior registered from your own trusted local
  configuration, see [project overlays](docs/customization.md#project-context-and-trust).
- **Disable in-buffer Markdown rendering**: `:RenderMarkdown toggle`, or add
  `{ "MeanderingProgrammer/render-markdown.nvim", enabled = false }` under
  `plugins` in `local.lua`.

## Health checks

Run `:checkhealth` for a top-down view. Start with this config's own check:

- `:checkhealth config` — this config's own check; run it first. It covers,
  **Neovim** (the version floor), **Core prerequisites** (`git` and conditional
  parser-build requirements: compiler, tree-sitter CLI 0.26.1+, download/extraction
  tools), **Runtime state
  directories** (swap, and undo when `undofile` is on, must be writable),
  **Search & pickers** (`rg`, `fzf`, `fd`), the **C/C++ toolchain**
  (`clangd`, `clang-format`, `clang-tidy`), **Language runtimes** (`node`,
  Python 3 as `python3` or `python`, Rust tools where selected; fzf older than 0.45 is flagged because some fzf-lua
  pickers need newer), **Dev & test tooling**, and **Mason-managed servers /
  formatters / debug adapters** (deferred to `:checkhealth mason` rather
  than duplicated here), and **Optional tooling skipped on this machine**
  (automatic installs/builds and server runtimes skipped by prerequisite checks).
  It flags what's missing or the wrong version, and
  notes when `'exrc'` is on (project `.nvim.lua` files run once `:trust`ed).
  Intentional opt-outs and prerequisite skips are distinguished from usable
  installed tools. See [tool selection](docs/tooling-configuration.md).
  (Implemented in `lua/config/health.lua`.)

Useful single-plugin variants:

- `:checkhealth lazy`
- `:checkhealth nvim-treesitter`
- `:checkhealth mason`
- `:checkhealth telescope`
- `:checkhealth vim.lsp`

## Neovim 0.12 features deliberately not enabled

Recorded here so the decision is easy to revisit:

- **`'autocomplete'`** (0.12): built-in insert-mode completion that pops
  up as you type, fed by `'complete'` sources including functions. Not
  used because blink.cmp already provides completion (LSP, snippets,
  paths, buffer, cmdline, signature help); turning both on would show
  two menus. To try it instead of blink: disable the blink spec, then
  `vim.o.autocomplete = true` and set `'complete'` / `'completeopt'`
  (`:help 'autocomplete'`, `:help ins-autocompletion`).
- **ui2** (0.12, experimental): a redesigned message and command-line
  UI (no "Press ENTER" prompts, works well with `cmdheight=0`). Left off
  because it is marked experimental and changes how every message
  appears; revisit when it is no longer experimental (`:help ui2`). To
  try it for a session: `:lua require('vim._core.ui2').enable({})`.

### Built-ins that overlap a plugin kept here

| Neovim 0.12 built-in | Plugin kept | Why the plugin stays |
|----------------------|-------------|----------------------|
| `:Undotree` (after `:packadd nvim.undotree`) | atone.nvim (`<leader>u`) | Diff preview of each undo state and persistent node marks; the built-in is a plain tree you move through. |
| `:DiffTool {left} {right}` (after `:packadd nvim.difftool`) | diffview-plus.nvim (`<leader>gd`) | Git-aware: working tree vs index or any revision, file and line-range history, the merge-conflict view. For two plain files or directories `:DiffTool` and `:DiffviewDiffFiles` / `:DiffviewDiffDirs` overlap; either works. |
| `:restart` | auto-session (`ZR` runs `:restart!`) | Per-directory sessions saved on exit. `!` skips Neovim's own session save/restore, so the two don't fight. |
| Progress in the default statusline (`vim.ui.progress_status()`) | fidget.nvim + lualine | lualine replaces the default statusline, and LSP progress reaches the built-in only through an `LspProgress` autocmd (`:help LspProgress`); fidget needs no glue. |
| Incremental selection: `an` / `in`, `]n` / `[n` | — | Used as is; no plugin for it. |

## Testing

This config has a lightweight test suite to catch the kinds of breakage
that show up after big refactors — "does my config still load?", "did I
just add a duplicate `<leader>` keymap?" — plus regression specs for
behaviour that was once broken.

```bash
make test         # config smoke test, keymap duplicates, behaviour specs
make test-scoper  # scoper.nvim's own test suite
make test-seed    # scripts/offline-seed.py: hostile seeds, install safety (Python, no Neovim)
make lint         # luacheck init.lua lua/ tests/
make fmt-check    # stylua --check (this tree)
make format       # stylua, both trees, in place
make check        # luacheck + stylua --check over this tree AND scoper.nvim/ (lua/ plugin/ tests/)
make check-docs   # doc-sync guards: README tree, keymaps, commands, plugins, version floor, templates
make check-actions # offline CI action pin guard and updater tests (Python)
make ci           # check + check-docs + check-actions + test + test-scoper + test-seed
make hooks        # enable the tracked pre-commit hook (one-time per clone)
```

### Enforcement: CI + pre-commit hook

These checks are now *enforced*, not just available:

- **CI** — `.github/workflows/ci.yml` runs `make check` (luacheck + stylua,
  both trees, scoper.nvim's `plugin/` included; the latest stylua)
  and `make check-docs` (the doc-sync guards) in one fast job, plus the
  plenary specs: the full-config suite
  (`make test`) on Ubuntu, and scoper.nvim's own suite on **both Ubuntu and
  Windows** — the cheapest way to exercise `scoper/path.lua`'s drive-letter /
  UNC / backslash handling on a real Windows box. `make test-seed` runs on
  Ubuntu, Windows and macOS with the runner's own Python. Both spec jobs run on
  Neovim `stable`; to test the `MIN_NVIM` floor in `init.lua` as well, add
  `v0.12.0` to their `nvim:` matrix. CI runs the same targets as `make ci`
  but not in the same environment (Ubuntu and Windows runners, the newest
  stylua, luacheck and tree-sitter CLI), so a green `make ci`
  locally is a strong hint, not a guarantee.
  Jobs have explicit 5–20 minute limits; the full-config test step has a
  10 minute limit. Failures include bounded output in Actions annotations,
  alongside the complete streamed job log.
  The Windows Scoper job also exercises native DAP process spawning. The
  Windows seed job executes an actual relocated distlib Python launcher using
  the runner's bundled pip resource; it downloads no test packages.
- **Pre-commit hook** — `.githooks/pre-commit` runs luacheck and
  `stylua --check` on the **staged** content of each `*.lua` file (what
  you're committing, not the working copy), then the doc-sync guards
  (`scripts/check-docs.sh`, pure grep/diff, no Neovim). It's
  version-controlled but off until you opt in per clone:
  ```bash
  make hooks     # == git config core.hooksPath .githooks
  ```
  If luacheck or stylua isn't installed, the hook says so and skips that
  gate (CI still catches it); any gate *failing* blocks the commit (bypass
  a one-off with `git commit --no-verify`).
- **Formatting**: the tree is stylua-formatted and `make check` / CI
  enforce it (CI uses the latest stylua). Hand-aligned blocks are fenced with
  `-- stylua: ignore start` / `-- stylua: ignore end`; put new columnar
  tables inside such a pair. `make format` formats both trees.

Run `make test` from the repository root (the harness resolves paths
against the cwd); any checkout location works.
Both suites enter through a Lua `-l` script so initialization and harness errors
exit nonzero instead of leaving a headless editor waiting indefinitely.
Spec files run sequentially to avoid simultaneous full-config startups contending
for plugin caches and short asynchronous UI deadlines. The test initializer
disables automatic parser/tool provisioning in child processes; installer specs
exercise controlled tasks instead of competing for shared build directories.

CI actions are pinned to full commit SHAs. Their comments record the selected
update tags; updates happen only when you run the updater with authenticated
GitHub CLI access:

```sh
python3 scripts/update-ci-actions.py --dry-run
python3 scripts/update-ci-actions.py
# To move one action to a new major explicitly:
python3 scripts/update-ci-actions.py --ref actions/checkout=v8
make ci
git diff -- .github/workflows/ci.yml
```

Commit and push the reviewed diff when ready. `--check` and `make check-actions`
work offline. The updater supports block-style `uses` scalars in this workflow;
it rejects unsupported forms and retains the file if resolution fails or a
concurrent edit is detected. This pins the action source, while tools downloaded
by actions, Mason and parser versions keep their existing update policies.

What the suite covers:

- **Smoke** (`tests/config_spec.lua`) — a headless Neovim boots `init.lua`
  and the config reaches the end (mapleader set, lazy.nvim loaded, more
  than 10 plugin specs parsed). The runner starts Neovim with
  `--noplugin`, which would make lazy.nvim skip setup entirely, so
  `tests/minimal_init.lua` turns `'loadplugins'` back on for it.
- **Duplicate `<leader>` keymaps** — `tests/minimal_init.lua` wraps
  `nvim_set_keymap` (the chokepoint every global mapping goes through)
  during the config load and logs each `(mode, lhs)`; the spec adds every
  lazy.nvim `keys` entry from lazy's own spec table. Two registrations of
  one `<leader>` key in one mode fail the test — between keymaps.lua and
  a plugin, or between two plugins. (lazy's own stub-then-real
  re-registration of a key is recognised and not counted.) Blind spots:
  buffer-local maps and maps a plugin sets inside its own `config()`.
- **Behaviour** (`tests/behavior_spec.lua`) — regression specs for bugs
  that were fixed, one `describe` block per area: buffer deletion that
  keeps the window layout (including the pickers' shared delete action
  and neo-tree's buffers view), the debugger fallback configurations,
  keymaps and keymap hygiene, snippets, the Windows `tar` shim, startup
  without plugins, fold persistence, and formatting. The `describe`
  names in the file are the up-to-date list.
- **Offline seed** (`tests/offline_seed_test.py`, `make test-seed`) —
  Python `unittest`, in temporary folders only. Hostile seeds (`..` and
  absolute paths, links out of the seed or written through, devices,
  duplicates, size limits) must be refused with nothing written; `--force`
  must move an existing `lazy/` aside instead of writing through a link;
  a failed swap must roll back; checksum, lockfile and platform gates; and
  the completeness check must fail, not pass, when Neovim crashes, hangs or
  writes no report (a fake `nvim` stands in).

`scoper.nvim/` has its own tests covering the pure-logic modules
(`state`, `path`, `util`), plus specs for `pickers` (the `:find` path
builder, ripgrep exclude quoting, grug-far path escaping, the fzf-lua,
telescope and plain-Vim backends), `lsp` (the `compile_commands.json`
scope filter, the per-project clangd `cmd`, and the restart logic: only
this project's clangd, re-attached once it has exited), the `:Scoper*`
commands and their completion, and `setup()` (options, following `:cd`
through `DirChanged`). The Windows case-insensitivity rules run on every
OS. Run them with `make test-scoper` from this directory, or `make test`
from inside `scoper.nvim/`. See `scoper.nvim/README.md` for what's
covered.

### Install the test runner

The Lua tooling (luacheck, stylua) is covered in the Prerequisites
section above. Plenary.nvim — the busted-style runner the tests use —
is fetched automatically on first `make test`, into
`stdpath("cache")/test-deps/plenary.nvim` (kept off your normal package
path). Subsequent runs reuse the clone.

Without make (e.g. Windows), run the underlying commands from the repo
root. In a POSIX shell, cmd.exe or PowerShell 7+:

```sh
nvim --headless --noplugin -u NONE -l scoper.nvim/tests/run.lua
cd scoper.nvim && nvim --headless --noplugin -u NONE -l tests/run.lua && cd ..
luacheck init.lua lua tests
stylua --check init.lua lua tests
```

Windows PowerShell 5.1 has no `&&`, so the scoper line becomes:

```powershell
Push-Location scoper.nvim; nvim --headless --noplugin -u NONE -l tests/run.lua; Pop-Location
```

(`sh scripts/check-docs.sh` needs a POSIX shell such as Git Bash.)

## Terminal & multiplexer notes

A few behaviours that look like config bugs are really limitations of the
terminal emulator or multiplexer underneath Neovim. Collected here so they
don't have to be rediscovered.

### `<C-Space>` and other "modified special key" combos

Neovim can distinguish `<C-CR>`, `<S-CR>`, `<C-Tab>` and similar combinations
only when the terminal sends distinct encodings. Neovim supports CSI-u/parts of
the kitty keyboard protocol and xterm's separate `modifyOtherKeys` mechanism;
these are not interchangeable names for one protocol. Support depends on the
terminal version and its settings, and a multiplexer can intercept the encoding.
See `:help tui-input` and `:help tui-csiu` before choosing mappings that rely on it.

`<C-Space>` needs no protocol in most terminals: they send it as a NUL
byte, which Neovim reads as `<C-Space>`. On the Windows console (and
zellij/tmux running over it), though, Ctrl+Space can arrive as a bare
`<Space>` — i.e. it behaves like `<leader>` — so a mapping on `<C-Space>`
silently does the wrong thing. That's why completion (blink.cmp) is also
reachable through **`<C-n>` / `<C-p>`** in this config, which every terminal
can send. See `docs/cheatsheets/keymaps.html` and the completion section of
`docs/cheatsheets/vs-to-nvim.html`.

To investigate a missing key, compare what Neovim receives with and without your
multiplexer: enter Insert mode and type `<C-v>` followed by the desired key (or
use `:lua print(vim.fn.keytrans(vim.fn.getcharstr()))` and press it). If the key
arrives as another key, changing a Neovim map cannot recover the lost distinction.
Check terminal/multiplexer protocol settings or use the provided alternative map.

### Mouse drag-select and scroll under zellij

With `mouse = "a"` (the default here) Neovim handles the mouse itself. Under
**zellij**, versions and terminal combinations have exhibited these behaviors:

- **Drag-select doesn't auto-scroll symmetrically** — dragging past the top
  or bottom edge scrolls unevenly or not at all.
- **The scroll wheel restarts/clears an in-progress selection** instead of
  extending it.

The config's mouse handling uses `mouse = "a"` with no
wheel or drag remaps and neoscroll bound only to keyboard motions
(`<C-u>` / `<C-d>` / `<C-f>` / `<C-b>` / `<C-y>` / `<C-e>`), so there's
no custom drag-selection implementation. Compare a session outside the
multiplexer to isolate the layer involved, then try these workarounds:

- Hold **Shift** while selecting to bypass the application's mouse capture
  and use the terminal's own text selection (works in most terminals).
- Disable zellij's mouse mode (dump its config with `zellij setup
  --dump-config`, set `mouse_mode false`) so the terminal handles the mouse
  directly.
- Prefer keyboard motions for scrolling (the neoscroll maps above) and
  Visual mode for selection.

These are tracked in zellij's own issue tracker; check there for the current
status before assuming a given version still has them.

## Clearing caches

When something feels stale — a plugin update that didn't take, a
treesitter parser that refuses to recompile, mysterious post-update
errors — there are three levels of reset, ordered least to most
destructive. Start with level 1.

First, run this inside nvim to get the exact paths on your system
(they differ slightly per OS and installation method):

```vim
:echo stdpath('cache') . "\n" . stdpath('data') . "\n" . stdpath('state') . "\n" . stdpath('log') . "\n" . stdpath('config')
```

With no `XDG_*` or `NVIM_APPNAME` overrides they resolve to:

| Path                | Windows                      | Linux and macOS          | Holds                                                 |
|---------------------|------------------------------|--------------------------|-------------------------------------------------------|
| `stdpath('config')` | `%LOCALAPPDATA%\nvim`        | `~/.config/nvim`         | Your config. **Never delete this.**                   |
| `stdpath('data')`   | `%LOCALAPPDATA%\nvim-data`   | `~/.local/share/nvim`    | Plugins (lazy), Mason packages, installed parsers, sessions and breakpoints |
| `stdpath('state')`  | (same as data)               | `~/.local/state/nvim`    | ShaDa, logs, undo, swap and fold views in this config |
| `stdpath('cache')`  | `%TEMP%\nvim`                | `~/.cache/nvim`          | luac bytecode cache, parser downloads, scoper's compile_commands copies |
| `stdpath('log')`    | (same as data)               | `~/.local/state/nvim`    | lsp.log, DiagnosticDump output                        |

The Unix commands below work in bash, zsh and fish. They target the default paths
in the table: substitute the actual `stdpath()` values if using XDG overrides or
another `NVIM_APPNAME`. Close all Neovim instances using those paths before any
reset, including before deleting Scoper caches referenced by running clangd.

### Level 1 — generated caches

This preserves installed plugins, parsers and Mason tools. Generated Lua/cache
and Scoper files are rebuilt as needed; cached download/build inputs may need
to be fetched again. It does not select different plugin versions.

```powershell
# Windows — quit nvim first.
Remove-Item -Recurse -Force "$env:TEMP\nvim"
```

```sh
# Linux / macOS — quit nvim first.
rm -rf ~/.cache/nvim
```

### Level 2 — cache, selected logs and ShaDa, keep plugins and recovery data

This additionally loses command/register/mark history and the named logs.
Preserve diagnostic evidence first. It does not remove undo, swap, views,
sessions or breakpoints; use the state guide for those individual policies.

```powershell
Remove-Item -Recurse -Force "$env:TEMP\nvim"
Remove-Item -Force "$env:LOCALAPPDATA\nvim-data\*.log*" -ErrorAction SilentlyContinue
Remove-Item -Force "$env:LOCALAPPDATA\nvim-data\shada\*" -ErrorAction SilentlyContinue
```

```sh
rm -rf ~/.cache/nvim
find ~/.local/state/nvim/. ! -name . -prune -type f -name '*.log*' -exec rm -f {} +
find ~/.local/state/nvim/shada -type f -exec rm -f {} +
```

The log command prunes child directories, so it only removes direct log files
and keeps nested undo/swap/view data even when an encoded filename contains
`.log`. `find` can report a directory that has never been created. The quoted
filename pattern avoids shell differences when no logs match.

### Level 3 — nuclear: everything except config

Wipes plugins, Mason, sessions, breakpoints, the lot, **including swap
files with unsaved work**: run `nvim --clean -r` first and recover
anything marked "modified: YES" ([docs/workflows/swap-files.md](docs/workflows/swap-files.md)).
Next launch needs network access to reinstall enabled plugins and tools, and
build prerequisites for missing parsers/native extensions. It preserves tracked
and local configuration, so a configuration logic error can still recur.

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\nvim-data"
Remove-Item -Recurse -Force "$env:TEMP\nvim" -ErrorAction SilentlyContinue
```

```sh
rm -rf ~/.local/share/nvim
rm -rf ~/.local/state/nvim
rm -rf ~/.cache/nvim
```

### In-editor alternatives (surgical, no shell)

Target one subsystem instead of nuking everything:

- **Swap files** — `:SwapClean` deletes the leftovers that hold no
  unsaved work; see [docs/workflows/swap-files.md](docs/workflows/swap-files.md).
  Undo, ShaDa, sessions and logs have different retention and recovery policies:
  [docs/workflows/state-files.md](docs/workflows/state-files.md).

- **Lazy plugin clean / reinstall** — `:Lazy clean` (removes plugins no
  spec uses) or `:Lazy restore` (back to the `lazy-lock.json` commits)
- **Single plugin reinstall** — quit, delete just that plugin's folder
  (`Remove-Item -Recurse -Force "$env:LOCALAPPDATA\nvim-data\lazy\<plugin>"`,
  or `rm -rf ~/.local/share/nvim/lazy/<plugin>`), relaunch
- **Mason packages** — `:Mason` → `X` on a package, or `:MasonUninstallAll`
- **Treesitter parsers** — `:TSUninstall <lang>` then `:TSInstall <lang>`.
  Automatic installation can reinstall selected parsers after a restart or a
  matching file open. To keep one absent, remove it from the startup
  `tools.parsers` list **and** disable `tools.parsers_on_demand`, or disable all
  automatic installation as described in the tooling guide.
- **Sessions** — `:AutoSession delete` for the current project. Behaviours
  worth knowing:
  - By default, starting **with file arguments** (`nvim foo.c`) saves only
    after the work grows to 2+ ordinary file buffers or 2+ tabs. Session policies
    in `local.lua` can change automatic saving and suppression.
  - Home, Downloads, temp directories and filesystem roots are suppressed by
    the shipped policy; see the session guide for pattern/predicate boundaries.
  - Never-written file buffers are excluded from the saved layout without
    discarding their in-memory edits. Write important new buffers to disk;
    session files are not a substitute for saving their contents.
  - Saving while debugging (`:AutoSession save`, switching sessions)
    keeps the debug session running; dap-ui closes for the save and
    reopens. Quitting still terminates the debuggee.
- **shada** (marks, registers, command history) — delete
  `main.shada` in the `shada` folder of `stdpath('state')`
  (`%LOCALAPPDATA%\nvim-data\shada\`, `~/.local/state/nvim/shada/`)

### What clearing does and doesn't fix

- **Stale cache** (level 1) fixes weird highlighting after an update,
  treesitter parsers that won't recompile, post-update Lua oddities.
- **Wrong plugin code** — inspect `:Lazy` and use `:Lazy restore` for the
  committed lockfile or an explicit update for a new revision. A targeted
  reinstall is for a damaged checkout; deleting all runtime data is unnecessary.
- **Config logic bugs** can't be cache-cleared away. The problem is in
  `lua/`.

If `Remove-Item` fails with "file in use" on Windows, make sure every
nvim instance (including ones in VS Code's terminal or in tmux) is
closed — Mason binaries and the LSP log are held open while nvim runs.

## Troubleshooting hangs

When nvim becomes unresponsive — frozen for tens of seconds, won't take
input, no cursor blink — the goal is to capture enough state that
someone can tell you what hung. There's a one-shot command baked in:

### `:DiagnosticDump`

Writes a timestamped report to `stdpath('log')` containing:

- nvim version + platform + path roots + cwd
- swap/undo settings, the swap guard and big-file flags, the session file
- complete `:messages` history (often holds the smoking gun)
- active LSP clients with their root dirs and attached-buffer counts
- every loaded buffer with line count + treesitter-active flag +
  big_file flag (huge buffers with treesitter on are a classic hang)
- every swap file, classified as `:SwapClean` sees it (own, live,
  dirty, clean, empty, unreadable)
- scoper: root, active scope, the clangd cmd last applied, the last
  compile_commands filter result and how the last background run ended
- DAP session state (if any), with `env` values and secret-looking keys
  (token, password, auth, api key, …) redacted; `:DiagnosticDump!`
  writes them as is
- plugin list from lazy.nvim
- last 64 KiB of the LSP log

Run `:DiagnosticDump`, inspect the file, and share only the parts needed for the
issue. Redaction is limited: filenames, messages, source fragments and LSP logs
can contain private information even without `!`. A dump is a snapshot, not a
stack trace of code that was blocked before the command could execute.

### When nvim is *fully* hung

`:DiagnosticDump` can't run if nvim isn't taking input. The workflow:

1. **Try `<C-c>` first** — interrupts whatever's blocking. If it
   unhangs, immediately run `:DiagnosticDump` while you can.
2. **Open Task Manager / Process Explorer** and look at `nvim.exe`:
   - high CPU → investigate active computation such as parsing or an autocmd loop
   - low CPU → investigate waits or I/O; this alone does not identify the cause
3. **Force-kill nvim**, then restart in the same project.
4. **Run `:DiagnosticDump`** in the fresh nvim. This describes the new process;
   old LSP messages may remain in `lsp.log` or its rotated `lsp.log.old`, but
   startup rotation can replace the older generation. Preserve logs before
   repeated restarts if they matter to the investigation.
5. Review the report and logs before sharing them with a note about the trigger.

For especially nasty hangs on Windows, [ProcDump](https://learn.microsoft.com/sysinternals/downloads/procdump)
captures a memory snapshot of the still-frozen process so the call
stacks of every nvim thread are recoverable: `procdump -ma <pid>`.
Capture before killing the process if a native stack is needed. Memory dumps can
contain source code, credentials and other process data; share them privately
only with the intended debugger/support recipient.

### Preemptive verbose logging

If a hang is reproducible, turn the LSP log level up before triggering
it. The verbose log captures every JSON-RPC message in and out, which
makes "what was the server doing when nvim froze?" answerable:

```vim
:lua vim.lsp.log.set_level("debug")     " or "trace" for even more
```

Setting persists for the session. The log lives at the path printed by
`:lua print(vim.lsp.log.get_filename())`. Revert with `"warn"` when done —
debug/trace generates a *lot* of output on big projects.

Neovim's own low-level log (rare; useful when nvim itself crashes before
reaching Lua) is `stdpath('log')/nvim.log` — `%LOCALAPPDATA%\nvim-data\nvim.log`
on Windows. To write it somewhere else, e.g. a fresh file for one run,
set `NVIM_LOG_FILE` before launching:

```powershell
# PowerShell
$env:NVIM_LOG_FILE = "$env:TEMP\nvim-debug.log"; nvim
```

```cmd
:: cmd.exe
set NVIM_LOG_FILE=%TEMP%\nvim-debug.log
nvim
```

### Common culprits worth checking yourself first

| Symptom | Likely cause | What to try |
|---|---|---|
| Hang when opening a specific file | huge file + treesitter | open the file with `nvim --clean <file>` to confirm |
| Completion slow or absent | Server/runtime availability, project setup or completion configuration | `:checkhealth vim.lsp`, inspect attached clients and logs; an asynchronous LSP request alone does not establish why the whole UI froze |
| Windows: Mason install fails with "tar: unrecognized option --no-same-owner" | Another tool's `tar` (Git/MSYS, vendor shells) is first on PATH | Handled automatically: when Mason loads, System32's `tar.exe` is copied to `stdpath("data")/tar-shim` and put first on PATH for Neovim (`vim.g.windows_tar_shim = false` to opt out). `:checkhealth config` shows which tar is used; then `:MasonInstall <pkg>` again |
| Hang on `:wq` after long session | session-save iterating thousands of buffers | `:lua print(#vim.api.nvim_list_bufs())` — if >500, something's leaking buffers |
| Sluggish typing | treesitter on a huge buffer | check `:DiagnosticDump`'s buffer table for big files with `ts=true` and `big_file=false` (the big-file guard isn't catching it) |
| Hang on git operation in a huge repo | gitsigns / diffview blocking | `:Lazy reload gitsigns.nvim` to confirm |
| Repeated slow native debugger startup on Windows | Symbol loading or another startup bottleneck | Try the per-project [CodeLLDB symbol-loading settings](docs/debug-terminal-configuration.md#codelldb-symbol-loading-for-slow-launches), then inspect adapter logs; timing alone does not identify antivirus scanning |
