#!/usr/bin/env python3
"""Stream a CI command and expose bounded failure details as an Actions annotation."""

import collections
import os
import re
import subprocess
import sys


def main(command):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not command:
        print("usage: ci-run.py COMMAND [ARG ...]", file=sys.stderr)
        return 2
    details = collections.deque(maxlen=120)
    tail = collections.deque(maxlen=20)
    remaining = 0
    ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
    try:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, encoding="utf-8", errors="replace", bufsize=1) as process:
            for line in process.stdout:
                print(line, end="", flush=True)
                clean = ansi.sub("", line).rstrip("\r\n")
                tail.append(clean)
                routine = clean.lstrip().startswith("Success") or re.match(
                    r"^\s*(?:Failed|Errors)\s*:\s*0(?:\s|$)", clean
                )
                if not routine and re.search(
                    r"\b(?:fail|failed|error|traceback)\b|check-docs:", clean, re.I
                ):
                    remaining = 8
                if remaining:
                    details.append(clean)
                    remaining -= 1
            status = process.wait()
    except OSError as error:
        print(error, file=sys.stderr)
        details.append(str(error))
        status = 127
    if status and os.environ.get("GITHUB_ACTIONS") == "true":
        message = "Command failed: " + subprocess.list2cmdline(command)
        message += "\n" + "\n".join([*details, "--- final output ---", *tail])
        payload = message.encode("utf-8")[:18000].decode("utf-8", errors="ignore").encode("utf-8")
        print()  # Commands need not finish their last output line with a newline.
        # Actions truncates annotation messages at 4096 bytes. Keep each part
        # below that limit, without splitting a UTF-8 character.
        part = 1
        while payload:
            message = payload[:3000].decode("utf-8", errors="ignore")
            payload = payload[len(message.encode("utf-8")):]
            message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::error title=CI command failed ({part})::" + message, flush=True)
            part += 1
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
