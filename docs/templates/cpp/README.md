# C++ project-root templates

These files configure the C/C++ tooling. **None of them are loaded by
Neovim** — copy them to the **root of your C++ project** (e.g.
`<project-root>/`), where clangd / clang-format / clang-tidy discover
them by walking up from the file being edited.

## Two flavours per tool

For each tool you get two files — pick the one that fits:

| Ready-to-copy (concise) | Reference (heavily annotated) | Tool |
|---|---|---|
| `.clangd` | `clangd.example` | clangd (LSP) |
| `.clang-format` | `clang-format.example` | clang-format |
| `.clang-tidy` | `clang-tidy.example` | clang-tidy |

- The **dotfiles** (`.clang-format`, `.clang-tidy`, `.clangd`) are minimal,
  current, and validated — copy one straight to your project root and
  go. They carry the project's chosen defaults (incl. the `lower_case`
  function/member naming and the `-std=c++20` pin).
- The **`.example` files** are the same settings expanded into a full
  annotated reference: every option explained. `clang-format.example` and
  `clang-tidy.example` produce exactly the dotfile's behaviour;
  `clangd.example` adds sections the minimal `.clangd` omits (extra
  warning flags, `Remove`/`Index`/`Diagnostics`/`InlayHints`, commented
  per-directory `If:` blocks, etc.). Read these to understand *why*, or
  copy one and trim. `scripts/check-docs.sh` fails when a pair drifts.

You don't need both — they're the same destination file at different
levels of detail. A common workflow: start from the `.example` to learn
the options, then keep the trimmed dotfile in your repo.

## clang-tidy note

`clangd.example` configures clang-tidy **inside clangd** via its
`Diagnostics.ClangTidy` block, which carries the same checks and options
as `.clang-tidy` — an alternative to the standalone file. If you use that
block, you don't also need the separate `.clang-tidy` file (and vice
versa); with both, clangd applies the block's `Add`/`Remove` on top of
`.clang-tidy`. The standalone `.clang-tidy` is handy when you also run the
`clang-tidy` CLI in CI; the inline block is simpler if clangd is your only
consumer.

## Reminders

- **They're dotfiles** (leading `.`), hidden by default in Explorer /
  `ls`. Confirm with `ls -a` (or `dir /a` on Windows) after copying.
- **Set the C++ standard** to match your build. `.clangd`'s `-std=c++20`
  is appended to every C++ file's flags, after the `compile_commands.json`
  ones, so it overrides the database's `-std` too (and covers headers that
  have no entry). Its `If: PathMatch` keeps it off C files. If your
  targets use different standards, switch to the headers-only block at
  the bottom of `.clangd`.
- **Restart clangd after adding `.clangd`/`.clang-tidy`:** `:ScoperLspReload`
  (reconfigures clangd for the current scope and restarts this project's
  clangd only) or `:lsp restart clangd` (restarts every clangd client), so
  clangd re-reads them.
- Companion cheatsheets: `../../cheatsheets/clang-tools.html` (concepts)
  and `../../cheatsheets/clang-settings-reference.html` (the exact values
  in these files).
