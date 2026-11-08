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
INTEGRITY_CLASS = "com.ciberdefensa.aura.SecureStorageIntegrityTest"
EXPECTED_INTEGRITY_CASES = frozenset({
    "refusesDestructiveAesToRsaAliasReplacementAndPreservesSecret",
    "rejectsTamperedGcmValueWithoutResettingOtherSecrets",
    "corruptedLegacyFailsWithoutResetAndCanRetryAfterExactRestoration",
    "conflictingLegacyAndCurrentSecretsFailWithoutOverwritingEither",
    "identicalAlreadyMigratedSecretRecoversWithoutRekeying",
    "refusesDestructiveRsaToAesAliasReplacementAndPreservesSecret",
})
VPN_CLASS = "com.ciberdefensa.aura.VpnForwardingInstrumentationTest"
EXPECTED_VPN_CASES = frozenset({
    "controlOnlyTcpDoesNotActivateForwarding",
    "forwardsRealTcpUdpIpv4AndRejectsUnauthenticatedProxyClients",
    "forwardsRealTcpUdpIpv6WithoutBypassingTun",
    "recoversTerminatedNativeWorkerAndRoutesNewTraffic",
    "panicIsolationRetainsTunPreventsUdpLeakAndResumes",
})
FAILURE_TAGS = frozenset({
    "failure", "error", "skipped", "flakyFailure", "flakyError",
    "rerunFailure", "rerunError",
})


def verify_results(directory: Path, *, require_vpn: bool = False,
                   require_vault_integrity: bool = False) -> dict:
    """Fail closed on absent, incomplete, skipped or failed instrumentation.

    Call only on the connected Android test output directory, never on JVM
    test-results. XML is evidence to retain, not proof of an Android provider
    by itself; the instrumented test verifies its own UID and uses Keystore.
    """
    paths = sorted(directory.rglob("TEST-*.xml"))
    if not paths:
        raise ValueError(f"No connected Android JUnit XML exists under {directory}")
    expected = {(MIGRATION_CLASS, name) for name in EXPECTED_CASES}
    if require_vault_integrity:
        expected.update((INTEGRITY_CLASS, name) for name in EXPECTED_INTEGRITY_CASES)
    if require_vpn:
        expected.update((VPN_CLASS, name) for name in EXPECTED_VPN_CASES)
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
            identity = (case.get("classname"), name)
            if identity in expected:
                observed.append(identity)
        total_cases += len(cases)
        files.append({"path": str(path), "sha256": hashlib.sha256(data).hexdigest()})
    if set(observed) != expected or len(observed) != len(expected):
        raise ValueError(
            "All required original migration/VPN cases must execute exactly once: "
            f"expected={sorted(expected)}, observed={sorted(observed)}"
        )
    return {
        "status": "passed",
        "evidence_type": "connected-android-junit-xml",
        "test_class": MIGRATION_CLASS,
        "required_cases": sorted(name for cls, name in observed if cls == MIGRATION_CLASS),
        "required_vpn_cases": sorted(name for cls, name in observed if cls == VPN_CLASS),
        "required_vault_integrity_cases": sorted(name for cls, name in observed if cls == INTEGRITY_CLASS),
        "total_cases": total_cases,
        "result_files": files,
    }



def case_diagnostics(directory: Path) -> dict:
    """Report individual outcomes even when another class failed; never accept."""
    files = []
    for path in sorted(directory.rglob("TEST-*.xml")):
        data = path.read_bytes()
        root = ET.fromstring(data)
        cases = [{
            "class": case.get("classname"), "name": case.get("name"),
            "negative_result_tags": sorted({node.tag for node in case.iter() if node.tag in FAILURE_TAGS}),
        } for case in root.iter("testcase")]
        counters = [{name: suite.get(name, "0") for name in ("tests", "failures", "errors", "skipped", "disabled")}
                    for suite in root.iter("testsuite")]
        files.append({"path": str(path), "sha256": hashlib.sha256(data).hexdigest(),
                      "cases": cases, "suite_counters": counters})
    return {"diagnostic_only": True, "acceptance": "strict verifier is still mandatory", "files": files}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--require-vpn", action="store_true")
    parser.add_argument("--require-vault-integrity", action="store_true")
    arguments = parser.parse_args()
    try:
        diagnostics = json.dumps(case_diagnostics(arguments.directory), separators=(",", ":"))
        diagnostics = diagnostics.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::notice title=Actual Android case diagnostics::{diagnostics}", flush=True)
        report = verify_results(
            arguments.directory, require_vpn=arguments.require_vpn,
            require_vault_integrity=arguments.require_vault_integrity,
        )
    except (ValueError, OSError, ET.ParseError) as error:
        print(f"Android instrumentation evidence rejected: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2))
    notice = json.dumps(report, separators=(",", ":")).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::notice title=Actual Android instrumentation results::{notice}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
