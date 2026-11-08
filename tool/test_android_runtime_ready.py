"""Preflight-validator fixtures ONLY; none of these execute Android/adb."""
from copy import deepcopy
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_android_runtime_ready import readiness_failures  # noqa: E402


def parser_fixture():
    values = {
        "sdk": "36", "boot_completed": "1", "abi": "x86_64",
        "fingerprint": "parser-fixture-not-a-device",
        "android_package": "package:/system/framework/framework-res.apk",
    }
    return {name: {"stdout": value, "exit_code": 0} for name, value in values.items()}


def test_preflight_parser_accepts_complete_required_api36_metadata():
    assert not readiness_failures(parser_fixture(), expected_api=36, expected_abi="x86_64")


def test_preflight_parser_checks_the_declared_api29_variant_not_api36():
    snapshot = parser_fixture()
    snapshot["sdk"]["stdout"] = "29"
    snapshot["abi"]["stdout"] = "x86"
    assert not readiness_failures(snapshot, expected_api=29, expected_abi="x86")


@pytest.mark.parametrize("name,field,value", [
    ("sdk", "stdout", "1"),
    ("sdk", "stdout", "29"),
    ("boot_completed", "stdout", "0"),
    ("abi", "stdout", "x86"),
    ("android_package", "stdout", "cmd: Can't find service: package"),
    ("android_package", "exit_code", 1),
    ("fingerprint", "stdout", ""),
])
def test_preflight_parser_never_accepts_wrong_missing_or_failed_android_state(name, field, value):
    snapshot = deepcopy(parser_fixture())
    snapshot[name][field] = value
    assert readiness_failures(snapshot, expected_api=36, expected_abi="x86_64")


def test_each_lane_compiles_before_emulation_and_checks_the_real_runtime():
    source = (Path(__file__).resolve().parents[1] / ".github/workflows/android-debug-build.yml").read_text()
    assert source.index("name: Compile exact migration APKs before starting Android 16") < source.index("name: Real v9 to v10 Keystore migration on Android 16 emulator")
    assert source.index("name: Compile exact migration APKs before starting Android 10") < source.index("name: Execute original migration plus integrity tests on real Android 10")
    assert "verify_android_runtime_ready.py --expected-api 36 --expected-abi x86_64" in source
    assert "verify_android_runtime_ready.py --expected-api 29 --expected-abi x86" in source


def test_ddmlib_getprop_timeout_is_bounded_and_only_changes_the_read_deadline():
    source = (Path(__file__).resolve().parents[1] / ".github/workflows/android-debug-build.yml").read_text()
    commands = [line for line in source.splitlines() if "python3 ../tool/ci_run.py" in line
                and ":app:connectedStorageMigrationAndroidTest" in line]
    assert len(commands) == 2
    for command in commands:
        assert "-Dddmlib.getprop.timeout.sec=20 --no-daemon" in command
        assert "com.ciberdefensa.aura.SecureStorageMigrationTest" in command
        assert "com.ciberdefensa.aura.SecureStorageIntegrityTest" in command
        assert "||" not in command
    assert "name: Expose the first actual API29 provider or setup failure" in source
    assert "continue-on-error" not in source
