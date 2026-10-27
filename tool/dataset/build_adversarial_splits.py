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

ROOT = Path(__file__).resolve().parents[2]
SPLIT_DIR = ROOT / "data" / "splits"
POPULAR_PATH = ROOT / "tool" / "domain_lists" / "majestic_top_5000_20261018.txt"
MANIFEST_PATH = ROOT / "data" / "adversarial_split_manifest.json"
FIELDS = ["domain", "label", "source", "license", "retrieved_at"]
ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"
MIN_ADVERSARIAL_ROWS_PER_CLASS = 500
MAX_TRAIN_BASES = 3500
MAX_TEST_BASES = 1500
DOMAIN_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(f"Required dataset split is missing: {path}")
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != FIELDS:
            raise ValueError(f"Unexpected CSV schema in {path}: {reader.fieldnames}")
        rows = list(reader)
    for row in rows:
        if not row["domain"] or "." not in row["domain"] or row["label"] not in {"0", "1"}:
            raise ValueError(f"Invalid dataset row in {path}: {row}")
    return rows


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
    popular = tuple(POPULAR_PATH.read_text(encoding="ascii").splitlines())
    if len(popular) != 5000 or len(set(popular)) != 5000:
        raise ValueError(f"{POPULAR_PATH} must contain exactly 5000 unique domains")

    existing_labels: dict[str, int] = {}
    for row in train + validation + test:
        existing_labels[row["domain"]] = int(row["label"])
    existing_domains = set(existing_labels)
    train_safe = set(row["domain"] for row in train if row["label"] == "0")
    test_safe = set(row["domain"] for row in test if row["label"] == "0")
    train_bases = [domain for domain in popular if domain in train_safe][:MAX_TRAIN_BASES]
    test_bases = [domain for domain in popular if domain in test_safe][:MAX_TEST_BASES]
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
    for index, base in enumerate(train_bases):
        for attempt in range(16):
            variant = generate_variant(base, index * 16 + attempt)
            if variant and variant not in existing_domains and variant not in train_generated:
                train_generated.add(variant)
                train_adversarial.append({
                    "domain": variant,
                    "label": "1",
                    "source": "synthetic-typosquat",
                    "license": "CC0-1.0",
                    "retrieved_at": generated_at,
                })
                break

    test_adversarial: list[dict[str, str]] = []
    test_generated: set[str] = set()
    for index, base in enumerate(test_bases):
        variant = None
        for attempt in range(32):
            candidate = generate_variant(base, 100_000 + index * 32 + attempt)
            if (
                candidate
                and candidate not in existing_domains
                and candidate not in train_generated
                and candidate not in test_generated
            ):
                variant = candidate
                break
        if variant is None:
            continue
        # Reuse the actual held-out safe row so the negative class has provenance.
        safe_row = next(row for row in test if row["domain"] == base and row["label"] == "0")
        test_adversarial.append(dict(safe_row))
        test_adversarial.append({
            "domain": variant,
            "label": "1",
            "source": "synthetic-typosquat",
            "license": "CC0-1.0",
            "retrieved_at": generated_at,
        })
        test_generated.add(variant)

    counts = {
        "train_real_rows": len(train),
        "train_synthetic_typosquats": len(train_generated),
        "train_adversarial_rows": len(train_adversarial),
        "test_adversarial_safe_rows": sum(row["label"] == "0" for row in test_adversarial),
        "test_adversarial_synthetic_threat_rows": sum(row["label"] == "1" for row in test_adversarial),
        "test_adversarial_rows": len(test_adversarial),
    }
    if (
        counts["train_synthetic_typosquats"] < MIN_ADVERSARIAL_ROWS_PER_CLASS
        or counts["test_adversarial_safe_rows"] < MIN_ADVERSARIAL_ROWS_PER_CLASS
        or counts["test_adversarial_synthetic_threat_rows"] < MIN_ADVERSARIAL_ROWS_PER_CLASS
    ):
        raise SystemExit(
            "Synthetic adversarial generation produced too few examples; "
            f"refusing to continue with misleading metrics: {counts}"
        )

    train_path = SPLIT_DIR / "train_adversarial.csv"
    test_path = SPLIT_DIR / "test_adversarial.csv"
    write_rows(train_path, train_adversarial)
    write_rows(test_path, test_adversarial)
    manifest = {
        "manifest_version": 1,
        "created_at": generated_at,
        "method": "deterministic single-label mutations of popular safe domains",
        "limitations": [
            "Generated domains are synthetic lexical examples and are not asserted to be registered or live.",
            "Real-world held-out metrics are computed separately from data/splits/test.csv.",
            "Train and adversarial-test base domains are selected from disjoint canonical splits.",
        ],
        "counts": counts,
        "sha256": {
            "train_source": sha256_file(SPLIT_DIR / "train.csv"),
            "validation_source": sha256_file(SPLIT_DIR / "val.csv"),
            "test_source": sha256_file(SPLIT_DIR / "test.csv"),
            "train_adversarial": sha256_file(train_path),
            "test_adversarial": sha256_file(test_path),
        },
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("ADVERSARIAL_SPLIT_COUNTS=" + json.dumps(counts, sort_keys=True))
    print(f"ADVERSARIAL_SPLIT_MANIFEST={MANIFEST_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
