"""Own real host traffic peers while the unchanged Android runner executes."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import select
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect-logcat", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    command = arguments.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("A real connectedAndroidTest command is required")
    log_path = ROOT / "build/vpn-instrumentation-fixture.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    fixture = subprocess.Popen(
        [sys.executable, str(ROOT / "tool/vpn_echo_fixture.py"), "--port", "32967"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0,
    )
    command_returncode = None
    try:
        readable, _, _ = select.select([fixture.stdout], [], [], 15)
        if not readable:
            raise RuntimeError("Real TCP/UDP fixtures did not bind within 15 seconds")
        first_line = fixture.stdout.readline()
        with log_path.open("w", encoding="utf-8") as log:
            log.write(first_line.decode("utf-8", errors="backslashreplace"))
        ready = json.loads(first_line)
        if ready.get("status") != "ready" or ready.get("port") != 32967:
            raise RuntimeError(f"Invalid real fixture readiness: {ready}")
        print("Real emulator host traffic peers: " + first_line.decode("utf-8", errors="backslashreplace").strip(), flush=True)
        completed = subprocess.run(command, timeout=1800)
        command_returncode = completed.returncode
        if completed.returncode != 0:
            return completed.returncode
        if fixture.poll() is not None:
            raise RuntimeError("The traffic fixture died before instrumentation completed")
        return 0
    finally:
        # Capture the real emulator before emulator-runner terminates it. This
        # diagnostic never changes the instrumentation command's result.
        if arguments.collect_logcat:
            try:
                with (ROOT / "build/vpn-instrumentation-logcat.txt").open("w", encoding="utf-8") as log:
                    diagnostic = subprocess.run(
                        ["adb", "logcat", "-d", "-v", "threadtime"],
                        stdout=log, stderr=subprocess.STDOUT, timeout=30,
                    )
                if diagnostic.returncode:
                    print("WARNING: emulator logcat could not be captured", file=sys.stderr)
            except (OSError, subprocess.TimeoutExpired) as error:
                print(f"WARNING: emulator logcat unavailable: {error}", file=sys.stderr)
        fixture.terminate()
        try:
            remaining, _ = fixture.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            fixture.kill()
            remaining, _ = fixture.communicate(timeout=5)
        remaining = remaining.decode("utf-8", errors="backslashreplace")
        with log_path.open("a", encoding="utf-8") as log:
            log.write(remaining)
        print(remaining, end="", flush=True)
        if fixture.returncode != 0:
            message = f"Real traffic fixture did not shut down cleanly: {fixture.returncode}"
            if command_returncode == 0:
                raise RuntimeError(message)
            print(message, file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
