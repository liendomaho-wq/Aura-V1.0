#!/usr/bin/env python3
"""Build reproducible synthetic typosquat examples from disjoint train/test safe domains.

These generated examples are a lexical robustness set, not claims about live or
registered phishing domains. Real-world holdout metrics remain in test.csv.
"""
from __future__ import annotations

import csv
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

if __package__:
    from .grouped_splits import registrable_group
else:
    from grouped_splits import registrable_group

ROOT = Path(__file__).resolve().parents[2]
SPLIT_DIR = ROOT / "data" / "splits"
POPULAR_PATH = ROOT / "tool" / "domain_lists" / "majestic_top_5000_20261018.txt"
MANIFEST_PATH = ROOT / "data" / "adversarial_split_manifest.json"
FIELDS = ["domain", "label", "source", "license", "retrieved_at"]
ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"
MIN_ADVERSARIAL_ROWS_PER_CLASS = 500
MAX_TRAIN_BASES = 3500
MAX_TEST_BASES = 1500
MAX_VALIDATION_BASES = 1500
MAX_VARIANTS_PER_BASE = 4
MAX_VARIANT_ATTEMPTS = 128
DOMAIN_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(f"Required dataset split is missing: {path}")
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != FIELDS:
            raise ValueError(f"Unexpected CSV schema in {path}: {reader.fieldnames}")
        rows = list(reader)
    seen = set()
    for row in rows:
        try:
            row["domain"] = row["domain"].strip().lower().rstrip(".").encode("idna").decode("ascii")
            registrable_group(row["domain"])
        except (AttributeError, UnicodeError, ValueError) as error:
            raise ValueError(f"Invalid dataset domain in {path}") from error
        if row["label"] not in {"0", "1"}:
            raise ValueError(f"Invalid dataset label in {path}")
        if row["domain"] in seen:
            raise ValueError(f"Duplicate dataset domain in {path}")
        seen.add(row["domain"])
    return rows


def groups_for(rows: list[dict[str, str]]) -> set[str]:
    return {registrable_group(row["domain"]) for row in rows}


def require_disjoint_groups(train, validation, test):
    groups = [groups_for(rows) for rows in (train, validation, test)]
    if groups[0] & groups[1] or groups[0] & groups[2] or groups[1] & groups[2]:
        raise ValueError("Canonical train, validation and test groups must be disjoint")
    return groups


def variant_group_is_allowed(domain: str, protected_groups: set[str]) -> bool:
    try:
        return registrable_group(domain) not in protected_groups
    except ValueError:
        return False


def mutation_seed(offset: int, index: int, attempt: int) -> int:
    # An odd stride rotates seed % 4 across bases. A multiple of four would
    # accidentally use substitutions for every first successful candidate.
    return offset + index * 33 + attempt


def generate_variants(
    domain: str,
    offset: int,
    index: int,
    blocked_domains: set[str],
    protected_groups: set[str],
) -> list[str]:
    """Generate up to one deterministic example for each of the four mutation modes."""
    variants: list[str] = []
    seen_modes: set[int] = set()
    for attempt in range(MAX_VARIANT_ATTEMPTS):
        seed = mutation_seed(offset, index, attempt)
        mode = seed % 4
        if mode in seen_modes:
            continue
        candidate = generate_variant(domain, seed)
        if (
            candidate
            and candidate not in blocked_domains
            and candidate not in variants
            and variant_group_is_allowed(candidate, protected_groups)
        ):
            variants.append(candidate)
            seen_modes.add(mode)
            if len(variants) == MAX_VARIANTS_PER_BASE:
                break
    return variants


def generate_variant(domain: str, seed: int) -> str | None:
    """Deterministically mutate one registrable-looking label without changing the TLD."""
    labels = domain.lower().rstrip(".").split(".")
    if len(labels) < 2:
        return None
    target_index = len(labels) - 2
    original = labels[target_index]
    if len(original) < 4 or len(original) >= 63:
        return None

    position = (seed * 13 + 1) % len(original)
    mode = seed % 4
    if mode == 0:
        old = original[position]
        if old not in ALPHABET:
            replacement = "x"
        else:
            replacement = ALPHABET[(ALPHABET.index(old) + 1 + seed % 7) % len(ALPHABET)]
            if replacement == old:
                replacement = "z" if old != "z" else "a"
        changed = original[:position] + replacement + original[position + 1:]
    elif mode == 1:
        inserted = "x" if seed % 2 == 0 else "0"
        changed = original[:position] + inserted + original[position:]
    elif mode == 2:
        position = min(position, len(original) - 2)
        if original[position] == original[position + 1]:
            changed = original[:position] + "x" + original[position + 1:]
        else:
            changed = (
                original[:position] + original[position + 1] +
                original[position] + original[position + 2:]
            )
    else:
        changed = original[:position] + original[position + 1:]
        if len(changed) < 3:
            return None

    if not DOMAIN_LABEL.fullmatch(changed) or changed == original:
        return None
    labels[target_index] = changed
    candidate = ".".join(labels)
    return candidate if candidate != domain.lower().rstrip(".") else None


def write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    train = read_rows(SPLIT_DIR / "train.csv")
    validation = read_rows(SPLIT_DIR / "val.csv")
    test = read_rows(SPLIT_DIR / "test.csv")
    train_groups, validation_groups, test_groups = require_disjoint_groups(train, validation, test)
    popular = tuple(POPULAR_PATH.read_text(encoding="ascii").splitlines())
    if len(popular) != 5000 or len(set(popular)) != 5000:
        raise ValueError(f"{POPULAR_PATH} must contain exactly 5000 unique domains")

    existing_labels: dict[str, int] = {}
    for row in train + validation + test:
        existing_labels[row["domain"]] = int(row["label"])
    existing_domains = set(existing_labels)
    train_safe = set(row["domain"] for row in train if row["label"] == "0")
    test_safe = set(row["domain"] for row in test if row["label"] == "0")
    validation_safe = set(row["domain"] for row in validation if row["label"] == "0")
    train_bases = [domain for domain in popular if domain in train_safe][:MAX_TRAIN_BASES]
    test_bases = [domain for domain in popular if domain in test_safe][:MAX_TEST_BASES]
    validation_bases = [domain for domain in popular if domain in validation_safe][:MAX_VALIDATION_BASES]
    if len(train_bases) < MIN_ADVERSARIAL_ROWS_PER_CLASS:
        raise SystemExit(
            f"Need at least {MIN_ADVERSARIAL_ROWS_PER_CLASS} popular safe training bases; "
            f"found {len(train_bases)}."
        )
    if len(test_bases) < MIN_ADVERSARIAL_ROWS_PER_CLASS:
        raise SystemExit(
            f"Need at least {MIN_ADVERSARIAL_ROWS_PER_CLASS} popular safe test bases; "
            f"found {len(test_bases)}. Refusing to label seed-only data as a holdout."
        )

    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    train_adversarial = list(train)
    train_generated: set[str] = set()
    train_generated_groups: set[str] = set()
    heldout_groups = validation_groups | test_groups
    for index, base in enumerate(train_bases):
        variants = generate_variants(
            base, 0, index, existing_domains | train_generated, heldout_groups
        )
        for variant in variants:
            train_generated.add(variant)
            train_generated_groups.add(registrable_group(variant))
            train_adversarial.append({
                "domain": variant,
                "label": "1",
                "source": "synthetic-typosquat",
                "license": "CC0-1.0",
                "retrieved_at": generated_at,
            })

    # Calibration examples are generated only from validation bases, never the
    # final test set. Protect both real test groups and generated training groups.
    validation_adversarial: list[dict[str, str]] = []
    validation_generated: set[str] = set()
    validation_generated_groups: set[str] = set()
    validation_safe_rows = {row["domain"]: row for row in validation if row["label"] == "0"}
    for index, base in enumerate(validation_bases):
        variants = generate_variants(
            base,
            200_000,
            index,
            existing_domains | train_generated | validation_generated,
            train_groups | test_groups | train_generated_groups | validation_generated_groups,
        )
        if variants:
            validation_adversarial.append(dict(validation_safe_rows[base]))
        for candidate in variants:
            validation_adversarial.append({
                "domain": candidate, "label": "1", "source": "synthetic-typosquat",
                "license": "CC0-1.0", "retrieved_at": generated_at,
            })
            validation_generated.add(candidate)
            validation_generated_groups.add(registrable_group(candidate))

    test_adversarial: list[dict[str, str]] = []
    test_generated: set[str] = set()
    test_generated_groups: set[str] = set()
    protected_train_groups = train_groups | validation_groups | train_generated_groups | validation_generated_groups
    for index, base in enumerate(test_bases):
        variants = generate_variants(
            base,
            100_000,
            index,
            existing_domains | train_generated | validation_generated | test_generated,
            protected_train_groups | test_generated_groups,
        )
        if not variants:
            continue
        # Keep one provenance-backed safe base for all its generated threat variants.
        safe_row = next(row for row in test if row["domain"] == base and row["label"] == "0")
        test_adversarial.append(dict(safe_row))
        for candidate in variants:
            test_adversarial.append({
                "domain": candidate,
                "label": "1",
                "source": "synthetic-typosquat",
                "license": "CC0-1.0",
                "retrieved_at": generated_at,
            })
            test_generated.add(candidate)
            test_generated_groups.add(registrable_group(candidate))

    counts = {
        "train_real_rows": len(train),
        "train_synthetic_typosquats": len(train_generated),
        "train_adversarial_rows": len(train_adversarial),
        "validation_adversarial_safe_rows": sum(row["label"] == "0" for row in validation_adversarial),
        "validation_adversarial_synthetic_threat_rows": len(validation_generated),
        "test_adversarial_safe_rows": sum(row["label"] == "0" for row in test_adversarial),
        "test_adversarial_synthetic_threat_rows": sum(row["label"] == "1" for row in test_adversarial),
        "test_adversarial_rows": len(test_adversarial),
    }
    if (
        counts["train_synthetic_typosquats"] < MIN_ADVERSARIAL_ROWS_PER_CLASS
        or counts["validation_adversarial_safe_rows"] < MIN_ADVERSARIAL_ROWS_PER_CLASS
        or counts["validation_adversarial_synthetic_threat_rows"] < MIN_ADVERSARIAL_ROWS_PER_CLASS
        or counts["test_adversarial_safe_rows"] < MIN_ADVERSARIAL_ROWS_PER_CLASS
        or counts["test_adversarial_synthetic_threat_rows"] < MIN_ADVERSARIAL_ROWS_PER_CLASS
    ):
        raise SystemExit(
            "Synthetic adversarial generation produced too few examples; "
            f"refusing to continue with misleading metrics: {counts}"
        )

    train_path = SPLIT_DIR / "train_adversarial.csv"
    validation_path = SPLIT_DIR / "val_adversarial.csv"
    test_path = SPLIT_DIR / "test_adversarial.csv"
    write_rows(train_path, train_adversarial)
    write_rows(validation_path, validation_adversarial)
    write_rows(test_path, test_adversarial)
    manifest = {
        "manifest_version": 1,
        "created_at": generated_at,
        "method": "deterministic multi-mode mutations of popular safe domains",
        "mutation_schedule": "up-to-four-distinct-modes-per-base-v3",
        "limitations": [
            "v3 generates up to four distinct mutation modes per base; metrics are not directly comparable with v2.",
            "Generated domains are synthetic lexical examples and are not asserted to be registered or live.",
            "Real-world held-out metrics are computed separately from data/splits/test.csv.",
            "Train, validation and real-test base domains have disjoint ICANN registrable groups.",
            "Synthetic train variants cannot share held-out groups; validation and test variants cannot share train groups or each other's groups.",
            "Group disjointness does not prove temporal, source, or lexical independence.",
        ],
        "counts": counts,
        "sha256": {
            "train_source": sha256_file(SPLIT_DIR / "train.csv"),
            "validation_source": sha256_file(SPLIT_DIR / "val.csv"),
            "test_source": sha256_file(SPLIT_DIR / "test.csv"),
            "train_adversarial": sha256_file(train_path),
            "validation_adversarial": sha256_file(validation_path),
            "test_adversarial": sha256_file(test_path),
        },
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("ADVERSARIAL_SPLIT_COUNTS=" + json.dumps(counts, sort_keys=True))
    print(f"ADVERSARIAL_SPLIT_MANIFEST={MANIFEST_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
