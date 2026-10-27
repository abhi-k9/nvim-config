# Language tools and executable policies

Put machine choices in the ignored `local.lua` at the config root. Return a
table; the loader applies it before core behavior and Lazy activation. These
settings do not edit the shipped plugin specs or pin updates automatically.
Use normal Lazy spec overrides under `plugins` for other plugin options.

```lua
return {
  tools = {
    servers = { "lua_ls", "pyright", "ruff", "jsonls" },
    packages = { "stylua", "debugpy", { "prettierd", version = "0.29.0" } },
    parsers = { "lua", "python", "json", "markdown", "markdown_inline" },
    parsers_on_demand = false,
    formatters = {
      lua = { "stylua" },
      python = { "ruff_format" },
      c = {}, -- no Conform formatter for C; this does not stop core trimming
    },
  },
  lsp = {
    servers = {
      clangd = false,
      lua_ls = { settings = { Lua = { diagnostics = { globals = { "vim", "describe", "it" } } } } },
    },
    python = { organize_imports = "ruff", type_checking = "basic" },
  },
}
```

## Selection and merge rules

| Setting | Default | Meaning |
| --- | --- | --- |
| `tools.servers` | Existing `mason-lspconfig.nvim` list in `lua/plugins/lsp.lua` | Replace the requested installation list, using lspconfig server names. `name@version` preserves a Mason server pin. |
| `tools.packages` | Existing `mason-tool-installer.nvim` list in `lua/plugins/formatting.lua` | Replace the requested non-server Mason package list. Strings or Mason installer entries are accepted. A pin may use `name@version` or `{ "name", version = "version" }`. |
| `tools.parsers` | Existing parser list in `lua/plugins/treesitter.lua` | Replace startup parser requirements. An empty list disables this config's automatic parser builds, including first use and update hooks. Installed/bundled parsers can still highlight. |
| `tools.parsers_on_demand` | `true` | With a nonempty parser list, also install supported parsers when opening additional languages. Set `false` to keep automatic provisioning to the startup list. |
| `tools.formatters` | No overrides | Merge filetype keys into Conform defaults; each filetype value replaces its formatter list/options. `{}` disables that filetype's formatter list. |
| `tools.development` | Whether LuaLS or StyLua is selected | Include optional `luacheck`/StyLua development checks in health reporting. |
| `lsp.servers` | No overrides | Apply server configuration tables after shipped defaults and before the first automatic activation. A value of `false` suppresses installation from the server list and Mason automatic enable for that server. |

An absent list retains defaults; an empty list replaces it. To extend a list,
copy the desired shipped list and add entries, or use a native Lazy `opts`
function. Native plugin options retain their plugin's merge rules; they are
resolved before installer readiness filters run. Lazy handles appearance,
schemas, filetypes, Lua globals, completion providers and lazydev's contextual
libraries through these normal overrides. Lazydev continues loading libraries
only when a Lua buffer refers to them.

The server installation list and server activation are distinct Mason options.
Removing a server from `tools.servers` does not uninstall it or disable an
already installed server. Use `lsp.servers.NAME = false` for that, or override
`mason-lspconfig.nvim`'s `automatic_enable` with `false`, an allowlist, or an
`exclude` list. This preserves Mason's established installed-server behavior.

Tool entries may use `condition = false` or a function returning a boolean.
These are deliberate opt-outs: runtime installation, health reporting and seed
checking honor them. A prerequisite failure is different: it skips automatic
work quietly while the requested tool remains visible as unavailable. An
unavailable requested tool still makes an offline seed incomplete. Conflicting
enabled version requirements for the same Mason package raise a configuration
error before either installer is configured, including requirements added with
native Lazy `opts` functions and server/package aliases. Disabled conditions do
not conflict with enabled pins. Pinned seeds must contain
the requested installed version, not just a package directory.

Server/package aliases use metadata from an already loaded Mason-LSP bridge or
Mason registry, with the shipped server aliases as a fallback. Resolving intent
does not load the bridge or download registry metadata. Custom aliases therefore
need local registry metadata to be available for package identity, health and
cross-installer pin validation. Prerequisite checks cover the shipped known
packages; other selections retain Mason's upstream installer behavior.

The existing `globals = { treesitter_auto_install = false }` opt-out also
removes parser build prerequisites and offline parser requirements, even if a
nonempty parser list remains configured. This differs from missing compiler or
download prerequisites: requested parsers remain seed requirements when their
automatic provisioning is enabled but cannot run on this machine.

Selecting a language does not infer every formatter/debugger/parser package.
Keep the three lists coherent. Ruff's server and Conform formatters share one
binary; the shipped defaults install `ruff` only through the server list to
avoid concurrent installers. If disabling its server but retaining formatting,
request `ruff` in `tools.packages` instead.

## Python provider coordination

`lsp.python.ruff_hover` defaults to `false` when Pyright is selected and `true`
otherwise. `organize_imports` accepts `"ruff"`, `"pyright"` or `"none"`; its
default is Ruff when selected, then Pyright, then none. Pyright's import action
and Conform's Ruff import action follow that choice. `type_checking` accepts
`"basic"` (default), `"strict"` or `"off"`.

This retains hover/import functionality for a Ruff-only or Pyright-only stack.
Explicit `lsp.servers.pyright = false`/`ruff = false` also informs coordination.
If manually enabling providers outside these installation lists, set the policy
explicitly. Python formatting still requests `ruff_format` by default; replace
`tools.formatters.python` when using another formatter or no Ruff binary.

## Compiler and runtime discovery

```lua
return {
  tools = {
    executables = {
      compiler = "/opt/LLVM/bin/clang", -- Windows: [[C:\Program Files\LLVM\bin\clang.exe]]
      vswhere = [[D:\Visual Studio\Installer\vswhere.exe]],
      python = "/opt/python/bin/python3", -- optional health runtime probe
    },
    native_sorter_build = false, -- always retain Telescope's Lua sorter
  },
}
```

Executable values are literal program names/paths, not shell command strings
with flags. An explicit compiler wins over inherited `CC`, then normal compiler
discovery applies. The selected compiler is exposed through `CC` to tree-sitter.
Global project directory changes reconcile `CC` immediately: leaving a project
compiler restores the inherited value, preserving intervening external edits.
Window/tab directory changes do not change this process-wide environment.
An empty project `tools.executables = {}` also clears a machine compiler override.
For the native Telescope sorter, an explicit compiler uses CMake with literal
`-DCMAKE_C_COMPILER=...` argv when CMake is present, including paths with spaces.
On Unix, a compiler without spaces can also use the Makefile's `CC` interface.
Paths containing shell/Make/CMake metacharacters (such as `$`, `;`, `&` or `%`)
skip this optional native build and retain the Lua sorter: these backends generate
command text after the initial process launch. The compiler remains available to
tools with a literal executable-path interface. An explicit trusted build override
can provide a different supported backend.
Windows Make is selected automatically only for its own `gcc` default: that
Makefile overrides environment `CC`. CMake/MSVC remains the fallback. Existing
CMake build-directory caches retain CMake's own compiler rules; rebuild or clear
that plugin's build directory when switching toolchains.

`tools.native_sorter_build` may also be a Lazy build command string or build
function; explicit overrides are trusted and bypass automatic prerequisite
selection. Missing supported build tools select the Lua sorter quietly.
`tools.executables.vswhere` changes this config's bounded MSVC discovery probe;
tree-sitter/CMake retain their own Visual Studio discovery behavior. For a
nonstandard installation their native environment/toolchain setup is still
required. No third-party discovery implementation is patched.

`tools.executables.python` chooses an additional runtime health probe. Mason's
PyPI installer independently resolves canonical `python`/`python3` names on PATH;
an arbitrary custom interpreter path does not override that interface. The
installer readiness gate checks the same PATH candidates and venv/ensurepip,
rejecting Windows Store aliases. Add the intended Python installation to PATH
for Mason; use `debug.python` for the debugger's literal custom interpreter.
The health report explains this boundary instead of claiming the installer will
use the probe path.

## Missing tools, inspection and verification

Automatic installation remains enabled when prerequisites exist. Missing tools
do not repeatedly trigger known failing automatic builds. Explicit `:MasonInstall`
and `:TSInstall` remain available; they intentionally expose their own errors.
The existing customizable monthly health reminder continues to use
`:checkhealth config`; intentionally disabled packages are identified separately
from missing prerequisites. Mason package installation details remain under
`:Mason` / `:checkhealth mason`.

Inspect declared resolved lists with
`:lua vim.print(require("config.tool_intent").resolved())` and recorded skips
with `:lua vim.print(require("config.tooling").skipped())`. Declaration is read
before prerequisite filtering, so strict offline preflight cannot mistake a
minimal machine for a complete seed. `scripts/offline-seed-check.lua` shares
identity, pin and condition handling with runtime/health rather than maintaining
another server-name mapping policy.

Targeted regressions cover pins, disabled conditions, unavailable requested
packages, seed version mismatches, list replacement, empty parser opt-out,
provider combinations, literal compiler argv and first-client configuration.
Run `make test` and `make test-seed` from the documented test environment.

Relevant upstream contracts:

- [Mason automatic enable and server installation](https://github.com/mason-org/mason-lspconfig.nvim#configuration)
- [Mason tool installer conditions and versions](https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim#configuration)
- [Mason's Python discovery](https://github.com/mason-org/mason.nvim/blob/main/lua/mason-core/installer/managers/pypi.lua)
- [CMake compiler selection](https://cmake.org/cmake/help/latest/variable/CMAKE_LANG_COMPILER.html)
- [Telescope native sorter's Makefile](https://github.com/nvim-telescope/telescope-fzf-native.nvim/blob/main/Makefile)
- [Neovim LSP configuration](https://neovim.io/doc/user/lsp.html#vim.lsp.config())
- [Lazy plugin specification and options](https://lazy.folke.io/spec)
