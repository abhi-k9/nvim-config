# Bufferline maintenance and alternatives — 2026-11-08

## Recommendation

**Retain Bufferline's workflow, harden the current integration, and prefer a
small maintenance fork over a production migration.** A fork adds no runtime
dependency and preserves the existing command/API surface. It is justified by
reproduced pin-persistence defects and the absence of merged upstream changes
since January 2025, not simply by the age of a release. Creating, publishing and
adopting a fork are separate decisions; this audit does none of those.

Barbar is the strongest replacement candidate. It has responsive compatibility
maintenance and faster rendering in this probe, but migration still needs
scope/session hooks, safe-close integration, and a right-click menu solution.
Cokeline is a customization framework with larger pin/session gaps. mini.tabline
is the best dependency-light option only if the requested workflow is simplified.
There is no compelling reason to replace working defaults immediately.

This change adds **zero dependencies**, keeps every keymap, keeps Bufferline's
lockfile revision, and leaves ignored local configuration alone. Production
still has exactly one bufferline implementation.

## Architecture and dependency cost

- `lua/plugins/ui.lua` owns the strip, keys, diagnostic indicators, Neo-tree
  offsets and context menu. Catppuccin highlights are conditional on the active
  theme. Filetype icons can be disabled.
- Bufferline and scope.nvim load before auto-session's VimEnter restore.
  Bufferline registers pin/sort restoration; scope owns tab membership by
  changing `buflisted`. Deferring either until VeryLazy can miss startup restore.
- `lua/plugins/session.lua` supplies save/restore hooks and panel cleanup.
  `lua/config/session.lua` persists scope membership through validated JSON and
  literal buffer APIs. The scope cache is indexed by live tab handles at runtime
  and visual tab order on disk. `sessions.global_buffers=true` skips this layer.
- `lua/config/util.lua` owns safe deletion, dirty-buffer protection and window
  replacement. Pickers in `lua/plugins/finder.lua` and the tab menu share it.
  This business logic should remain independent of the chosen strip renderer.
- Bundled Scoper filters project files/search/clangd inputs; scope.nvim manages
  tab buffer ownership. Scoper does not own Bufferline pin state or its ordering.
  A renderer replacement must not conflate these two meanings of “scope.”
- Devicons, Catppuccin and scope.nvim are already shared configuration choices.
  Removing Bufferline does not remove those requirements elsewhere. Barbar's
  optional devicons/gitsigns are already installed. Current Cokeline removed its
  old Plenary requirement in June 2026. mini.tabline works without dependencies
  and can reuse devicons rather than adding mini.icons or all of mini.nvim.

Dependency count alone therefore does not decide among these four. Locally owned
compatibility code, session formats, callbacks and tests are maintenance costs too.

## Upstream maintenance evidence

Snapshots were inspected on the date above. Repository `updated_at`, stars,
automated review runs and community comments are not proof of maintainer support.

| Candidate / reviewed revision | Evidence | Assessment |
| --- | --- | --- |
| Bufferline `655133c3b4c3e5e05ec549b9f8cc2894ac6f51b3` | Latest main commit and release v4.9.1: 2025-01-14. [PR #992](https://github.com/akinsho/bufferline.nvim/pull/992) merged then; [#989](https://github.com/akinsho/bufferline.nvim/pull/989) merged 2025-01-11. Compatibility [#1051](https://github.com/akinsho/bufferline.nvim/pull/1051) opened 2026-05-24 remains open with zero comments/review comments in the inspected metadata. Diagnostic performance [#1010](https://github.com/akinsho/bufferline.nvim/pull/1010) remains open since 2025-04-02. | Maintenance risk is substantial despite a useful, stable feature set. Do not assume forthcoming Neovim compatibility fixes will be merged promptly. |
| Barbar `337ecfadb8bf005050990bf2f624dc4fc828dabd` | Latest code fixes: 2026-06-10, highlight cache and diagnostic redraw timing. [#668](https://github.com/romgrk/barbar.nvim/pull/668) merged 2026-04-28 for Neovim 0.13's BufModifiedSet removal; [#658](https://github.com/romgrk/barbar.nvim/pull/658) merged 2025-12-02 for session-export validity. Latest listed release v1.9.1 is older, 2024-08-05. | Strongest concrete compatibility-maintenance signal among the full-feature alternatives. Release age alone would give the wrong impression. |
| Cokeline `854849e6b853a6ee1f17d62c80ae37435cfb0a3e` | [#217](https://github.com/willothy/nvim-cokeline/pull/217) merged 2026-06-19, replacing Plenary with builtins. [#205](https://github.com/willothy/nvim-cokeline/pull/205) merged 2025-01-24 for multi-close picking. Latest listed release v0.4.0: 2023-07-02; release 1.0 PR remains open. | Some meaningful maintenance, but sparse delivery and considerable workflow implementation cost. |
| mini.tabline `d77cc478ec18fc8e8651b69233b02d5b32ed2b74` | Maintained under [nvim-mini](https://github.com/nvim-mini/mini.tabline); mirror pushed 2026-11-06. Small documented rendering/formatting API. | Good minimalist component, not a feature-equivalent substitute. |

Bufferline has a real Plenary test suite covering rendering, groups, sorting,
offsets, numbers and highlights. Its checked-in [CI](https://github.com/akinsho/bufferline.nvim/blob/655133c3b4c3e5e05ec549b9f8cc2894ac6f51b3/.github/workflows/ci.yaml)
is push-only, Linux/nightly, uses the old nightly AppImage URL and unpinned action
tags, and includes formatting commits/pushes. It needs modernization for a fork.
Recent failed *PR-subject* workflows are not evidence that runtime tests failed.
Barbar's inspected checkout has publishing CI but no comparable behavioral test
suite; Cokeline's workflows emphasize lint, line width, docs and releases. Neither
is automatically a test-quality upgrade. This was source inspection, not a full
execution of every upstream CI workflow.

A bounded fork sample did not establish a maintained drop-in successor. In
particular, MariaSolOs/bufferline.nvim main matched upstream; its relevant
`deprecation` branch supplies #1051, not a demonstrated long-term release process.
A newer fork push timestamp alone is insufficient reason to adopt it.

Additional relevant reports: [session pin mismatch #1037](https://github.com/akinsho/bufferline.nvim/issues/1037),
[scope visibility #925](https://github.com/akinsho/bufferline.nvim/issues/925),
[sort insertion #1000](https://github.com/akinsho/bufferline.nvim/issues/1000) and
[proposed fix #1056](https://github.com/akinsho/bufferline.nvim/pull/1056),
[number/position mismatch #652](https://github.com/akinsho/bufferline.nvim/issues/652).
These reports corroborate risk areas; they are not all reproduced defects here.

## Functionality and compatibility matrix

“Adapt” means configuration or owned code is required; it is not verified parity.
All candidates loaded in the Neovim 0.12.6 Linux comparison. The repository floor
is 0.12.0; older minimum-version claims in candidate READMEs are not our support target.

| Required behavior | Current Bufferline | Barbar | Cokeline | mini.tabline |
| --- | --- | --- | --- | --- |
| Per-tab buffers / global mode | Existing scope bridge / setting | Documented scope pre-leave/post-enter events; adapt hooks | Listed-buffer filtering helps; order/session integration unverified | Listed-buffer rendering; ownership remains scope's job |
| Visual-order next/previous | Native cycle commands | Native BufferNext/Previous | Native focus-next/previous mappings | Build navigation policy |
| Pin/unpin / pinned-first order | Native; private read boundary | Native BufferPin and buffer-target API | No equivalent native pin workflow found | Build it |
| Persist pins and manual order | Native, with reproduced pin defects below | SessionSavePre plus SessionLoadPost integration; adapt auto-session hooks and scope round-trip | Build persistence and pin state | Build persistence and ordering |
| Numeric first…last | Native GoToBuffer 1…9/-1 | BufferGoto 1…9, BufferLast | Focus-index API/mappings; adapt “last” | Build visual-index mapping |
| Letter pick / close pick | Native, configured safe close callback | BufferPick / BufferPickDelete; audit deletion routes | Native pick / pick-close; adapt deletion routes | Build picker or use an existing picker with changed semantics |
| Manual move / sorting | Native | Native | Native switching/reordering APIs | Build it |
| Close unpinned safely | Shared config helper plus checked pin snapshot | Adapt bulk/pin inspection to shared deletion | Build pin state and shared-close routing | Build it |
| Theme and icons | Existing Catppuccin adapter + shared devicons | Catppuccin integration + optional shared devicons | Custom highlight/component styling + optional shared devicons | Highlight groups; optional shared devicons |
| Modified and all four diagnostic severities | Existing indicators and cache | Native indicators, event-cached counts | Component diagnostics; aggregation during buffer refresh | Modified highlighting; diagnostics need a format callback/cache |
| Disabled-diagnostic policy | Cache checks enabled buffer/namespace state | Counting source does not filter is_enabled; parity requires checking/adaptation | Aggregation also reads diagnostic.get without is_enabled filtering | Depends on custom implementation |
| Neo-tree offsets / narrow width | Existing offset; native truncation | Native sidebar offset and scrolling | Sidebar configuration; native component truncation | No equivalent fixed sidebar-offset policy found |
| Right-click menu / keyboard menu | Existing callbacks and guarded menu | No matching configurable right-click menu hook found; native handlers require adaptation | Component on_click can route to shared menu | Build click dispatch/menu mapping |
| Dirty files / multiple windows | Existing shared deletion tested | Bundled bbye is useful, but integrating our exact close policy still needs tests | Default deletion repoints one bufwinid window; multi-window parity not assured | No native close workflow |
| Extra runtime dependencies for this config | Zero added | Zero required beyond existing optional plugins | Zero required beyond existing optional icons | Zero required; feature gaps cost local code |

Key mapping plan if Barbar is chosen later:

| Existing keys | Barbar equivalent / work |
| --- | --- |
| `<S-h>` / `<S-l>` | BufferPrevious / BufferNext |
| `<leader>bp` | BufferPin |
| `<leader>bP` | Keep shared bulk-delete policy; obtain visible unpinned targets safely |
| `<leader>bj` / `<leader>bJ` | BufferPick / BufferPickDelete; retain the current dirty-buffer policy |
| `<leader>bm` | Keep the config menu, replace its pin/ordering callbacks |
| `[B` / `]B` | BufferMovePrevious / BufferMoveNext |
| `<leader>1`…`<leader>9`, `<leader>0` | BufferGoto 1…9, BufferLast |

The row above describes a plan, not an activated prototype. Barbar's default
animation would be disabled for our reduced-motion policy. Native closing,
terminal handling and right-click behavior must not silently replace our rules.

## Findings and changes

### Fixed in this configuration

1. **Unsafe compatibility assumption in close-unpinned.** Pin inspection was
   embedded in the key callback with no contract checks. A new small
   `config.bufferline` boundary validates buffer-mode IDs, the public element
   list and boolean pin membership before any deletion. Unknown state cancels
   the whole operation. Unlisted/deleted stale render entries are excluded so a
   tab switch cannot make a prior tab's buffers eligible for closing.
2. **Optional diagnostic optimization could abort plugin setup.** The cache used
   an unconditional require/assert on its internal getter. Missing/incompatible
   APIs now warn once and leave plugin setup to proceed with native behavior.
   This does not promise that a fundamentally broken plugin can be repaired by
   disabling the cache; it isolates failure of the optional optimization itself.

`get_elements()` is documented but does not expose pin membership. There is no
public membership getter at the reviewed revision. `_is_pinned` remains behind
one checked boundary, rather than pretending CSV globals or rendered labels are
reliable public APIs. The diagnostic indicator callback formats already-computed
counts; it cannot replace the expensive diagnostic provider. Consequently the
existing `bufferline.diagnostics.get` adapter remains justified and removable.

### Reproduced upstream defects: proposed fork work, not fixed here

- **Comma/path matching in pins.** With buffers named `comma,name.txt`, `comma`
  and another `name.txt`, native pin serialization/restoration left the intended
  buffer unpinned and pinned the unrelated `comma` buffer. A single comma name
  can appear to work because `bufnr()` matches fragments; that is not safe
  serialization. Fix with validated JSON names and exact name-to-buffer matching,
  with a deliberately bounded legacy migration path.
- **Repeated session restoration.** The pin SessionLoadPost callback is
  registered `once=true`. A second simulated session restore did not restore its
  saved pin. Fix repeated restoration, clearing previous pin membership without
  clearing user-defined groups, and group ownership under repeated setup.

Pin state is buffer-global, not a separately persisted pin choice per tab. The
same buffer in two tabs therefore shares pin state. Current superscript numbers
are assigned before pinned-first sorting and can differ from positional numeric
navigation; the existing documentation already explains that limitation.

The two upstream pin defects remain open in the shipped plugin. We did not add
another local session-format workaround while evaluating ownership of a fork.

## Bounded measurements and regression results

One disposable embedded-UI process per candidate, Neovim 0.12.6 on Linux,
180-column UI, 100 named buffers plus the initial scratch buffer, 10,000 diagnostics,
three warm renders, then 25 measured renders. Icons were disabled. No servers,
compilers, native builds or debug adapters were started.

| Probe | Setup ms | Median render ms | p95 render ms |
| --- | ---: | ---: | ---: |
| Bufferline native diagnostics | 5.53 | 14.63 | 25.36 |
| Bufferline with our cache | 5.45 | 3.95 | 5.62 |
| Barbar, animation off | 4.92 | 1.07 | 1.93 |
| Cokeline, explicit four-count label | 3.12 | 11.33 | 12.03 |
| mini.tabline, no diagnostic indicators | 0.50 | 0.48 | 0.91 |

These are warm in-process render costs, not keystroke latency or total editor
startup. Candidate layouts/features differ, so the table is not a feature-equal
ranking. In particular mini.tabline does less work. Barbar receives counts on
DiagnosticChanged, whereas Bufferline's native provider repeatedly scans all
workspace diagnostics. Our cache is about 3.7× faster than native median render
in this sample; no claim is made about all projects or hardware.

The first headless probe failed with a native process crash across every candidate;
those runs were discarded. The reported runs used a real embedded UI. This is a
harness limitation, not evidence that all five plugins crash in ordinary editing.

**48 focused regression tests passed**: compatibility boundary (5), diagnostic
cache (15), buffer lifecycle (4), context menus (4), session scope bridge (8),
UI policy including global mode/missing optional plugins (6), and search scope (6).
Existing tests cover changed targets during callbacks, dirty-buffer protection,
window replacement, cache enable/disable and insert policy, tab switches and
literal session names. They are not a claim of exhaustive upstream coverage.

### Repeating the comparison

`tests/manual/bufferline_compare.lua` is opt-in and excluded from the normal spec
suite. Install candidate checkouts separately; it never downloads dependencies.
Pass candidate name and checkout path using the existing bounded embedded-UI
transport (Python requires the already documented test-only `msgpack==1.2.1`).
From the repository root, in Python:

```python
import importlib.util, json, os, shutil, tempfile
from pathlib import Path
spec = importlib.util.spec_from_file_location("runner", "scripts/portable-smoke.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
kind, checkout = "cached", "/absolute/path/to/bufferline.nvim"
probe = Path("tests/manual/bufferline_compare.lua").resolve()
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    fixture = root / "run.lua"
    fixture.write_text("arg = " + "{" + json.dumps(kind) + "," +
                       json.dumps(checkout) + "}; return dofile(" +
                       json.dumps(str(probe).replace("\\", "/")) + ")")
    env = os.environ.copy()
    env.pop("NVIM", None)
    env["NVIM_APPNAME"] = "nvim"
    env["NVIM_LOG_FILE"] = str(root / "nvim.log")
    for key in ("CONFIG", "DATA", "STATE", "CACHE"):
        directory = root / key
        directory.mkdir()
        env["XDG_" + key + "_HOME"] = str(directory)
    runner.run_ui(shutil.which("nvim"), fixture, kind, Path.cwd(), env)
```

Use forward-slash absolute checkout paths in this example on Windows. Candidates
are `native`, `cached`, `barbar`, `cokeline`, `mini`. Each UI process has a 45-second
external deadline. The native probe also reports the two pin regressions.

## Maintenance-fork scope and exit criteria

A fork is preferable to growing multiple config-side patches, provided its scope
is explicit. Suggested small commits, each with a reproducer:

1. Add a documented `is_pinned(bufnr)` public query and a documented diagnostic
   provider/count boundary, retaining old behavior for existing users.
2. Fix pin serialization and repeated session restore; test commas, pattern-like
   filenames, Windows paths, vanished files, several tabs and sequential projects.
3. Integrate the proven event-invalidated diagnostic cache behind the public
   provider. Preserve disabled namespace/buffer semantics and insert policy;
   #1010's proposed limiting is not automatically equivalent to exact counts.
4. Handle `vim.nonnil` with compatibility fallback for the older API in #1051.
   Current 0.12.6 operation is verified; future removals still need real-version tests.
5. Replace inherited auto-format/push CI with read-only style/tests, immutable
   Actions pins, job/process deadlines and push/PR checks. Use the declared
   version floor and stable; keep nightly and broad native UI stress opt-in.

Keep upstream as a remote, retain license/attribution, publish a short patch
ledger and compatibility policy, and update the config lockfile explicitly.
Prefer fixes upstream when maintainers resume; do not promise response times or
open-ended feature development. A fork is ongoing ownership, not a free upgrade.
The fork should let us remove the local diagnostic interception and private pin
fallback once the new public APIs are adopted and their regressions pass.

## Remaining gaps and verification limits

- The pin defects above are verified and remain unfixed upstream; no fork or PR
  was created/published, and no migration was activated.
- Candidate performance probes are isolated setups, not full replacement
  prototypes. Barbar's scope/session/menu/close adaptation is not implemented.
  Cokeline/mini pin persistence and all key semantics remain parity work.
- Native Windows/macOS execution, a full fresh-process pinned-session round-trip,
  upcoming Neovim versions, all unusual terminal encodings, and visual/input
  acceptance in a real terminal were not repeated in this audit. Embedded UI
  execution is not a substitute for manual appearance/interaction verification.
- Before adopting a fork or replacement, manually check Catppuccin flavors,
  icons on/off, narrow widths, Neo-tree offsets, mouse right-click and keyboard
  menu, letter picking, numeric navigation after pin/reorder, dirty files and
  terminals in several splits/tabs, and session A → B → A on all target OSes.
- Scoper was reviewed at its search/visibility boundaries, not re-audited in full.
  No extra recurring CI workload was added.
