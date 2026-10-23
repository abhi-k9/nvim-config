# Offline install: plugins, Mason tools and parsers without internet

A normal first start downloads about 50 plugins, 22 Mason packages and 29
treesitter parsers. On a machine without internet access, install an
**offline seed** instead: one archive with all of them, built on a machine
where the config already works. `scripts/offline-seed.py` builds, checks and
installs it. It needs only Python 3.8+ (standard library) and runs the same
from fish, bash, zsh, PowerShell or cmd.

Below, `python3` stands for your Python: on Windows that's usually `py -3`
or `python`.

## What the offline machine needs

- Neovim 0.12 or newer, ideally the version the seed was built with (the
  manifest records it).
- The config zip **and** a seed built for the **same OS and CPU**. Mason's
  tools and the compiled parsers and plugin binaries (blink.cmp's matcher,
  telescope-fzf-native) are native code. A Windows seed doesn't work on
  Linux or macOS, and an x64 seed doesn't work on arm64.
- Python 3.8+ to run the installer. Mason's PyPI tools (`debugpy`,
  `clang-format`) run in their own virtual environments and need the
  **same major.minor Python** as the build machine (the installer says
  which). The installer points them at the local Python itself.
- `node` on PATH for the npm-based Mason tools: pyright, ts_ls, bashls,
  jsonls, yamlls, html, cssls, prettierd.
- **Not** needed: git, curl, tar, the tree-sitter CLI, a C compiler. They're
  only used to download or build, which the seed has already done.

## 1. Build the seed (on a machine with internet)

1. Install the config as usual (README, First-time setup checklist) and let
   the first start finish: plugins, Mason tools and parsers. The `gitcommit`
   parser takes a few minutes to compile; don't quit Neovim before it's done.
2. Check that nothing is still pending. Run this from the config folder
   (`~/.config/nvim`, or `%LOCALAPPDATA%\nvim` on Windows):

   ```sh
   python3 scripts/offline-seed.py check
   ```

   It prints `complete: …` (exit 0), or one `missing plugin|mason|parser
   <name>` line per gap (exit 1). Fix the gaps online (`:Lazy sync`,
   `:MasonToolsInstall`, `:TSInstall <lang>`) and check again. Exit 2 means
   the check itself couldn't run: `nvim` isn't on PATH, Neovim errored or
   didn't finish within 5 minutes, or it wrote no report. That never counts
   as complete.
3. Build:

   ```sh
   python3 scripts/offline-seed.py build --out-dir ~/transfer
   ```

   It writes `nvim-offline-seed_<os>-<arch>_lock-<hash>.zip` on Windows and
   `….tar.gz` on Linux and macOS. The tar.gz keeps executable bits and
   Mason's symlinks. `<hash>` is the start of `lazy-lock.json`'s SHA-256,
   so you can tell which config a seed belongs to. Expect around 450 MB.
   Next to it, `<seed>.sha256` holds the seed's SHA-256 (`sha256sum`
   format), which `build` also prints.

   `build` runs the same check as step 2 and stops if it finds gaps or
   can't run. It also stops if a plugin isn't checked out at its
   `lazy-lock.json` commit (`:Lazy restore` fixes that), and it re-reads the
   finished archive with the installer's own rules, so it never writes a seed
   that `install` would refuse.

   | Option | Effect |
   |--------|--------|
   | `--data-dir DIR` | Read another data folder than this config's `stdpath('data')` |
   | `--only lazy,site` | Pack only some parts (`lazy`, `mason`, `site`) |
   | `--allow-mismatch` | Pack anyway despite gaps or lockfile differences (warns) |
   | `--no-check` | Skip the Neovim-based completeness check |

Copy the config zip, the seed **and its `.sha256` file** to the offline
machine. A seed is executable code (plugins, Mason binaries, parsers), so
treat it like an installer. The `.sha256` file catches a damaged copy, but
someone who can swap the seed can swap that file too. If the seed passes
through hands or storage you don't control, write the hash down on the build
machine and pass it with `--sha256` on the offline one.

## 2. Install (on the offline machine)

1. Extract the config zip ([install-update-uninstall.md](install-update-uninstall.md),
   Install, step 3).
2. Install the seed into the data folder:

   ```sh
   python3 ~/.config/nvim/scripts/offline-seed.py install ~/transfer/nvim-offline-seed_linux-x64_lock-60c75712.tar.gz
   ```

   On Windows (PowerShell):

   ```powershell
   py -3 $env:LOCALAPPDATA\nvim\scripts\offline-seed.py install D:\transfer\nvim-offline-seed_windows-x64_lock-60c75712.zip
   ```

   What the installer does, in order, stopping at the first problem:

   1. Compares the seed's SHA-256 with `--sha256`, or else with the
      `.sha256` file next to it. With neither, it stops.
   2. Checks the seed was built for this OS and CPU, and from this config's
      `lazy-lock.json`. Manifest metadata is limited to 1 MiB before JSON
      decoding, independently of the archive's file-size limits.
   3. Checks every entry before writing anything. Each one must sit under
      `lazy/`, `mason/` or `site/`, or be the manifest. These are refused:
      absolute, `..`, drive-letter or backslash paths; duplicates; devices;
      links that point out of the seed (except the Python links inside Mason
      venvs, which step 6 re-points); entries written through a link; and
      seeds over the size limits or larger than the free disk space.
   4. Unpacks into a new `.offline-seed-staging-*` folder inside the data
      folder.
   5. Moves `lazy/`, `mason/` and `site/` from there into place. With
      `--force`, any existing ones are first moved, not merged, to
      `offline-seed-backup-<date>-*/` in the data folder. This includes a
      link named `lazy`, so nothing is ever written through it. If a move
      fails (usually because a running Neovim holds a file), every move is
      undone and the data folder is left as it was.
   6. Re-points Mason's Python venvs at this machine's Python. On POSIX it also
      rebases recognized console-script launchers to the installed venv,
      including paths with spaces. On Windows it rebases recognized unsigned
      distlib `.exe` launchers, preserving their native stub and embedded script.
      New seeds record the builder venv path for exact relocation; older seeds
      need an unambiguous venv creation command in `pyvenv.cfg`. Signed, custom,
      ambiguous or oversized Python launchers are left intact and reported as
      incomplete. Reinstall those packages at the final path. An incomplete
      repair exits with an error after installation; any previous data remains
      in the backup. General virtual environments are not fully portable.

   | Option | Effect |
   |--------|--------|
   | `--data-dir DIR` | Install into another data folder than this config's `stdpath('data')` |
   | `--force` | Replace existing `lazy/`, `mason/`, `site/` (the old ones go to the backup folder) |
   | `--sha256 HEX` | The hash to expect, from a source you trust (default: the `.sha256` file) |
   | `--no-verify` | Skip the checksum comparison (for a seed you built yourself without one) |
   | `--allow-lock-mismatch` | Install a seed built from another `lazy-lock.json`: plugins run at the seed's commits, and `:Lazy restore` needs the network |
   | `--allow-platform-mismatch` | Install a seed built for another OS or CPU (its native tools won't run) |
   | `--max-total-mb N`, `--max-file-mb N`, `--max-entries N` | Size limits (defaults 16384, 4096, 1000000; a real seed is about 1.3 GB unpacked, about 50,000 entries) |
3. Start `nvim`. Nothing should download: no lazy.nvim install window, no
   "Downloading tree-sitter-…" messages. `:Lazy` and `:Mason` show
   everything installed.

The data folder is `stdpath('data')`:

| OS | Data folder |
|----|-------------|
| Windows | `%LOCALAPPDATA%\nvim-data\` |
| Linux | `~/.local/share/nvim/` |
| macOS | `~/.local/share/nvim/` |

`NVIM_APPNAME` and `XDG_DATA_HOME` change it, and the script follows both.
The installer also writes `offline-seed-manifest.json` there: build date,
platform, Neovim version, config commit, and the plugin commits and package
list.

## Keeping a seed current

Rebuild the seed after anything that changes what gets downloaded:
`lazy-lock.json` (plugin updates), the Mason lists (`lua/plugins/lsp.lua`,
`lua/plugins/formatting.lua`) or the parser list (`lua/plugins/treesitter.lua`).
Doc or keymap changes don't need a new seed. A new lockfile gives the seed a
new name, so an old seed next to a new config is easy to spot.

## What still needs the network

On the offline machine these fail, just as they would anywhere without a
connection: `:Lazy update` / `:Lazy sync` / `:Lazy restore` to another
commit, `:MasonInstall`, `:MasonToolsUpdate`, `:TSInstall` / `:TSUpdate`.
lazy.nvim's daily update check runs and fails quietly. To update, build a
new seed online and install it with `--force`. The old `lazy/`, `mason/`
and `site/` go to `offline-seed-backup-*/`; delete that folder once the new
seed works.
