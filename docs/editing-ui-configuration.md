# Editing, UI and retention preferences

Put machine preferences in the optional, ignored `local.lua` beside `init.lua`.
It returns a table; do not edit the shipped plugin specs to make a local change.
See the main customization guide for loading, trust and project overlays.

```lua
return {
  editing = {
    trim_whitespace = false,
    trim_skip_filetypes = { "markdown", "diff", "text" },
    continue_comments = true,
    equalize_windows = false,
    prose_undo = {
      enabled = true,
      filetypes = { "markdown", "text", "gitcommit" },
      chars = { ",", ".", "!", "?", ";", ":" },
    },
  },
  mappings = { navigation = true },
  ui = { colorscheme = "habamax", icons = false, reduced_motion = true },
  retention = { views_days = 30, log_max_bytes = 10 * 1024 * 1024 },
}
```

## Content and navigation

| Setting | Shipped default | Behavior |
| --- | --- | --- |
| `editing.trim_whitespace` | `true` | Strip trailing whitespace on save. Accepts a boolean or `function(bufnr)` returning whether to trim the written buffer. |
| `editing.trim_skip_filetypes` | `{ "markdown", "diff" }` | Replace the filetype exception list. An empty list removes these configurable exceptions. |
| `editing.continue_comments` | `false` | When false, remove `c`, `r` and `o` from the filetype's `formatoptions`. When true, leave the filetype/user's flags alone; this does not force continuation in every filetype. |
| `editing.equalize_windows` | `true` | Equalize split sizes when Neovim receives `VimResized`. |
| `editing.prose_undo.enabled` | `true` | Create an insert-mode undo break after configured punctuation in configured prose filetypes. |
| `editing.prose_undo.filetypes` | `{ "markdown", "text", "gitcommit" }` | Replace the list of participating filetypes. An empty list disables participation. |
| `editing.prose_undo.chars` | `{ ",", ".", "!", "?", ";", ":" }` | Replace the list of single-character keys. An empty list creates no punctuation maps. |
| `mappings.navigation` | `true` | Install display-line `j`/`k`, centered `n`/`N`, horizontal Alt-h/Alt-l and the custom scrolling integration. Other editing, window and plugin mappings keep their own normal overrides. |

Trimming remains independent of Conform's `:FormatToggle`. Disable both when a
workflow should leave content entirely alone on save. A project EditorConfig
`trim_trailing_whitespace` value takes precedence over this trim hook in either
direction; Neovim's EditorConfig support performs a requested trim itself.
Binary, diff, read-only, nonmodifiable, special and large-file buffers remain
protected even with an empty exception list. Background writes operate on the
written buffer and preserve the ambient buffer and view.

For a selective policy, use a predicate instead of a global disable:

```lua
return {
  editing = {
    trim_whitespace = function(bufnr)
      return not vim.api.nvim_buf_get_name(bufnr):match("[/\\]generated[/\\]")
    end,
  },
}
```

Prose punctuation mappings are buffer-local. A later filetype or policy change
removes only maps that still have this configuration's RHS and description.
Independent buffer-local replacements are preserved. Like the original default,
a mapped punctuation character does not trigger an insert abbreviation for that
character. Each listed `chars` item must be a single character, not a key notation
such as `<CR>`.

## Themes, fonts and motion

`ui.colorscheme` defaults to `"catppuccin"`. The Catppuccin variants, such as
`"catppuccin-latte"`, use the same plugin. A stock scheme, such as `"habamax"` or
`"retrobox"`, disables that plugin and activates the stock scheme during plugin
configuration. Bufferline falls back to its generic highlights; lualine retains
its existing `theme = "auto"`. Other themes should be added and activated with a
normal Lazy spec in `plugins`; `ui.colorscheme` does not install a theme plugin.

`ui.icons` defaults to `true`. Set it to `false` for an ordinary terminal font:
shared diagnostic, Git and fold indicators use ASCII, the owned statusline,
bufferline and incline consumers omit file icons, and which-key uses text key
labels. Markdown retains code/table rendering with plain heading markers and
raw checkbox/link/quote text. Ordinary Unicode borders and third-party UI text
can still appear. The devicons plugin may remain installed as a dependency;
font portability does not require removing shared dependencies.

`ui.reduced_motion` defaults to `false`. When true, both Neoscroll and
smear-cursor remain unloaded, Fidget uses a static progress marker and the
configured half-page navigation uses native centered scrolling. Disabling
`mappings.navigation` also leaves Neoscroll unloaded so it cannot reinstall
those navigation maps.

Theme, icon, motion, global/tab buffer ownership and navigation-map decisions are
startup settings. Restart Neovim after changing them; registering a trusted
project overlay after plugins have loaded does not undo existing plugin hooks.
Content-editing policies are checked when their corresponding events run.
Layout, glyph and folding-provider refinements remain ordinary plugin `opts`
overrides rather than separate configuration keys.

## Fold persistence and split sizing

Fold structure comes from ufo's selected provider; open/closed state is saved
per file in native view files, independently of sessions. Restoring folds
preserves the live cursor and scroll. The first idle event reasserts that state
to accommodate asynchronous providers, but does not wait indefinitely for a slow
provider. Views older than the source file are skipped to avoid stale line ranges.

`editing.equalize_windows` controls terminal-resize equalization, not the
`<leader>wm` zoom toggle. Unzoom restores saved sizes only while the split layout
is unchanged; after splits are added, removed or exchanged it equalizes instead.
Debugger panel width protection has its own
[fixed-column contract](debug-terminal-configuration.md#fixed-window-widths-during-debugging).

## Retention

`retention.views_days` defaults to `90`. Set a finite positive number of days to
change the cutoff, or `false` to disable the exit-time view janitor. It considers
only recognized native view files directly inside the configured `viewdir`;
unrelated files and directories are preserved.

`retention.log_max_bytes` defaults to `20 * 1024 * 1024`. Set a finite positive
byte count or `false`. Rotation runs once at startup before LSP clients open the
log. A larger existing `lsp.log` is renamed to `lsp.log.old`, retaining one prior
generation. A failed rename leaves the existing log in place. Changing this
setting takes effect at the next startup. Rotation does not coordinate live
writers in other Neovim instances: a Unix writer can continue in the renamed
file; Windows may refuse the rename while a writer has it open.

## Validation and references

`tests/editing_policy_spec.lua` exercises false/empty/predicate policies,
background-buffer writes, EditorConfig and safety guards, comment continuation
and preservation of independent prose mappings. `tests/retention_policy_spec.lua`
uses disposable files for disabled/custom retention. `tests/ui_policy_spec.lua`
also starts the full configuration with a real override file, a stock scheme,
no icons, reduced motion and global buffers, then loads the deferred UI plugins.

The underlying contracts are documented in Neovim's
[`formatoptions`](https://neovim.io/doc/user/change.html#fo-table),
[`EditorConfig`](https://neovim.io/doc/user/editorconfig.html),
[`viewdir`](https://neovim.io/doc/user/options.html#'viewdir') and
[`nvim_buf_call`](https://neovim.io/doc/user/api.html#nvim_buf_call()) references,
and the upstream [lualine](https://github.com/nvim-lualine/lualine.nvim),
[bufferline](https://github.com/akinsho/bufferline.nvim),
[which-key](https://github.com/folke/which-key.nvim) and
[Fidget](https://github.com/j-hui/fidget.nvim) configuration documentation.
