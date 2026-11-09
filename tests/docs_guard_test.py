"""Prove that documentation drift guards fail on deliberately broken inputs.

Use a disposable copy of the tracked tree; never modify the working checkout.
The tests invoke the real POSIX shell guard, not a reimplementation.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DocumentationGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nvim-doc-drift-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        for name in ("lua", "tests", "docs", "scripts", ".githooks", ".github", "scoper.nvim"):
            shutil.copytree(ROOT / name, self.repo / name)
        for source in ROOT.iterdir():
            if source.is_file() and source.name != "local.lua":
                shutil.copy2(source, self.repo / source.name)

    def check(self):
        env = os.environ.copy()
        # Limit this test to documentation guards, not installed clang-format.
        env["CLANG_FORMAT"] = "__nvim_docs_test_missing_clang_format__"
        return subprocess.run(
            ["sh", "scripts/check-docs.sh"],
            cwd=self.repo, env=env,
            capture_output=True, text=True, check=False,
            timeout=30,
        )

    def test_pristine_tree_passes(self):
        result = self.check()
        self.assertEqual(0, result.returncode, result.stderr)

    def test_missing_middle_numeric_leader_mapping_fails(self):
        path = self.repo / "lua/plugins/ui.lua"
        content, count = re.subn(
            r'(?m)^.*\{ "<leader>5".*\n', "", path.read_text(encoding="utf-8"),
        )
        self.assertEqual(1, count)
        path.write_text(content, encoding="utf-8")
        result = self.check()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("leader map in keymaps.html but not in source: <leader>5", result.stderr)

    def test_missing_documented_numeric_mapping_fails(self):
        path = self.repo / "docs/cheatsheets/keymaps.html"
        original = path.read_text(encoding="utf-8")
        self.assertEqual(1, original.count("&lt;leader&gt;0"))
        path.write_text(original.replace("&lt;leader&gt;0", "&lt;leader&gt;9"), encoding="utf-8")
        result = self.check()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("leader map in source but not in keymaps.html: <leader>0", result.stderr)


if __name__ == "__main__":
    unittest.main()
