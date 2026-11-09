# Prepared Bufferline fork migration

This is a **local candidate**, based on `c287c4e` and `e09c9a6`. The production
checkout remains on `c287c4e`, using upstream Bufferline
`655133c3b4c3e5e05ec549b9f8cc2894ac6f51b3`. No ignored local configuration was
edited. Nothing has been published, pushed or opened as a PR.

The candidate spec and lockfile select `abhi-k9/bufferline.nvim` at
`4e964066ed10eb61f7b42b634f9b0877047eccdd`. This commit currently exists locally;
it must be published with authorization before a normal Lazy installation can
fetch it. Validation used the local fork checkout directly.

## Exact changes

1. Change the repository in `lua/plugins/ui.lua`; pin the full reviewed SHA in
   both the plugin spec and `lazy-lock.json`. Keep startup loading, icons,
   Catppuccin, offsets, menus, sorting, numbers, letter picks and every keymap.
2. In `lua/config/bufferline.lua`, replace `_is_pinned(element)` with the public
   `bufferline.is_pinned(bufnr)`. Keep this module: its fail-closed validation,
   stale visibility filter, deduplication and shared safe-close policy are still
   required. Keep `lua/config/util.lua` unchanged.
3. Pass `ui.bufferline_diagnostic_cache` to `options.diagnostics_cache`. Delete
   `lua/config/bufferline_diagnostics.lua` and its custom setup hook. Lazy's
   standard `setup(opts)` path now owns cache lifecycle. Keep the user-facing
   opt-out setting and every-severity diagnostic formatter.
4. Append `bufferline.restore_pins()` after scope restoration and reconciliation
   in auto-session's `post_restore_cmds`. Skip it if scope restoration failed or
   Bufferline is unavailable. Keep `config.session`'s serialization and literal
   buffer creation; this hook must not take over tab ownership.
5. Update the boundary, option, session and manual probe tests. Cache algorithm
   regressions move with the implementation to the fork; adapter interception
   and ownership tests are superseded by native cache lifecycle tests.

## Evidence

- Fork baseline pin defects reproduced before fixing; a separate attached-UI
  fresh-process test reproduced hidden scope pins being skipped before scope's
  post-restore hook created their buffers.
- Final fork suite: **109/109** on both Neovim 0.12.0 and 0.12.6, bounded to 10s
  per file and 120s overall. StyLua and whitespace checks pass.
- Candidate config: **27/27 focused tests**, using isolated initialization and
  the actual fork/scope modules: pin boundary 5, cache option 2, deletion 4,
  menus 4, scope/session 9, debugger cleanup during session save 3.
- Attached UI on Linux/0.12.6: scoped/global modes, pin/manual order, numeric,
  cycling and letter navigation, all severity counts, Catppuccin flavors,
  icons on/off, both menus, dirty text, offsets and narrow-width state. Native
  session files were restored in a fresh process, then A -> B -> A, including
  a comma-containing hidden pinned buffer.

This is not a full Lazy bootstrap or auto-session plugin end-to-end run. The
actual config hooks and native session files were exercised directly. Neo-tree
was represented by its filetype/window boundary. Windows/macOS, actual terminal
font/input/clipboard behavior, live CoC and terminal job shutdown remain manual
acceptance work. Existing superscript/visual-position mismatch is unchanged;
very narrow strips may clip all buffer labels without losing navigation state.

## Adoption, only after explicit authorization

1. Back up session files. Re-pin ambiguous legacy comma-separated pin records
   and save them after adoption. Re-save pre-0.12 session scripts, or ensure
   they emit SessionLoadPre before globals; new 0.12 sessions already do so.
2. Publish the reviewed fork commit (planned as a fast-forward of fork `main`),
   then verify the remote advertises the exact SHA. Do not force-push.
3. Review and apply this integration commit to the production config, then
   restore the locked dependency and restart Neovim. Apply all integration
   changes together; do not remove the adapter with the old upstream pin.
4. Perform native terminal acceptance on each target OS: scoped/global tabs,
   dirty buffers and terminals in several splits, menus and picks, Catppuccin
   and icons, and repeated sessions. The opt-in fork UI probe can be repeated
   against this checkout without a full plugin installation.
5. Keep the fork's patch ledger and upstream remote. Reconcile individual
   patches only when upstream offers equivalent contracts and tests pass.

## Rollback

Revert the entire integration commit, restoring the upstream repository/pin,
old diagnostic adapter and private-query boundary together. Restart Neovim;
do not attempt a live plugin swap. Restore backed-up session files or re-pin
and save using upstream: its CSV loader cannot interpret this fork's versioned
JSON string. The new post-scope hook must also be reverted. Shared deletion,
local settings and scope session data need no independent changes.
