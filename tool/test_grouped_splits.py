"""Deterministic leakage guards for the real-data training pipeline."""

import json
import sys

import pytest

from tool import train_max_aura_brain as trainer
from tool.dataset import build_adversarial_splits as adversarial
from tool.train_max_aura_brain import read_split, validate_split_integrity
from tool.dataset.grouped_splits import (
    public_suffix_snapshot_sha256,
    registrable_group,
    split_dataset,
    split_name_for_group,
)
from tool.dataset.build_adversarial_splits import require_disjoint_groups, variant_group_is_allowed


def test_registrable_groups_use_offline_icann_psl_and_conservative_private_policy():
    assert registrable_group("x.Example.co.uk.") == "example.co.uk"
    assert registrable_group("y.example.co.uk") == "example.co.uk"
    assert registrable_group("x.city.kawasaki.jp") == "city.kawasaki.jp"  # PSL exception
    assert registrable_group("other.blogspot.com") == "blogspot.com"  # private suffix ignored
    assert registrable_group("one.unknownsuffix") == "one.unknownsuffix"
    assert registrable_group("a.täst.de") == "xn--tst-qla.de"
    assert len(public_suffix_snapshot_sha256()) == 64


@pytest.mark.parametrize("host", ["co.uk", "192.168.0.1", "invalid..com", "-x.example", "http://x.com"])
def test_group_rejects_public_suffixes_ips_and_invalid_hosts(host):
    with pytest.raises(ValueError):
        registrable_group(host)


def test_grouped_split_is_deterministic_and_preserves_all_rows():
    rows = [
        {"domain": f"{prefix}{index}.example", "label": label}
        for label, prefix in ((0, "safe"), (1, "threat"))
        for index in range(2000)
    ]
    # Mixed labels and subdomains of the same group must follow that group.
    rows.extend([
        {"domain": "a.family.co.uk", "label": 0},
        {"domain": "b.family.co.uk", "label": 1},
    ])
    first = split_dataset(rows, min_rows_per_class=20)
    second = split_dataset(list(reversed(rows)), min_rows_per_class=20)
    assert first == second
    assert sum(map(len, first.values())) == len(rows)
    groups = {name: {registrable_group(row["domain"]) for row in split} for name, split in first.items()}
    assert not groups["train"] & groups["val"]
    assert not groups["train"] & groups["test"]
    assert not groups["val"] & groups["test"]
    assert sum("family.co.uk" in group_set for group_set in groups.values()) == 1
    assert split_name_for_group("family.co.uk") in first


def test_insufficient_and_imbalanced_groups_fail_closed():
    with pytest.raises(ValueError, match="at least"):
        split_dataset([{"domain": "only.example", "label": 0}])
    # Many rows but only one group for a class cannot provide a valid holdout.
    rows = [{"domain": f"x{i}.same.example", "label": 0} for i in range(300)]
    rows += [{"domain": f"different{i}.example", "label": 1} for i in range(300)]
    with pytest.raises(ValueError):
        split_dataset(rows, min_rows_per_class=1)


def test_adversarial_generation_excludes_protected_groups():
    train = [{"domain": "train.example"}]
    validation = [{"domain": "a.other.co.uk"}]
    test = [{"domain": "heldout.example"}]
    groups = require_disjoint_groups(train, validation, test)
    assert not variant_group_is_allowed("b.other.co.uk", groups[1])
    assert variant_group_is_allowed("newdomain.co.uk", groups[1])
    assert not variant_group_is_allowed("co.uk", groups[1])
    with pytest.raises(ValueError, match="disjoint"):
        require_disjoint_groups(train, validation, [{"domain": "b.other.co.uk"}])


def test_adversarial_builder_outputs_disjoint_groups_end_to_end(tmp_path, monkeypatch):
    split_dir = tmp_path / "splits"
    popular_path = tmp_path / "popular.txt"
    manifest_path = tmp_path / "manifest.json"
    monkeypatch.setattr(adversarial, "ROOT", tmp_path)
    monkeypatch.setattr(adversarial, "SPLIT_DIR", split_dir)
    monkeypatch.setattr(adversarial, "POPULAR_PATH", popular_path)
    monkeypatch.setattr(adversarial, "MANIFEST_PATH", manifest_path)
    monkeypatch.setattr(adversarial, "MIN_ADVERSARIAL_ROWS_PER_CLASS", 3)
    train_safe = [f"safetrain{i}.com" for i in range(3)]
    test_safe = [f"safetest{i}.com" for i in range(3)]
    popular_path.write_text("\n".join(train_safe + test_safe + [f"extra{i}.com" for i in range(4994)]) + "\n")

    def row(domain, label):
        return {"domain": domain, "label": str(label), "source": "fixture", "license": "test", "retrieved_at": "test"}

    adversarial.write_rows(split_dir / "train.csv", [row(host, 0) for host in train_safe] + [row("badtrain.net", 1)])
    adversarial.write_rows(split_dir / "val.csv", [row("safeval.com", 0), row("badval.net", 1)])
    adversarial.write_rows(split_dir / "test.csv", [row(host, 0) for host in test_safe] + [row("badtest.net", 1)])
    assert adversarial.main() == 0
    validate_split_integrity(
        read_split(split_dir / "train_adversarial.csv"),
        read_split(split_dir / "val.csv"),
        read_split(split_dir / "test.csv"),
        read_split(split_dir / "test_adversarial.csv"),
    )
    assert manifest_path.exists()


def test_seed_only_fallback_is_rejected_without_fabricated_holdout(tmp_path, monkeypatch):
    monkeypatch.setattr(trainer, "ROOT", tmp_path)
    monkeypatch.setattr(trainer, "DATASET_DIR", tmp_path / "missing-data")
    monkeypatch.setattr(trainer, "MODEL_OUTPUT", tmp_path / "candidate.json")
    monkeypatch.setattr(sys, "argv", ["train_max_aura_brain.py", "--allow-seed-only"])
    captured = {}
    monkeypatch.setattr(trainer, "write_metrics", lambda metrics: captured.update(metrics))
    with pytest.raises(SystemExit) as error:
        trainer.main()
    assert error.value.code == 2  # The quality gate must reject this candidate.
    assert captured["evaluation_mode"] == "seed-only-not-a-holdout"
    assert captured["adversarial_test_rows"] == 0
    assert captured["adversarial_test_metrics"] is None
    assert json.loads((tmp_path / "candidate.json").read_text())["csv_files"] == []
