"""XML parser regression fixtures, NOT Android/Keystore execution evidence."""

from pathlib import Path
import sys
import xml.etree.ElementTree as ET

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_android_instrumentation import (  # noqa: E402
    EXPECTED_CASES, MIGRATION_CLASS, verify_results,
)


def write_parser_fixture(directory, *, names=None, counter=None, tag=None):
    names = sorted(EXPECTED_CASES) if names is None else names
    suite = ET.Element("testsuite", tests=str(len(names)), failures="0", errors="0", skipped="0")
    if counter:
        suite.set(counter, "1")
    for name in names:
        case = ET.SubElement(suite, "testcase", classname=MIGRATION_CLASS, name=name)
        if tag:
            ET.SubElement(case, tag)
    (directory / "TEST-parser-fixture.xml").write_bytes(ET.tostring(suite))


def test_accepts_exactly_both_passing_case_names(tmp_path):
    write_parser_fixture(tmp_path)
    report = verify_results(tmp_path)
    assert report["required_cases"] == sorted(EXPECTED_CASES)
    assert report["total_cases"] == 2
    assert len(report["result_files"][0]["sha256"]) == 64


def test_rejects_missing_results_instead_of_treating_compilation_as_execution(tmp_path):
    with pytest.raises(ValueError, match="No connected Android JUnit XML"):
        verify_results(tmp_path)


@pytest.mark.parametrize("names", [[], sorted(EXPECTED_CASES)[:1], ["unrelatedTest"], sorted(EXPECTED_CASES) * 2])
def test_rejects_empty_missing_or_repeated_required_cases(tmp_path, names):
    write_parser_fixture(tmp_path, names=names)
    with pytest.raises(ValueError):
        verify_results(tmp_path)


@pytest.mark.parametrize("tag", ["failure", "error", "skipped", "flakyFailure", "rerunError"])
def test_rejects_failure_or_skip_even_if_suite_counters_are_zero(tmp_path, tag):
    write_parser_fixture(tmp_path, tag=tag)
    with pytest.raises(ValueError, match="Failed, retried or omitted"):
        verify_results(tmp_path)


@pytest.mark.parametrize("counter", ["failures", "errors", "skipped", "disabled"])
def test_rejects_nonzero_suite_counters(tmp_path, counter):
    write_parser_fixture(tmp_path, counter=counter)
    with pytest.raises(ValueError, match="Nonzero"):
        verify_results(tmp_path)


def test_rejects_dishonest_case_count(tmp_path):
    write_parser_fixture(tmp_path)
    path = tmp_path / "TEST-parser-fixture.xml"
    root = ET.parse(path).getroot()
    root.set("tests", "42")
    path.write_bytes(ET.tostring(root))
    with pytest.raises(ValueError, match="does not match declared tests"):
        verify_results(tmp_path)


def test_rejects_another_class_using_the_required_names(tmp_path):
    write_parser_fixture(tmp_path)
    path = tmp_path / "TEST-parser-fixture.xml"
    root = ET.parse(path).getroot()
    for case in root:
        case.set("classname", "other.Class")
    path.write_bytes(ET.tostring(root))
    with pytest.raises(ValueError, match="must execute exactly once"):
        verify_results(tmp_path)


def test_vpn_is_required_in_addition_to_original_migration_not_instead(tmp_path):
    write_parser_fixture(tmp_path)
    with pytest.raises(ValueError, match="must execute exactly once"):
        verify_results(tmp_path, require_vpn=True)


def test_accepts_all_required_vpn_and_original_case_identities_only_when_present(tmp_path):
    from verify_android_instrumentation import EXPECTED_VPN_CASES, VPN_CLASS
    write_parser_fixture(tmp_path)
    suite = ET.Element("testsuite", tests=str(len(EXPECTED_VPN_CASES)), failures="0", errors="0", skipped="0")
    for name in sorted(EXPECTED_VPN_CASES):
        ET.SubElement(suite, "testcase", classname=VPN_CLASS, name=name)
    (tmp_path / "TEST-vpn-parser-fixture.xml").write_bytes(ET.tostring(suite))
    report = verify_results(tmp_path, require_vpn=True)
    assert report["total_cases"] == 7
    assert report["required_cases"] == sorted(EXPECTED_CASES)
    assert report["required_vpn_cases"] == sorted(EXPECTED_VPN_CASES)


def test_vault_integrity_cannot_be_satisfied_by_migration_alone(tmp_path):
    write_parser_fixture(tmp_path)
    with pytest.raises(ValueError, match="must execute exactly once"):
        verify_results(tmp_path, require_vault_integrity=True)


def test_accepts_additional_real_result_class_identity(tmp_path):
    from verify_android_instrumentation import EXPECTED_INTEGRITY_CASES, INTEGRITY_CLASS
    write_parser_fixture(tmp_path)
    suite = ET.Element("testsuite", tests=str(len(EXPECTED_INTEGRITY_CASES)), failures="0", errors="0", skipped="0")
    for name in sorted(EXPECTED_INTEGRITY_CASES):
        ET.SubElement(suite, "testcase", classname=INTEGRITY_CLASS, name=name)
    (tmp_path / "TEST-integrity-parser-fixture.xml").write_bytes(ET.tostring(suite))
    report = verify_results(tmp_path, require_vault_integrity=True)
    assert report["total_cases"] == 7
    assert report["required_vault_integrity_cases"] == sorted(EXPECTED_INTEGRITY_CASES)


def test_diagnostics_do_not_turn_a_failed_case_into_acceptance(tmp_path):
    from verify_android_instrumentation import case_diagnostics
    write_parser_fixture(tmp_path, tag="failure")
    report = case_diagnostics(tmp_path)
    assert report["diagnostic_only"] is True
    assert report["files"][0]["cases"][0]["negative_result_tags"] == ["failure"]
    with pytest.raises(ValueError):
        verify_results(tmp_path)


def test_empty_diagnostics_are_never_passing_instrumentation(tmp_path):
    from verify_android_instrumentation import case_diagnostics
    assert case_diagnostics(tmp_path)["files"] == []
    with pytest.raises(ValueError):
        verify_results(tmp_path)


def test_control_only_tcp_negative_is_mandatory_not_an_optional_extra(tmp_path):
    from verify_android_instrumentation import EXPECTED_VPN_CASES, VPN_CLASS
    negative = "controlOnlyTcpDoesNotActivateForwarding"
    assert negative in EXPECTED_VPN_CASES
    write_parser_fixture(tmp_path)
    names = EXPECTED_VPN_CASES - {negative}
    suite = ET.Element("testsuite", tests=str(len(names)), failures="0", errors="0", skipped="0")
    for name in sorted(names):
        ET.SubElement(suite, "testcase", classname=VPN_CLASS, name=name)
    (tmp_path / "TEST-vpn-incomplete-fixture.xml").write_bytes(ET.tostring(suite))
    with pytest.raises(ValueError, match="must execute exactly once"):
        verify_results(tmp_path, require_vpn=True)
