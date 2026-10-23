#!/usr/bin/env python3
"""Refresh immutable GitHub Action pins only when explicitly requested."""

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
USES = re.compile(
    r"^(?P<prefix>[ \t]*(?:-[ \t]*)?(?:uses|'uses'|\"uses\")[ \t]*:[ \t]*)"
    r"(?P<value>[^\r\n]*)$", re.M,
)
TARGET = re.compile(r"(?P<action>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*)@(?P<ref>[A-Za-z0-9_./-]+)")
SHA = re.compile(r"[0-9a-fA-F]{40}")
REF = re.compile(r"[A-Za-z0-9_./-]+")


def entries(source):
    result = []
    # This updater supports block-style uses scalars, as used by this repo.
    # Refuse flow mappings rather than silently skipping an unpinned action.
    for line in source.splitlines():
        if not line.lstrip().startswith("#") and re.search(r"[\{,]\s*['\"]?uses['\"]?\s*:", line):
            raise ValueError("Flow-style uses mappings are unsupported; use a block-style uses scalar")
    for match in USES.finditer(source):
        value, _, comment = match["value"].partition("#")
        value = value.strip()
        if value.startswith(("\"", "'")):
            if len(value) < 2 or value[-1] != value[0]:
                raise ValueError("Unbalanced quoted action reference")
            value = value[1:-1]
        if value.startswith("./"):
            continue
        target = TARGET.fullmatch(value)
        if not target:
            raise ValueError(f"Unsupported action reference: {value}")
        action, current = target["action"], target["ref"]
        repo = "/".join(action.split("/")[:2])
        track = comment.strip().split()[0] if comment.strip() else None
        if SHA.fullmatch(current):
            if not track or not REF.fullmatch(track) or SHA.fullmatch(track):
                raise ValueError(f"Missing update tag/branch comment for {action}")
        else:
            track = current
        result.append((match, action, repo, current, track))
    if not result:
        raise ValueError("No external GitHub Actions found")
    return result


def check_pins(source):
    seen = {}
    for _, action, repo, current, track in entries(source):
        if not SHA.fullmatch(current):
            raise ValueError(f"Mutable action reference: {action}@{current}")
        key = (repo, track)
        if key in seen and seen[key] != current.lower():
            raise ValueError(f"Inconsistent pins for {repo}@{track}")
        seen[key] = current.lower()


def resolve(repo, ref):
    result = subprocess.run(
        ["gh", "api", f"repos/{repo}/commits/{quote(ref, safe='')}"],
        check=True, capture_output=True, text=True, timeout=30,
    )
    payload = json.loads(result.stdout)
    sha = payload.get("sha", "") if isinstance(payload, dict) else None
    if not isinstance(sha, str) or not SHA.fullmatch(sha):
        raise ValueError(f"GitHub returned an invalid commit for {repo}@{ref}")
    return sha.lower()


def updated(source, overrides=None, resolver=resolve):
    actions = entries(source)
    overrides = overrides or {}
    unknown = set(overrides) - {repo for _, _, repo, _, _ in actions}
    if unknown:
        raise ValueError("Unknown action repositories: " + ", ".join(sorted(unknown)))
    wanted = {(repo, overrides.get(repo, track)) for _, _, repo, _, track in actions}
    for _, ref in wanted:
        if not isinstance(ref, str) or not REF.fullmatch(ref) or ref.startswith("-"):
            raise ValueError(f"Invalid update reference: {ref}")
    # Resolve everything before modifying the workflow. One failed lookup
    # leaves every existing pin untouched.
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(4, len(wanted))) as pool:
        pending = {key: pool.submit(resolver, *key) for key in sorted(wanted)}
        commits = {key: future.result() for key, future in pending.items()}
    for key, sha in commits.items():
        if not isinstance(sha, str) or not SHA.fullmatch(sha):
            raise ValueError(f"Invalid resolved commit for {key[0]}@{key[1]}")
    output = source
    changes = []
    for match, action, repo, current, track in reversed(actions):
        track = overrides.get(repo, track)
        commit = commits[(repo, track)].lower()
        replacement = f"{match['prefix']}{action}@{commit} # {track}"
        output = output[:match.start()] + replacement + output[match.end():]
        if current.lower() != commit:
            changes.append(f"{action}: {current} -> {commit} ({track})")
    check_pins(output)
    return output, sorted(set(changes))


def write_atomic(path, source, expected=None):
    mode = path.stat().st_mode & 0o777
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            stream.write(source)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        if expected is not None and path.read_text(encoding="utf-8") != expected:
            raise ValueError("Workflow changed during resolution; retry with the latest file")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate pins locally without network or edits")
    parser.add_argument("--dry-run", action="store_true", help="resolve updates without changing the workflow")
    parser.add_argument("--ref", action="append", default=[], metavar="OWNER/REPO=TAG",
                        help="explicitly switch an action's update track, e.g. actions/checkout=v8")
    args = parser.parse_args(argv)
    if args.check and (args.dry_run or args.ref):
        parser.error("--check cannot be combined with update options")
    try:
        source = WORKFLOW.read_text(encoding="utf-8")
        if args.check:
            check_pins(source)
            print("CI actions: every external action is pinned to an immutable commit.")
            return 0
        overrides = {}
        for value in args.ref:
            repo, separator, ref = value.partition("=")
            if not separator or repo in overrides:
                raise ValueError(f"Expected one OWNER/REPO=TAG override per repository: {value}")
            overrides[repo] = ref
        output, changes = updated(source, overrides)
        for change in changes:
            print(change)
        if output != source and not args.dry_run:
            write_atomic(WORKFLOW, output, expected=source)
            print("Updated ci.yml. Review the diff, run make ci, then commit when ready.")
        elif not changes:
            print("CI action pins are already current for their selected update tracks.")
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"CI action update failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
