"""Offline registrable-domain grouping for dataset leakage prevention.

Uses tldextract's bundled Public Suffix List snapshot, not a network fetch.
Private PSL rules are deliberately excluded, grouping hosted tenants under the
same ICANN registrable domain. This is conservative, not proof of independence.
"""
from __future__ import annotations

import hashlib
import ipaddress
import re
from functools import lru_cache
from importlib.resources import files

import tldextract

PSL_EXTRACTOR = tldextract.TLDExtract(
    suffix_list_urls=(), cache_dir=None, include_psl_private_domains=False,
)
SPLIT_SEED = 42
SPLIT_THRESHOLDS = (70, 85)
MIN_ROWS_PER_CLASS = 500
MAX_CLASS_RATIO_DEVIATION = 0.05
EXPECTED_EXTRACT_VERSION = "5.3.0"
EXPECTED_SNAPSHOT_SHA256 = "b69315c085d53972724b8f2df111ffc329b0c84fe0a47d62c8c91655cc774a38"


def public_suffix_snapshot_sha256() -> str:
    snapshot = files("tldextract").joinpath(".tld_set_snapshot").read_bytes()
    digest = hashlib.sha256(snapshot).hexdigest()
    if tldextract.__version__ != EXPECTED_EXTRACT_VERSION or digest != EXPECTED_SNAPSHOT_SHA256:
        raise RuntimeError("Unexpected Public Suffix List snapshot; install the pinned training requirements")
    return digest


# Fail closed before assigning groups if the bundled PSL changed.
public_suffix_snapshot_sha256()


@lru_cache(maxsize=131072)
def registrable_group(host: str) -> str:
    """Return an ICANN registrable group, conservatively using last two labels
    for unknown TLDs. Input must already be a canonical domain, not a URL/IP.
    """
    value = host.strip().lower().rstrip(".")
    try:
        value = value.encode("idna").decode("ascii")
    except UnicodeError as error:
        raise ValueError("Invalid domain in group assignment") from error
    labels = value.split(".")
    if len(value) > 253 or len(labels) < 2 or any(
        len(label) > 63 or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label)
        for label in labels
    ):
        raise ValueError("Invalid domain in group assignment")
    try:
        ipaddress.ip_address(value)
    except ValueError:
        pass
    else:
        raise ValueError("IP addresses cannot be dataset domains")
    extracted = PSL_EXTRACTOR(value)
    if extracted.top_domain_under_public_suffix:
        return extracted.top_domain_under_public_suffix
    if extracted.suffix:
        # A bare public suffix is not a registrable domain; do not group it as
        # if it were unrelated to all of the domains underneath it.
        raise ValueError("A public suffix cannot be a dataset host")
    return ".".join(value.split(".")[-2:])


def split_name_for_group(group: str, seed: int = SPLIT_SEED) -> str:
    digest = hashlib.sha256(f"aura-domain-group-v1:{seed}:{group}".encode("ascii")).digest()
    bucket = int.from_bytes(digest[:8], "big")
    limit = 1 << 64
    if bucket < limit * SPLIT_THRESHOLDS[0] // 100:
        return "train"
    if bucket < limit * SPLIT_THRESHOLDS[1] // 100:
        return "val"
    return "test"


def split_dataset(rows, *, min_rows_per_class=MIN_ROWS_PER_CLASS,
                  max_deviation=MAX_CLASS_RATIO_DEVIATION):
    """Stable 70/15/15 hash split. Refuse unbalanced or inadequate datasets.

    Assignment is by group (not by row or label) so mixed-label groups cannot
    cross splits. Class ratios are checked, not claimed to be stratified.
    """
    splits = {name: [] for name in ("train", "val", "test")}
    totals = {0: 0, 1: 0}
    counts = {name: {0: 0, 1: 0} for name in splits}
    for row in rows:
        label = int(row["label"])
        if label not in totals:
            raise ValueError("Dataset labels must be 0 or 1")
        group = registrable_group(str(row["domain"]))
        split = split_name_for_group(group)
        splits[split].append(row)
        counts[split][label] += 1
        totals[label] += 1
    for split, expected in (("train", 0.70), ("val", 0.15), ("test", 0.15)):
        for label in (0, 1):
            count = counts[split][label]
            if count < min_rows_per_class or totals[label] == 0:
                raise ValueError(f"{split} must have at least {min_rows_per_class} rows for each class")
            if abs(count / totals[label] - expected) > max_deviation:
                raise ValueError(
                    f"{split} class {label} group split is too imbalanced; "
                    "add independent real domains instead of splitting related groups"
                )
    for rows_in_split in splits.values():
        rows_in_split.sort(key=lambda row: str(row["domain"]))
    return splits
