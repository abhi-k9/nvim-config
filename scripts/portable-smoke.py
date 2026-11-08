#!/usr/bin/env python3
"""Run the opt-in native smoke/stress fixture with isolated state and hard deadlines."""

import argparse
import os
from pathlib import Path
import queue
import shutil
import signal
import subprocess
import tempfile
import threading
import time


REPO = Path(__file__).resolve().parents[1]
PREFERENCES = """return {
  globals = { treesitter_auto_install = false, tooling_reminder_days = 0 },
  tools = { servers = {}, packages = {}, parsers = {} },
  sessions = { auto_save = false, auto_restore = false },
  ui = { reduced_motion = true },
  plugins = {
    { "mason-org/mason.nvim", build = false },
    { "mason-org/mason-lspconfig.nvim", opts = { automatic_enable = false } },
    { "WhoIsSethDaniel/mason-tool-installer.nvim", opts = { run_on_start = false } },
    { "nvim-treesitter/nvim-treesitter", build = false },
    { "nvim-telescope/telescope-fzf-native.nvim", build = false },
  },
}
"""


def stop_tree(process):
    if process.poll() is not None:
        return
    if os.name == "nt":
        try:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           check=False, timeout=10, stdout=subprocess.DEVNULL)
        finally:
            if process.poll() is None:
                process.kill()
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait()


def process_options():
    return {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" else {"start_new_session": True}


def run_phase(command, directory, env, seconds):
    start = time.monotonic()
    with subprocess.Popen(command, cwd=directory, env=env, **process_options()) as process:
        try:
            code = process.wait(timeout=seconds)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            # Stop only this fixture's process tree, including any git children.
            stop_tree(process)
            raise
    print(f"{command[-1]} phase: {time.monotonic() - start:.2f}s (limit {seconds}s)", flush=True)
    if code:
        raise RuntimeError(f"Neovim exited with status {code}")


def run_ui(nvim, fixture, phase, directory, env):
    import json
    import msgpack

    start, replies = time.monotonic(), queue.Queue()
    with tempfile.TemporaryFile() as log, subprocess.Popen(
        [nvim, "--embed", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE"],
        cwd=directory, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=log, bufsize=0, **process_options(),
    ) as process:
        def receive():
            try:
                for packet in msgpack.Unpacker(process.stdout, raw=False, read_size=4096):
                    # Drain redraw notifications; only responses finish the check.
                    if packet[0] == 1 and (packet[1] == 2 or packet[2] is not None):
                        replies.put(packet)
                        return
                replies.put(RuntimeError("embedded Neovim exited before replying"))
            except Exception as error:
                replies.put(error)

        reader = threading.Thread(target=receive, daemon=True)
        reader.start()
        try:
            process.stdin.write(msgpack.packb([0, 1, "nvim_ui_attach", [180, 60, {"ext_linegrid": True}]]))
            process.stdin.write(msgpack.packb([0, 2, "nvim_exec_lua", [
                "local path, phase = ...; arg = { phase }; return dofile(path)",
                [str(fixture), phase],
            ]]))
            try:
                reply = replies.get(timeout=45)
            except queue.Empty as error:
                raise RuntimeError("embedded smoke/stress exceeded 45 seconds") from error
            if isinstance(reply, Exception):
                raise RuntimeError(str(reply))
            if reply[2] is not None:
                raise RuntimeError(str(reply[2]))
            print(json.dumps(reply[3]), flush=True)
        finally:
            stop_tree(process)
            reader.join(timeout=1)
            log.seek(0)
            details = log.read().decode("utf-8", errors="replace")
            if details:
                print(details, flush=True)
    print(f"{phase} phase: {time.monotonic() - start:.2f}s (limit 45s)", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stress", action="store_true", help="also run 25 bounded lifecycle cycles")
    parser.add_argument("--data-home", type=Path, help="reuse a dedicated test data cache; never use your normal Neovim data")
    parser.add_argument("--nvim", default="nvim", help="Neovim executable (default: nvim on PATH)")
    args = parser.parse_args()
    nvim = shutil.which(args.nvim)
    if not nvim:
        parser.error("Neovim was not found; install it or pass --nvim")
    try:
        import msgpack  # noqa: F401 -- check the optional transport before downloads
    except ImportError:
        parser.error("install the optional test transport first: python -m pip install msgpack==1.2.1")
    # Copy only shipped config surfaces. Ignore private local.lua; Lazy can
    # rewrite only the copied lockfile, leaving the working checkout untouched.
    with tempfile.TemporaryDirectory(prefix="nvim-portable-") as temporary:
        root = Path(temporary)
        config = root / "config" / "nvim"
        config.mkdir(parents=True)
        for name in ("init.lua", "lazy-lock.json", "README.md", "CHANGES.md"):
            shutil.copy2(REPO / name, config / name)
        for name in ("lua", "docs"):
            shutil.copytree(REPO / name, config / name)
        for name in ("lua", "plugin"):
            shutil.copytree(REPO / "scoper.nvim" / name, config / "scoper.nvim" / name)
        (config / "local.lua").write_text(PREFERENCES, encoding="utf-8")
        env = os.environ.copy()
        env.pop("NVIM", None)
        env["NVIM_APPNAME"] = "nvim"
        (root / "log").mkdir()
        env["NVIM_LOG_FILE"] = str(root / "log" / "nvim.log")
        for kind in ("CONFIG", "STATE", "CACHE", "DATA"):
            path = args.data_home.resolve() if kind == "DATA" and args.data_home else root / kind.lower()
            path.mkdir(parents=True, exist_ok=True)
            env[f"XDG_{kind}_HOME"] = str(path)
        fixture = REPO / "tests" / "manual" / "portable_smoke.lua"
        command = [nvim, "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-l", str(fixture)]
        try:
            run_phase([*command, "prepare"], config, env, 180)
            run_ui(nvim, fixture, "stress" if args.stress else "smoke", config, env)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            print(f"Portable check failed: {error}", flush=True)
            return 1
        except KeyboardInterrupt:
            return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
