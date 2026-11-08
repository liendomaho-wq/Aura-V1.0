"""Mobile serialization/budget regressions; not held-out training metrics."""

import ast
import hashlib
import inspect
import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))
from train_max_aura_brain import (  # noqa: E402
    MAX_MOBILE_MODEL_BYTES, MOBILE_TRAINING_CONFIGURATIONS, FEATURE_ORDER,
    mobile_size_failure_message, mobile_tree_stats, serialize_mobile_model,
    train_mobile_preset,
)


@pytest.fixture(scope="module")
def packaged_model():
    return json.loads((ROOT / "assets/model/aura_brain_model.json").read_bytes())


def test_configuration_plan_really_contains_bounded_lower_complexity_retries():
    configurations = MOBILE_TRAINING_CONFIGURATIONS
    assert configurations[0] == (10, 512)
    assert 2 <= len(configurations) <= 4
    assert any(depth == 8 for depth, _ in configurations)
    assert configurations[-1][0] <= 6
    for previous, current in zip(configurations, configurations[1:]):
        assert current[0] < previous[0]
        assert current[1] > previous[1]


def test_last_retry_has_a_worst_case_full_tree_within_unchanged_byte_budget(packaged_model):
    # Deliberate worst-case serialization fixture, NOT a fitted candidate.
    # A depth-d binary tree has at most 2**d leaves. Fit/quality is tested by
    # the separate pipeline on real, grouped training/validation/test data.
    depth = MOBILE_TRAINING_CONFIGURATIONS[-1][0]

    def full_tree(remaining):
        if not remaining:
            return {"type": "leaf", "value": 1}
        return {
            "type": "split", "feature_index": 17, "threshold": 253.9999,
            "left": full_tree(remaining - 1), "right": full_tree(remaining - 1),
        }

    model = dict(packaged_model)
    model["feature_order"] = FEATURE_ORDER
    model["trees"] = [{"root": full_tree(depth)} for _ in range(500)]
    assert mobile_tree_stats(model) == (500 * 2 ** depth, depth)
    assert MAX_MOBILE_MODEL_BYTES == 4_194_304
    assert len(serialize_mobile_model(model)) < MAX_MOBILE_MODEL_BYTES


def test_exact_finite_utf8_round_trip_of_real_packaged_model(packaged_model):
    encoded = serialize_mobile_model(packaged_model)
    assert encoded.endswith(b"\n")
    assert json.loads(encoded) == packaged_model
    assert len(encoded) < MAX_MOBILE_MODEL_BYTES


@pytest.mark.parametrize("invalid", [float("nan"), float("inf"), float("-inf")])
def test_never_serializes_nonfinite_thresholds(packaged_model, invalid):
    model = dict(packaged_model)
    model["decision_threshold"] = invalid
    with pytest.raises(ValueError):
        serialize_mobile_model(model)


def test_tree_statistics_match_independent_walk_of_real_packaged_model(packaged_model):
    leaves = 0
    deepest = 0
    for tree in packaged_model["trees"]:
        stack = [(tree["root"], 0)]
        while stack:
            node, depth = stack.pop()
            deepest = max(deepest, depth)
            if node["type"] == "leaf":
                leaves += 1
            else:
                stack.extend(((node["left"], depth + 1), (node["right"], depth + 1)))
    assert mobile_tree_stats(packaged_model) == (leaves, deepest)
    assert leaves >= 500


def test_failure_diagnostics_list_only_actual_trials(packaged_model):
    trial = {
        "max_depth": packaged_model["training_config"]["max_depth"],
        "min_samples_leaf": packaged_model["training_config"]["min_samples_leaf"],
        "bytes": len(serialize_mobile_model(packaged_model)),
    }
    message = mobile_size_failure_message([trial])
    assert "1 actual training attempts" in message
    assert "depth=10" in message
    assert "depth=8" not in message
    assert "aggressive pruning" not in message
    assert str(trial["bytes"]) in message


def test_holdout_scoring_is_outside_configuration_selection_loop():
    # A source policy guard, not substitute evidence for the real training run.
    function = ast.parse(inspect.getsource(train_mobile_preset)).body[0]
    configuration_loop = next(
        node for node in function.body
        if isinstance(node, ast.For) and isinstance(node.iter, ast.Name)
        and node.iter.id == "configurations"
    )
    scoring_arguments = [
        node.args[1].id
        for node in ast.walk(configuration_loop)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
        and node.func.id == "score_serialized_model"
    ]
    assert scoring_arguments == ["val_rows"]
    assert any(
        isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
        and node.func.id == "score_serialized_model"
        and isinstance(node.args[1], ast.Name) and node.args[1].id == "test_rows"
        for node in ast.walk(function)
    )


def test_active_signed_model_stays_unmodified_at_version_3(packaged_model):
    assert packaged_model["model_version"] == "3.0.0"
    assert hashlib.sha256((ROOT / "assets/model/aura_brain_model.json").read_bytes()).hexdigest() == (
        "d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2"
    )
