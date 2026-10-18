#!/usr/bin/env python3
"""Genera ejemplos adversariales deterministas sin alterar los splits limpios."""

from __future__ import annotations

import argparse
import csv
import random
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = ROOT / "data"
SPLIT_DIR = DATA_DIR / "splits"
BRAND_DOMAINS = ROOT / "tool/domain_lists/majestic_top_5000_20261018.txt"
CSV_FIELDS = ["domain", "label", "source", "license", "retrieved_at"]
SEED = 42
SYNTHETIC_LICENSE = "LicenseRef-Aura-Synthetic"
LATIN_CONFUSABLES = {
    "a": "а",
    "e": "е",
    "o": "о",
    "p": "р",
    "c": "с",
    "x": "х",
    "y": "у",
    "i": "і",
    "s": "ѕ",
    "j": "ј",
}
DIGIT_SUBSTITUTIONS = {
    "o": "0",
    "i": "1",
    "e": "3",
    "a": "4",
    "s": "5",
    "t": "7",
    "g": "9",
}
PREFIXES = ("my-", "secure-")
SUFFIXES = ("-login", "-verify", "-account", "-update")
BENIGN_TLDS = ("com", "org", "net", "edu", "gov")
SUSPICIOUS_TLDS = ("click", "top", "xyz", "zip", "work", "support")
SYLLABLES = (
    "ba", "bel", "cor", "dan", "dex", "fal", "gan", "hex", "jor", "kel",
    "lan", "mor", "nel", "pon", "qua", "rax", "sen", "tor", "ul", "ven",
    "wyn", "xel", "yor", "zen",
)
LABEL_PATTERN = re.compile(r"^[^\W_](?:[^\W_]|-){0,61}[^\W_-]$", re.UNICODE)


def _read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != CSV_FIELDS:
            raise ValueError(f"Esquema CSV inesperado en {path}: {reader.fieldnames}")
        return list(reader)


def _write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=CSV_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def _valid_domain(domain: str) -> bool:
    labels = domain.split(".")
    return (
        len(domain) <= 253
        and len(labels) >= 2
        and all(1 <= len(label) <= 63 and LABEL_PATTERN.fullmatch(label) for label in labels)
    )


def _brand_label_and_suffix(domain: str) -> tuple[str, str] | None:
    label, separator, suffix = domain.partition(".")
    if not separator or not label or not suffix:
        return None
    return label, "." + suffix


def _threat_variants(domain: str) -> list[tuple[str, str]]:
    parts = _brand_label_and_suffix(domain)
    if parts is None:
        return []
    brand, suffix = parts
    variants: list[tuple[str, str]] = []

    for index, character in enumerate(brand):
        confusable = LATIN_CONFUSABLES.get(character)
        if confusable is not None:
            variants.append(
                ("homoglyph", brand[:index] + confusable + brand[index + 1 :] + suffix)
            )
        digit = DIGIT_SUBSTITUTIONS.get(character)
        if digit is not None:
            variants.append(
                ("digit_substitution", brand[:index] + digit + brand[index + 1 :] + suffix)
            )

    middle = max(1, len(brand) // 2)
    if len(brand) > 1:
        variants.append(("hyphen_insertion", brand[:middle] + "-" + brand[middle:] + suffix))
        variants.append(("dot_insertion", brand[:middle] + "." + brand[middle:] + suffix))
        duplicated_index = min(len(brand) - 1, middle)
        variants.append(
            (
                "duplicate_insertion",
                brand[:duplicated_index] + brand[duplicated_index] + brand[duplicated_index:] + suffix,
            )
        )
    for prefix in PREFIXES:
        variants.append(("prefix_insertion", prefix + brand + suffix))
    for ending in SUFFIXES:
        variants.append(("suffix_insertion", brand + ending + suffix))
    return [(source, candidate.lower()) for source, candidate in variants if _valid_domain(candidate)]


def _dga_domains() -> list[str]:
    domains = set()
    for first in SYLLABLES:
        for second in SYLLABLES:
            for tld in BENIGN_TLDS + SUSPICIOUS_TLDS:
                domains.add(f"{first}{second}.{tld}")
    return sorted(domains)


def _hard_negative(domain: str) -> bool:
    lowered = domain.lower()
    return any(character.isdigit() for character in lowered) or "-" in lowered or any(
        keyword in lowered for keyword in ("login", "secure", "account", "pay")
    )


def _maximum_synthetic_threats(clean_threat_count: int) -> int:
    return clean_threat_count * 3 // 7


def _counts(rows: list[dict[str, str]]) -> dict[str, int]:
    labels = Counter(int(row["label"]) for row in rows)
    return {"safe": labels[0], "threat": labels[1]}


def build(
    train_path: Path,
    val_path: Path,
    test_path: Path,
    train_output: Path,
    adversarial_test_output: Path,
    brand_domains_path: Path = BRAND_DOMAINS,
) -> dict[str, object]:
    rng = random.Random(SEED)
    train_rows = _read_rows(train_path)
    val_rows = _read_rows(val_path)
    test_rows = _read_rows(test_path)
    brand_domains = brand_domains_path.read_text(encoding="ascii").splitlines()
    if len(brand_domains) != 5000 or len(set(brand_domains)) != 5000:
        raise ValueError(f"{brand_domains_path} debe contener 5.000 dominios únicos.")

    clean_domains = {
        row["domain"].strip().lower()
        for row in train_rows + val_rows + test_rows
    }
    brand_order = list(brand_domains)
    rng.shuffle(brand_order)
    train_brands = set(brand_order[:4000])
    test_brands = set(brand_order[4000:])

    train_variants: dict[str, str] = {}
    test_variants: dict[str, str] = {}
    for source_domains, destination in (
        (train_brands, train_variants),
        (test_brands, test_variants),
    ):
        for domain in sorted(source_domains):
            for source, candidate in _threat_variants(domain):
                if candidate not in clean_domains:
                    destination.setdefault(candidate, source)

    train_dga = _dga_domains()
    rng.shuffle(train_dga)
    dga_test_count = max(1, len(train_dga) // 5)
    train_dga_domains = train_dga[dga_test_count:]
    test_dga_domains = train_dga[:dga_test_count]
    for domain in train_dga_domains:
        if domain not in clean_domains:
            train_variants.setdefault(domain, "dga_syllables")
    for domain in test_dga_domains:
        if domain not in clean_domains:
            test_variants.setdefault(domain, "dga_syllables")

    clean_train_threats = sum(row["label"] == "1" for row in train_rows)
    maximum_synthetic = _maximum_synthetic_threats(clean_train_threats)
    if len(train_variants) > maximum_synthetic:
        candidates = list(train_variants.items())
        rng.shuffle(candidates)
        train_variants = dict(candidates[:maximum_synthetic])

    train_by_domain = {row["domain"].strip().lower(): row for row in train_rows}
    train_hard_negatives = 0
    test_hard_negatives = 0
    for domain in brand_domains:
        if not _hard_negative(domain):
            continue
        clean_train = train_by_domain.get(domain)
        if clean_train is not None and clean_train["label"] == "0":
            clean_train["source"] = "hard_negative_top5000"
            train_hard_negatives += 1

    adversarial_test_rows = [
        {
            "domain": domain,
            "label": "1",
            "source": f"adversarial_{source}",
            "license": SYNTHETIC_LICENSE,
            "retrieved_at": "deterministic-seed-42",
        }
        for domain, source in sorted(test_variants.items())
    ]
    brand_domain_set = set(brand_domains)
    for row in test_rows:
        domain = row["domain"].strip().lower()
        if row["label"] == "0" and domain in brand_domain_set and _hard_negative(domain):
            safe_row = dict(row)
            safe_row["source"] = "hard_negative_top5000"
            adversarial_test_rows.append(safe_row)
            test_hard_negatives += 1

    synthetic_rows = [
        {
            "domain": domain,
            "label": "1",
            "source": f"adversarial_{source}",
            "license": SYNTHETIC_LICENSE,
            "retrieved_at": "deterministic-seed-42",
        }
        for domain, source in sorted(train_variants.items())
    ]
    augmented_train = train_rows + synthetic_rows
    if len({row["domain"].strip().lower() for row in augmented_train}) != len(augmented_train):
        raise ValueError("El train adversarial contiene dominios duplicados.")
    synthetic_share = len(synthetic_rows) / (
        clean_train_threats + len(synthetic_rows)
    )
    if synthetic_share > 0.30:
        raise AssertionError(f"La proporción sintética superó el 30%: {synthetic_share:.6f}")
    if not train_hard_negatives or not test_hard_negatives:
        raise ValueError(
            "No se encontraron hard negatives SAFE derivados de dominios "
            "Majestic top-5000 en train y test."
        )

    _write_rows(train_output, augmented_train)
    _write_rows(adversarial_test_output, adversarial_test_rows)
    source_counts = Counter(row["source"] for row in synthetic_rows)
    test_source_counts = Counter(row["source"] for row in adversarial_test_rows)
    report: dict[str, object] = {
        "seed": SEED,
        "clean_train_rows": len(train_rows),
        "augmented_train_rows": len(augmented_train),
        "train_class_counts": _counts(augmented_train),
        "synthetic_threat_rows": len(synthetic_rows),
        "synthetic_threat_share": synthetic_share,
        "synthetic_rows_by_source": dict(sorted(source_counts.items())),
        "train_hard_negative_safe_rows": train_hard_negatives,
        "clean_val_rows": len(val_rows),
        "clean_test_rows": len(test_rows),
        "adversarial_test_rows": len(adversarial_test_rows),
        "adversarial_test_class_counts": _counts(adversarial_test_rows),
        "adversarial_test_rows_by_source": dict(sorted(test_source_counts.items())),
        "adversarial_test_hard_negative_safe_rows": test_hard_negatives,
    }
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train", type=Path, default=SPLIT_DIR / "train.csv")
    parser.add_argument("--val", type=Path, default=SPLIT_DIR / "val.csv")
    parser.add_argument("--test", type=Path, default=SPLIT_DIR / "test.csv")
    parser.add_argument(
        "--train-output",
        type=Path,
        default=SPLIT_DIR / "train_adversarial.csv",
    )
    parser.add_argument(
        "--test-output",
        type=Path,
        default=SPLIT_DIR / "test_adversarial.csv",
    )
    parser.add_argument("--brand-domains", type=Path, default=BRAND_DOMAINS)
    args = parser.parse_args()
    report = build(
        args.train,
        args.val,
        args.test,
        args.train_output,
        args.test_output,
        args.brand_domains,
    )
    for key, value in report.items():
        print(f"{key.upper()}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
