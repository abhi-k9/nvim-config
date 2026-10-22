# Install, update and uninstall (Windows, Linux, macOS)

The config ships as a zip with one top-level folder, `nvim/`. You extract it
into the folder that *contains* Neovim configs, and it becomes the config
folder. Everything else (plugins, Mason tools, parsers, sessions, undo
history) lives in Neovim's own data, state and cache folders, which the
config fills on first start.

Commands are given for PowerShell (Windows) and for a Unix shell. The Unix
blocks run unchanged in bash, zsh and fish. For machines without internet,
see [offline-install.md](offline-install.md).

## Where things live

| What | Windows | Linux and macOS |
|------|---------|-----------------|
| Config (`stdpath('config')`) | `%LOCALAPPDATA%\nvim\` | `~/.config/nvim/` |
| Data: plugins, Mason, parsers, sessions, breakpoints, scopes (`stdpath('data')`) | `%LOCALAPPDATA%\nvim-data\` | `~/.local/share/nvim/` |
| State: undo, swap, views, ShaDa, logs (`stdpath('state')`) | same folder as data | `~/.local/state/nvim/` |
| Cache: Lua bytecode, scoper's compile_commands copies (`stdpath('cache')`) | `%TEMP%\nvim\` | `~/.cache/nvim/` |

`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME`
move these folders, on Windows too. `NVIM_APPNAME` renames them (see "Try it
next to your current config"). Inside Neovim, this shows the real paths:

```vim
:echo stdpath('config') . "\n" . stdpath('data') . "\n" . stdpath('state') . "\n" . stdpath('cache')
```

## Install

1. Install the prerequisites (README, Prerequisites; there are per-platform
   recipes there).
2. If you already have a Neovim config, move it out of the way. If it came
   from another setup (a distribution, packer, vim-plug), move its data,
   state and cache aside too, so old plugins don't mix with these.

   ```powershell
   Move-Item "$env:LOCALAPPDATA\nvim" "$env:LOCALAPPDATA\nvim.bak"
   Move-Item "$env:LOCALAPPDATA\nvim-data" "$env:LOCALAPPDATA\nvim-data.bak"   # other setups only
   ```

   ```sh
   mv ~/.config/nvim ~/.config/nvim.bak
   mv ~/.local/share/nvim ~/.local/share/nvim.bak      # other setups only
   mv ~/.local/state/nvim ~/.local/state/nvim.bak      # other setups only
   mv ~/.cache/nvim ~/.cache/nvim.bak                  # other setups only
   ```

3. Extract the zip into the parent folder (replace the file name with yours):

   ```powershell
   Expand-Archive .\nvim-config.zip -DestinationPath $env:LOCALAPPDATA
   # or, with the tar built into Windows 10+:  tar -xf nvim-config.zip -C $env:LOCALAPPDATA
   ```

   ```sh
   mkdir -p ~/.config
   unzip -q nvim-config.zip -d ~/.config
   ```

   `unzip` comes with macOS. On Linux, if it's missing, install it
   (`sudo pacman -S unzip`, `sudo apt install unzip`, `sudo dnf install unzip`),
   or use `bsdtar -xf nvim-config.zip -C ~/.config` or
   `python3 -m zipfile -e nvim-config.zip ~/.config`. The Python one doesn't
   keep executable bits: afterwards run
   `chmod +x ~/.config/nvim/.githooks/pre-commit ~/.config/nvim/scripts/offline-seed.py`.

   Check that you have `~/.config/nvim/init.lua` (or
   `%LOCALAPPDATA%\nvim\init.lua`) and not `nvim/nvim/init.lua`.
4. Start `nvim` and follow the README's First-time setup checklist.

### Try it next to your current config

`NVIM_APPNAME` runs a second config with its own data, state and cache, and
leaves your current setup untouched:

```powershell
Expand-Archive .\nvim-config.zip -DestinationPath "$env:TEMP\nvim-new"
Move-Item "$env:TEMP\nvim-new\nvim" "$env:LOCALAPPDATA\nvim-new"
$env:NVIM_APPNAME = 'nvim-new'; nvim     # this terminal only
```

```sh
mkdir -p /tmp/nvim-new && unzip -q nvim-config.zip -d /tmp/nvim-new
mv /tmp/nvim-new/nvim ~/.config/nvim-new
env NVIM_APPNAME=nvim-new nvim
```

Its folders are then `nvim-new`, `nvim-new-data` (Windows) or
`~/.local/share/nvim-new` and so on. Everything in these docs applies with
`nvim` replaced by `nvim-new`, and `scripts/offline-seed.py` follows the
config folder's name by itself. To make it permanent, set `NVIM_APPNAME` in
your shell profile (`set -gx NVIM_APPNAME nvim-new` in fish's
`config.fish`), or rename the folders to `nvim`.

## Update to a new zip

Your data folder is kept: sessions, undo history, ShaDa, breakpoints and
scoper scopes survive the update. Only the config folder is replaced.

1. Quit every Neovim instance, including ones in other terminals, tmux or
   zellij, and IDE terminals.
2. Move the current config aside. It keeps your own edits and the old
   lockfile for a rollback:

   ```powershell
   Move-Item "$env:LOCALAPPDATA\nvim" "$env:LOCALAPPDATA\nvim.bak"
   Expand-Archive .\nvim-config.zip -DestinationPath $env:LOCALAPPDATA
   ```

   ```sh
   mv ~/.config/nvim ~/.config/nvim.bak
   unzip -q nvim-config.zip -d ~/.config
   ```

3. Carry over your own changes, if you made any. Compare the two folders:

   ```sh
   git diff --no-index ~/.config/nvim.bak ~/.config/nvim
   ```

   On Windows, use `git diff --no-index "$env:LOCALAPPDATA\nvim.bak" "$env:LOCALAPPDATA\nvim"`.
   Or open single files side by side with `nvim -d old new`.
4. Start `nvim`. New plugins, Mason tools and parsers install by
   themselves. Then bring the plugins in line with the new config:
   - `:Lazy restore` checks out exactly the commits in the new
     `lazy-lock.json` (the set this release was tested with). Follow it with
     `:Lazy clean` to remove the plugins the new config dropped.
   - Or `:Lazy sync` updates every plugin to its latest commit, removes the
     dropped ones, and rewrites `lazy-lock.json`.

   `:MasonToolsUpdate` updates the Mason tools, and `:TSUpdate` the parsers.
5. Run `:checkhealth config`, and skim `CHANGES.md` for anything a release
   asks you to do by hand.
6. When you're happy, delete `nvim.bak`.

On a machine without internet, steps 1–3 are the same. For step 4, build a
new seed online and install it as the last section of
[offline-install.md](offline-install.md) describes.

### Roll back

Quit Neovim, move the new config aside, rename `nvim.bak` back to `nvim`,
start Neovim, and run `:Lazy restore`. That returns the plugins to the old
lockfile's commits, which needs the network. Offline, reinstall the old
seed with `--force`, or move `lazy/`, `mason/` and `site/` back from the
`offline-seed-backup-*` folder the new seed's install left in the data
folder.

```powershell
Move-Item "$env:LOCALAPPDATA\nvim" "$env:LOCALAPPDATA\nvim.new"
Move-Item "$env:LOCALAPPDATA\nvim.bak" "$env:LOCALAPPDATA\nvim"
```

```sh
mv ~/.config/nvim ~/.config/nvim.new && mv ~/.config/nvim.bak ~/.config/nvim
```

## Uninstall

1. Quit every Neovim instance. On Windows, Mason's tools and the LSP log are
   locked while Neovim runs, so the delete fails otherwise.
2. Optional: check for swap files that still hold unsaved work
   (`nvim --clean -r`, see [swap-files.md](swap-files.md)). Keep the
   sessions folder if you might come back.
3. Delete the four folders:

   ```powershell
   Remove-Item -Recurse -Force "$env:LOCALAPPDATA\nvim", "$env:LOCALAPPDATA\nvim-data"
   Remove-Item -Recurse -Force "$env:TEMP\nvim" -ErrorAction SilentlyContinue
   ```

   ```sh
   rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
   ```

   With `NVIM_APPNAME`, use that name instead of `nvim`.

Outside these folders, the config leaves only:

- the tree-sitter CLI's own cache (`%LOCALAPPDATA%\tree-sitter\`,
  `~/.cache/tree-sitter/`). Other tree-sitter users share it, so remove it
  only if nothing else needs it.
- files you copied from `docs/templates/` into your projects
  (`.clang-format`, `.clangd`, `.vscode/launch.json`, …).
- the prerequisites (ripgrep, fd, node, the tree-sitter CLI, …). Remove
  them with the package manager you installed them with.

Neovim itself is uninstalled separately (winget, scoop, pacman, brew, …).
