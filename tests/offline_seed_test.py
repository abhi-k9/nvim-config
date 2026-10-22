"""Tests for scripts/offline-seed.py: hostile seeds, install safety, fail-closed check.

    python3 -m unittest discover -s tests -p "offline_seed_test.py" -v

Standard library only. Everything happens in temporary folders; the real
Neovim data folder and the real nvim are never touched (the completeness
check runs against a fake nvim put first on PATH).
"""

import argparse
import importlib.util
import io
import json
import os
import shlex
import shutil
import stat
import sys
import tarfile
import tempfile
import unittest
import warnings
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("offline_seed", ROOT / "scripts" / "offline-seed.py")
S = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(S)

WINDOWS = os.name == "nt"
FILES = {
    "lazy/plug/": None,
    "lazy/plug/init.lua": b"return 1\n",
    "mason/packages/tool/tool": b"#!/bin/sh\necho ok\n",
    "site/parser/lua.so": b"so",
}


def manifest(**over):
    m = {"platform": S.this_platform(), "lockfile_sha256": S.read_lock()[1], "contents": ["test"]}
    m.update(over)
    return json.dumps(m).encode()


def make_zip(path, files=FILES, man=None, extra=(), sidecar=True):
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")  # duplicate-name tests
        with zipfile.ZipFile(path, "w") as z:
            z.writestr(S.MANIFEST, man if man is not None else manifest())
            for name, data in files.items():
                z.writestr(name, b"" if data is None else data)
            for info, data in extra:
                z.writestr(info, data)
    if sidecar:
        S.write_checksum(path)
    return path


def tar_member(name, kind="file", data=b"", link="", mode=0o644):
    info = tarfile.TarInfo(name)
    info.mode = mode
    info.type = {"file": tarfile.REGTYPE, "dir": tarfile.DIRTYPE, "symlink": tarfile.SYMTYPE,
                 "hardlink": tarfile.LNKTYPE, "chr": tarfile.CHRTYPE, "fifo": tarfile.FIFOTYPE}[kind]
    info.linkname = link
    if kind == "file":
        info.size = len(data)
    return info, (io.BytesIO(data) if kind == "file" else None)


def make_tar(path, members, man=None):
    with tarfile.open(path, "w:gz") as t:
        t.addfile(*tar_member(S.MANIFEST, data=man if man is not None else manifest()))
        for args in members:
            t.addfile(*tar_member(*args))
    S.write_checksum(path)
    return path


def can_symlink(tmp):
    try:
        os.symlink(tmp, os.path.join(tmp, ".probe"), target_is_directory=True)
    except (OSError, NotImplementedError):
        return False
    os.unlink(os.path.join(tmp, ".probe"))
    return True


def dir_link(target, link):
    """A directory symlink, or on Windows without the privilege, a junction."""
    try:
        os.symlink(target, link, target_is_directory=True)
        return True
    except OSError:
        if not WINDOWS:
            return False
    import _winapi

    try:
        _winapi.CreateJunction(str(target), str(link))
    except OSError:
        return False
    return True


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="seed-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.data = self.tmp / S.data_dir_name()

    def install(self, seed, **kw):
        """Exit code of `install`: 0, or the failure message."""
        args = dict(seed=str(seed), data_dir=str(self.data), force=False, sha256=None, no_verify=False,
                    allow_lock_mismatch=False, allow_platform_mismatch=False, max_total_mb=S.MAX_TOTAL_MB,
                    max_file_mb=S.MAX_FILE_MB, max_entries=S.MAX_ENTRIES)
        args.update(kw)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            try:
                return S.cmd_install(argparse.Namespace(**args))
            except SystemExit as e:
                return e.code

    def assertRefused(self, code, words):
        self.assertIsInstance(code, str, "install should have failed")
        self.assertIn(words, code)

    def leftovers(self):
        if not self.data.exists():
            return []
        return [p.name for p in self.data.iterdir() if p.name.startswith((".offline-seed-staging", "offline-seed-backup"))]

    def outside(self):
        """Every path under tmp except the data dir and the seeds: nothing may appear here."""
        return sorted(str(p.relative_to(self.tmp)) for p in self.tmp.rglob("*")
                      if self.data not in p.parents and p != self.data and not p.name.startswith("seed"))


class RoundTrip(Base):
    def test_zip_installs_and_verifies_sidecar(self):
        seed = make_zip(self.tmp / "seed.zip")
        self.assertEqual(self.install(seed), 0)
        self.assertEqual((self.data / "lazy" / "plug" / "init.lua").read_bytes(), b"return 1\n")
        self.assertTrue((self.data / "site" / "parser" / "lua.so").is_file())
        self.assertTrue((self.data / S.MANIFEST).is_file())
        self.assertEqual(self.leftovers(), [])

    def test_tar_keeps_links_and_modes(self):
        if WINDOWS and not can_symlink(str(self.tmp)):
            self.skipTest("no symlink privilege")
        seed = make_tar(self.tmp / "seed.tar.gz", [
            ("mason/packages/tool/tool", "file", b"#!/bin/sh\n", "", 0o755),
            ("mason/bin/tool", "symlink", b"", "../packages/tool/tool"),
            ("mason/packages/tool/copy", "hardlink", b"", "mason/packages/tool/tool", 0o755),
            ("mason/packages/py/venv/bin/python", "symlink", b"", "/nonexistent/python3"),
        ])
        self.assertEqual(self.install(seed), 0)
        self.assertEqual(os.readlink(self.data / "mason" / "bin" / "tool"), "../packages/tool/tool")
        if not WINDOWS:
            self.assertTrue(os.stat(self.data / "mason" / "packages" / "tool" / "tool").st_mode & stat.S_IXUSR)
        self.assertTrue((self.data / "mason" / "packages" / "tool" / "copy").is_file())


class HostileSeeds(Base):
    def test_zip_paths_outside_are_refused(self):
        for name in ("../evil.txt", "lazy/../../evil.txt", "/abs.txt", "C:/evil.txt", "lazy\\..\\..\\evil.txt"):
            with self.subTest(name=name):
                seed = make_zip(self.tmp / "seed.zip", {**FILES, name: b"x"})
                self.assertRefused(self.install(seed), "unsafe path")
                self.assertEqual(self.outside(), [])
                self.assertEqual(self.leftovers(), [])

    def test_unexpected_top_level_is_refused(self):
        seed = make_zip(self.tmp / "seed.zip", {**FILES, "sessions/x.vim": b"x"})
        self.assertRefused(self.install(seed), "unexpected entry")

    def test_top_level_file_where_folder_belongs_is_refused(self):
        seed = make_zip(self.tmp / "seed.zip", {"lazy": b"x"})
        self.assertRefused(self.install(seed), "wrong type")

    def test_duplicate_entries_are_refused(self):
        seed = make_zip(self.tmp / "seed.zip", extra=[(zipfile.ZipInfo("lazy/plug/init.lua"), b"two")])
        self.assertRefused(self.install(seed), "duplicate")

    def test_zip_symlink_entry_is_refused(self):
        info = zipfile.ZipInfo("lazy/plug/link")
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        seed = make_zip(self.tmp / "seed.zip", extra=[(info, b"/etc")])
        self.assertRefused(self.install(seed), "unexpected entry type")

    def test_tar_write_through_archive_symlink_is_refused(self):
        seed = make_tar(self.tmp / "seed.tar.gz", [
            ("mason/link", "symlink", b"", "../site"),
            ("mason/link/x", "file", b"x"),
        ])
        self.assertRefused(self.install(seed), "goes through the symlink")

    def test_tar_symlink_out_of_seed_is_refused(self):
        for link in ("/bin/sh", "../../../etc", "../../outside"):
            with self.subTest(link=link):
                seed = make_tar(self.tmp / "seed.tar.gz", [("mason/bin/x", "symlink", b"", link)])
                self.assertRefused(self.install(seed), "points outside the seed")

    def test_tar_venv_exemption_applies_only_to_python_executables(self):
        victim = self.tmp / "outside.cfg"
        original = f"home = /missing/python\nversion = {sys.version_info[0]}.{sys.version_info[1]}.0\n"
        victim.write_text(original)
        for name in ("pyvenv.cfg", "bin/not-python", "lib/anything"):
            with self.subTest(name=name):
                seed = make_tar(self.tmp / "seed.tar.gz", [
                    (f"mason/packages/tool/venv/{name}", "symlink", b"", str(victim)),
                ])
                self.assertRefused(self.install(seed), "points outside the seed")
                self.assertEqual(victim.read_text(), original)

    def test_repair_does_not_follow_existing_external_venv_cfg(self):
        if not can_symlink(str(self.tmp)):
            self.skipTest("no symlink privilege")
        victim = self.tmp / "outside.cfg"
        original = f"home = /missing/python\nversion = {sys.version_info[0]}.{sys.version_info[1]}.0\n"
        victim.write_text(original)
        cfg = self.data / "mason" / "packages" / "tool" / "venv" / "pyvenv.cfg"
        cfg.parent.mkdir(parents=True)
        cfg.symlink_to(victim)
        with mock.patch.object(S.subprocess, "run") as run, redirect_stderr(io.StringIO()):
            S.repair_venvs(self.data)
        run.assert_not_called()
        self.assertEqual(victim.read_text(), original)

    def test_repair_skips_a_cyclic_venv_cfg(self):
        if not can_symlink(str(self.tmp)):
            self.skipTest("no symlink privilege")
        cfg = self.data / "mason" / "packages" / "tool" / "venv" / "pyvenv.cfg"
        cfg.parent.mkdir(parents=True)
        cfg.symlink_to(cfg.name)
        with mock.patch.object(S.subprocess, "run") as run, redirect_stderr(io.StringIO()):
            S.repair_venvs(self.data)
        run.assert_not_called()
        self.assertTrue(cfg.is_symlink())

    def test_tar_hard_link_out_of_seed_is_refused(self):
        for link in ("/etc/passwd", "../etc/passwd", "mason/absent"):
            with self.subTest(link=link):
                seed = make_tar(self.tmp / "seed.tar.gz", [("mason/x", "hardlink", b"", link)])
                self.assertRefused(self.install(seed), "unsafe hard link")

    def test_tar_devices_are_refused(self):
        for kind in ("chr", "fifo"):
            with self.subTest(kind=kind):
                seed = make_tar(self.tmp / "seed.tar.gz", [("mason/dev", kind)])
                self.assertRefused(self.install(seed), "unexpected entry type")


class Limits(Base):
    def test_entry_count(self):
        self.assertRefused(self.install(make_zip(self.tmp / "seed.zip"), max_entries=2), "--max-entries")

    def test_file_size(self):
        seed = make_zip(self.tmp / "seed.zip", {**FILES, "site/big": b"x" * 4096})
        self.assertRefused(self.install(seed, max_file_mb=0.001), "--max-file-mb")

    def test_total_size(self):
        seed = make_zip(self.tmp / "seed.zip", {f"site/f{i}": b"x" * 800 for i in range(3)})
        self.assertRefused(self.install(seed, max_total_mb=0.002), "--max-total-mb")

    def test_free_space_checked_before_writing(self):
        full = shutil._ntuple_diskusage(100, 100, 0)
        with mock.patch.object(S.shutil, "disk_usage", return_value=full):
            self.assertRefused(self.install(make_zip(self.tmp / "seed.zip")), "free")
        self.assertEqual(list(self.data.iterdir()), [])


class Authenticity(Base):
    def test_sidecar_mismatch(self):
        seed = make_zip(self.tmp / "seed.zip")
        Path(str(seed) + ".sha256").write_text("0" * 64 + "  seed.zip\n")
        self.assertRefused(self.install(seed), "checksum mismatch")
        self.assertFalse(self.data.exists())

    def test_explicit_hash(self):
        seed = make_zip(self.tmp / "seed.zip", sidecar=False)
        self.assertRefused(self.install(seed, sha256="f" * 64), "checksum mismatch")
        self.assertEqual(self.install(seed, sha256=S.sha256_of(seed).upper()), 0)

    def test_no_checksum_needs_no_verify(self):
        seed = make_zip(self.tmp / "seed.zip", sidecar=False)
        self.assertRefused(self.install(seed), "--no-verify")
        self.assertEqual(self.install(seed, no_verify=True), 0)

    def test_lock_mismatch(self):
        seed = make_zip(self.tmp / "seed.zip", man=manifest(lockfile_sha256="0" * 64))
        self.assertRefused(self.install(seed), "--allow-lock-mismatch")
        self.assertEqual(self.install(seed, allow_lock_mismatch=True), 0)

    def test_platform_mismatch(self):
        seed = make_zip(self.tmp / "seed.zip", man=manifest(platform="plan9-mips"))
        self.assertRefused(self.install(seed), "--allow-platform-mismatch")
        self.assertEqual(self.install(seed, allow_platform_mismatch=True), 0)


class ExistingData(Base):
    def test_refused_without_force(self):
        (self.data / "lazy").mkdir(parents=True)
        (self.data / "lazy" / "mine.txt").write_text("keep")
        self.assertRefused(self.install(make_zip(self.tmp / "seed.zip")), "--force")
        self.assertEqual((self.data / "lazy" / "mine.txt").read_text(), "keep")

    def test_dangling_link_counts_as_existing(self):
        self.data.mkdir()
        if not dir_link(self.tmp / "gone", self.data / "lazy"):
            self.skipTest("no directory links here")
        self.assertRefused(self.install(make_zip(self.tmp / "seed.zip")), "--force")

    def test_force_moves_old_parts_to_backup(self):
        (self.data / "lazy").mkdir(parents=True)
        (self.data / "lazy" / "stale.txt").write_text("old")
        self.assertEqual(self.install(make_zip(self.tmp / "seed.zip"), force=True), 0)
        self.assertFalse((self.data / "lazy" / "stale.txt").exists())
        backups = [p for p in self.data.iterdir() if p.name.startswith("offline-seed-backup")]
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "lazy" / "stale.txt").read_text(), "old")

    def test_force_never_writes_through_existing_link(self):
        """S2-001: data/lazy is a link to a folder outside; --force must not write there."""
        victim = self.tmp / "victim"
        victim.mkdir()
        (victim / "precious.txt").write_text("mine")
        self.data.mkdir()
        if not dir_link(victim, self.data / "lazy"):
            self.skipTest("no directory links here")
        self.assertEqual(self.install(make_zip(self.tmp / "seed.zip"), force=True), 0)
        self.assertEqual(sorted(p.name for p in victim.iterdir()), ["precious.txt"])
        lazy = self.data / "lazy"
        self.assertFalse(lazy.is_symlink())
        self.assertTrue((lazy / "plug" / "init.lua").is_file())
        backup = next(p for p in self.data.iterdir() if p.name.startswith("offline-seed-backup"))
        self.assertEqual(sorted(p.name for p in (backup / "lazy").iterdir()), ["precious.txt"])
        if WINDOWS:
            os.rmdir(backup / "lazy")  # removes the link, not the victim
        else:
            os.unlink(backup / "lazy")

    def test_failed_swap_rolls_back(self):
        (self.data / "lazy").mkdir(parents=True)
        (self.data / "lazy" / "stale.txt").write_text("old")
        real = os.replace

        def flaky(src, dst):
            if Path(src).name == "mason" and ".offline-seed-staging" in str(src):
                raise PermissionError("in use")
            return real(src, dst)

        with mock.patch.object(S.os, "replace", side_effect=flaky):
            code = self.install(make_zip(self.tmp / "seed.zip"), force=True)
        self.assertRefused(code, "left as it was")
        self.assertEqual((self.data / "lazy" / "stale.txt").read_text(), "old")
        self.assertFalse((self.data / "lazy" / "plug").exists())
        self.assertFalse((self.data / "mason").exists())
        self.assertEqual(self.leftovers(), [])


FAKE_NVIM = """\
import json, os, sys, time
mode = os.environ["FAKE_NVIM_MODE"]
out = os.environ.get("OFFLINE_SEED_CHECK_OUT")
if mode == "crash":
    sys.exit(13)
if mode == "silent":
    sys.exit(0)
if mode == "hang":
    time.sleep(5)
    sys.exit(0)
text = {
    "partial": "{",
    "error": json.dumps({"version": 1, "error": "boom"}),
    "wrongtype": json.dumps({"version": 1, "missing": "everything"}),
    "gaps": json.dumps({"version": 1, "missing": ["missing parser gitcommit"]}),
    "complete": json.dumps({"version": 1, "missing": {}}),
}[mode]
with open(out, "w") as f:
    f.write(text)
sys.exit(1 if mode == "error" else 0)
"""


class CompletenessCheck(Base):
    def setUp(self):
        super().setUp()
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        (bin_dir / "fake_nvim.py").write_text(FAKE_NVIM)
        if WINDOWS:
            (bin_dir / "nvim.cmd").write_text(f'@"{sys.executable}" "{bin_dir / "fake_nvim.py"}" %*\n')
        else:
            sh = bin_dir / "nvim"
            sh.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{bin_dir / "fake_nvim.py"}" "$@"\n')
            sh.chmod(0o755)
        path = mock.patch.dict(os.environ, {"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"})
        path.start()
        self.addCleanup(path.stop)
        self.data.mkdir()

    def check(self, mode):
        with mock.patch.dict(os.environ, {"FAKE_NVIM_MODE": mode}):
            return S.run_check(self.data)

    def test_failures_never_read_as_complete(self):
        for mode, words in (("crash", "without writing"), ("silent", "without writing"),
                            ("partial", "without writing"), ("error", "boom"), ("wrongtype", "malformed")):
            with self.subTest(mode=mode):
                with self.assertRaises(S.CheckFailed) as cm:
                    self.check(mode)
                self.assertIn(words, str(cm.exception))

    def test_timeout(self):
        with mock.patch.object(S, "CHECK_TIMEOUT", 1), self.assertRaises(S.CheckFailed):
            self.check("hang")

    def test_reports(self):
        self.assertEqual(self.check("gaps"), ["missing parser gitcommit"])
        self.assertEqual(self.check("complete"), [])

    def test_wrong_data_dir_name(self):
        with self.assertRaises(S.CheckFailed):
            S.run_check(self.tmp / "elsewhere")

    def test_check_and_build_exit_codes(self):
        ns = argparse.Namespace(data_dir=str(self.data))
        for mode, code in (("crash", 2), ("gaps", 1), ("complete", 0)):
            with self.subTest(mode=mode), mock.patch.dict(os.environ, {"FAKE_NVIM_MODE": mode}), \
                    redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(S.cmd_check(ns), code)
        (self.data / "lazy").mkdir()
        build = argparse.Namespace(data_dir=str(self.data), out_dir=str(self.tmp / "out"), only=None,
                                   allow_mismatch=False, no_check=False)
        with mock.patch.dict(os.environ, {"FAKE_NVIM_MODE": "crash"}), redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as cm:
                S.cmd_build(build)
        self.assertIn("--no-check", str(cm.exception.code))


@unittest.skipIf(WINDOWS, "POSIX console scripts; Windows native launchers are not rewritten")
class VenvRelocation(Base):
    def make_relocated_venv(self, destination=None, shell_wrapper=False):
        old = self.tmp / "builder" / "venv"
        old.parent.mkdir()
        result = S.subprocess.run(
            [sys.executable, "-m", "venv", "--without-pip", str(old)],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        body = b"import sys\nprint('ENTRYPOINT_OK:' + sys.prefix)\n"
        if shell_wrapper:
            header = ("#!/bin/sh\n'''exec' " + shlex.quote(str(old / "bin" / "python"))
                      + ' "$0" "$@"\n\' \'\'\'\n').encode()
        else:
            header = ("#!" + str(old / "bin" / "python") + "\n").encode()
        (old / "bin" / "report").write_bytes(header + body)
        (old / "bin" / "report").chmod(0o751)
        destination = destination or self.data / "mason" / "packages" / "tool" / "venv"
        destination.parent.mkdir(parents=True)
        old.rename(destination)
        return destination, body

    def assert_launcher_works(self, venv):
        result = S.subprocess.run([str(venv / "bin" / "report")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "ENTRYPOINT_OK:" + str(venv))

    def test_relocates_console_script_even_when_base_python_still_exists(self):
        venv, body = self.make_relocated_venv()
        with self.assertRaises(FileNotFoundError):
            self.assert_launcher_works(venv)
        S.repair_venvs(self.data)
        self.assert_launcher_works(venv)
        script = venv / "bin" / "report"
        self.assertTrue(script.read_bytes().endswith(body))
        self.assertEqual(stat.S_IMODE(script.stat().st_mode), 0o751)
        before = (script.read_bytes(), script.stat().st_ino)
        S.repair_venvs(self.data)
        self.assertEqual((script.read_bytes(), script.stat().st_ino), before)

    def test_relocates_distlib_wrapper_to_long_path_with_spaces_and_quotes(self):
        destination = (self.data / "mason" / "packages" / ("long space's " + "x" * 130) / "venv")
        venv, body = self.make_relocated_venv(destination, shell_wrapper=True)
        S.repair_venvs(self.data)
        self.assert_launcher_works(venv)
        self.assertTrue((venv / "bin" / "report").read_bytes().endswith(body))

    def test_relocates_entrypoint_after_interpreter_upgrade(self):
        venv, _ = self.make_relocated_venv()
        cfg = venv / "pyvenv.cfg"
        text = cfg.read_text()
        text = "\n".join("home = /missing/build-python" if line.startswith("home =") else line
                         for line in text.splitlines()) + "\n"
        cfg.write_text(text)
        with redirect_stdout(io.StringIO()):
            S.repair_venvs(self.data)
        self.assert_launcher_works(venv)

    def test_preserves_latin1_source_encoding_across_repair_and_repeat(self):
        destination = self.data / "mason" / "packages" / "latin1 space" / "venv"
        venv, _ = self.make_relocated_venv(destination)
        script = venv / "bin" / "report"
        body = b"# -*- coding: latin-1 -*-\nprint('caf\xe9')\n"
        script.write_bytes(b"#!/old/venv/bin/python\n" + body)
        script.chmod(0o751)

        S.repair_venvs(self.data)
        result = S.subprocess.run([str(script)], capture_output=True,
                                  env=dict(os.environ, PYTHONIOENCODING="utf-8"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.decode("utf-8").strip(), "caf\u00e9")
        self.assertTrue(script.read_bytes().endswith(body))
        self.assertEqual(script.read_bytes().splitlines()[1], b"# coding: latin-1")
        self.assertEqual(stat.S_IMODE(script.stat().st_mode), 0o751)
        before = (script.read_bytes(), script.stat().st_ino)

        S.repair_venvs(self.data)
        self.assertEqual((script.read_bytes(), script.stat().st_ino), before)
        result = S.subprocess.run([str(script)], capture_output=True,
                                  env=dict(os.environ, PYTHONIOENCODING="utf-8"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.decode("utf-8").strip(), "caf\u00e9")

    def test_keeps_direct_shebang_for_docstrings_and_future_imports(self):
        venv, _ = self.make_relocated_venv()
        script = venv / "bin" / "report"
        body = b'"""original module documentation"""\nfrom __future__ import annotations\nprint(__doc__)\n'
        script.write_bytes(b"#!/old/venv/bin/python\n" + body)
        script.chmod(0o751)
        S.repair_venvs(self.data)
        result = S.subprocess.run([str(script)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "original module documentation")
        self.assertEqual(script.read_bytes(), os.fsencode("#!" + str(venv / "bin/python") + "\n") + body)

    def test_leaves_an_already_correct_direct_launcher_and_flag_untouched(self):
        venv, body = self.make_relocated_venv()
        script = venv / "bin" / "report"
        script.write_bytes(os.fsencode("#!" + str(venv / "bin/python") + " -s\n") + body)
        before = (script.read_bytes(), script.stat().st_ino)
        S.repair_venvs(self.data)
        self.assertEqual((script.read_bytes(), script.stat().st_ino), before)
        self.assert_launcher_works(venv)

    def test_refuses_unsafe_wrapper_conversion_for_a_custom_docstring(self):
        destination = self.data / "mason" / "packages" / "custom space" / "venv"
        venv, _ = self.make_relocated_venv(destination)
        script = venv / "bin" / "report"
        body = b'"""custom docs"""\nfrom __future__ import annotations\nprint(__doc__)\n'
        script.write_bytes(b"#!/old/venv/bin/python\n" + body)
        before = (script.read_bytes(), script.stat().st_ino)
        errors = io.StringIO()
        with redirect_stderr(errors):
            S.repair_venvs(self.data)
        self.assertEqual((script.read_bytes(), script.stat().st_ino), before)
        self.assertIn("leaving custom Python launcher", errors.getvalue())
        self.assertIn("reinstall this package at its final path", errors.getvalue())

    def test_skips_linked_scripts_and_unrelated_interpreters(self):
        venv, _ = self.make_relocated_venv()
        outside = self.tmp / "outside.py"
        original = b"#!/old/venv/bin/python\nprint('must remain unchanged')\n"
        outside.write_bytes(original)
        (venv / "bin" / "linked-script").symlink_to(outside)
        unrelated = venv / "bin" / "system-script"
        unrelated.write_bytes(b"#!/usr/bin/python3\nprint('system script')\n")
        S.repair_venvs(self.data)
        self.assertTrue((venv / "bin" / "linked-script").is_symlink())
        self.assertEqual(outside.read_bytes(), original)
        self.assertEqual(unrelated.read_bytes(), b"#!/usr/bin/python3\nprint('system script')\n")


if __name__ == "__main__":
    unittest.main()
