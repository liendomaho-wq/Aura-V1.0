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
