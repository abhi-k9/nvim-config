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
                if re.search(r"\b(?:fail|failed|error|traceback)\b|check-docs:", clean, re.I):
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
        message = message[-18000:]
        message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print()  # Commands need not finish their last output line with a newline.
        print("::error title=CI command failed::" + message, flush=True)
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
