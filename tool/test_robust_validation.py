"""Tests for validation-only calibration; no model or device is exercised."""

import pytest

from tool.train_max_aura_brain import (
    choose_robust_validation_threshold,
    validate_split_integrity,
)


def test_calibration_uses_validation_constraints_and_improves_adversarial_recall():
    threshold, rule, metrics = choose_robust_validation_threshold(
        [0.1, 0.9], [0, 1], [0.1, 0.4], [0, 1]
    )
    assert rule == "validation_adversarial_recall_constrained"
    assert 0.1 < threshold <= 0.4
    assert metrics["adversarial"]["recall"] == 1.0
    assert metrics["regular"]["false_positive_rate"] == 0.0


def test_calibration_rejects_when_no_valid_threshold_exists():
    with pytest.raises(ValueError, match="No validation threshold"):
        choose_robust_validation_threshold([0.8, 0.1], [0, 1], [0.8, 0.1], [0, 1])


def test_adversarial_validation_cannot_share_test_or_train_groups():
    train = [("train.example", 0)]
    val = [("val.example", 0)]
    test = [("test.example", 0)]
    adv_test = [("test.example", 0), ("other.example", 1)]
    validate_split_integrity(train, val, test, adv_test,
                             [("val.example", 0), ("valsecure.example", 1)])
    with pytest.raises(ValueError, match="Leakage"):
        validate_split_integrity(train, val, test, adv_test,
                                 [("val.example", 0), ("x.other.example", 1)])
    with pytest.raises(ValueError, match="Only matching safe"):
        validate_split_integrity(train, val, test, adv_test,
                                 [("val.example", 1), ("valsecure.example", 1)])
