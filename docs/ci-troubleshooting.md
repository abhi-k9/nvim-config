# Running and troubleshooting CI

Open the failing job in Actions and check its annotations for the command and
error. To reproduce a full-config failure locally, run `make test` from the
checkout. For lint, formatting, documentation and all suites, run `make ci`.

## Push batches and notifications

The workflow starts for a push to `main`/`master` and for pull-request events.
A single push containing several commits normally creates one push-triggered
workflow run at the new branch tip, not one run per commit. Separate pushes
create separate runs; a branch with a pull request can also have a distinct
pull-request run. GitHub notification preferences and job reruns affect how many
emails you receive, so email counts do not directly count commits or pushes.

Concurrency cancels a superseded run on the same ref. It does not combine
separate pushes into a single event, and a cancellation can itself be reported.
Batching related commits into one push therefore reduces redundant runs.

## Manual native smoke and stress checks

Use **Actions → CI → Run workflow** when changing startup, UI integration or
plugin pins. This dispatch runs only the Windows and macOS smoke jobs; the
ordinary regression jobs are skipped. There is no schedule and these jobs do
not run on pushes or pull requests. Manual and automatic runs have separate
concurrency groups. Leave **stress** enabled for 25 short lifecycle cycles, or
disable it for the basic smoke check. With GitHub CLI:

```sh
gh workflow run ci.yml --ref main -f stress=true
```

A separate Windows job on the same dispatch builds a small C++ executable with
MSVC and a full PDB. It checks two Scoper reloads against live clangd and two
CodeLLDB launches against a source breakpoint, including normal process exit.
It uses the lockfile revision of nvim-dap and a checksum-pinned CodeLLDB archive.
This eight-minute job runs even with stress disabled. Its small fixture checks
correctness; launch times for large production PDBs still require local testing.

The UI smoke runner copies shipped config files into a disposable directory, ignores
private `local.lua`, isolates config/state/cache and reads the copied lockfile.
CI reuses a dedicated plugin data cache. Language servers, Mason package/parser
installation and native-sorter builds are disabled for this check. Optional
tool installation has separate existing regression coverage.
Reduced motion avoids counting transient cursor-animation windows as lifecycle
leaks; this check does not measure animation quality.

A small MessagePack client [attaches a Neovim UI over RPC](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/api.txt#L3692), consuming redraw
events without a physical terminal. Checks exercise startup, a literal filename,
Telescope buffer search, Neo-tree source switching, the real scope.nvim session
bridge, Bufferline diagnostic counts, and DAP panel open/close with sidebar width
preservation. The stress phase repeats buffer/diagnostic/session/DAP lifecycles
and checks for accumulating buffers, windows or config-owned `user_*`
autocommands after warmup. Total callback growth, Lua heap size and elapsed time
are reported, without fragile machine-speed or heap
threshold assertions. This short check does not establish absence of long-term
leaks, physical terminal rendering, debugger adapter correctness or network-share
behavior.

Bounds: **180 seconds** for cold plugin preparation, **45 seconds** for the UI
check, a **15-second** cycle-loop budget, **4 minutes** for the Actions check step
and **6 minutes** for each complete job. The jobs run in parallel. Timeouts fail
and terminate the owned Neovim process tree; there is no automatic retry.
Warm caches already at the lockfile revisions skip `Lazy restore` and its fetches.

Locally, use Python 3, Git and a supported Neovim. The extra Python dependency is
test-only and is never needed by the editor:

```sh
python -m pip install msgpack==1.2.1
python scripts/portable-smoke.py --stress
```

Use `python3` where that is the Python executable. Add `--data-home PATH` to reuse
a **dedicated test** data directory; never point it at your ordinary Neovim data,
because preparation can restore plugin checkouts to the repository's pins. Omit
`--stress` for one measured cycle, or pass `--nvim PATH` for another editor build.
Fresh runs without a data cache download plugins again. The default test suite
does not discover this manual fixture as a spec.

The first short run exposed repeated `BufWinLeave`/`WinClosed` registration in
the pinned DAP UI control panel (`DAPUIControls`, 4 to 30 entries over 25 cycles). The
[registration site](https://github.com/rcarriga/nvim-dap-ui/blob/cc9dd33aade7f20bae414d0cba163bc60d4d4b43/lua/dapui/controls.lua#L46)
creates new handlers when the panel re-enters its buffer. The config now uses
[the DAP UI fork](debug-terminal-configuration.md#dap-ui-fork-and-toolbar-lifecycle)
with a native fix; the temporary local adapter has been removed. The check
requires stable `DAPUIControls` handler counts and exercises toolbar presence
after a control buffer is wiped and recreated. Keep this check when updating
the fork or switching back to a fixed upstream revision.

Other reported deltas include Neovim's diagnostic hooks and ungrouped callbacks,
whose growth alone does not establish an ongoing leak. No plugin source is
patched by this runner. A passing check establishes the specific assertions
above, rather than claiming that all callback counts stay flat.

## Automatic checks: execution bounds and failure visibility

The workflow now sets explicit limits:

| Job | Maximum job time | Test/check step limit |
| --- | --- | --- |
| Lint and documentation | 10 minutes | 3 minutes lint; 2 minutes each for docs and action-pin checks |
| Full configuration | 20 minutes | 10 minutes tests |
| Scoper, each OS | 10 minutes | 5 minutes specs; 2 minutes for the additional Windows adapter fixture |
| Python seed tests, each OS | 5 minutes | 3 minutes tests |

The Lua harness also bounds each spec process to 60 seconds. These limits cover
different layers: a process initialization error should fail promptly, a stalled
spec is bounded by the harness, and a stuck tool/bootstrap is bounded by Actions.

`scripts/ci-run.py` streams the complete command output, preserves its exit code,
and adds bounded, escaped failure details to GitHub annotations. This makes a
failed assertion visible in the run summary as well as the full log.
