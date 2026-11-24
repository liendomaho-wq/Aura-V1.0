"""Contrato mínimo de `tool/audit_classifier_quality.py`.

Estas pruebas no evalúan la calidad del modelo: comprueban que el auditor sigue
midiendo el asset real y que su salida conserva la forma que consumen la
documentación y un futuro gate de CI. Si el modelo o la extracción cambian, el
informe debe seguir siendo interpretable o esta prueba falla.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
AUDITOR = ROOT / "tool/audit_classifier_quality.py"


@pytest.fixture(scope="module")
def report() -> dict:
    result = subprocess.run(
        [sys.executable, str(AUDITOR), "--json"],
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_auditor_measures_the_packaged_model(report: dict) -> None:
    model = report["model"]
    assert model["model_version"] == "3.0.0"
    assert model["feature_order"] == [
        "length",
        "shannon_entropy",
        "digit_ratio",
        "vowel_ratio",
        "consonant_sequence_ratio",
        "suspicious_tld",
    ]
    # El asset no declara umbral; el cliente debe caer en 0.50 y el informe
    # tiene que reflejar ese fallback en vez de inventar un valor.
    assert model["declared_decision_threshold"] is None
    assert model["effective_decision_threshold"] == 0.5


def test_legitimate_corpus_report_is_internally_consistent(report: dict) -> None:
    corpus = report["legitimate_corpus"]
    assert corpus["domains_after_static_allowlist"] <= corpus["domains_total"]
    assert 0.0 <= corpus["false_positive_rate"] <= 1.0
    by_length = corpus["by_length"]
    assert by_length, "El informe debe desglosar al menos un tramo de longitud."
    assert (
        sum(values["domains"] for values in by_length.values())
        == corpus["domains_after_static_allowlist"]
    )
    for values in by_length.values():
        assert 0.0 <= values["false_positive_rate"] <= 1.0


def test_threshold_sweep_and_ablation_are_present(report: dict) -> None:
    sweep = report["threshold_sweep"]
    assert [row["threshold"] for row in sweep] == [0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
    ablation = report["ablation"]
    assert set(ablation) == {
        "full_host",
        "etld1_only",
        "full_host_no_tld_feature",
    }
    for values in ablation.values():
        assert 0.0 <= values["false_positive_rate_common"] <= 1.0
        assert 0.0 <= values["detection_rate_dga_synthetic"] <= 1.0
