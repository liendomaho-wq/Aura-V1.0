#!/usr/bin/env python3
"""Read-only Android runtime preflight, NOT instrumentation/test acceptance."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

COMMANDS = {
    "sdk": ["adb", "shell", "getprop", "ro.build.version.sdk"],
    "boot_completed": ["adb", "shell", "getprop", "sys.boot_completed"],
    "abi": ["adb", "shell", "getprop", "ro.product.cpu.abi"],
    "fingerprint": ["adb", "shell", "getprop", "ro.build.fingerprint"],
    "android_package": ["adb", "shell", "cmd", "package", "path", "android"],
}


def readiness_failures(snapshot: dict, *, expected_api: int, expected_abi: str) -> list[str]:
    failures = []
    for name in COMMANDS:
        record = snapshot.get(name, {})
        if record.get("exit_code") != 0 or not record.get("stdout", "").strip():
            failures.append(f"Real adb read {name} failed or was empty")
    value = lambda name: snapshot.get(name, {}).get("stdout", "").strip()
    if value("sdk") != str(expected_api):
        failures.append(f"Actual SDK {value('sdk')!r} != required {expected_api}; no API=1 default")
    if value("boot_completed") != "1":
        failures.append("Android has not reported completed boot")
    if value("abi") != expected_abi:
        failures.append(f"Actual ABI {value('abi')!r} != required {expected_abi}")
    if not re.fullmatch(r"package:/\S+\.apk", value("android_package")):
        failures.append("Real Package Manager did not resolve the Android framework APK")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-api", type=int, choices=(29, 36), required=True)
    parser.add_argument("--expected-abi", choices=("x86", "x86_64"), required=True)
    arguments = parser.parse_args()
    snapshot = {}
    for name, command in COMMANDS.items():
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=20, check=False)
            snapshot[name] = {
                "command": command, "exit_code": result.returncode,
                "stdout": result.stdout.strip(), "stderr": result.stderr.strip(),
            }
        except (OSError, subprocess.TimeoutExpired) as error:
            snapshot[name] = {"command": command, "exit_code": None, "stdout": "", "error": str(error)}
    failures = readiness_failures(snapshot, expected_api=arguments.expected_api,
                                  expected_abi=arguments.expected_abi)
    report = {
        "status": "failed" if failures else "passed",
        "scope": "real emulator setup readiness ONLY, not test/Keystore/TUN/device acceptance",
        "expected_api": arguments.expected_api, "expected_abi": arguments.expected_abi,
        "failures": failures, "actual_adb_reads": snapshot,
    }
    serialized = json.dumps(report, separators=(",", ":"), allow_nan=False)
    escaped = serialized.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::{'error' if failures else 'notice'} title=Real Android runtime preflight::{escaped}", flush=True)
    if failures:
        print("Real Android setup not ready; no tests accepted or retried.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
