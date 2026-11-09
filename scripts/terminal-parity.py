#!/usr/bin/env python3
"""Compare installed terminal plugins in disposable, UI-attached Neovim processes."""

import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin-root", required=True, type=Path,
                        help="directory containing dedicated test checkouts of both plugins")
    parser.add_argument("--nvim", default="nvim")
    parser.add_argument("--backend", choices=("toggleterm", "snacks"),
                        help="check only one backend (default: both)")
    args = parser.parse_args()
    nvim = shutil.which(args.nvim)
    if not nvim:
        parser.error("Neovim was not found; install it or pass --nvim")
    try:
        import msgpack  # noqa: F401 -- optional test dependency, never installed automatically
    except ImportError:
        parser.error("install the test transport: python -m pip install msgpack==1.2.1")
    spec = importlib.util.spec_from_file_location("portable_smoke", REPO / "scripts/portable-smoke.py")
    portable = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(portable)
    backends = (args.backend,) if args.backend else ("toggleterm", "snacks")
    try:
        for backend in backends:
            plugin = args.plugin_root.resolve() / (backend + ".nvim")
            if not (plugin / "lua" / backend).exists() and not (plugin / "lua" / (backend + ".lua")).exists():
                parser.error(f"missing plugin checkout: {plugin}")
            pin = subprocess.check_output(["git", "-C", str(plugin), "rev-parse", "HEAD"],
                                          text=True, timeout=10).strip()
            print(f"{backend}: {pin}", flush=True)
            with tempfile.TemporaryDirectory(prefix="nvim-terminal-parity-") as temporary:
                root = Path(temporary)
                env = os.environ.copy()
                env.pop("NVIM", None)
                env["NVIM_APPNAME"] = "nvim"
                env["NVIM_LOG_FILE"] = str(root / "nvim.log")
                env["NVIM_TERMINAL_AUDIT_ROOT"] = str(root)
                env["NVIM_TERMINAL_AUDIT_PLUGINS"] = str(args.plugin_root.resolve())
                for kind in ("CONFIG", "DATA", "STATE", "CACHE"):
                    path = root / kind.lower()
                    path.mkdir()
                    env[f"XDG_{kind}_HOME"] = str(path)
                portable.run_ui(nvim, REPO / "tests/manual/terminal_parity.lua", backend, REPO, env)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Terminal comparison failed: {error}", flush=True)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
