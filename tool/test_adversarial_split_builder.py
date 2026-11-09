import re

from tool.dataset.build_adversarial_splits import (
    generate_variant,
    generate_variants,
    mutation_seed,
)


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


def test_first_attempt_rotates_all_mutation_modes_for_each_split():
    for offset in (0, 100_000, 200_000):
        assert [mutation_seed(offset, index, 0) % 4 for index in range(4)] == [0, 1, 2, 3]
        assert mutation_seed(offset, 2, 1) == mutation_seed(offset, 2, 0) + 1


def test_variant_builder_skips_too_short_labels():
    assert generate_variant("a.co", 0) is None



def test_multi_variant_builder_covers_each_mutation_mode_without_duplicates():
    variants = generate_variants("example.com", 0, 0, set(), set())

    assert len(variants) == 4
    assert len(set(variants)) == 4
    assert all(variant.endswith(".com") for variant in variants)
    assert variants == generate_variants("example.com", 0, 0, set(), set())


def test_multi_variant_builder_respects_blocked_domains_and_groups():
    blocked = {generate_variant("example.com", seed) for seed in range(4)}
    variants = generate_variants("example.com", 0, 0, blocked, set())

    assert all(variant not in blocked for variant in variants)
