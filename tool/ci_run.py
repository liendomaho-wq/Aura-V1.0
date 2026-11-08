#!/usr/bin/env python3
"""Run a real CI command, preserving its exit code and exposing failure evidence.

GitHub's log archives may be unreachable from restricted review environments.
Failure annotations contain the actual output tail, never a replacement result.
The optional Dart-only diff records the formatter's changes for review.
"""
from collections import deque
import os
import subprocess
import sys


def annotate(level, title, message):
    def escape(value):
        return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")

    print(f"::{level} title={title}::{escape(message)}", flush=True)


def main(args):
    format_diff = bool(args and args[0] == "--format-diff")
    if format_diff:
        args = args[1:]
    if not args:
        raise SystemExit("Usage: ci_run.py [--format-diff] COMMAND [ARG ...]")

    print("COMMAND: " + " ".join(args), flush=True)
    tail = deque(maxlen=60)
    with subprocess.Popen(
        args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, errors="replace",
    ) as process:
        for line in process.stdout:
            print(line, end="", flush=True)
            tail.append(line)
        status = process.wait()

    if status and os.environ.get("GITHUB_ACTIONS") == "true":
        annotate("error", "Command failed", " ".join(args) + "\n" + "".join(tail))
        if format_diff:
            diff = subprocess.run(
                ["git", "diff", "--no-ext-diff", "--", "*.dart"],
                check=True, text=True, stdout=subprocess.PIPE,
            ).stdout
            # Keep each annotation well below GitHub's per-message size limit.
            for offset in range(0, len(diff), 16000):
                annotate("notice", f"Dart format patch {offset // 16000 + 1}",
                         diff[offset:offset + 16000])
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
