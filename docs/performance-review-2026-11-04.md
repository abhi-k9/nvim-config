# Responsiveness review — 2026-11-04

This review follows the Telescope result-formatting and prompt-cursor fixes.
It covers startup settings, Scoper database selection, LSP attachment/highlights,
completion/snippets, Tree-sitter, status components and Neo-tree scanning. These
are targeted measurements on Linux with Neovim 0.12.6 and the existing lockfile,
not a promise of identical Windows timings or exhaustive runtime coverage.

## Settings reads

Without trusted project overlays, settings reads previously normalized the
global working directory twice per read. They now skip that work. A standalone
loop of 100,000 scalar reads took about 439 ms before and 38 ms after, with cwd
lookups falling from 200,000 to zero. Startup makes far fewer reads, so this is
a small shared-path improvement rather than a comparable startup speedup.

There is no new cache: registering an overlay enables directory matching
immediately, and subsequent `:cd` changes retain their existing behavior.
`tests/settings_spec.lua` verifies this boundary.

## Scoper discovery and fold restoration

Scoper now shares one resolved selection within a status read or warm command
preparation, rather than discovering it repeatedly. A fixture containing 4,000
immediate root entries gave these results:

| Operation | Directory scans before → after | Approximate elapsed time before → after |
| --- | --- | --- |
| Status | 2 → 1 | 4.1–4.8 ms → 1.9 ms |
| Selected clangd command | 3 → 1 | 6.2 ms → 2.0 ms |

Independent calls still resolve again. Cold filters compare their captured
context after work, retry once on a changed selection, and return no obsolete
filtered directory if changes continue. This also closes a pre-existing gap
where successful old output could be paired with a new selection in status.
Background delivery retains its obsolete-result checks. No discovery cache
persists across operations. Selecting an explicit known database avoids
root enumeration altogether; see [database selection](scoper-integration-notes.md#choose-the-source-database).
Restart polling retains its context checks, which can repeat discovery while a
client exits. Reducing that cost needs care to preserve changes from arbitrary
resolvers and external state; it remains a follow-up opportunity.

Fold restoration now stops immediately when no saved view exists. A probe of
100 entries and their first idle callbacks retained 200 saved-view checks and
removed 200 source-file stat calls. Saved views still get subsecond freshness
validation, cursor preservation and the existing first-idle reassertion.

## Behaviors retained after measurement

The probes loaded the locked plugin implementations and invoked their real
callbacks, avoiding dependency upgrades or a new profiling plugin.

| Area | Observation | Decision |
| --- | --- | --- |
| LuaSnip cursor checks | About 2.2 microseconds without an active snippet and 7–7.5 microseconds with 3–100 placeholders. Deletion validation reached about 0.255 ms at 100 placeholders. | Keep region/deletion checks so moving out of a snippet and deleting it remain correct. |
| LSP attachment | 100 repeated attachments retained one highlight/clear/detach callback per configured event. No synchronous requests on the inspected typing/cursor paths. | Keep attachment and highlight behavior. |
| Reference clearing | Empty clearing was negligible; populated namespaces cost more once, then subsequent moves hit the empty path. | Keep immediate clearing to avoid stale highlights. |
| Completion | Blink already caches buffer words, limits total text and switches from synchronous to asynchronous work before skipping oversized buffers. | Retain useful completion sources and upstream size guards. |
| Tree-sitter | Context updates already coalesce by window over 150 ms. Native highlighting reattachment reuses the existing tree. | Avoid another throttle/cache or removing session reattachment. |
| Status components | Lualine diff uses Gitsigns' cached counts; Incline already debounces rendering. | Avoid replacing useful UI with speculative caches. |

Bufferline has a remaining upstream scaling cost: in a fixture with 20 buffers,
100 real normal-mode renders spent about 99 ms aggregating 1,000 diagnostics
and 1,042 ms aggregating 10,000 diagnostics. The larger case is about 10.4 ms
per render for aggregation alone. Its locked implementation already reuses
results during insert mode, but normal-mode refreshes aggregate again. There is
no supported custom diagnostic getter to replace just this work. A useful
future improvement would be upstream invalidation on diagnostic changes rather
than a local monkeypatch or removing diagnostic indicators by default.

## Deferred: forcing asynchronous Neo-tree scans

The locked Neo-tree defaults to `filesystem.async_directory_scan = "auto"`:
background refreshes are asynchronous, while command-triggered scans are
synchronous. A real 40-directory fixture showed that `"always"` reduced the
warmed command's initial main-thread work from about 7.1 ms to 4.2 ms, while
producing the same nodes in ordinary navigation. That measures command return,
not the time until the completed tree is displayed. These single-run UI timings
are exploratory; the controlled stale-scan sequence determines the decision.

A delayed-I/O probe then exposed a race: open directory A, hold its asynchronous
scan, navigate to B, wait for B's tree, then release A. The visible tree became
A even though Neo-tree's root state still named B. The configuration therefore
retains the default policy. Revisit this option after scan completion checks
that it still owns the current navigation, with a regression for this sequence.
No workaround or third-party plugin patch is installed by this review.

## Corroborating upstream sources

These online sources match the locked revisions inspected by the probes:

- [Neo-tree scan policy](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/d5b8a12b74683ddaefa519ce66a097610672859f/lua/neo-tree/defaults.lua#L546)
- [Neo-tree scan completion and rendering](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/d5b8a12b74683ddaefa519ce66a097610672859f/lua/neo-tree/sources/filesystem/lib/fs_scan.lua#L209-L224)
- [Bufferline diagnostic aggregation](https://github.com/akinsho/bufferline.nvim/blob/655133c3b4c3e5e05ec549b9f8cc2894ac6f51b3/lua/bufferline/diagnostics.lua#L145-L161)
- [Blink buffer cache and size defaults](https://github.com/Saghen/blink.cmp/blob/78336bc89ee5365633bcf754d93df01678b5c08f/lua/blink/cmp/sources/buffer/init.lua)
- [LuaSnip callbacks](https://github.com/L3MON4D3/LuaSnip/blob/642b0c595e11608b4c18219e93b88d7637af27bc/lua/luasnip/init.lua)
- [Tree-sitter context update throttling](https://github.com/nvim-treesitter/nvim-treesitter-context/blob/8decd73460d26ef0a0befb745d022dd1fc2c38b8/lua/treesitter-context.lua)

For user-controlled motion changes, see [editing/UI preferences](editing-ui-configuration.md#themes-fonts-and-motion).
For the earlier finder fixes and large-repository alternatives, see
[picker responsiveness](search-session-configuration.md#picker-responsiveness).

## Verification and limits

The regression specs cover machine settings followed by late overlay registration
and `:cd`, missing versus fresh/stale fold views, independent database discovery,
changing resolver results, successful cold build switches and bounded retries.
They assert behavior and avoided calls rather than fragile timing thresholds.
The normal gate is `make ci`; focused Scoper checks use
`scoper.nvim/tests/pipeline_resolution_spec.lua`, `lsp_spec.lua` and `lsp_modes_spec.lua`.

The timing fixtures use local directories and warmed locked implementations.
They do not measure native Windows filesystem/antivirus costs, network shares,
the terminal renderer, or a real production clangd index. Those need a profile
on the affected machine before making broader changes.
