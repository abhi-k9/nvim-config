#!/usr/bin/env python3
"""Offline seed: this config's plugins, Mason tools and treesitter parsers in one archive.

Build it on a machine where the config is installed and working, carry it to a
machine without internet access together with the config, and install it there:

    python3 scripts/offline-seed.py check                 # what is still missing here?
    python3 scripts/offline-seed.py build --out-dir DIR   # write the seed
    python3 scripts/offline-seed.py install SEED          # on the offline machine

The seed holds lazy/<plugin> for every lazy-lock.json entry, mason/ (without
staging/), site/ (parsers and queries) and offline-seed-manifest.json. Mason
binaries and compiled parsers only run on the OS and CPU they were built on,
so build one seed per platform: a .zip on Windows, a .tar.gz on Linux and
macOS (keeps executable bits and Mason's symlinks). `build` also writes
<seed>.sha256, which `install` verifies.

A seed is executable code: `install` validates every entry before writing,
unpacks into a fresh staging folder inside the data folder, and only then
swaps lazy/, mason/ and site/ into place (old ones go to a backup folder).

Standard library only, Python 3.8+. Any shell (fish, bash, zsh, PowerShell,
cmd) runs it the same way. See docs/workflows/offline-install.md.
"""

import argparse
import ast
import hashlib
import io
import json
import ntpath
import os
import platform
import posixpath
import re
import shlex
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path

# Preserve a symlinked config's installed name (for example ~/.config/nvim
# -> a checkout named nvim-config); that name selects Neovim's data paths.
CONFIG_DIR = Path(__file__).absolute().parent.parent
CHECK_LUA = CONFIG_DIR / "scripts" / "offline-seed-check.lua"
MANIFEST = "offline-seed-manifest.json"
PARTS = ("lazy", "mason", "site")
WINDOWS = os.name == "nt"
CHECK_TIMEOUT = 300
MAX_TOTAL_MB = 16 * 1024
MAX_FILE_MB = 4 * 1024
MAX_ENTRIES = 1_000_000
MAX_MANIFEST_BYTES = 2**20
MAX_WINDOWS_LAUNCHER_BYTES = 2**21


def fail(msg):
    sys.exit(f"offline-seed: {msg}")


def warn(msg):
    print(f"offline-seed: warning: {msg}", file=sys.stderr)


def app_name():
    """NVIM_APPNAME this config runs under (the name of its folder)."""
    return CONFIG_DIR.name


def data_dir_name():
    return app_name() + ("-data" if WINDOWS else "")


def default_data_dir():
    """stdpath('data') for this config, as Neovim computes it."""
    base = os.environ.get("XDG_DATA_HOME")
    if not base:
        base = os.environ["LOCALAPPDATA"] if WINDOWS else str(Path.home() / ".local" / "share")
    return Path(base) / data_dir_name()


def this_platform():
    if WINDOWS:
        system = "windows"
    elif sys.platform == "darwin":
        system = "macos"
    else:
        system = "linux"
    machine = platform.machine().lower()
    arch = {"amd64": "x64", "x86_64": "x64", "aarch64": "arm64"}.get(machine, machine)
    return f"{system}-{arch}"


def read_lock():
    lock = CONFIG_DIR / "lazy-lock.json"
    if not lock.is_file():
        fail(f"no lazy-lock.json in {CONFIG_DIR}")
    raw = lock.read_bytes()
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


def git(*args):
    try:
        res = subprocess.run(["git", *args], capture_output=True, text=True)
    except FileNotFoundError:
        return None
    return res.stdout.strip() if res.returncode == 0 else ""


def nvim_env(data_dir):
    """Environment that makes Neovim load THIS config and read data_dir, or None."""
    if data_dir.name != data_dir_name():
        return None
    env = dict(os.environ)
    env["XDG_CONFIG_HOME"] = str(CONFIG_DIR.parent)
    if app_name() != "nvim":
        env["NVIM_APPNAME"] = app_name()
    else:
        env.pop("NVIM_APPNAME", None)
    env["XDG_DATA_HOME"] = str(data_dir.parent)
    return env


class CheckFailed(Exception):
    pass


def run_check(data_dir):
    """Gaps reported by offline-seed-check.lua.

    Raises CheckFailed unless Neovim exited 0 AND wrote a well-formed report,
    so a crash, a timeout or a missing report never reads as "complete".
    """
    nvim = shutil.which("nvim")
    if not nvim:
        raise CheckFailed("nvim is not on PATH")
    env = nvim_env(data_dir)
    if env is None:
        raise CheckFailed(f"the data dir must be named '{data_dir_name()}' for Neovim to use it")
    fd, out = tempfile.mkstemp(prefix="nvim-seed-check-", suffix=".json")
    os.close(fd)
    env["OFFLINE_SEED_CHECK_OUT"] = out
    try:
        try:
            res = subprocess.run(
                [nvim, "--headless", f"+luafile {CHECK_LUA.as_posix()}"],
                cwd=CONFIG_DIR, env=env, stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=CHECK_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            raise CheckFailed(f"Neovim didn't finish within {CHECK_TIMEOUT} s") from None
        try:
            report = json.loads(Path(out).read_text(encoding="utf-8") or "null")
        except ValueError:
            report = None
    finally:
        Path(out).unlink(missing_ok=True)
    if not isinstance(report, dict) or report.get("version") != 1:
        raise CheckFailed(f"Neovim exited {res.returncode} without writing a check report")
    if "error" in report:
        raise CheckFailed(f"the check failed inside Neovim: {report['error']}")
    if res.returncode != 0:
        raise CheckFailed(f"Neovim exited {res.returncode}")
    gaps = report.get("missing")
    if gaps == {}:  # vim.json.encode writes an empty list as {}
        gaps = []
    if not isinstance(gaps, list) or not all(isinstance(g, str) for g in gaps):
        raise CheckFailed("the check report is malformed")
    return gaps


def cmd_check(args):
    data_dir = Path(args.data_dir) if args.data_dir else default_data_dir()
    try:
        gaps = run_check(data_dir)
    except CheckFailed as e:
        print(f"offline-seed: check failed: {e}", file=sys.stderr)
        return 2
    if gaps:
        print("\n".join(gaps))
        print("Start Neovim online and let it finish (:Lazy sync, :MasonToolsInstall, :TSUpdate).")
        return 1
    print(f"complete: nothing left to download for {data_dir}")
    return 0


def collect(data_dir, parts, lock, allow_mismatch):
    paths, summary, mismatches = [], [], []
    if "lazy" in parts:
        missing = []
        have_git = git("--version") is not None
        for name in sorted(lock):
            d = data_dir / "lazy" / name
            if not d.is_dir():
                missing.append(name)
                continue
            if have_git:
                head = git("-C", str(d), "rev-parse", "HEAD")
                if head != lock[name]["commit"]:
                    mismatches.append(f"{name} (have {head or '?'}, lockfile {lock[name]['commit']})")
            paths.append(Path("lazy") / name)
        if missing:
            fail("not installed: " + ", ".join(missing) + ". Run :Lazy sync first.")
        if not have_git:
            warn("git not found: plugin commits were not compared with lazy-lock.json")
        if mismatches:
            msg = "checkout differs from lazy-lock.json:\n  " + "\n  ".join(mismatches)
            if not allow_mismatch:
                fail(msg + "\nRun :Lazy restore (or :Lazy sync and keep the new lockfile), or pass --allow-mismatch.")
            warn(msg)
        summary.append(f"{len(lock)} plugins")
    mason_pkgs = []
    if "mason" in parts:
        mason = data_dir / "mason"
        if mason.is_dir():
            paths += [Path("mason") / p.name for p in sorted(mason.iterdir()) if p.name != "staging"]
            if (mason / "packages").is_dir():
                mason_pkgs = sorted(p.name for p in (mason / "packages").iterdir() if p.is_dir())
            summary.append(f"{len(mason_pkgs)} Mason packages")
        else:
            warn(f"no mason/ in {data_dir}; skipped")
    parsers = []
    if "site" in parts:
        site = data_dir / "site"
        if site.is_dir():
            paths.append(Path("site"))
            if (site / "parser").is_dir():
                parsers = sorted(p.stem for p in (site / "parser").iterdir() if p.is_file())
            summary.append(f"{len(parsers)} parsers")
        else:
            warn(f"no site/ in {data_dir}; skipped")
    return paths, summary, mason_pkgs, parsers


def write_zip(out, data_dir, paths, manifest):
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True, compresslevel=6) as z:
        z.writestr(MANIFEST, manifest)
        for rel in paths:
            top = data_dir / rel
            if top.is_file():
                z.write(top, rel.as_posix())
                continue
            for root, dirs, files in os.walk(top):
                root_p = Path(root)
                arc = root_p.relative_to(data_dir).as_posix()
                # Directory entries too: git needs .git/refs and friends even when empty.
                z.write(root_p, arc + "/")
                for f in files:
                    z.write(root_p / f, f"{arc}/{f}")


def write_tgz(out, data_dir, paths, manifest):
    with tarfile.open(out, "w:gz", compresslevel=6) as t:
        info = tarfile.TarInfo(MANIFEST)
        data = manifest.encode("utf-8")
        info.size, info.mtime, info.mode = len(data), int(time.time()), 0o644
        t.addfile(info, io.BytesIO(data))
        for rel in paths:
            t.add(data_dir / rel, rel.as_posix(), recursive=True)


def cmd_build(args):
    data_dir = Path(args.data_dir) if args.data_dir else default_data_dir()
    if not (data_dir / "lazy").is_dir():
        fail(f"no lazy/ folder in {data_dir}. Start Neovim once online, or pass --data-dir.")
    data_dir = data_dir.resolve()
    parts = args.only.split(",") if args.only else list(PARTS)
    bad = [p for p in parts if p not in PARTS]
    if bad:
        fail("--only takes " + ", ".join(PARTS) + "; got " + ", ".join(bad))

    if not args.no_check:
        try:
            gaps = run_check(data_dir)
        except CheckFailed as e:
            fail(f"completeness check failed: {e}. Fix that, or pass --no-check to build without it.")
        if gaps:
            msg = "this install would still download:\n  " + "\n  ".join(gaps)
            if not args.allow_mismatch:
                fail(msg + "\nStart Neovim online and let it finish, or pass --allow-mismatch.")
            warn(msg)

    lock, lock_hash = read_lock()
    paths, summary, mason_pkgs, parsers = collect(data_dir, parts, lock, args.allow_mismatch)
    plat = this_platform()
    nvim_version = ""
    nvim = shutil.which("nvim")
    if nvim:
        res = subprocess.run([nvim, "--version"], capture_output=True, text=True)
        nvim_version = res.stdout.splitlines()[0] if res.stdout else ""
    manifest = json.dumps({
        "built": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "platform": plat,
        "neovim": nvim_version,
        "config": git("-C", str(CONFIG_DIR), "rev-parse", "--short", "HEAD") or "",
        "lockfile_sha256": lock_hash,
        "contents": summary,
        "plugins": {name: lock[name]["commit"] for name in sorted(lock)} if "lazy" in parts else {},
        "mason_packages": mason_pkgs,
        "parsers": parsers,
        # Console-script launchers embed the builder's absolute venv path.
        # Record provenance for exact relocation, including Python < 3.11
        # whose pyvenv.cfg has no creation command.
        "python_venv_roots": {
            cfg.parent.parent.name: str(cfg.parent.resolve())
            for cfg in sorted((data_dir / "mason" / "packages").glob("*/venv/pyvenv.cfg"))
        } if WINDOWS and "mason" in parts else {},
    }, indent=2) + "\n"
    if len(manifest.encode("utf-8")) > MAX_MANIFEST_BYTES:
        fail("manifest exceeds the 1 MiB metadata limit")

    ext = "zip" if WINDOWS else "tar.gz"
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"nvim-offline-seed_{plat}_lock-{lock_hash[:8]}.{ext}"
    part = out.with_name(out.name + ".part")
    print(f"Packing {'; '.join(summary)} from {data_dir}\n  -> {out}")
    try:
        (write_zip if WINDOWS else write_tgz)(part, data_dir, paths, manifest)
        with open_seed(part, WINDOWS) as archive:  # never ship a seed `install` would refuse
            validate(seed_entries(archive), MAX_ENTRIES, MAX_TOTAL_MB * 2**20, MAX_FILE_MB * 2**20)
        os.replace(part, out)
    finally:
        if part.exists():
            part.unlink()
    digest = write_checksum(out)
    print(f"Done: {out.name} ({out.stat().st_size / 2**20:.1f} MB)\n  sha256 {digest}  (also in {out.name}.sha256)")
    return 0


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_checksum(seed):
    """Write <seed>.sha256 in `sha256sum` format; returns the digest."""
    digest = sha256_of(seed)
    Path(str(seed) + ".sha256").write_text(f"{digest}  {seed.name}\n", encoding="utf-8")
    return digest


def verify_checksum(seed, expected, no_verify):
    """Compare the seed with --sha256, else with its .sha256 file; fail on any doubt."""
    if no_verify:
        warn("--no-verify: the seed's checksum was not checked")
        return
    source = "--sha256"
    if not expected:
        sidecar = Path(str(seed) + ".sha256")
        if not sidecar.is_file():
            fail(f"no {sidecar.name} next to the seed and no --sha256 given. Copy the .sha256 file "
                 "along, pass --sha256 <hex> from a trusted source, or --no-verify to skip.")
        words = sidecar.read_text(encoding="utf-8").split()
        expected = words[0] if words else ""
        source = sidecar.name
    expected = expected.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        fail(f"{source} doesn't hold a SHA-256 digest")
    actual = sha256_of(seed)
    if actual != expected:
        fail(f"checksum mismatch: {seed.name} is {actual}, {source} says {expected}. "
             "The file is damaged or not the seed you think it is.")
    print(f"Checksum OK ({source}).")


def read_manifest(seed):
    try:
        with open_seed(seed) as archive:
            if isinstance(archive, zipfile.ZipFile):
                member = archive.getinfo(MANIFEST)
                size = member.file_size
            else:
                member = archive.getmember(MANIFEST)
                if not member.isfile():
                    fail(f"{seed.name} has no regular {MANIFEST}; not an offline seed")
                size = member.size
            # Metadata is parsed before the archive-wide entry checks. Bound
            # both the declared size and the actual read before JSON decoding.
            if size > MAX_MANIFEST_BYTES:
                fail("manifest exceeds the 1 MiB metadata limit")
            source = (archive.open(member) if isinstance(archive, zipfile.ZipFile)
                      else archive.extractfile(member))
            with source:
                raw = source.read(MAX_MANIFEST_BYTES + 1)
            if len(raw) > MAX_MANIFEST_BYTES:
                fail("manifest exceeds the 1 MiB metadata limit")
        manifest = json.loads(raw)
        if not isinstance(manifest, dict):
            fail("manifest must be a JSON object")
        contents = manifest.get("contents", [])
        if not isinstance(contents, list) or not all(isinstance(item, str) for item in contents):
            fail("manifest contents must be a list of strings")
        roots = manifest.get("python_venv_roots", {})
        if (not isinstance(roots, dict)
                or not all(isinstance(name, str) and name not in ("", ".", "..")
                           and not any(c in name for c in "/\\:\x00\r\n")
                           and isinstance(root, str) and len(root) <= 8192
                           and not any(c in root for c in "\x00\r\n")
                           and ntpath.isabs(root) and ntpath.splitdrive(root)[0]
                           and ntpath.basename(root).casefold() == "venv"
                           for name, root in roots.items())):
            fail("manifest python_venv_roots must map package names to absolute Windows venv paths")
        return manifest
    except (KeyError, AttributeError, ValueError, OSError, RecursionError, tarfile.TarError, zipfile.BadZipFile):
        fail(f"{seed.name} has no readable {MANIFEST}; not an offline seed")


def entry_parts(name):
    """Path components of an archive entry, or None if it could land outside the destination."""
    if not name or "\x00" in name or "\\" in name or name.startswith("/") or re.match(r"[A-Za-z]:", name):
        return None
    parts = tuple(p for p in name.split("/") if p not in ("", "."))
    if not parts or ".." in parts:
        return None
    if WINDOWS and any(":" in p or p != p.rstrip(" .") for p in parts):
        return None
    return parts


class Entry:
    """One archive member: kind is file, dir, symlink, hardlink or other."""

    def __init__(self, name, kind, size=0, link="", mode=0, src=None):
        self.name, self.kind, self.size, self.link, self.mode, self.src = name, kind, size, link, mode, src
        self.parts = entry_parts(name)


def zip_entries(z):
    entries = []
    for info in z.infolist():
        mode = info.external_attr >> 16
        if info.is_dir():
            kind = "dir"
        elif stat.S_IFMT(mode) in (0, stat.S_IFREG):
            kind = "file"
        else:
            kind = "other"  # symlinks, devices: never written from a zip
        entries.append(Entry(info.filename, kind, info.file_size, mode=mode, src=info))
    return entries


def tar_entries(t):
    entries = []
    for m in t.getmembers():
        if m.isfile():
            kind = "file"
        elif m.isdir():
            kind = "dir"
        elif m.issym():
            kind = "symlink"
        elif m.islnk():
            kind = "hardlink"
        else:
            kind = "other"
        entries.append(Entry(m.name, kind, m.size if m.isfile() else 0, m.linkname, m.mode, m))
    return entries


def validate(entries, max_entries, max_total, max_file):
    """Refuse a seed unless every entry stays inside lazy/, mason/, site/ or the manifest.

    No absolute, `..`, drive or backslash paths, no duplicates, no devices,
    nothing written through a symlink in the archive, and size limits so a
    hostile seed can't fill the disk. Returns the total unpacked size.
    """
    if len(entries) > max_entries:
        fail(f"seed has {len(entries)} entries, more than the {max_entries} allowed (--max-entries)")
    fold = str.casefold if WINDOWS or sys.platform == "darwin" else str
    allowed = set(PARTS) | {MANIFEST}
    kinds, links, total = {}, set(), 0
    for e in entries:
        if e.parts is None:
            fail(f"unsafe path in seed: {e.name!r}")
        top = e.parts[0]
        if top not in allowed:
            fail(f"unexpected entry in seed: {e.name!r} (only {', '.join(sorted(allowed))})")
        if len(e.parts) == 1 and e.kind != ("file" if top == MANIFEST else "dir"):
            fail(f"seed entry {e.name!r} has the wrong type ({e.kind})")
        if top == MANIFEST and len(e.parts) > 1:
            fail(f"unexpected entry in seed: {e.name!r}")
        if e.kind == "other":
            fail(f"unexpected entry type in seed: {e.name!r}")
        key = fold("/".join(e.parts))
        if key in kinds and not (kinds[key] == "dir" == e.kind):
            fail(f"duplicate entry in seed: {e.name!r}")
        kinds[key] = e.kind
        if e.kind == "symlink":
            links.add(key)
            # A venv's bin/python points at the build machine's Python (repair_venvs
            # re-points it); every other link must stay inside the seed.
            # Exempt only the interpreter links, not arbitrary venv paths:
            # repair_venvs writes pyvenv.cfg, so allowing it to be an external
            # link would turn a later repair into an out-of-tree write.
            in_venv = (
                len(e.parts) == 6
                and e.parts[:2] == ("mason", "packages")
                and e.parts[3] == "venv"
                and e.parts[4] == ("Scripts" if WINDOWS else "bin")
                and re.fullmatch(r"python(?:\d+(?:\.\d+)*)?(?:\.exe)?", e.parts[5]) is not None
            )
            target = entry_parts(posixpath.normpath("/".join(e.parts[:-1] + (e.link,))))
            if not in_venv and (e.link.startswith("/") or target is None or target[0] not in PARTS):
                fail(f"seed symlink {e.name!r} points outside the seed ({e.link})")
        if e.kind == "file":
            if e.size > max_file:
                fail(f"seed entry {e.name!r} is {e.size >> 20} MB, over the {max_file >> 20} MB limit (--max-file-mb)")
            total += e.size
            if total > max_total:
                fail(f"seed unpacks to more than {max_total >> 20} MB (--max-total-mb)")
    for e in entries:
        for i in range(1, len(e.parts)):
            if fold("/".join(e.parts[:i])) in links:
                fail(f"seed entry {e.name!r} goes through the symlink {'/'.join(e.parts[:i])}")
        if e.kind == "hardlink":
            target = entry_parts(e.link)
            if target is None or kinds.get(fold("/".join(target))) != "file":
                fail(f"unsafe hard link in seed: {e.name!r} -> {e.link!r}")
    return total


def extract_zip(z, entries, dest):
    for e in entries:
        target = dest.joinpath(*e.parts)
        if e.kind == "dir":
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        written = 0
        with z.open(e.src) as src, open(target, "xb") as dst:
            for chunk in iter(lambda: src.read(1 << 20), b""):
                written += len(chunk)
                if written > e.size:
                    fail(f"seed entry {e.name!r} is larger than its header says")
                dst.write(chunk)
        if not WINDOWS and e.mode & 0o777:
            os.chmod(target, e.mode & 0o777)


def remove_tree(path):
    def retry(func, p, _exc):  # git marks pack files read-only on Windows
        os.chmod(p, stat.S_IWRITE)
        func(p)

    if not os.path.lexists(path):
        return
    try:
        if sys.version_info >= (3, 12):
            shutil.rmtree(path, onexc=retry)
        else:
            shutil.rmtree(path, onerror=retry)
    except OSError as e:
        warn(f"could not remove {path}: {e}")


def promote(staging, data_dir, tops):
    """Move staging/<top> into data_dir, moving any existing <top> to a backup folder first.

    os.replace renames a symlink or junction itself instead of writing through
    it. If any move fails, every earlier one is undone. Returns the backup
    folder, or None if nothing had to be moved aside.
    """
    backup, done = None, []
    top = None
    try:
        for top in tops:
            target = data_dir / top
            if os.path.lexists(target):
                if backup is None:
                    stamp = time.strftime("%Y%m%d-%H%M%S")
                    backup = Path(tempfile.mkdtemp(prefix=f"offline-seed-backup-{stamp}-", dir=data_dir))
                os.replace(target, backup / top)
                done.append((target, backup / top))
            os.replace(staging / top, target)
            done.append((staging / top, target))
    except OSError as e:
        for src, dst in reversed(done):
            try:
                os.replace(dst, src)
            except OSError as undo:
                warn(f"could not move {dst} back to {src}: {undo}")
        if backup is not None:
            try:
                backup.rmdir()
            except OSError:
                pass
        fail(f"could not move {top} into {data_dir} ({e}); the data folder was left as it was. "
             "Quit every Neovim that uses it and try again.")
    return backup


def repair_posix_entrypoints(venv):
    """Rebase recognized Python launchers, preserving script bodies and modes.

    venv --upgrade repairs its interpreter but deliberately leaves installed
    console scripts alone. Use distlib's shell/Python wrapper format so the
    restored path may contain spaces or exceed the kernel's shebang limit.
    """
    if WINDOWS:
        return
    venv = venv.resolve()
    bindir, python = venv / "bin", venv / "bin" / "python"
    if not python.is_file():
        return
    pattern = re.compile(r"^/(?:.*/)?venv/bin/python(?:\d+(?:\.\d+)*)?$")
    coding_cookie = re.compile(br"^[ \t\f]*#.*?coding[:=][ \t]*([-_.a-zA-Z0-9]+)")
    for script in sorted(bindir.iterdir()):
        if script.is_symlink() or not script.is_file():
            continue
        try:
            script.resolve().relative_to(venv.resolve())
            with script.open("rb") as source:
                first = source.readline(8192)
                if not first.endswith(b"\n"):
                    continue
                options = []
                encoding = None
                direct = None
                if first.startswith(b"#!") and first.strip() != b"#!/bin/sh":
                    # Standard pip console scripts have an absolute interpreter
                    # followed by optional interpreter flags, never shell code.
                    direct = re.fullmatch(
                        r"(/(?:.*/)?venv/bin/python(?:\d+(?:\.\d+)*)?)(?:[ \t]+(.*))?",
                        os.fsdecode(first[2:].strip()),
                    )
                    if not direct:
                        continue
                    options = shlex.split(direct[2] or "")
                    # PEP 263 recognizes a source encoding only in the first
                    # two lines. Keep a copy in the shell wrapper's second
                    # line before moving the original body below its prefix.
                    body_offset = source.tell()
                    declaration = coding_cookie.match(source.readline(8192))
                    if declaration:
                        encoding = declaration[1]
                    source.seek(body_offset)
                elif first == b"#!/bin/sh\n":
                    second = source.readline(8192)
                    declaration = coding_cookie.match(second)
                    if declaration:
                        encoding = declaration[1]
                        second = source.readline(8192)
                    third = source.readline(8192)
                    if not second.startswith(b"'''exec' ") or third != b"' '''\n":
                        continue
                    parts = shlex.split(os.fsdecode(second[len(b"'''exec' "):].strip()))
                    if (len(parts) < 3 or parts[-2:] != ["$0", "$@"]
                            or not pattern.fullmatch(parts[0])):
                        continue
                    options = parts[1:-2]
                else:
                    continue
                # Only interpreter flags belong here; leave unfamiliar wrappers
                # untouched rather than interpreting or broadening their role.
                if any(not option.startswith("-") for option in options):
                    continue
                if direct and direct[1] == str(python):
                    continue  # An already-correct launcher needs no mutation.
                header = os.fsencode("#!" + str(python)
                                     + (" " + " ".join(options) if options else "") + "\n")
                simple = (len(header) <= 127 and len(options) <= 1
                          and not any(c.isspace() for c in str(python))
                          and not any(c.isspace() for option in options for c in option))
                if not simple:
                    command = " ".join(shlex.quote(arg) for arg in [str(python), *options])
                    header = b"#!/bin/sh\n"
                    if encoding:
                        header += b"# coding: " + encoding + b"\n"
                    header += os.fsencode("'''exec' " + command + ' "$0" "$@"\n\' \'\'\'\n')
                body_offset = source.tell()
                if direct and not simple:
                    # A shell/Python prefix is itself a module docstring. It
                    # cannot safely precede a custom docstring (or __doc__
                    # usage), especially before a from __future__ import.
                    # Inspect only bounded source bytes, never execute them.
                    body = source.read(1024 * 1024 + 1)
                    try:
                        if len(body) > 1024 * 1024:
                            raise ValueError("launcher is too large to inspect")
                        tree = ast.parse(first + body, filename=str(script))
                        if (ast.get_docstring(tree) is not None
                                or any(isinstance(node, ast.Name) and node.id == "__doc__"
                                       for node in ast.walk(tree))):
                            raise ValueError("a wrapper would change its module docstring")
                        compile(header + body, str(script), "exec", dont_inherit=True)
                    except (SyntaxError, ValueError, RecursionError) as exc:
                        warn(f"leaving custom Python launcher {script} unchanged ({exc}); "
                             "reinstall this package at its final path")
                        continue
                source.seek(0)
                if source.read(body_offset) == header:
                    continue
                source.seek(body_offset)
                fd, temp = tempfile.mkstemp(prefix=".offline-entrypoint-", dir=str(bindir))
                try:
                    with os.fdopen(fd, "wb") as dest:
                        dest.write(header)
                        shutil.copyfileobj(source, dest)
                    os.chmod(temp, stat.S_IMODE(script.stat().st_mode))
                    os.replace(temp, script)
                finally:
                    if os.path.exists(temp):
                        os.unlink(temp)
        except (OSError, RuntimeError, ValueError) as exc:
            warn(f"could not relocate Python entrypoint {script}: {exc}")


def _pe_image_end(raw):
    """End of an unsigned PE image; distlib appends its shebang here."""
    try:
        pe = struct.unpack_from("<I", raw, 60)[0]
        if raw[:2] != b"MZ" or raw[pe:pe + 4] != b"PE\0\0":
            raise ValueError("unrecognized PE executable")
        machine, count = struct.unpack_from("<HH", raw, pe + 4)
        optional_size = struct.unpack_from("<H", raw, pe + 20)[0]
        optional = pe + 24
        magic = struct.unpack_from("<H", raw, optional)[0]
        if machine not in (0x14c, 0x8664, 0xaa64) or magic not in (0x10b, 0x20b) or not 1 <= count <= 16:
            raise ValueError("unsupported PE layout")
        directory = 112 if magic == 0x20b else 96
        if optional_size < directory + 40:
            raise ValueError("truncated PE optional header")
        if (machine == 0x14c) != (magic == 0x10b) or struct.unpack_from("<I", raw, optional + directory - 4)[0] < 5:
            raise ValueError("unsupported PE data directories")
        certificate = struct.unpack_from("<II", raw, optional + directory + 32)
        if certificate != (0, 0):
            raise ValueError("signed launchers cannot be rewritten safely")
        if struct.unpack_from("<I", raw, optional + 64)[0] != 0:
            raise ValueError("checksummed launchers cannot be rewritten safely")
        end = struct.unpack_from("<I", raw, optional + 60)[0]
        sections = optional + optional_size
        for i in range(count):
            size, start = struct.unpack_from("<II", raw, sections + 40 * i + 16)
            end = max(end, start + size)
        if end < sections + 40 * count or end > len(raw):
            raise ValueError("invalid PE section boundaries")
        return end
    except struct.error as exc:
        raise ValueError("truncated PE executable") from exc


def rebase_windows_launcher(raw, source_root, target_root, command=""):
    """Rebase only an unsigned distlib-style PE + shebang + __main__.py ZIP.

    Return None for unrelated binaries. Unsupported Python overlays raise a
    portability error; the original bytes must be left untouched by callers.
    """
    if raw[:2] != b"MZ" or not zipfile.is_zipfile(io.BytesIO(raw)):
        return None
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            members = archive.infolist()
            if not any(member.filename == "__main__.py" for member in members):
                return None
            if (len(members) != 1 or archive.comment or members[0].compress_type != zipfile.ZIP_STORED
                    or members[0].flag_bits & 1 or members[0].file_size > 2**20):
                raise ValueError("custom Python ZIP overlay is not a standard distlib launcher")
            # Standard distlib overlays have one uncompressed script, no ZIP64
            # or comments, and offsets relative to the appended ZIP itself.
            if raw[-22:-18] != b"PK\x05\x06":
                raise ValueError("unsupported Python ZIP trailer")
            disk, cd_disk, entries, total, cd_size, cd_offset, comment = struct.unpack_from("<4H2IH", raw, len(raw) - 18)
            if (disk, cd_disk, entries, total, comment) != (0, 0, 1, 1, 0):
                raise ValueError("unsupported Python ZIP directory")
            zip_start = archive.start_dir - cd_offset
            if (zip_start != members[0].header_offset
                    or zip_start + cd_offset + cd_size + 22 != len(raw)
                    or raw[zip_start:zip_start + 4] != b"PK\x03\x04"):
                raise ValueError("ambiguous Python ZIP offsets")
            archive.read(members[0])  # bounded above; validate headers and CRC, never execute.
        image_end = _pe_image_end(raw)
        header = raw[image_end:zip_start]
        if not 0 < len(header) <= 8192:
            raise ValueError("unsupported Python launcher shebang")
        text = header.decode("utf-8")
        match = re.fullmatch(r'#!(?:"([^"\r\n]+)"|([^\s"\r\n]+))\r?\n', text)
        if not match:
            raise ValueError("custom Python interpreter arguments are not rewritten")
        old = match[1] or match[2]
        leaf = ntpath.basename(old).casefold()
        old_root = ntpath.dirname(ntpath.dirname(old))
        if (leaf not in ("python.exe", "pythonw.exe")
                or ntpath.basename(ntpath.dirname(old)).casefold() != "scripts"
                or ntpath.basename(old_root).casefold() != "venv"
                or not ntpath.isabs(old) or not ntpath.splitdrive(old)[0]):
            raise ValueError("launcher does not target a recognized Windows venv interpreter")
        target = ntpath.join(str(target_root), "Scripts", leaf)
        if (not ntpath.isabs(target) or not ntpath.splitdrive(target)[0]
                or any(c in target for c in '"\x00\r\n')):
            raise ValueError("invalid destination venv interpreter")
        if ntpath.normcase(ntpath.normpath(old)) == ntpath.normcase(ntpath.normpath(target)):
            return raw
        # Old manifests predate explicit provenance. A venv creation command
        # can establish the same exact source root without interpreting it.
        same_root = source_root and ntpath.normcase(ntpath.normpath(str(source_root))) == ntpath.normcase(old_root)
        suffix = " " + old_root
        legacy_root = source_root is None and " -m venv " in command and command.casefold().endswith(suffix.casefold())
        if not same_root and not legacy_root:
            raise ValueError("the launcher's source venv is not established by the seed metadata")
        new_header = ('#!"' + target + '"\n').encode("utf-8")
        return raw[:image_end] + new_header + raw[zip_start:]
    except (UnicodeError, struct.error, zipfile.BadZipFile) as exc:
        raise ValueError("unrecognized Python launcher overlay") from exc


def repair_windows_entrypoints(venv, source_root=None, command=""):
    """Relocate verified distlib entrypoints; leave unsupported executables intact."""
    venv = venv.resolve()
    complete = True
    for script in sorted((venv / "Scripts").glob("*.exe")):
        if script.is_symlink():
            if not re.fullmatch(r"python(?:w|\d+(?:\.\d+)*)?\.exe", script.name, re.I):
                warn(f"could not relocate linked Python entrypoint {script}; reinstall at its final path")
                complete = False
            continue
        if not script.is_file():
            continue
        try:
            script.resolve().relative_to(venv)
            with script.open("rb") as source:
                raw = source.read(MAX_WINDOWS_LAUNCHER_BYTES + 1)
            if len(raw) > MAX_WINDOWS_LAUNCHER_BYTES:
                # Native binaries can be large and need no relocation. Only a
                # bounded, exact Python ZIP directory makes this a known gap.
                with script.open("rb") as source:
                    source.seek(-22, os.SEEK_END)
                    trailer = source.read(22)
                    if trailer[:4] != b"PK\x05\x06":
                        continue
                    count, size = struct.unpack_from("<HI", trailer, 10)
                    if count > 1024 or size > 65536:
                        continue
                    source.seek(-22 - size, os.SEEK_END)
                    directory = source.read(size)
                names = []
                offset = 0
                for _ in range(count):
                    if directory[offset:offset + 4] != b"PK\x01\x02" or len(directory) - offset < 46:
                        break
                    name_len, extra_len, comment_len = struct.unpack_from("<3H", directory, offset + 28)
                    names.append(directory[offset + 46:offset + 46 + name_len])
                    offset += 46 + name_len + extra_len + comment_len
                if b"__main__.py" not in names:
                    continue
                raise ValueError("Python launcher exceeds the 2 MiB inspection limit")
            repaired = rebase_windows_launcher(raw, source_root, str(venv), command)
            if repaired is None or repaired == raw:
                continue
            fd, temp = tempfile.mkstemp(prefix=".offline-entrypoint-", dir=str(script.parent))
            try:
                with os.fdopen(fd, "wb") as dest:
                    dest.write(repaired)
                os.chmod(temp, stat.S_IMODE(script.stat().st_mode))
                os.replace(temp, script)
            finally:
                if os.path.exists(temp):
                    os.unlink(temp)
        except (OSError, RuntimeError, ValueError) as exc:
            complete = False
            warn(f"could not relocate Python entrypoint {script}: {exc}; reinstall at its final path")
    return complete


def repair_venvs(data_dir, source_roots=None):
    """Re-point Mason's Python venvs (debugpy, clang-format, ...) at this Python.

    A venv records the absolute path of the Python that created it; on another
    machine that path usually doesn't exist. `venv --upgrade` fixes that when
    this Python has the same major.minor version, without the network. POSIX
    console-script shebangs and verified distlib Windows launchers need separate
    relocation even when the original base Python still exists.
    """
    here = "%d.%d" % sys.version_info[:2]
    complete = True
    source_roots = source_roots or {}
    for cfg in sorted((data_dir / "mason" / "packages").glob("*/venv/pyvenv.cfg")):
        # This also protects existing data when repair_venvs is called directly:
        # never read or rewrite a cfg linked outside the selected data folder.
        if cfg.is_symlink():
            warn(f"refusing to repair linked venv configuration: {cfg}")
            complete = False
            continue
        try:
            cfg.resolve().relative_to(data_dir.resolve())
        except (OSError, RuntimeError, ValueError):
            warn(f"refusing to repair venv outside the data folder or through invalid links: {cfg}")
            complete = False
            continue
        vals = {}
        for line in cfg.read_text(encoding="utf-8", errors="replace").splitlines():
            key, sep, val = line.partition("=")
            if sep:
                vals[key.strip()] = val.strip()
        home = vals.get("home", "")
        python = cfg.parent / ("Scripts/python.exe" if WINDOWS else "bin/python")
        if home and Path(home).exists() and python.is_file():
            if WINDOWS:
                complete = repair_windows_entrypoints(cfg.parent, source_roots.get(cfg.parent.parent.name), vals.get("command", "")) and complete
            else:
                repair_posix_entrypoints(cfg.parent)
            continue
        name = cfg.parent.parent.name
        version = vals.get("version") or vals.get("version_info", "")
        if ".".join(version.split(".")[:2]) != here:
            warn(f"Mason package {name} needs Python {version} (its venv points at {home}); "
                 f"this is Python {platform.python_version()}. Install Python {version[:4]} and run "
                 f"this install again with --force, or {name} won't start.")
            complete = False
            continue
        # `venv --upgrade` fails on the dangling bin/python* links left by the old home.
        for exe in (cfg.parent / ("Scripts" if WINDOWS else "bin")).glob("python*"):
            if exe.is_symlink() and not exe.exists():
                exe.unlink()
        res = subprocess.run([sys.executable, "-m", "venv", "--upgrade", "--without-pip", str(cfg.parent)],
                             capture_output=True, text=True)
        if res.returncode == 0:
            if WINDOWS:
                complete = repair_windows_entrypoints(cfg.parent, source_roots.get(name), vals.get("command", "")) and complete
            else:
                repair_posix_entrypoints(cfg.parent)
            print(f"  re-pointed {name}'s venv at {sys.executable}")
        else:
            warn(f"could not repair {name}'s venv (exit {res.returncode}): {(res.stderr or res.stdout).strip()}")
            complete = False
    return complete


def open_seed(seed, is_zip=None):
    if is_zip is None:
        is_zip = seed.name.endswith(".zip")
    return zipfile.ZipFile(seed) if is_zip else tarfile.open(seed, "r:*")


def seed_entries(archive):
    return zip_entries(archive) if isinstance(archive, zipfile.ZipFile) else tar_entries(archive)


def cmd_install(args):
    seed = Path(args.seed).resolve()
    if not seed.is_file():
        fail(f"no such file: {seed}")
    verify_checksum(seed, args.sha256, args.no_verify)
    manifest = read_manifest(seed)
    plat = this_platform()
    if manifest.get("platform") != plat:
        msg = f"seed was built for {manifest.get('platform')}, this machine is {plat}"
        if not args.allow_platform_mismatch:
            fail(msg + "; its Mason tools and parsers won't run here (--allow-platform-mismatch installs anyway)")
        warn(msg)
    lock_path = CONFIG_DIR / "lazy-lock.json"
    if lock_path.is_file() and hashlib.sha256(lock_path.read_bytes()).hexdigest() != manifest.get("lockfile_sha256"):
        msg = "the seed was built from a different lazy-lock.json than this config's"
        if not args.allow_lock_mismatch:
            fail(msg + ". Use the config the seed was built with, or pass --allow-lock-mismatch "
                 "(plugins then run at the seed's commits, and :Lazy restore needs the network).")
        warn(msg)

    data_dir = Path(args.data_dir) if args.data_dir else default_data_dir()
    with open_seed(seed) as archive:
        entries = seed_entries(archive)
        total = validate(entries, args.max_entries, int(args.max_total_mb * 2**20), int(args.max_file_mb * 2**20))
        tops = sorted({e.parts[0] for e in entries})
        present = [p for p in tops if os.path.lexists(data_dir / p)]
        if present and not args.force:
            fail(f"{data_dir} already has {', '.join(present)}. Move it aside first, or pass --force "
                 "to replace it (the old one is moved to a backup folder, not merged).")
        data_dir.mkdir(parents=True, exist_ok=True)
        free = shutil.disk_usage(data_dir).free
        if free < total + 2**26:
            fail(f"the seed unpacks to {total >> 20} MB but {data_dir} has only {free >> 20} MB free")
        print(f"Unpacking {seed.name} ({'; '.join(manifest.get('contents', []))})\n  -> {data_dir}")
        staging = Path(tempfile.mkdtemp(prefix=".offline-seed-staging-", dir=data_dir))
        try:
            if isinstance(archive, zipfile.ZipFile):
                extract_zip(archive, entries, staging)
            elif hasattr(tarfile, "tar_filter"):
                # Not the "data" filter: it rejects a venv's absolute bin/python link,
                # and some patch releases also reject Mason's relative bin/ links.
                archive.extractall(staging, [e.src for e in entries], filter="tar")
            else:
                archive.extractall(staging, [e.src for e in entries])
            backup = promote(staging, data_dir, tops)
        finally:
            remove_tree(staging)
    if backup is not None:
        print(f"  the previous {', '.join(present)} moved to {backup}; delete it once nvim works")
    if "mason" in tops:
        if not repair_venvs(data_dir, manifest.get("python_venv_roots", {})):
            fail("seed files were installed, but Python tooling relocation is incomplete; "
                 "review the warnings and reinstall affected packages at their final paths. "
                 "Any previous data remains in the backup shown above.")
    print("Done. Start nvim; :checkhealth should report no downloads pending.")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    data_help = "Neovim data dir (default: stdpath('data') for this config)"

    c = sub.add_parser("check", help="list what this install would still download")
    c.add_argument("--data-dir", help=data_help)
    c.set_defaults(func=cmd_check)

    b = sub.add_parser("build", help="write a seed from this machine's install")
    b.add_argument("--data-dir", help=data_help)
    b.add_argument("--out-dir", default=".", help="where the archive goes (default: current dir)")
    b.add_argument("--only", help="comma list of lazy,mason,site (default: all)")
    b.add_argument("--allow-mismatch", action="store_true",
                   help="pack even if plugins differ from lazy-lock.json or something is missing")
    b.add_argument("--no-check", action="store_true", help="skip the Mason/parser completeness check")
    b.set_defaults(func=cmd_build)

    i = sub.add_parser("install", help="unpack a seed into the data dir")
    i.add_argument("seed")
    i.add_argument("--data-dir", help=data_help)
    i.add_argument("--force", action="store_true",
                   help="replace existing lazy/, mason/, site/ (moved to a backup folder first)")
    i.add_argument("--sha256", help="expected SHA-256 of the seed, from a source you trust "
                                    "(default: compare with <seed>.sha256)")
    i.add_argument("--no-verify", action="store_true", help="skip the checksum comparison")
    i.add_argument("--allow-lock-mismatch", action="store_true",
                   help="install a seed built from a different lazy-lock.json")
    i.add_argument("--allow-platform-mismatch", action="store_true",
                   help="install a seed built for another OS or CPU")
    i.add_argument("--max-total-mb", type=float, default=MAX_TOTAL_MB,
                   help=f"refuse a seed that unpacks to more than this (default {MAX_TOTAL_MB})")
    i.add_argument("--max-file-mb", type=float, default=MAX_FILE_MB,
                   help=f"refuse a seed with a larger file than this (default {MAX_FILE_MB})")
    i.add_argument("--max-entries", type=int, default=MAX_ENTRIES,
                   help=f"refuse a seed with more entries than this (default {MAX_ENTRIES})")
    i.set_defaults(func=cmd_install)

    args = ap.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
