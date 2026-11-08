#!/usr/bin/env python3
"""Run a real CI command, preserving its exit code and exposing failure evidence.

GitHub's log archives may be unreachable from restricted review environments.
Failure annotations contain the actual output tail, never a replacement result.
The optional Dart-only diff records the formatter's changes for review.
"""
from collections import deque
import base64
import hashlib
import lzma
import os
import subprocess
import sys


def annotate(level, title, message):
    def escape(value):
        return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")

    print(f"::{level} title={title}::{escape(message)}", flush=True)


def annotation_chunks(text):
    # Actions check messages are truncated at 4096 UTF-8 bytes. Leave room
    # for escaped newlines and never split a multi-byte code point.
    data = text.encode("utf-8")
    while data:
        end = min(3500, len(data))
        while end < len(data) and data[end] & 0xC0 == 0x80:
            end -= 1
        yield data[:end].decode("utf-8")
        data = data[end:]


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
            # A step also has a ten-notice cap. Compress the exact diff, rather
            # than silently losing later chunks of a large formatting-only patch.
            payload = base64.b64encode(lzma.compress(diff.encode("utf-8"))).decode("ascii")
            chunks = list(annotation_chunks(payload))
            digest = hashlib.sha256(diff.encode("utf-8")).hexdigest()
            annotate("notice", "Dart format evidence",
                     f"SHA256={digest}; chunks={len(chunks)}; bytes={len(diff.encode('utf-8'))}; encoding=xz+base64")
            for index, chunk in enumerate(chunks, 1):
                annotate("notice", f"Dart format compressed patch {index}", chunk)
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
