import re

from dataset.build_adversarial_splits import generate_variant


def test_generated_typosquat_variants_are_deterministic_and_valid():
    base = "example.com"
    variants = [generate_variant(base, seed) for seed in range(4)]

    assert all(variant for variant in variants)
    assert all(variant != base for variant in variants)
    assert all(variant.endswith(".com") for variant in variants)
    assert len(set(variants)) == len(variants)
    assert all(
        re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.[a-z]{2,}", variant)
        for variant in variants
    )
    assert variants == [generate_variant(base, seed) for seed in range(4)]


def test_variant_builder_skips_too_short_labels():
    assert generate_variant("a.co", 0) is None
