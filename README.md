# Neovim Configuration

A well-commented Neovim configuration for **Neovim ≥ 0.12.0** — the floor
that nvim-treesitter's `main` branch needs. A guard at the top of `init.lua`
(`MIN_NVIM`) checks it at startup, and `make check-docs` fails if this
README, the health check or CI name a different floor. The zip holds one
top-level `nvim/` folder; extract it into the parent folder so it becomes
your config folder:

| OS              | Extract into          | Config folder              |
|-----------------|-----------------------|----------------------------|
| Linux / macOS   | `~/.config/`          | `~/.config/nvim/`          |
| Windows (PS)    | `$env:LOCALAPPDATA\`  | `$env:LOCALAPPDATA\nvim\`  |

Commands for extracting, updating to a new zip, trying it next to another
config, and uninstalling, per OS:
[docs/workflows/install-update-uninstall.md](docs/workflows/install-update-uninstall.md).

The first `nvim` launch will bootstrap [lazy.nvim](https://github.com/folke/lazy.nvim)
and install every plugin. Give it ~30–60 seconds, then quit and relaunch.

## Prerequisites

This config doesn't replace external tools — it orchestrates them.
Install these **before** the first `nvim` launch; otherwise plugins
will fail in confusing ways during their initial build/install step.

### Required

| Tool                  | Why                                                                  |
|-----------------------|----------------------------------------------------------------------|
| **Neovim ≥ 0.12.0**   | nvim-treesitter's `main` branch requires it, and the config uses 0.12 features (`:restart`, `:lsp`, `'winborder'`). Checked at startup by the guard at the top of `init.lua`. |
| **git**               | Plugin install + auto-update.                                        |
| **tree-sitter CLI ≥ 0.26.1** | nvim-treesitter (`main`) builds every parser with it. See [Installing the tree-sitter CLI](#installing-the-tree-sitter-cli) below. Without it only Neovim's bundled parsers highlight. |
| **`tar` and `curl`**  | nvim-treesitter downloads parser sources with them. Both ship with Windows 10+ and every Linux/macOS. |
| **A C compiler**      | Each parser is compiled to a `.so`/`.dll`. On Windows the MSVC Build Tools are found automatically (they don't need to be on `PATH`); to use LLVM instead, install it and set `CC=clang`. Compiler errors during `:TSInstall` / `:TSUpdate` always trace back here. |
| **A Nerd Font**       | Icons in bufferline / lualine / telescope / neo-tree. Grab one from <https://www.nerdfonts.com>; set it as your terminal font (not just shell). |

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
| `fd`        | First choice of the file finders (`<leader>ff`, `<leader>Ff`); without it they list files with `rg --files` |
| `node`      | Many LSP servers (`ts_ls`, `pyright`, `bashls`, `jsonls`, `yamlls`, `html`/`cssls`) and `prettierd` are JS-based |
| `python` / `python3` | Mason installs `clang-format` and `debugpy` from PyPI, and `pyright`/`debugpy` work against your real Python |
| `cargo` / `rustup`   | Rust toolchain itself — `rust_analyzer` ships via Mason, but `rustfmt` and `cargo` come from rustup. (blink.cmp needs no cargo: it downloads a prebuilt fuzzy matcher, else falls back to its Lua matcher with a warning.) |
| `lazygit`   | `<leader>tg` floating lazygit terminal                                  |
| `make` or `cmake` | Builds `telescope-fzf-native` (native C sorter). The spec auto-detects which is on PATH: it prefers `make`, whose Makefile calls **`gcc`** (on Windows that means MinGW — `scoop install mingw`), else falls back to `cmake` (needs CMake + a C toolchain — e.g. the MSVC Build Tools). If the build fails, telescope still works with its Lua sorter. `make` also runs the test suite (`make test`). |
| `gdb` or `lldb` | DAP debugging of native code (C / C++ / Rust). gdb on Linux/Windows, lldb on macOS. codelldb is auto-installed by Mason as a third option. |

#### Per-language quick guide

What you need installed before nvim is useful for that language:

| Language | Required runtime  | Auto-installed via Mason            | DAP adapter (Mason)       |
|----------|-------------------|-------------------------------------|---------------------------|
| C / C++  | `gcc`/`clang` + `gdb` or `lldb` | `clangd` (LSP), `clang-format` (formatter) | `cppdbg`, `codelldb` |
| Rust     | `rustup` (gets you `cargo`, `rustfmt`) | `rust_analyzer` (LSP) — `rustfmt` comes from rustup, not Mason | `codelldb` |
| Python   | `python` (Windows) / `python3` | `pyright` (LSP: types), `ruff` (LSP: lint + import sort, AND conform formatter) | `debugpy`     |
| Lua      | (none — Neovim ships its own) | `lua_ls` (LSP), `stylua` (formatter) | (no DAP)         |
| Bash     | `bash`            | `bashls` (LSP), `shfmt` (formatter) | `bashdb`                  |
| Scheme   | a Scheme impl (guile / chez / racket) | — treesitter highlighting only; no LSP and no formatter exist | (no DAP) |
| Batch    | (Windows shell)   | — nothing exists (no LSP, formatter, or parser) | (no DAP)      |
| JS / TS  | `node` + `npm`    | `ts_ls` (LSP); `prettierd` (formatter) | (disabled by default — see `lua/plugins/dap.lua` to re-enable) |
| Go       | `go` (rustup-style installer) | `gopls` (commented out — uncomment in `lsp.lua`) | (disabled by default) |
| Markdown | (none)            | `marksman` (LSP); `prettierd` (formatter) | (no DAP)         |

The `mason-tool-installer` spec in `lua/plugins/formatting.lua` installs
`stylua`, `clang-format`, `shfmt`, `prettierd` and `shellcheck` (bashls
needs it for diagnostics), plus the four debug adapters `debugpy`,
`codelldb`, `cpptools` and `bash-debug-adapter`. `ruff` and `taplo` arrive
with their language servers (mason-lspconfig's list in
`lua/plugins/lsp.lua`), and `rustfmt` rides along with the rustup
toolchain and is found on `PATH`. For anything else, add the Mason
package name to one of those lists, or run `:MasonInstall <name>` once.

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

`mingw` provides `gcc`, which `make` needs to build telescope-fzf-native
(its Makefile calls `gcc`). Without it, uninstall `make` so the spec falls
back to `cmake` with the MSVC Build Tools. Treesitter parsers are compiled
by the MSVC Build Tools (Visual Studio Build Tools, "Desktop development
with C++"), which are found automatically; with LLVM instead, `CC=clang`
must be set.

**macOS** (using Homebrew):

```sh
brew install neovim git tree-sitter ripgrep fd fzf node lazygit
brew install --cask font-jetbrains-mono-nerd-font
# Optional extras:
brew install bat stylua luacheck lldb
```

Whatever the OS: run `tree-sitter --version` (must be **0.26.1+**); see
[Installing the tree-sitter CLI](#installing-the-tree-sitter-cli) if it
fails. Keep stylua current (`:MasonToolsUpdate`): CI uses the latest
release, and an older one may format some lines differently.

Xcode Command Line Tools provide the C compiler (`xcode-select --install` if you haven't already).

**Linux** (Debian/Ubuntu, adapt to your package manager):

```sh
sudo apt install git build-essential curl ripgrep fd-find nodejs npm lazygit
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

`fd` is sometimes called `fdfind` on Debian-based distros; symlink or alias it as `fd` if so.

## Layout

```
nvim/
├── init.lua                  Entry point
├── lua/
│   ├── config/
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
│   │   ├── diagnostics.lua   :DiagnosticDump (hang triage)
│   │   ├── health.lua        :checkhealth config (external toolchain check)
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
│   ├── minimal_init.lua
│   ├── config_spec.lua
│   ├── bootstrap_spec.lua     locked first-boot plugin manager
│   ├── prose_undo_spec.lua  prose mapping cleanup after filetype changes
│   ├── buffer_lifecycle_spec.lua  buffer deletion under reentrant autocmds
│   ├── buffer_menu_split_spec.lua  buffer menu splits from file windows
│   ├── session_ui_visibility_spec.lua  preserve visible debugger layouts on save
│   ├── dap_ui_lifecycle_spec.lua  shared debugger UI across sessions
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
│   ├── audit-2026-10-21.md     findings, regressions, sources, and limits
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
├── .luacheckrc               luacheck config
├── stylua.toml               stylua config
├── .githooks/                tracked git hooks (pre-commit → luacheck + stylua + doc-sync)
├── .github/workflows/ci.yml  CI: luacheck, stylua, doc-sync, specs (nvim stable; scoper also on Windows)
├── Makefile                  test / lint / fmt-check / check / check-docs / format / all / ci / hooks
├── scripts/
│   ├── check-docs.sh             doc-sync guards: tree, keymaps, commands, plugins, version floor, templates, health
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

To remove any of them, delete its block from the relevant file and run
`:Lazy clean`.

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

In order — each step assumes the previous succeeded.

1. **Install the prerequisites** from the Prerequisites section above.
   Verify each is on PATH in a fresh shell before continuing:
   ```
   nvim --version       # ≥ 0.12.0
   git --version
   tree-sitter --version   # ≥ 0.26.1, and not the npm package
   tar --version; curl --version   # both ship with Windows 10+
   cc --version         # or clang --version; on Windows the MSVC Build Tools needn't be on PATH
   rg --version         # ripgrep (recommended)
   fd --version         # (recommended)
   ```
   If any of these come back "not found", fix that first — lazy.nvim's
   build steps assume they're available.

2. **Extract this config** into the parent folder for your OS (table at
   the top; commands in
   [docs/workflows/install-update-uninstall.md](docs/workflows/install-update-uninstall.md)).
   Move an existing config aside first. No internet on this machine? Install an offline seed built elsewhere
   instead of steps 3–7: [docs/workflows/offline-install.md](docs/workflows/offline-install.md).

3. **Launch `nvim`.** lazy.nvim will clone itself and every plugin —
   a flurry of progress messages, then the lazy.nvim UI. Let it run to
   completion (30–60 seconds on a fresh install).

4. **Quit and relaunch.** Some plugins finalize on the second boot.

5. **Run `:checkhealth`** and address any "missing executable" notes.
   The most common offenders are Nerd Font, ripgrep, and node. Single-
   plugin variants (`:checkhealth nvim-treesitter`, etc.) narrow the
   focus.

6. **Let the treesitter parsers build.** On first start the config
   installs every parser in its list in the background; that takes a
   minute or two. Compiler errors there mean the C compiler check in
   step 1 was wrong. `:TSInstall <lang>` retries one parser (`:TSUpdate`
   only updates parsers that are already installed).

7. **Run `:Mason`** to verify LSP servers, formatters, and DAP adapters
   from `ensure_installed` finished installing. If anything is missing,
   `:MasonInstall <name>` to retry.

8. **Open a Lua file** and confirm completion + `gd` (go-to-definition)
   work. This is the smoke test that the LSP stack came up correctly.
   If it doesn't work in Lua, no other language will either.

### Stuck during setup?

- Mason package failing to install → open `:MasonLog` for the actual
  error. Most failures are missing-toolchain (no `go`, no `node`, no C
  compiler) or network/proxy issues.
- Plugin reports an error you don't recognize → `:Lazy log` shows the
  recent operations; in `:Lazy`, `<CR>` on a plugin shows its branch,
  commit and directory. If a plugin's on the wrong branch or commit,
  see "Clearing caches" below.
- A parser build fails with `Lock file '…tree-sitter…\lock\<lang>-….lock'
  appears stale` → Neovim was closed while that parser compiled (gitcommit
  takes a few minutes). With no `tree-sitter` process running, delete that
  one lock file (in `%LOCALAPPDATA%\tree-sitter\lock\` on Windows,
  `~/.cache/tree-sitter/lock/` on Linux and macOS) and `:TSInstall <lang>`
  again.
- Treesitter parsers won't compile → almost always the C compiler or
  tree-sitter CLI prerequisite. `:checkhealth config` checks both
  (it flags an npm or pre-0.26.1 CLI); then `:TSInstall <lang>`
  retries. On Windows the MSVC Build Tools are found automatically;
  with LLVM instead, `CC=clang` must be set.
- LSP server not attaching → `:checkhealth vim.lsp` shows the per-buffer
  status. If it shows "no clients", confirm the server is in Mason's
  installed list (`:Mason`).
- Everything else → `:DiagnosticDump` writes a snapshot of all the
  above plus the LSP log tail to `stdpath('log')`; attach when asking
  for help.

## Common tweaks

- **Change colorscheme**: edit `lua/plugins/colorscheme.lua`,
  change `flavour` to `"latte"` / `"frappe"` / `"macchiato"` / `"mocha"`,
  or replace the catppuccin block with a different scheme entirely
  and update the `vim.cmd.colorscheme(...)` call.
- **Format on save** (off by default): in `lua/plugins/formatting.lua`,
  uncomment the `format_on_save = function(bufnr) … end` block (it honours
  `:FormatToggle`) **and** add `event = { "BufWritePre" }` to the conform
  spec. Without the event, conform loads only on `:ConformInfo` or its
  keys, so `:w` wouldn't format until something else had loaded it.
- **Big-file threshold**: files larger than `vim.g.big_file_size` bytes
  (default 1 MB) open in big-file mode: no treesitter, regex syntax, swap,
  folding (ufo included) or LSP, and no whitespace trim on save.
  Set it in your own config or live: `:let g:big_file_size = 5000000`.
- **Treesitter parsers on demand**: opening a filetype whose parser isn't
  installed builds it in the background (needs the tree-sitter CLI; once
  you install the CLI, the next buffer of that filetype starts the build).
  A failed build is retried after 5 minutes at the earliest.
  `vim.g.treesitter_auto_install = false` turns that off.
- **Plugin versions**: `lazy-lock.json` pins every plugin to the commit
  this config was last tested against. Commit it; `:Lazy restore` returns
  to those pins after an update goes wrong, and `:Lazy update` moves them
  forward (and rewrites the file). CI's plugin cache is keyed on it.
- **Add an LSP**: append the server name to `ensure_installed` in
  `lua/plugins/lsp.lua`. Mason picks it up next launch.
- **Add a treesitter parser**: same idea, in `lua/plugins/treesitter.lua`;
  `:TSInstall <lang>` builds it right away.
- **Disable smear-cursor / neoscroll**: motion can be distracting; add
  `enabled = false` to its spec in `lua/plugins/editor.lua` (or remove the
  block and run `:Lazy clean`). Don't delete the file: it holds several
  other plugins.
- **Re-enable implicit system clipboard**: by default this config keeps
  Vim's unnamed register separate from `"+"` so `dd` / `cc` / `x` don't
  clobber the OS clipboard — at the cost of needing `"+y` / `"+p` for
  clipboard access. To restore the convenient-but-leaky `clipboard =
  "unnamedplus"` behaviour, uncomment the line so labelled in
  `lua/config/options.lua`.
- **Per-project config (`exrc`)**: `exrc` is **on** (`lua/config/options.lua`),
  so a `.nvim.lua` (or `.nvimrc` / `.exrc`) in the current directory **and
  in every parent directory** runs at startup — handy for pinning a
  clangd `-std`, seeding a scoper scope, or setting `makeprg` per repo.
  A trusted file in a parent (your home folder, say) therefore applies to
  every project below it; a file that sets `vim.o.exrc = false` stops the
  search above it. It is **trust-gated**: Neovim never runs an untrusted
  file, prompting `(i)gnore / (v)iew / (d)eny` and remembering your
  `:trust` decision by content hash — choose `(v)iew`, read the file,
  then `:trust` it; `:trust ++remove` in that buffer revokes it. It
  is *not* a sandbox, though — a trusted `.nvim.lua` runs with full power, so
  only `:trust` project files you'd run by hand. Turn it off with `vim.o.exrc
  = false`. Full security rationale is in the `exrc` block comment in
  `options.lua`.
- **Disable in-buffer Markdown rendering**: `:RenderMarkdown toggle`, or
  remove the render-markdown block from `lua/plugins/editor.lua`.

## Health checks

Run `:checkhealth` for a top-down view. Start with this config's own check:

- `:checkhealth config` — this config's own check; run it first. It covers,
  in order: **Neovim** (the version floor), **Core prerequisites** (a C
  compiler, `git`, the **tree-sitter CLI** — required, 0.26.1+ and not the
  npm package; nvim-treesitter's `main` branch builds every parser with
  it — plus `curl`/`wget` and
  `tar`; Mason can't supply these), **Runtime state
  directories** (swap, and undo when `undofile` is on, must be writable),
  **Search & pickers** (`rg`, `fzf`, `fd`), the **C/C++ toolchain**
  (`clangd`, `clang-format`, `clang-tidy`), **Language runtimes** (`node`,
  Python 3 as `python3` or `python`, `cargo`; fzf older than 0.45 is flagged because some fzf-lua
  pickers need newer), **Dev & test tooling**, and **Mason-managed servers /
  formatters / debug adapters** (deferred to `:checkhealth mason` rather
  than duplicated here). It flags what's missing or the wrong version, and
  notes when `'exrc'` is on (project `.nvim.lua` files run once `:trust`ed).
  (Implemented in `lua/config/health.lua`.)

Useful single-plugin variants:

- `:checkhealth lazy`
- `:checkhealth nvim-treesitter`
- `:checkhealth mason`
- `:checkhealth telescope`
- `:checkhealth vim.lsp` (`:checkhealth lsp` is the same report)

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
make ci           # the targets CI runs (check + check-docs + test + test-scoper + test-seed), with your local tools
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
nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
cd scoper.nvim && nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }" && cd ..
luacheck init.lua lua tests
stylua --check init.lua lua tests
```

Windows PowerShell 5.1 has no `&&`, so the scoper line becomes:

```powershell
Push-Location scoper.nvim; nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"; Pop-Location
```

(`sh scripts/check-docs.sh` needs a POSIX shell such as Git Bash.)

## Terminal & multiplexer notes

A few behaviours that look like config bugs are really limitations of the
terminal emulator or multiplexer underneath Neovim. Collected here so they
don't have to be rediscovered.

### `<C-Space>` and other "modified special key" combos

Neovim can only see `<C-CR>`, `<S-CR>`, `<C-Tab>` and similar
combinations if the terminal encodes them, which requires the **kitty
keyboard protocol** (aka CSI-u / "fixterms"). Terminals that speak it:
WezTerm, kitty, Alacritty, and recent Windows Terminal. The legacy Windows
console (`conhost`, the default `cmd.exe` window) does **not**, and a
multiplexer in the middle can swallow the encoding even when the outer
terminal supports it.

`<C-Space>` needs no protocol in most terminals: they send it as a NUL
byte, which Neovim reads as `<C-Space>`. On the Windows console (and
zellij/tmux running over it), though, Ctrl+Space can arrive as a bare
`<Space>` — i.e. it behaves like `<leader>` — so a mapping on `<C-Space>`
silently does the wrong thing. That's why completion (blink.cmp) is also
reachable through **`<C-n>` / `<C-p>`** in this config, which every terminal
can send. See `docs/cheatsheets/keymaps.html` and the completion section of
`docs/cheatsheets/vs-to-nvim.html`.

If you want the modified combos to work: use one of the terminals above, and
if you run a multiplexer make sure it passes the protocol through (zellij and
tmux both need reasonably recent versions).

### Mouse drag-select and scroll under zellij

With `mouse = "a"` (the default here) Neovim handles the mouse itself. Under
**zellij** specifically, two rough edges are upstream multiplexer
limitations, not config problems:

- **Drag-select doesn't auto-scroll symmetrically** — dragging past the top
  or bottom edge scrolls unevenly or not at all.
- **The scroll wheel restarts/clears an in-progress selection** instead of
  extending it.

The config's mouse handling is deliberately vanilla — `mouse = "a"` with no
wheel or drag remaps and neoscroll bound only to keyboard motions
(`<C-u>` / `<C-d>` / `<C-f>` / `<C-b>` / `<C-y>` / `<C-e>`), so there's
nothing here to change. Workarounds:

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
errors — there are four levels of reset, ordered least to most
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
| `stdpath('data')`   | `%LOCALAPPDATA%\nvim-data`   | `~/.local/share/nvim`    | Plugins (lazy), Mason packages, parsers, sessions, undo, swap |
| `stdpath('state')`  | (same as data)               | `~/.local/state/nvim`    | shada, logs                                           |
| `stdpath('cache')`  | `%TEMP%\nvim`                | `~/.cache/nvim`          | luac bytecode cache, parser downloads, scoper's compile_commands copies |
| `stdpath('log')`    | (same as data)               | `~/.local/state/nvim`    | lsp.log, DiagnosticDump output                        |

The Unix commands below run unchanged in bash, zsh and fish.

### Level 1 — just the cache (safe, fixes most "stale" issues)

This is what people usually mean by "clear cache". Lua bytecode and
treesitter compile artifacts are regenerated on next launch — nothing
gets re-downloaded.

```powershell
# Windows — quit nvim first.
Remove-Item -Recurse -Force "$env:TEMP\nvim"
```

```sh
# Linux / macOS — quit nvim first.
rm -rf ~/.cache/nvim
```

### Level 2 — cache + logs + shada/state, keep plugins & Mason

Deeper reset; preserves the big downloads (plugins, Mason packages).

```powershell
Remove-Item -Recurse -Force "$env:TEMP\nvim"
Remove-Item -Force "$env:LOCALAPPDATA\nvim-data\*.log" -ErrorAction SilentlyContinue
Remove-Item -Force "$env:LOCALAPPDATA\nvim-data\shada\*" -ErrorAction SilentlyContinue
```

```sh
rm -rf ~/.cache/nvim
rm -f ~/.local/state/nvim/*.log
rm -f ~/.local/state/nvim/shada/*
```

### Level 3 — nuclear: everything except config

Wipes plugins, Mason, sessions, breakpoints, the lot, **including swap
files with unsaved work**: run `nvim --clean -r` first and recover
anything marked "modified: YES" ([docs/workflows/swap-files.md](docs/workflows/swap-files.md)).
Next launch
re-clones every plugin and recompiles every parser. Slow (1–2 minutes
on first nvim launch), but reliably gets you back to a clean state.

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
  Undo history, ShaDa, sessions and logs grow forever too:
  [docs/workflows/state-files.md](docs/workflows/state-files.md).

- **Lazy plugin clean / reinstall** — `:Lazy clean` (removes plugins no
  spec uses) or `:Lazy restore` (back to the `lazy-lock.json` commits)
- **Single plugin reinstall** — quit, delete just that plugin's folder
  (`Remove-Item -Recurse -Force "$env:LOCALAPPDATA\nvim-data\lazy\<plugin>"`,
  or `rm -rf ~/.local/share/nvim/lazy/<plugin>`), relaunch
- **Mason packages** — `:Mason` → `X` on a package, or `:MasonUninstallAll`
- **Treesitter parsers** — `:TSUninstall <lang>` then `:TSInstall <lang>`
  (`:TSUpdate` never installs a missing parser); after `:TSUninstall all`,
  restart and the config reinstalls its parser list
- **Sessions** — `:AutoSession delete` for the current project. Behaviours
  worth knowing:
  - Started **with file arguments** (`nvim foo.c`), the session is only
    auto-saved if the work grew to 2+ file buffers or 2+ tabs, so a quick
    one-file edit never overwrites the project's session.
  - Home, Downloads, the temp dirs and the filesystem root never get an
    automatic session (both slash styles on Windows).
  - A window whose file doesn't exist on disk yet (a never-written new
    buffer) is closed before saving — if it was a tab's only window, that
    tab is not in the session.
  - Saving while debugging (`:AutoSession save`, switching sessions)
    keeps the debug session running; dap-ui closes for the save and
    reopens. Quitting still terminates the debuggee.
- **shada** (marks, registers, command history) — delete
  `main.shada` in the `shada` folder of `stdpath('state')`
  (`%LOCALAPPDATA%\nvim-data\shada\`, `~/.local/state/nvim/shada/`)

### What clearing does and doesn't fix

- **Stale cache** (level 1) fixes weird highlighting after an update,
  treesitter parsers that won't recompile, post-update Lua oddities.
- **Wrong plugin code** (a `branch` or `commit` change that didn't take)
  needs level 3 or a targeted single-plugin reinstall — *not* level 1,
  because the cache isn't what's wrong, the checked-out code is.
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

Run `:DiagnosticDump`, attach the file. Done.

### When nvim is *fully* hung

`:DiagnosticDump` can't run if nvim isn't taking input. The workflow:

1. **Try `<C-c>` first** — interrupts whatever's blocking. If it
   unhangs, immediately run `:DiagnosticDump` while you can.
2. **Open Task Manager / Process Explorer** and look at `nvim.exe`:
   - high CPU → likely treesitter or a tight-loop autocmd
   - low CPU → blocked on I/O (LSP, network, antivirus, slow disk)
3. **Force-kill nvim**, then restart in the same project.
4. **Run `:DiagnosticDump`** in the fresh nvim — the dump points at the
   LSP log, which is what we want from the previous session (it
   persists across kills).
5. Send the dump file + a note about what you were doing when it hung.

For especially nasty hangs on Windows, [ProcDump](https://learn.microsoft.com/sysinternals/downloads/procdump)
captures a memory snapshot of the still-frozen process so the call
stacks of every nvim thread are recoverable: `procdump -ma <pid>`.
Heavyweight; rarely necessary.

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
| Hang after autocomplete pause | LSP request stalled | `:checkhealth vim.lsp`, then `:lsp restart <name>` |
| Windows: Mason install fails with "tar: unrecognized option --no-same-owner" | Another tool's `tar` (Git/MSYS, vendor shells) is first on PATH | Handled automatically: when Mason loads, System32's `tar.exe` is copied to `stdpath("data")/tar-shim` and put first on PATH for Neovim (`vim.g.windows_tar_shim = false` to opt out). `:checkhealth config` shows which tar is used; then `:MasonInstall <pkg>` again |
| Hang on `:wq` after long session | session-save iterating thousands of buffers | `:lua print(#vim.api.nvim_list_bufs())` — if >500, something's leaking buffers |
| Sluggish typing | treesitter on a huge buffer | check `:DiagnosticDump`'s buffer table for big files with `ts=true` and `big_file=false` (the big-file guard isn't catching it) |
| Hang on git operation in a huge repo | gitsigns / diffview blocking | `:Lazy reload gitsigns.nvim` to confirm |
| Random multi-minute freezes on Windows | Defender scanning Mason packages | exclude `%LOCALAPPDATA%\nvim-data\mason\` from real-time scanning |
