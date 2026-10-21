# Swap files: collisions, recovery and cleanup

`'swapfile'` is on in this config. While you edit, Neovim keeps unsaved
changes in a swap file, in one central folder rather than next to your
files.
A swap that outlives its Neovim (crash, killed terminal, closed SSH
session, power loss) is a *leftover*. It either holds work you can recover
or is junk you can delete. This page covers both, on Windows, Linux and
macOS.

Short version:

| Situation | Do this |
|---|---|
| A prompt says "Swap file found" | Read the default button: Delete (nothing unsaved), Open read-only (disk is newer), Recover (unsaved work) |
| A file opened read-only by itself | It's open in another Neovim. Close it there, then `:e!` |
| You recovered a file | Save or discard, then `:SwapDelete` (the old swap stays until you do) |
| Leftovers keep piling up | `:SwapClean` reviews all swaps and deletes the ones that hold no work |
| Neovim won't start cleanly | `nvim --clean -r` lists every swap without loading the config |

## Where swaps live

Swaps go to `stdpath("state")/swap/` (Neovim's default `'directory'`):

| OS | Folder |
|---|---|
| Windows | `%LOCALAPPDATA%\nvim-data\swap\` |
| Linux, macOS | `~/.local/state/nvim/swap/` (`$XDG_STATE_HOME/nvim/swap/` when that is set) |

With `NVIM_APPNAME=foo` the `nvim` part becomes `foo`. To check on any
machine: `:echo &directory`. WSL and Windows are separate machines here:
each has its own swap folder.

A swap's name is the edited file's full path with `%` for every path
separator, plus `.swp`. When a swap with that name already exists, the
next one is `.swo`, then `.swn`, and so on. Examples:

| Swap name | Edited file |
|---|---|
| `C%%Users%me%proj%main.cpp.swp` | `C:\Users\me\proj\main.cpp` |
| `%home%me%proj%main.cpp.swp` | `/home/me/proj/main.cpp` |

Big files (over 1 MB, see `bigfile.lua`) are opened without a swap.

## When you open a file that has a swap

A guard in this config (`lua/config/autocmds/swap.lua`) replaces Neovim's
long E325 prompt. What happens depends on who owns the swap:

- **Another running Neovim** (same file open twice). The file opens
  read-only here, with a notice naming the other process. Finish there,
  quit that Neovim, then `:e!` here to take over. Don't force the write:
  two editors saving the same file overwrite each other's changes.
- **No running owner: a leftover.** A one-line prompt offers
  Recover / Open read-only / Edit anyway / Delete swap / Quit, and the
  default button is picked for you:
  - **Delete** when the swap holds no unsaved changes. Take it.
  - **Recover** when it holds unsaved changes.
  - **Open read-only** when it holds unsaved changes *but the file on
    disk is newer* than the swap, so recovering would put older text over
    newer edits. Compare first (see below).
  - `Esc` quits without touching anything.
- **Unreadable swap** (empty, cut short by a crash, or from another
  program). No prompt, so a session restore never stops on it. An empty
  swap older than a minute is deleted; anything else opens the file
  read-only with a notice. Run `:SwapDelete`, then `:e!`.

`:SwapGuardToggle` switches to stock Neovim behaviour (edit anyway for a
running owner, the full E325 prompt otherwise) for the next collision.

## Recover unsaved work

1. Open the file and choose **Recover** (or start with `nvim -r <file>`).
   The buffer now holds the swap's text and is marked modified. Nothing
   is written yet.
2. Compare with the file on disk. This opens the saved version in a
   vertical split, in diff mode:

   ```vim
   :vert new | set bt=nofile | r ++edit # | 0d_ | diffthis | wincmd p | diffthis
   ```

   Close the split with `:q` when you're done (`:diffoff` in the other
   window if needed).
3. Keep the recovered text with `:w`, or throw it away with `:e!`.
4. **Delete the old swap: `:SwapDelete`.** Recovering doesn't remove it,
   so without this step the prompt comes back the next time you open the
   file. `:SwapDelete` finds the swap by the file name recorded inside it,
   shows the path and whether it has unsaved changes, and asks before
   deleting (Cancel is the default). It refuses a swap that another
   running Neovim is using.

Several leftovers for one file (`.swp`, `.swo`, …): start
`nvim -r <file>` from a shell; Neovim lists them and asks which one to
use. Recover, compare and save one at a time; `:SwapDelete` then lists
and deletes them together.

## Clean up leftovers

### Inside Neovim (all platforms): `:SwapClean`

`:SwapClean` reads every swap in the swap folder and sorts it into one of
two groups:

- **Delete:** no running owner and no unsaved changes, or empty and more
  than a minute old.
- **Kept, with the reason:** in use by a running Neovim, has unsaved
  changes (open the file and recover first), or unreadable but not empty
  (check it, then `:SwapDelete! <path>`). A change you undid before the
  crash still counts as unsaved: the swap keeps that flag.

It then shows both lists and asks once, with Cancel as the default.
Swaps of the Neovim you run it from are never listed. A swap whose
recorded process ID now belongs to an unrelated running program is kept
as "in use"; that errs on the safe side.

`:SwapDelete <path>` deletes one swap by path, for example a kept one you
have checked. Paste the path as `:SwapClean` shows it: file-name
completion is off for this command, because it would turn the `%` in swap
names into the current file's name. It only takes a swap: a regular file
(not a link or folder) named `*.swp`, `*.swo`, … whose header Neovim can
read, so a mistyped path can't delete an ordinary file. For an unreadable
swap, use `:SwapDelete! <path>`.

### From a shell, without the config

List every swap with its recorded file name, process ID and whether it
holds unsaved changes ("modified: YES"). This works the same on every OS
and doesn't start an editor:

```sh
nvim --clean -r
```

Look at the folder directly:

```powershell
# Windows (PowerShell)
Get-ChildItem "$env:LOCALAPPDATA\nvim-data\swap" | Sort-Object LastWriteTime |
  Format-Table LastWriteTime, Length, Name -AutoSize
```

```sh
# Linux / macOS
ls -lt "${XDG_STATE_HOME:-$HOME/.local/state}/nvim/swap"
```

Delete leftovers by hand only when **no Neovim is running** and
`nvim --clean -r` shows "modified: no" for them. To clear the whole
folder in that situation:

```powershell
# Windows: quit every Neovim first (terminals, VS Code, other sessions)
Get-Process nvim -ErrorAction SilentlyContinue   # must print nothing
Remove-Item "$env:LOCALAPPDATA\nvim-data\swap\*" -Force
```

```sh
# Linux / macOS: quit every Neovim first (tmux panes, SSH sessions)
pgrep -l nvim                                    # must print nothing
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/nvim/swap/"*
```

Swap names start with `%` or a drive letter, never a dot, so `*` matches
all of them, including the swaps of hidden files such as `.bashrc`.

**Before a "nuclear" reset** (README → Clearing caches, level 3, which
deletes the whole state folder): run `nvim --clean -r` first and recover
anything marked "modified: YES". The reset deletes those changes with
the rest.

## Avoid new leftovers

- Quit Neovim (`:qa`) before you close its terminal window or tab, end an
  SSH session, or shut down. Closing the window kills Neovim and leaves
  a swap for every open file.
- On Windows, a terminal tab killed by an update or a crash leaves
  swaps too. Run `:SwapClean` after such an event.
- Open a file in one Neovim only. Use `:e!` to take over once the other
  one has quit, rather than "Edit anyway".
- A file you never want swapped (a secret, a huge log): `:setlocal
  noswapfile` before you edit it.

## Diagnose

- `:checkhealth config` checks that the swap folder is writable. If it
  isn't, Neovim edits without a swap (E303) and there is nothing to
  recover after a crash.
- `:swapname` shows the current buffer's swap. It's empty after Edit
  anyway, Open read-only or Recover, which is why `:SwapDelete` searches
  by the name recorded inside each swap instead.
- More in [plugins.html → Swap files](../cheatsheets/plugins.html) and
  [workflows.html → Troubleshoot](../cheatsheets/workflows.html).
