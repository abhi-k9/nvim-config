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
| A file opened read-only by itself | Read the notice: it may have a live owner, an owner on another host, or an unreadable swap. Resolve that case before `:e!`. |
| You recovered a file | Save or discard, then `:SwapDelete` (the old swap stays until you do) |
| Leftovers keep piling up | `:SwapClean` reviews all swaps and deletes the ones that hold no work |
| Neovim won't start cleanly | `nvim --clean -r` lists swaps in the default search directories without loading the config |

## Where swaps live

Swaps go to `stdpath("state")/swap/` (Neovim's default `'directory'`):

| OS | Folder |
|---|---|
| Windows | `%LOCALAPPDATA%\nvim-data\swap\` |
| Linux, macOS | `~/.local/state/nvim/swap/` (`$XDG_STATE_HOME/nvim/swap/` when that is set) |

With `NVIM_APPNAME=foo` the `nvim` part becomes `foo`. To check on any
machine: `:echo &directory`. These are defaults, not a requirement: a custom
`'directory'` can contain several locations, including per-file `.` entries.
WSL and native Windows normally use separate swap folders.

A swap's name is the edited file's full path with `%` for every path
separator, plus `.swp`. When a swap with that name already exists, the
next one is `.swo`, then `.swn`, and so on. Examples:

| Swap name | Edited file |
|---|---|
| `C%%Users%me%proj%main.cpp.swp` | `C:\Users\me\proj\main.cpp` |
| `%home%me%proj%main.cpp.swp` | `/home/me/proj/main.cpp` |

Big files (over `vim.g.big_file_size`, default 1 MiB) are opened without a swap.

## When you open a file that has a swap

A guard in this config (`lua/config/autocmds/swap.lua`) replaces Neovim's
long E325 prompt. What happens depends on who owns the swap:

- **Another running Neovim** (same file open twice). The file opens
  read-only here, with a notice naming the other process. Finish there,
  quit that Neovim, then `:e!` here to take over. Don't force the write:
  two editors saving the same file overwrite each other's changes.
- **Another or unknown host.** The file opens read-only. A local process
  check cannot establish whether an editor is running on a different
  machine sharing the swap directory. Verify that editor is closed before
  taking over or deleting its swap.
- **A different Unix user.** Neovim's stock prompt remains in force; the
  guard does not choose for that owner.
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
  program). The guard avoids the stock E325 prompt during session restore. An empty
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

`:SwapClean` reads swaps in the scannable `'directory'` entries and sorts them into
two groups:

- **Delete:** no running owner and no unsaved changes, or empty and more
  than a minute old.
- **Kept, with the reason:** in use by a running Neovim, owned by another
  or unknown host, has unsaved
  changes (open the file and recover first), or unreadable but not empty
  (check it, then `:SwapDelete! <path>`). A change you undid before the
  crash still counts as unsaved: the swap keeps that flag.

It then shows both lists and asks once, with Cancel as the default.
Targets are rechecked after confirmation and again after decoding the final
header and checking its owner; a replaced or updated swap is kept.
This reduces accidental cleanup races, but is not an atomic lock
against an editor changing the path immediately before deletion.
Swaps of the Neovim you run it from are never listed. A swap whose
recorded process ID now belongs to an unrelated running program is kept
as "in use"; that errs on the safe side.
Per-file `.` or `./subdirectory` entries cannot be scanned globally, so they
are excluded from this inventory. Use `:SwapDelete` for the current file or an
explicit swap path when those locations need attention.

`:SwapDelete <path>` deletes one swap by path, for example a kept one you
have checked. Paste the path as `:SwapClean` shows it: file-name
completion is off for this command, because it would turn the `%` in swap
names into the current file's name. It only takes a swap: a regular file
(not a link or folder) named `*.swp`, `*.swo`, … whose header Neovim can
read, so a mistyped path can't delete an ordinary file. For an unreadable
swap, use `:SwapDelete! <path>`. An explicit bang also permits deleting a
swap from another or unknown host, after confirmation that its owner's
liveness cannot be checked here. Use it only after verifying that editor
is closed; `:SwapClean` never forces deletion of these swaps.

### From a shell, without the config

List swaps with their recorded file name, process ID and whether they
holds unsaved changes ("modified: YES"). This works the same on every OS
and doesn't start an editor:

```sh
nvim --clean -r
```

This clean invocation uses Neovim's default swap search directories; it does
not load a custom `'directory'` from this configuration. Check `:echo &directory`
in the configured editor when its swaps live elsewhere. Keep the same
`NVIM_APPNAME` and XDG environment when inspecting an alternate installation.

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

Delete a leftover by hand only after checking that its owner is closed and
the swap holds no needed unsaved work. A local process list cannot check an
owner on another host. Use the exact reviewed path, rather than clearing a
directory that may also contain unrelated files:

```powershell
# Windows: quit every Neovim first (terminals, VS Code, other sessions)
Get-Process nvim -ErrorAction SilentlyContinue   # check local instances
Remove-Item -LiteralPath 'C:\exact\reviewed\swap.swp' -Confirm
```

```sh
# Linux / macOS: quit every Neovim first (tmux panes, SSH sessions)
pgrep -l nvim                                    # check local instances
rm -i -- '/exact/reviewed/swap.swp'
```

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
