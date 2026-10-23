import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


MODULE = Path(__file__).resolve().parents[1] / "scripts" / "update-ci-actions.py"
SPEC = importlib.util.spec_from_file_location("ci_actions", MODULE)
actions = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(actions)


class ActionPins(unittest.TestCase):
    def test_mutable_refs_are_rejected_by_local_check(self):
        with self.assertRaisesRegex(ValueError, "Mutable"):
            actions.check_pins("  - uses: actions/checkout@v7\n")

    def test_subactions_share_a_single_repository_resolution(self):
        calls = []
        def resolve(repo, ref):
            calls.append((repo, ref))
            return "a" * 40
        source = "  - uses: tree-sitter/setup-action/cli@v2\n  - uses: tree-sitter/setup-action@v2\n"
        output, _ = actions.updated(source, resolver=resolve)
        self.assertEqual(calls, [("tree-sitter/setup-action", "v2")])
        self.assertEqual(output.count("@" + "a" * 40 + " # v2"), 2)
        actions.check_pins(output)

    def test_explicit_track_change_preserves_the_subaction(self):
        source = f"uses: owner/action/cli@{'a' * 40} # v2\n"
        output, _ = actions.updated(source, {"owner/action": "v3"}, lambda repo, ref: "b" * 40)
        self.assertEqual(output, f"uses: owner/action/cli@{'b' * 40} # v3\n")

    def test_missing_track_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Missing update"):
            actions.check_pins(f"uses: owner/action@{'a' * 40}\n")

    def test_inconsistent_pins_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Inconsistent"):
            actions.check_pins(f"uses: owner/action@{'a' * 40} # v1\nuses: owner/action@{'b' * 40} # v1\n")

    def test_local_actions_are_left_unchanged(self):
        source = "uses: ./local/action\nuses: owner/action@v1\n"
        output, _ = actions.updated(source, resolver=lambda repo, ref: "c" * 40)
        self.assertTrue(output.startswith("uses: ./local/action\n"))

    def test_failed_resolution_never_writes_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ci.yml"
            original = "uses: owner/action@v1\n"
            path.write_text(original)
            with patch.object(actions, "WORKFLOW", path), patch.object(actions.subprocess, "run", side_effect=subprocess.TimeoutExpired("gh", 30)):
                self.assertEqual(actions.main([]), 1)
            self.assertEqual(path.read_text(), original)

    def test_invalid_remote_commit_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Invalid resolved"):
            actions.updated("uses: owner/action@v1\n", resolver=lambda repo, ref: "not-a-sha")
        for payload in ("[]", '{"sha": 42}'):
            with self.subTest(payload=payload), patch.object(
                actions.subprocess, "run", return_value=subprocess.CompletedProcess(["gh"], 0, payload)
            ), self.assertRaisesRegex(ValueError, "invalid commit"):
                actions.resolve("owner/action", "v1")

    def test_unknown_override_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unknown action"):
            actions.updated("uses: owner/action@v1\n", {"other/action": "v2"})

    def test_atomic_replacement_preserves_mode_and_cleans_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ci.yml"
            path.write_text("old\n")
            path.chmod(0o640)
            actions.write_atomic(path, "new\n")
            self.assertEqual(path.read_text(), "new\n")
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_check_is_offline(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ci.yml"
            path.write_text(f"uses: owner/action@{'d' * 40} # v1\n")
            with patch.object(actions, "WORKFLOW", path), patch.object(actions.subprocess, "run", side_effect=AssertionError("network")):
                self.assertEqual(actions.main(["--check"]), 0)

    def test_quoted_keys_values_and_spaces_are_checked(self):
        actions.check_pins(f"  - 'uses' : \"owner/action@{'d' * 40}\" # v1\n")
        with self.assertRaisesRegex(ValueError, "Mutable"):
            actions.check_pins("  - \"uses\" : 'owner/action@v1'\n")

    def test_unsupported_syntax_fails_closed(self):
        for source in ("uses: 'owner/action@v1\n", "uses: >\n  owner/action@v1\n",
                       "- { uses: owner/action@v1 }\n"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                actions.check_pins(source)

    def test_concurrent_workflow_edits_are_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ci.yml"
            path.write_text("another writer\n")
            with self.assertRaisesRegex(ValueError, "Workflow changed"):
                actions.write_atomic(path, "updated pins\n", expected="old workflow\n")
            self.assertEqual(path.read_text(), "another writer\n")
            self.assertEqual(list(path.parent.iterdir()), [path])


if __name__ == "__main__":
    unittest.main()
