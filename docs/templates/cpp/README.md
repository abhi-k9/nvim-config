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
`Diagnostics.ClangTidy` block, which requests the same check families,
exclusions and options as `.clang-tidy` — an alternative for editor policy.
The effective set also depends on clangd's supported checks and fast-check filter. If you use that
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
  have no entry). Its `If: PathMatch` excludes `.c` files but includes `.h`;
  remove `.h` for C headers. The flag does not change the compile language.
  If targets use different standards, remove the project-wide pin or adapt
  the commented headers-only rule to your layout and chosen header standard.
  Project config paths are relative to the directory containing `.clangd`.
- **If config edits are not reflected, restart clangd:** `:ScoperLspReload`
  reconfigures/restarts the current managed project in selected/filtered mode.
  Otherwise use `:lsp restart clangd` (restarts every clangd client).
- Companion cheatsheets: [tool concepts](../../cheatsheets/clang-tools.html)
  and [template values](../../cheatsheets/clang-settings-reference.html).
- Upstream references: [clangd configuration and precedence](https://clangd.llvm.org/config),
  [header compile-command inference](https://clangd.llvm.org/design/compile-commands),
  [clang-format options and semantic caveats](https://clang.llvm.org/docs/ClangFormatStyleOptions.html),
  and [clang-tidy suppression syntax](https://clang.llvm.org/extra/clang-tidy/#suppressing-undesired-diagnostics).
