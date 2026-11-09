# Configuration hardening — 2026-11-09

Baseline: `736f88a179fb0c3f63851a6baa645633f3b83380` on `main`.
Work branch: `audit/2026-11-09-hardening`.

This is an implementation and verification ledger, **not** a claim that
every previously identified risk is fixed. Behavioral changes are intentionally
small. No plugin migrations, lockfile changes, or user-state migrations are
included; all old behavior not explicitly listed is retained.

## Implemented

### Parser and fold lifecycle (`693f7d3`)

- On-demand Tree-sitter parser provisioning excludes buffers marked
  `b:big_file`, as highlighting already did. A subsequent ordinary buffer can
  still request the parser; the existing 5-minute failure backoff remains.
- A `SessionLoadPost` pass now considers missing parser installation as well
  as highlighting/indent reattachment for loaded restored filetypes. The same
  per-language pending state prevents duplicate builds.
- Synchronous exceptions from `install()` or `task:await()` now mark the
  language as failed (with the existing retry policy) instead of leaving it
  indefinitely pending. Completion callbacks are processed once.
- Fold-view read and save callbacks now exclude big-file buffers. This does
  not delete pre-existing view files or change cleanup retention settings.

Focused tests: `tests/treesitter_install_spec.lua`,
`tests/treesitter_install_alias_spec.lua`, and
`tests/fold_view_freshness_spec.lua`.

### Documentation and CI reproducibility (`9252ca8`)

- The source/cheatsheet mapping guard now detects numeric leader bindings.
  It expands the documented `<leader>1` through `<leader>9` range rather
  than requiring nine visually redundant rows.
- `tests/docs_guard_test.py` exercises the real documentation script in a
  disposable copy, including negative cases for missing source and missing
  documentation mappings. `make check-docs` runs this suite.
- The Linux CI StyLua archive is pinned to release `v2.6.0` with the
  SHA-256 recorded by GitHub's release asset metadata:
  `a485f72bbfa22e4642e77a84b5edc2611a5cab7477b34e2e709dd8f78e919895`.
  CI checks the digest **before** extracting the executable. Mason-managed
  local formatter versions remain independent.
- Historical Bufferline performance and maintenance audit reports now link
  to the November 9 fork adoption, without rewriting their measured history.

## Verification

A remote Git comparison confirmed the first two commits form a fast-forward
branch from the named baseline, with only the intended files changed.
The numeric-range extraction and negative-test deletion expression were
spot-checked independently using POSIX grep/sed and Python.

**Not yet executed:** the full Neovim runtime suite, Lua formatter/linter
suite, isolated documentation checker on the whole repository, or native
Windows/macOS interactive tests. The implementation environment lacks Neovim
and cannot download the toolchain. The repository only triggers its normal
full CI on `main`/`master` pushes or pull requests, so a push to this
feature branch alone is not evidence of passing CI.

Before merging, run:

```sh
make ci
make check-docs
# Optional UI check against an isolated dependency cache:
python scripts/portable-smoke.py --data-home /path/to/disposable/nvim-data
```

In particular, verify the synthetic Tree-sitter installer failure tests,
missing `FileType` session restores, large-file fold behavior, and any
formatter changes caused by the pinned StyLua version. Run native interactive
acceptance on Windows/macOS when possible.

## Retained decisions and follow-up work

1. **Mapping coverage:** the documentation guard compares presence of
   alphanumeric leader chords, not their runtime descriptions, effective
   modes, or all buffer-local/plugin-created mappings. Expand only with
   reproducible collisions and negative-control fixtures. Global
   `vim.g.no_plugin_maps` suppresses unrelated built-in ftplugin mappings;
   test narrower alternatives before changing it.
2. **Bufferline:** the fork already owns diagnostic caching, pin restore and
   inspected pin state. Preserve safe deletion and session ordering.
   Superscript ordinals can differ from visual positions with pinned buffers;
   address through an explicitly tested UX contract, not an implicit keymap
   change. Keep the fork's upstream patch ledger current.
3. **Terminals:** existing Toggleterm lifecycle and LazyGit identity semantics
   were compared against Snacks on 2026-11-08. The parity gaps are material:
   hidden/nonzero exits, multi-terminal views, direction/size/mode persistence
   and command compatibility. Do not replace solely because of update recency.
4. **Search:** Telescope and fzf-lua are both intentionally available.
   `telescope-ui-select.nvim` has an old pinned upstream commit; investigate
   maintenance and alternatives against selector behavior before migrating.
   Scoper-restricted replacement remains deliberately refused with the
   pinned Grug-far API rather than silently escaping the chosen root.
5. **Performance:** profile actual startup, event-loop latency, Scoper clangd
   restart directory discovery, fold view I/O and UI redraw on affected
   machines before adding caches. Keep Neo-tree's default scan policy until
   its documented stale-navigation race is addressed.
6. **Platforms and security:** Windows/macOS manual smoke remains opt-in to
   limit CI cost. Continue native shell, DAP, clipboard, terminal and UNC/path
   probes. Existing state-file recovery, swap safeguards and literal-path
   handling are high-value behavior: preserve them.

References: [responsiveness review](performance-review-2026-11-04.md),
[Bufferline adoption](bufferline-fork-migration-2026-11-09.md),
[terminal parity](terminal-migration-evaluation-2026-11-08.md), and
[historical audit resolution](audit-resolution.md).
