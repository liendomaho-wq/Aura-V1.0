from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent / "dataset"))

import adversarial


def test_generates_real_confusables_digits_insertions_and_dga_tlds():
    variants = adversarial._threat_variants("apple.com")

    assert ("homoglyph", "аpple.com") in variants
    assert ("digit_substitution", "4pple.com") in variants
    assert ("hyphen_insertion", "ap-ple.com") in variants
    assert ("dot_insertion", "ap.ple.com") in variants
    assert ("duplicate_insertion", "appple.com") in variants
    assert any(domain.endswith(".com") for domain in adversarial._dga_domains())
    assert any(domain.endswith(".click") for domain in adversarial._dga_domains())


@pytest.mark.parametrize(
    ("clean_threat_count", "maximum_synthetic"),
    [(0, 0), (7, 3), (100, 42), (269342, 115432)],
)
def test_synthetic_threat_share_never_exceeds_thirty_percent(
    clean_threat_count: int,
    maximum_synthetic: int,
):
    synthetic = adversarial._maximum_synthetic_threats(clean_threat_count)
    assert synthetic == maximum_synthetic
    if clean_threat_count + synthetic:
        assert synthetic / (clean_threat_count + synthetic) <= 0.30


def test_hard_negatives_are_safe_domain_shapes():
    assert adversarial._hard_negative("w3.org")
    assert adversarial._hard_negative("youtube-nocookie.com")
    assert adversarial._hard_negative("accounts.google.com")
    assert not adversarial._hard_negative("google.com")
