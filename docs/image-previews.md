# Optional local-image previews

## Quick start

`:ImageOpen path/to/image.png` opens a local raster image. Tab completes file
names, including Vim's escaping for spaces and `%` / `#`; do not use shell quoting.
Relative paths use the invoking window's cwd, including `:lcd` / `:tcd`.
`:ImageOpen` without a path uses the current buffer's file name. It does not
infer a Markdown link or use Scoper's root/filter.

Terminal rendering is **off by default**. The command requests the system image
viewer instead. To enable terminal previews, merge this into the ignored root
`local.lua`, then restart Neovim:

```lua
return {
  images = {
    enabled = true,
    fallback = "external", -- or "notify": report a missing capability without opening an app
    timeout_ms = 15000,     -- positive integer, up to 3600000; async preparation deadline
  },
}
```

Install ImageMagick and use a compatible terminal (below), then run `:ImageOpen`
with an image path. `q` / Esc closes only the read-only preview; `e` closes it and
requests the system viewer for the original file. `:ImageOpen! [path]` requests
the system viewer directly, including when `fallback = "notify"`.
`:ConfigHelp images` reads this guide inside Neovim.

The pinned **snacks.nvim** checkout is installed with the plugin set, but stays
unloaded until a terminal preview is requested. Its other UI features are not
enabled. Disable/remove the checkout through a normal local Lazy override if
desired: `{ "folke/snacks.nvim", enabled = false }` under `plugins`. The command
and fallback still work. `:Lazy update snacks.nvim` explicitly moves the pin;
`:Lazy restore snacks.nvim` installs the revision in the **current on-disk**
lockfile. To undo an update, first recover the desired lockfile from Git or a
backup, then restore. See the [plugin-update and rollback workflow](workflows/install-update-uninstall.md#update-and-share-plugin-versions-git-checkout).

## Platforms and dependencies

Terminal graphics support is independent of the shell: choosing Bash, PowerShell
or cmd does not enable image rendering. This renderer uses the **Kitty Graphics
Protocol**, not Sixel or an ASCII approximation.

| Environment | Terminal preview | System-viewer fallback |
| --- | --- | --- |
| CachyOS / Ubuntu | Kitty or Ghostty; upstream also lists limited WezTerm support. | `xdg-open` and an image association in the desktop session. |
| macOS | Kitty or Ghostty; limited WezTerm support. Other terminals need compatible graphics support. | macOS `open` and the image's file association. |
| Native Windows | Upstream lists limited WezTerm support; verify the particular build/configuration. A Windows Terminal session without Kitty graphics falls back. | `rundll32.exe` with the system file association; no `cmd /c start` or filename interpolation. |
| WSL | Depends on the terminal serving Neovim. Install Linux ImageMagick inside WSL for conversion. | First available `xdg-open` or `wslview`; an opener still needs a working desktop/host association. |
| SSH / remote hosts | Kitty graphics must reach the terminal; Snacks sends image data when it detects SSH. | Runs on the Neovim host, which may have no desktop. Use `fallback = "notify"` in that case. |

WezTerm support is partial; detection is not a guarantee of correct rendering
in every build. Use `:ImageOpen!` if the result is incomplete. tmux needs graphics
passthrough; Snacks tries to enable passthrough for the pane during detection.
Zellij is unsupported by this renderer.

ImageMagick is required by this profile **even for PNG**, because the pinned
implementation uses its identification step for metadata. Linux/macOS can use
`magick` (ImageMagick 7), or `convert` + `identify` (ImageMagick 6). Windows
requires **`magick`**: Windows' own `convert.exe` is a disk utility.

Install separately, then restart the terminal/editor so PATH changes are visible:

| OS | ImageMagick installation |
| --- | --- |
| CachyOS / Arch | `sudo pacman -S imagemagick` |
| Ubuntu | `sudo apt install imagemagick` |
| macOS / Homebrew | `brew install imagemagick` |
| Windows / winget | `winget install --id ImageMagick.ImageMagick --exact` |

The config does not install these packages automatically. No LuaRocks, Lua
Magick binding, Rust, Node, LaTeX or diagram tool is needed for this profile.

## Scope, fallback and files

The command accepts existing, readable local PNG, JPEG, GIF, WebP, BMP, TIFF,
AVIF, HEIC and ICO files. Codec availability depends on the ImageMagick build;
animated/multi-frame formats use the renderer's first-frame preview. URLs, data
URIs, SVG, PDF, videos and executable paths are outside this command's scope.

This profile provides **explicit floating previews**. It does not install image
file read/write handlers, attach inline Markdown images, fetch remote document
images or render maths/diagrams. Opening or scrolling a document does not start
image tools. To inspect an image referenced by Markdown, run `:ImageOpen` with
its local path relative to the active cwd.

Previewing uses an asynchronous private temporary copy. It preserves the original
file and source buffer, handles literal special characters, and avoids stale
path-based renderer caches after an image changes. Closing the preview or
abandoning a request removes its snapshot. Neovim also cleans its private
temporary directory at exit. Decoded output/metadata uses Snacks' normal
`stdpath("cache")/snacks/image` cache; remove that directory with Neovim closed
when you want to reclaim space.

Detection and conversion run asynchronously. A new request cancels the previous
conversion. Source-window/buffer/cwd/mode changes discard a late result without
opening an app or stealing focus. The asynchronous preparation stages—terminal
detection, snapshot copying and conversion—share the `timeout_ms` deadline.
A copy already running in the OS may finish after cancellation; its completion
only removes that request's snapshot.
Unavailable plugins/APIs, missing tools, unsupported terminals and decoding
failures use the selected fallback. System-open failures give a useful message;
a successful opener process does not prove an associated GUI displayed the image.

## Troubleshooting and verification

Use `:checkhealth config`'s **Optional image previews** section. Disabled rendering
is informational; opted-in missing ImageMagick is reported. Upstream
`:checkhealth snacks` provides terminal diagnostics, but can list requirements for
other document features outside this profile. Headless editors and GUI frontends
without a compatible terminal use the selected fallback.

Tests cover the default unloaded state, absent prerequisites, malformed APIs,
headless commands, Windows/macOS/Unix opener argv, special filenames, snapshot
cleanup, cache freshness, cancellation, stalled detection/copy/conversion,
immediate I/O submission failures, corrupt images and scoped
closing. An ImageMagick + pinned Snacks fixture decodes images and captures
emitted graphics protocol with terminal detection simulated. Native Windows CI
also runs the standalone command/path fixture. These are not physical-terminal
visual tests on all three OSes; terminal builds, associations and graphical
sessions need local verification.

Source references: [Snacks image documentation](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/docs/image.md),
[conversion implementation](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/image/convert.lua)
and [terminal detection](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/image/terminal.lua).
