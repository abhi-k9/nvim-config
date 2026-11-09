# Terminal migration evaluation — 2026-11-08

## Recommendation

**Retain Toggleterm and the existing dedicated LazyGit terminal.** Snacks can
provide the five primary mappings, but a direct replacement does not preserve
the current lifecycle, layout and command behavior. Configuration options close
some gaps; full parity would require maintaining a terminal controller here.
That does not meet this migration's goal of reducing maintenance while keeping
established behavior.

This evaluation changes tests and documentation only. The plugin specs, lockfile,
terminal settings, mappings, image setup and startup behavior are unchanged.
It introduces no runtime dependencies and does not read machine-specific
`local.lua` in the comparison environment.

## Versions and maintenance evidence

GitHub's default-branch commit API was checked during this evaluation. Both
repositories were unarchived, and both installed pins matched the latest main
commit reported by that API:

| Plugin | Evaluated commit | Latest main commit date (UTC) |
| --- | --- | --- |
| `akinsho/toggleterm.nvim` | `9a88eae817ef395952e08650b3283726786fb5fb` | 2025-03-09 |
| `folke/snacks.nvim` | `882c996cf28183f4d63640de0b4c02ec886d01f2` | 2026-05-25 |

Snacks has more recent activity, including a public terminal `focus()` method
added on 2026-03-21. `focus()` shows/focuses or hides one terminal; it does not
replace Toggleterm's saved multi-terminal view. Commit recency alone is not a
functional-parity result or a guarantee of future maintenance.

## Current integration and dependencies

- `lua/plugins/terminal.lua` owns lazy loading, all five mappings, invocation-time
  shell resolution, buffer-local navigation and LazyGit's handle cache. Only
  normal mode maps `<C-\>`; terminal mode retains Neovim's `<C-\><C-n>` escape.
- `lua/config/keymaps.lua` owns global terminal `<Esc><Esc>`. LazyGit overrides
  single Escape locally with `nowait`, and deliberately receives no window
  navigation mappings, preserving its native Ctrl-key actions.
- `lua/config/settings.lua` supplies `terminal.shell` and
  `terminal.lazygit_per_project`. A process starts in the active window's cwd,
  which can differ from the resolved project root used as LazyGit's cache key.
- `lua/plugins/images.lua` is the existing, lazy Snacks spec. Images are opt-in;
  ordinary file reads do not activate the renderer. A future terminal migration
  should extend this single spec and preserve those image settings.
- `lua/config/options.lua` deliberately omits `terminal` from `sessionoptions`.
  Session/scope code excludes special buffers from file rescue. Ordinary shell
  jobs are not recreated by session restoration; DAP has separate cleanup hooks.
- `lua/plugins/ui.lua` excludes the `toggleterm` filetype from lualine. A future
  migration needs to update that exclusion to `snacks_terminal`.
- The lockfile, terminal specs, native smoke fixture and terminal documentation
  refer to Toggleterm. The HTML cheatsheets also document `:ToggleTerm`, numbered
  `:2ToggleTerm`, custom split sizing and `:TermExec cmd="npm test"`. Those are
  part of the public workflow, not disposable implementation references.

No config code outside the terminal spec was found parsing Toggleterm buffer
names or consuming its terminal objects/events. Historical audit/changelog
references describe past behavior and should remain historical records.

## Functional comparison

“Observed” below means the attached-UI, real-job comparison on Linux/Neovim
0.12.6. Platform-specific shell behavior still needs native verification.

| Capability | Current Toggleterm configuration | Snacks public API / parity result |
| --- | --- | --- |
| `<C-\>` / `<leader>tt` | Floating terminal, normal-mode mappings | Supported with `win.position = "float"`; keep terminal-mode Ctrl-backslash unmapped. |
| `<leader>th` / `<leader>tv` | Horizontal 15 rows; vertical 40% of columns | Bottom/right windows support these sizes. Both measured 15 rows and 72 columns at a 180×60 UI. |
| Numbered selection | Explicit counts select a terminal independent of cwd | Supported, but default identity also includes command, cwd and env. Default same-count project switch created a different process. |
| Stable numbered identity | Existing job survives editor project/environment changes | Passing `cwd = "."`, a constant command identity and no explicit changing env preserves it. This small option change was tested successfully; no separate numbered-handle registry is necessary for this case. |
| Unnumbered toggle | Hides all visible ordinary terminals and restores the saved view | Snacks toggles one identity. With two splits, Toggleterm went from three windows to one and back to three; Snacks left two windows on hide. `count = 0` is not a replacement: Snacks treats it as a distinct identity. |
| Reusing a process in another direction | Hide a vertical terminal, request float, reuse its process in a float | Passing new `win` options to `toggle()` for an existing Snacks identity does not apply them. Observed terminal remained vertical. Requires explicit window-state management. |
| Remembering resized splits | `persist_size = true` remembers size by direction | Observed 21-row resize reopened at 21 with Toggleterm, at configured 15 with Snacks. Requires additional size capture/restoration. |
| Initial and subsequent mode | Initial insert; `persist_mode = true` restores normal/terminal mode | Both initially entered terminal mode. After hiding in normal mode, Toggleterm reopened in normal mode; Snacks reentered terminal mode. `auto_insert`/`start_insert` are switches, not saved-mode state. |
| Focus and float behavior | Split close restores recorded origin; leaving a Toggleterm float closes it | Snacks uses previous-window focus on close and can retain an unfocused float. Exact origin/floating-window behavior needs explicit policy and multi-window testing. |
| Borders and dimensions | Rounded float; Toggleterm's adaptive dimensions; winblend 0; terminal shading | Public Snacks window options can reproduce borders/dimensions. Default float is 90% with a backdrop, not the same sizing/shading policy. |
| Shell/default/legacy policy | Nil inherits `vim.o.shell`; string or resolver; Windows-only legacy `pwsh -NoLogo` preference | Resolver can be retained before spawn. Snacks `shell` accepts string/argv, but parses a shell string into argv; Toggleterm executes shell text with a terminal-identification suffix through Neovim. Parsing semantics are not interchangeable. |
| Literal cwd and original environment | Relative `.` avoids re-expansion of `$NAME`/special paths; running processes retain cwd/env | Both passed a directory containing spaces, `$NAME`, `%NAME%` and `#`, and retained the original cwd/env after a project switch with literal identity. New processes use the invocation cwd. |
| `<C-h/j/k/l>` | Buffer-local shell navigation; omitted for LazyGit | Public window key options/callbacks can provide the same mappings. Snacks has none by default. |
| `<Esc><Esc>` / interactive apps | Global double Escape; a single Escape waits for `timeoutlen`. LazyGit single Escape is immediate | Snacks uses a local single-Escape expression map with a 200ms double-press timer; the first Escape reaches the app. Disable its `term_normal` key to inherit the existing shell behavior; separately preserve LazyGit's immediate Escape. Both backends passed an input-level double-Escape/built-in escape smoke check. |
| Visible successful exit | Close/delete terminal, recreate on next invocation | Both cleaned up visible exit status 0. |
| Visible unsuccessful exit | Close/delete terminal, release LazyGit handle | Snacks reports the exit and keeps the dead buffer. Observed with status 7; subsequent toggle can reuse it. Requires an explicit lifecycle policy. |
| Hidden process exit | Job `on_exit` still runs and deletes buffer/releases handle | Snacks window hide deletes its autocmd group, including `TermClose`. Observed hidden exits 0 and 7 retained buffers; reopening returned the same dead buffers. |
| Sessions | No terminal jobs/buffers serialized | Both passed `mksession`/source with the shipped session options and a visible plus a hidden terminal. No `term://`/`termopen()` entries or restored terminal buffers. |
| Cleanup | Shutdown terminates owned jobs and removes windows | Explicit cleanup passed for both. Snacks emitted exit -1 notices during some intentional job termination; the comparison records these separately from assertions. |
| `:ToggleTerm` / `:TermExec` | Existing documented commands; execution can use an existing interactive shell's environment | Snacks has no command-compatible replacement. `terminal(command)` launches a command process; it does not send that command into the selected existing shell. Compatibility needs command parsing/selection and channel-send behavior. |

The shell parsing difference matters for quoted executable paths, arguments,
Windows cmd/PowerShell, and POSIX shell syntax. Snacks' documented argv interface
is preferable for launching a known executable. It does not automatically
preserve all accepted `terminal.shell` strings. Its internal `parse()` helper is
marked private and should not become a config dependency. No Windows failure is
inferred from the Linux results.

## LazyGit evaluated separately

`Snacks.lazygit.open()` constructs `{ "lazygit", ...args }` and delegates to
`Snacks.terminal`. The argv construction is useful. Its default `configure = true`
also writes a generated theme/config and changes `LG_CONFIG_FILE` in Neovim's
environment, including an editor preset. Adopting those defaults would change
the current external LazyGit configuration policy. `configure = false` avoids
that change and should be the starting point for any future evaluation.

Current behavior is one dedicated session process, ignoring mapping counts.
Optional per-project mode keys handles by resolved root while spawning in the
active cwd. Using default Snacks cwd/count identity would silently split the
session process or share/isolate processes differently. Passing the project root
as cwd would also change where a new process starts when invoked from a subfolder.

Public options can preserve the session case with fixed `count = 1`, `cwd = "."`
and `configure = false`. Project isolation still needs explicit handle/identity
policy. The same hidden-exit and nonzero-exit gaps apply because LazyGit delegates
to the terminal module. The controlled child verified that lifecycle, but an
actual LazyGit binary was not available for a native TUI run. Retain the current
LazyGit integration as well; re-evaluating only this mapping later is possible.

## Why a compatibility layer was not shipped

Simple public options solve stable shell identity, initial geometry, borders and
key overrides. Completing parity would additionally make this configuration own:

1. Saved multi-terminal views, selected terminal and unnumbered toggle semantics.
2. Direction changes, persistent split sizes, saved mode and origin-window policy.
3. Exit handling that survives hidden windows, failed-job disposal and stale
   handle protection, coordinated with Snacks' own buffer/window cleanup.
4. Per-project LazyGit identity without changing spawn cwd or external settings.
5. The documented ToggleTerm/TermExec command interface and existing-shell execution.

These are central terminal-manager responsibilities currently supplied by the
dependency being removed. A private-registry patch or broad wrapper would move
that maintenance into the config. This is a scope/maintenance decision, not a
claim that such an implementation is technically impossible.

Revisit when public upstream lifecycle/view support closes these gaps, or when
the desired workflow intentionally changes. Reuse the existing Snacks spec if a
future candidate passes; remove Toggleterm and update the lockfile/docs only then.

## Reproducing the bounded checks

The normal suite's `tests/terminal_policy_spec.lua` covers default/resolved shells,
nil fallback, invalid shell values, simulated Windows legacy selection, session
and project LazyGit handles, stale exit callbacks, missing executables and
separation of shell navigation from LazyGit's immediate Escape. Existing
`tests/terminal_literal_cwd_spec.lua` covers literal global/window-local cwd and
real process reuse.

The new opt-in comparison uses installed **dedicated test** plugin checkouts,
isolated XDG state, no Lazy bootstrap/downloads, and no machine-local preferences:

```sh
python -m pip install msgpack==1.2.1  # optional test transport, preferably in a venv
python scripts/terminal-parity.py --plugin-root /path/to/test-data/nvim/lazy
```

The root must contain `toggleterm.nvim` and `snacks.nvim`; their Git revisions are
printed. `--backend toggleterm` or `--backend snacks` limits the comparison;
`--nvim /path/to/nvim` selects the editor. Use the pins above to reproduce this
report. The runner does not move or update them.

Each backend runs in a separate Neovim process with an attached 180×60 UI and a
45-second external deadline. The fixture uses real PTYs and controlled Neovim
child processes; it checks literal cwd/env, reuse, counts, layouts, visible and
hidden exits, session serialization/restoration and teardown. Toggleterm baseline
contracts are asserted; Snacks differences are reported as JSON. **A zero runner
exit status means the comparison completed, not that Snacks achieved parity.**

No new CI jobs or platform matrix entries were added. The normal policy tests
remain fast; the optional real-job comparison completed in 0.20s for Toggleterm
and 0.27s for Snacks on this Linux host. Only focused checks were run for this
evaluation, rather than repeatedly running the entire repository suite.
The two focused spec files passed all 12 cases; `make check check-docs` also
passed, including Lua linting, formatting and documentation consistency.

## Performance and remaining verification

In one fresh-process sample, plugin setup/module loading took 2.27ms for
Toggleterm and 0.79ms for Snacks; the first shell/window creation API call took
1.23ms and 2.38ms respectively. These are local observations, not a statistically
controlled benchmark, shell-readiness timings or measurements of a complete
parity adapter. They do not establish a meaningful startup advantage. Both can
remain lazy until their first mapping. Retaining the current integration adds
no production startup cost.

An additional input-level attached-UI smoke check exercised initial terminal
mode, double Escape, the built-in Ctrl-backslash/Ctrl-N escape, reopen after
normal mode, and Toggleterm Ctrl-K returning to the source window. It confirmed
the saved-mode difference above. This does not replace testing a physical
terminal emulator's key encoding or interactive application behavior.

Before any future migration, manually verify on **native Windows cmd.exe and
PowerShell**, Linux bash/fish, and macOS zsh/default shell:

- All five mappings, counts, several simultaneous splits, direction switches,
  resized/reopened windows, focus across tabs and float closure on leaving.
- Default shell, explicit shell arguments, an invocation-time resolver and the
  Windows legacy policy; executable/project paths with spaces and native separators.
- Set a variable and change directory inside a running shell, switch editor
  projects, and verify neither is reset. Include window-local cwd and paths with
  literal `$`, `%`, `#`, and permitted shell metacharacters.
- Nested Neovim/fzf and actual LazyGit: single/double Escape, native Ctrl-key
  actions, shell navigation, `q`/normal exit and unsuccessful exit, both visible
  and hidden. Confirm reopening starts a live job and project isolation works.
- Save/restore using the real auto-session workflow with visible/hidden terminals,
  modified file buffers and other panels; exit Neovim and check for orphan jobs.
- Image previews with images enabled/disabled, external viewer fallback, missing
  LazyGit, and disabled/missing optional plugins.

The native Windows/macOS/fish cases and actual LazyGit TUI were **not run** here.
The policy tests simulate platform decisions; they do not certify native shell
quoting or console behavior. Those limits reinforce retaining the established
implementation rather than claiming unverified cross-platform parity.

## Sources

- [Snacks terminal public API and options](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/docs/terminal.md)
  and [implementation](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/terminal.lua):
  identity, job startup, Escape timing and exit policy.
- [Snacks window implementation](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/win.lua):
  `hide()`/`close()` remove the window autocmd group; `show()` registers it again.
- [Snacks LazyGit public configuration](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/docs/lazygit.md)
  and [implementation](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/lazygit.lua).
- [Toggleterm public interface](https://github.com/akinsho/toggleterm.nvim/blob/9a88eae817ef395952e08650b3283726786fb5fb/README.md),
  [toggle/view handling](https://github.com/akinsho/toggleterm.nvim/blob/9a88eae817ef395952e08650b3283726786fb5fb/lua/toggleterm.lua),
  [process lifecycle](https://github.com/akinsho/toggleterm.nvim/blob/9a88eae817ef395952e08650b3283726786fb5fb/lua/toggleterm/terminal.lua)
  and [window sizing](https://github.com/akinsho/toggleterm.nvim/blob/9a88eae817ef395952e08650b3283726786fb5fb/lua/toggleterm/ui.lua).
- [Snacks commit history](https://github.com/folke/snacks.nvim/commits/main/),
  [terminal history](https://github.com/folke/snacks.nvim/commits/main/lua/snacks/terminal.lua)
  and [Toggleterm commit history](https://github.com/akinsho/toggleterm.nvim/commits/main/).
