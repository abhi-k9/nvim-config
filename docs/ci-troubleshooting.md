# CI failures and long runs — 2026-10-22

This page records dated incident evidence, followed by the workflow's current
execution bounds. The historical test totals and timings are not current suite
sizes or performance guarantees.

The CI follow-up found separate startup, missing-tool, installer-concurrency, tool-version, and
platform-path problems. A successful local run with populated Neovim data did not exercise the
same first-install path as a fresh Actions runner.

## Why a run lasted more than six hours

[Run 39701985386](https://github.com/abhi-k9/nvim-config/actions/runs/39701985386)
lasted about **6 hours 1 minute**, including queue/setup/cleanup. GitHub reported
that its full-config job exceeded the **6-hour maximum execution time**. The
workflow had no explicit job timeout, so the default 360-minute limit applied.
The other jobs finished within seconds.

The full-config command was stuck in Neovim, rather than spending six hours
executing assertions. A fresh-checkout reproduction established this sequence:

1. The test initializer adds the checkout to `runtimepath`. On CI the checkout
   is outside Neovim's normal configuration directory.
2. Lazy resets that path during setup. Initial discovery can work from its
   cache, but a cold plugin installation resets module discovery again.
3. Lazy then reports `No specs found for module "plugins"`, and the test harness
   cannot load. Errors in a `-u` initializer or `:PlenaryBustedDirectory` command
   do not necessarily terminate a headless editor.
4. Neovim remains open until Actions cancels the job. Queue and cleanup time can
   make the workflow's displayed duration exceed six hours.

The configuration now explicitly preserves the resolved checkout in Lazy's
runtime-path settings. Both suites enter through a native Lua `-l` runner, whose
initialization errors exit nonzero. Tests cover the cold discovery reset and
prompt exits after initialization/harness failures.

Spec files run sequentially: simultaneous full-config startups can contend for
shared plugin caches and short asynchronous deadlines. A parallel local run
exposed a Grug setup timeout; the sequential full suite passed. A separate first
cold run also exposed a transient UFO initialization failure, while isolated and
complete reruns passed. No production workaround for that unproven initialization
timing issue was mixed into the startup correction.

## Other CI failures

| Job | Reproduced cause | Correction |
| --- | --- | --- |
| Doc-sync | In clang-format 18, the annotated template's explicit legacy `AlignConsecutiveMacros: None` changes a dormant `PadOperators` field. Its dump differs from the concise template despite disabled alignment. | Inherit LLVM's disabled macro-alignment defaults in both templates. The complete guard passes actual versions 15.0.7, 18.1.8, 20.1.8, and 23.1.3. |
| Windows seed tests | The tar fixture supplied a POSIX `venv/bin/python` link, while the installer correctly recognizes the Windows `venv/Scripts/python.exe` interpreter exception. | Make the fixture platform-correct; keep archive restrictions unchanged. |
| macOS seed tests | Temporary paths can use `/var` aliases while relocated interpreter paths resolve through `/private/var`. A direct-shebang test also assumed the final path stayed below its length limit. | Canonicalize fixture roots and explicitly use a short destination for the direct-shebang case. Unsafe long-path conversion remains separately tested. |
| Windows Scoper tests | One fixture expected an unnormalized temporary pathname. More significantly, native buffer paths expanded `RUNNER~1` to `runneradmin`, while scope roots retained the short name; valid files were rejected. | Normalize the fixture and expand native 8.3 prefixes through `GetLongPathNameW` for scope comparisons. Keep persisted scope identity and logical symlink behavior; version filtered compilation-cache fingerprints to invalidate older results. |
| Full configuration | The Linux job did not install ripgrep. Repeated child startups also scheduled real parser builds against shared checkout directories, causing missing parser/scanner files. | Install ripgrep explicitly, disable automatic provisioning in the test initializer, and test installer behavior using controlled tasks. The existing parser opt-out now also covers startup installation. |

## Isolated parser probes — 2026-10-27

An FZF parser test inherited a temporary `XDG_DATA_HOME`, then loaded the full
test initializer in its child editor. That child had no installed plugin tree,
so startup could bootstrap plugins again and exceed its ten-second deadline.
The parser probe now adds the parent's resolved, locked plugin source directories
to `runtimepath` directly. It keeps isolated scope state without running Lazy or
installers, and asserts that it did not create a plugin installation directory.

## Installer filesystem mismatch — 2026-11-04

In [run 41975763982](https://github.com/abhi-k9/nvim-config/actions/runs/41975763982),
Linux setup failed before tests with `EXDEV: cross-device link not permitted`.
The pinned installer extracts under Node's `os.tmpdir()`, then renames the
directory into `os.homedir()/nvim-stable`. On that runner, `/tmp` and the home
directory were on different filesystems. Its error text also suggested checking
the release asset, but this failure was a local filesystem rename.

The workflow now obtains the actual Linux home directory through a shell step
output and sets `TMPDIR` to that output for the Neovim setup step only. Extraction
and installation then share a parent filesystem. The action pin and other steps'
temporary-directory settings are retained. Node on Windows uses `TEMP`/`TMP`
instead, so its installation policy is unchanged. A literal `TMPDIR: $HOME` in an
action's `env` would not perform shell expansion; the step output is deliberate.

Upstream evidence: [temporary-directory creation](https://github.com/rhysd/action-setup-vim/blob/febef33995d6649302e9d88dda81e071b68f16a7/src/system.js#L29-L34)
and [installation rename](https://github.com/rhysd/action-setup-vim/blob/febef33995d6649302e9d88dda81e071b68f16a7/src/neovim.js#L144-L162).

The same run also caught raw-versus-normalized Windows path comparisons in the
new database-resolution spec. That fixture was corrected independently; Scoper's
production path normalization was already behaving as intended.

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

The runner copies shipped config files into a disposable directory, ignores
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
creates new handlers when the panel re-enters its buffer. The config now supplies
an isolated, removable [toolbar lifecycle adapter](debug-terminal-configuration.md#dap-toolbar-lifecycle-workaround).
The check requires stable combined native/local control-handler counts and
exercises toolbar presence after a control buffer is wiped and recreated. It
also supports validating an upstream fix with the adapter removed.

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

The investigation environment could access GitHub run metadata and annotations,
but its destination policy blocked Azure-backed log archive downloads. Local
reproductions and the new native CI run were therefore used to verify the fixes;
generic historical annotations alone were not treated as detailed failure logs.
A later run still exhibiting the hang was canceled while preparing this correction.

## Verification

The local complete suite passed **506 tests**: 201 configuration, 261 Scoper,
and 44 Python tests, with clean lint/format/doc checks. A further Windows-only
API/UTF-8 check runs on the native runner (skipped on Linux). The new CLI wrapper
also passed command success/failure, Unicode/annotation escaping, missing executable,
signal propagation, and missing-final-newline probes.

[Native run 39834251539](https://github.com/abhi-k9/nvim-config/actions/runs/39834251539)
passed all seven jobs at `683f6e5`: lint/documentation, full configuration,
Scoper on Linux and Windows, and seed tests on Linux, Windows, and macOS.
The Windows Scoper job explicitly completed successfully on its rerun in
36 seconds, including the native API/Unicode regression. Its initial job record
remained queued despite an overall success conclusion, so that badge alone was
not treated as verification.

The full-config job took 29 seconds on that run; the preceding successful native
run took 2 minutes 3 seconds. These are observed timings with different cache
states, not runtime guarantees. Explicit execution limits remain in place.

## Sources

- [GitHub job timeout defaults](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes).
- [Pinned Lazy runtime-path reset](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/core/config.lua).
- [Neovim filename modifier implementation](https://github.com/neovim/neovim/blob/d714648b8e7c476b7b5c1f661aa192b179bfc1d3/src/nvim/eval/fs.c#L80): `:p` can skip full-name expansion for an already-absolute path; the native run confirmed it retained the short alias.
- [Microsoft `GetLongPathNameW` contract](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/fileapi/nf-fileapi-getlongpathnamew.md): Unicode paths, buffer sizing, and zero on failure.
- [Neovim Lua-script startup and exit semantics](https://github.com/neovim/neovim/blob/d714648b8e7c476b7b5c1f661aa192b179bfc1d3/runtime/doc/starting.txt).
- [LLVM 18 legacy alignment conversion](https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/clang/lib/Format/Format.cpp#L74).
- [Ubuntu 24.04 runner tool inventory](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md).
- [Python virtual environments are not inherently portable](https://docs.python.org/3/library/venv.html#how-venvs-work).

The [expanded audit](audit-followup-2026-10-22.md) describes the preceding snapshot;
this page records the later CI-specific corrections and their native-run evidence.
