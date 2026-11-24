#!/usr/bin/env python3
"""Puerta de calidad del clasificador léxico.

Ejecuta la auditoría reproducible y falla si alguna métrica empeora más allá de
los límites declarados aquí. Los límites se fijaron a partir de la medición del
modelo 3.0.0 (2026-11-22):

    FPR corpus legítimo            3.55 %  -> límite 4.50 %
    FPR banda "prioridad alta"     2.28 %  -> límite 3.00 %
    DGA sintético (umbral 0.50)   94.60 %  -> mínimo 92.00 %
    DGA en banda alta             90.80 %  -> mínimo 88.00 %
    Phishing sintético            97.67 %  -> mínimo 96.00 %

Uso:
    python3 tool/ci_classifier_gate.py

Salida: una línea PASS/FAIL por métrica y código 1 si algo falla.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

_AUDIT = Path(__file__).with_name("audit_classifier_quality.py")


def _metric(report: dict, *path: str) -> float:
    value: object = report
    for key in path:
        if not isinstance(value, dict) or key not in value:
            raise SystemExit(f"No se encontró la métrica {'/'.join(path)}.")
        value = value[key]
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise SystemExit(f"La métrica {'/'.join(path)} no es numérica.")
    return float(value)


def main() -> int:
    result = subprocess.run(
        [sys.executable, str(_AUDIT), "--json"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        print("FAIL: la auditoría no pudo ejecutarse.", file=sys.stderr)
        return 1
    try:
        report = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        print(f"FAIL: la auditoría no devolvió JSON válido: {error}", file=sys.stderr)
        return 1

    checks = [
        (
            "FPR corpus legítimo",
            _metric(report, "legitimate_corpus", "false_positive_rate"),
            "<=",
            0.045,
        ),
        (
            "FPR banda prioridad alta",
            _metric(report, "legitimate_corpus", "banded", "false_positive_rate_high"),
            "<=",
            0.030,
        ),
        (
            "DGA sintético (umbral del modelo)",
            _metric(report, "synthetic_corpora", "dga_synthetic", "detection_rate"),
            ">=",
            0.920,
        ),
        (
            "DGA en banda prioridad alta",
            _metric(
                report,
                "synthetic_corpora",
                "dga_synthetic",
                "banded_high_detection_rate",
            ),
            ">=",
            0.880,
        ),
        (
            "Phishing sintético",
            _metric(
                report,
                "synthetic_corpora",
                "phishing_pattern_synthetic",
                "detection_rate",
            ),
            ">=",
            0.960,
        ),
    ]

    failed = 0
    for label, value, operator, limit in checks:
        ok = value <= limit if operator == "<=" else value >= limit
        state = "PASS" if ok else "FAIL"
        if not ok:
            failed += 1
        print(f"{state} {label}: {value:.4f} ({operator} {limit:.4f})")

    structure = report.get("structure", {})
    trees = structure.get("trees", structure.get("tree_count"))
    if trees is not None and trees != 500:
        print(f"FAIL estructura del bosque: {trees} árboles (se esperaban 500)")
        failed += 1
    declared = report.get("model", {}).get("declared_decision_threshold")
    if declared is None:
        print(
            "AVISO el asset no declara decision_threshold; el cliente aplica 0.50. "
            "La banda de revisión no depende de ese valor."
        )

    print(f"{'OK' if failed == 0 else 'FALLÓ'}: {len(checks) - failed}/{len(checks)} métricas dentro de límite.")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
