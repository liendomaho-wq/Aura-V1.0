"""Require actual Android JUnit XML; this script does not execute Android."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

MIGRATION_CLASS = "com.ciberdefensa.aura.SecureStorageMigrationTest"
EXPECTED_CASES = frozenset({
    "migratesRealVersion9EncryptedPreferencesAndPreservesSecret",
    "restartsAnInterruptedBackupAndStillMigratesVersion9Secret",
})
FAILURE_TAGS = frozenset({
    "failure", "error", "skipped", "flakyFailure", "flakyError",
    "rerunFailure", "rerunError",
})


def verify_results(directory: Path) -> dict:
    """Fail closed on absent, incomplete, skipped or failed instrumentation.

    Call only on the connected Android test output directory, never on JVM
    test-results. XML is evidence to retain, not proof of an Android provider
    by itself; the instrumented test verifies its own UID and uses Keystore.
    """
    paths = sorted(directory.rglob("TEST-*.xml"))
    if not paths:
        raise ValueError(f"No connected Android JUnit XML exists under {directory}")
    observed = []
    files = []
    total_cases = 0
    for path in paths:
        data = path.read_bytes()
        root = ET.fromstring(data)
        cases = list(root.iter("testcase"))
        if not cases:
            raise ValueError(f"Empty instrumentation results: {path}")
        for suite in root.iter("testsuite"):
            for counter in ("failures", "errors", "skipped", "disabled"):
                if int(suite.get(counter, "0")) != 0:
                    raise ValueError(f"Nonzero {counter} in {path}")
            declared = suite.get("tests")
            if declared is not None and int(declared) != len(list(suite.iter("testcase"))):
                raise ValueError(f"JUnit case count does not match declared tests in {path}")
        for case in cases:
            name = case.get("name")
            if any(node.tag in FAILURE_TAGS for node in case.iter()):
                raise ValueError(f"Failed, retried or omitted instrumentation case {name} in {path}")
            if case.get("classname") == MIGRATION_CLASS and name in EXPECTED_CASES:
                observed.append(name)
        total_cases += len(cases)
        files.append({"path": str(path), "sha256": hashlib.sha256(data).hexdigest()})
    if set(observed) != EXPECTED_CASES or len(observed) != len(EXPECTED_CASES):
        raise ValueError(
            "Both original migration cases must execute exactly once: "
            f"expected={sorted(EXPECTED_CASES)}, observed={sorted(observed)}"
        )
    return {
        "status": "passed",
        "evidence_type": "connected-android-junit-xml",
        "test_class": MIGRATION_CLASS,
        "required_cases": sorted(observed),
        "total_cases": total_cases,
        "result_files": files,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    arguments = parser.parse_args()
    try:
        report = verify_results(arguments.directory)
    except (ValueError, OSError, ET.ParseError) as error:
        print(f"Android instrumentation evidence rejected: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
