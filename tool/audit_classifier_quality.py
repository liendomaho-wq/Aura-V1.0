#!/usr/bin/env python3
"""Auditoría reproducible de la calidad del clasificador léxico de Aura.

Este script NO entrena ni modifica el modelo. Lee el asset firmado
`assets/model/aura_brain_model.json`, replica la extracción de las seis
características heredadas de `lib/inference/aura_ai_inference.dart` y evalúa el
bosque sobre:

1. La lista de dominios populares empaquetada en
   `lib/inference/aura_common_domains.dart` (Majestic top 5000), que se usa como
   aproximación de tráfico legítimo. Se excluyen los sufijos de la allowlist
   estática, igual que hace `AuraAIInference.analyzeHostSecure`.
2. Conjuntos sintéticos generados aquí mismo (DGA, cadenas de consonantes,
   typosquatting y patrones de phishing). **No son una evaluación real**: solo
   miden comportamientos léxicos concretos y sirven para comparar versiones.
3. Una ablación de `suspicious_tld` y una variante que evalúa el dominio
   registrable (eTLD+1 aproximado con las dos últimas etiquetas) en lugar del
   host completo.

Las tasas de falsos positivos sobre la lista de populares son una **cota
inferior sesgada**: esa lista contiene muchos hosts cortos y de marca, mientras
que la navegación real incluye más subdominios largos. Las métricas de este
script no sustituyen una evaluación holdout agrupada ni pruebas en dispositivo.

Uso:
    python3 tool/audit_classifier_quality.py
    python3 tool/audit_classifier_quality.py --json

Salida: informe legible por consola y, con `--json`, un objeto JSON con todas
las métricas para comparar entre versiones o publicarlo en un PR.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL_PATH = ROOT / "assets/model/aura_brain_model.json"
COMMON_DOMAINS_PATH = ROOT / "lib/inference/aura_common_domains.dart"

# Debe coincidir con AuraAIInference.auraStaticWhitelist
STATIC_WHITELIST = [
    "google.com",
    "apple.com",
    "microsoft.com",
    "amazonaws.com",
    "cloudflare.com",
    "akamaiedge.net",
    "android.com",
    "github.com",
    "whatsapp.net",
    "googleapis.com",
    "gstatic.com",
    "googleusercontent.com",
    "apple-dns.net",
    "icloud.com",
    "microsoftonline.com",
    "windows.net",
    "amazon.com",
    "awsstatic.com",
    "akamaized.net",
    "fastly.net",
]

# Debe coincidir con AuraAIInference.suspiciousTlds y con el modelo 3.0.0
SUSPICIOUS_TLDS = {
    "xyz", "info", "cc", "top", "cam", "click", "country", "date", "download",
    "fit", "gq", "loan", "mov", "party", "review", "rest", "stream", "support",
    "tk", "wang", "work", "zip",
}

FEATURE_NAMES = [
    "length",
    "shannon_entropy",
    "digit_ratio",
    "vowel_ratio",
    "consonant_sequence_ratio",
    "suspicious_tld",
]

THRESHOLD = 0.5  # AuraAIInference usa 0.5 cuando el modelo no declara umbral.
MAX_DEPTH = 32


def is_ascii_letter(code: int) -> bool:
    return 0x41 <= code <= 0x5A or 0x61 <= code <= 0x7A


def is_ascii_digit(code: int) -> bool:
    return 0x30 <= code <= 0x39


def legacy_features(host: str, zero_tld: bool = False) -> list[float]:
    """Réplica de AuraAIInference._calculateLegacyFeatures."""
    chars = [ord(c) for c in host]
    if not chars:
        return [0.0] * 6
    letters = [c for c in chars if is_ascii_letter(c)]
    digits = sum(1 for c in chars if is_ascii_digit(c))
    vowels = 0
    consonant_run = 0
    consonant_sequence = 0
    for code in chars:
        if not is_ascii_letter(code):
            if consonant_run >= 3:
                consonant_sequence += consonant_run
            consonant_run = 0
            continue
        lower = code | 0x20
        if lower in (0x61, 0x65, 0x69, 0x6F, 0x75):
            vowels += 1
            if consonant_run >= 3:
                consonant_sequence += consonant_run
            consonant_run = 0
        else:
            consonant_run += 1
    if consonant_run >= 3:
        consonant_sequence += consonant_run
    frequencies: dict[int, int] = {}
    for code in chars:
        frequencies[code] = frequencies.get(code, 0) + 1
    entropy = 0.0
    for count in frequencies.values():
        probability = count / len(chars)
        entropy -= probability * math.log2(probability)
    tld = host.rsplit(".", 1)[-1]
    suspicious = 0.0 if zero_tld else (1.0 if tld in SUSPICIOUS_TLDS else 0.0)
    return [
        float(len(chars)),
        entropy,
        digits / len(chars),
        (vowels / len(letters)) if letters else 0.0,
        (consonant_sequence / len(letters)) if letters else 0.0,
        suspicious,
    ]


class Forest:
    """Evaluador del bosque con el mismo recorrido que el cliente Dart."""

    def __init__(self, model: dict) -> None:
        self.model = model
        self.trees = model.get("trees")
        if not isinstance(self.trees, list) or not self.trees:
            raise SystemExit("El modelo no contiene un bosque válido.")
        self.feature_order = model.get("feature_order")
        if self.feature_order != FEATURE_NAMES:
            raise SystemExit(
                "El modelo declara un feature_order distinto del esperado por este "
                f"script: {self.feature_order!r}. Actualice FEATURE_NAMES."
            )
        declared = model.get("decision_threshold")
        self.threshold = (
            float(declared)
            if isinstance(declared, (int, float)) and 0 <= float(declared) <= 1
            else THRESHOLD
        )
        self.structure = self._structure()

    def _structure(self) -> dict:
        feature_use = {name: 0 for name in FEATURE_NAMES}
        depths: list[int] = []
        leaves = {0: 0, 1: 0}

        def walk(node: dict, depth: int) -> None:
            if node.get("type") == "leaf":
                leaves[int(node["value"])] += 1
                depths.append(depth)
                return
            feature_use[FEATURE_NAMES[node["feature_index"]]] += 1
            walk(node["left"], depth + 1)
            walk(node["right"], depth + 1)

        for tree in self.trees:
            walk(tree["root"], 0)
        total_splits = sum(feature_use.values())
        return {
            "trees": len(self.trees),
            "max_leaf_depth": max(depths),
            "mean_leaf_depth": statistics.mean(depths),
            "splits_by_feature": feature_use,
            "split_share_by_feature": {
                name: (count / total_splits if total_splits else 0.0)
                for name, count in feature_use.items()
            },
            "leaf_votes": leaves,
            "threat_leaf_share": leaves[1] / (leaves[0] + leaves[1]),
        }

    def score(self, host: str, zero_tld: bool = False) -> float:
        features = legacy_features(host, zero_tld=zero_tld)
        votes = 0
        for tree in self.trees:
            node = tree["root"]
            depth = 0
            while node["type"] != "leaf":
                depth += 1
                if depth > MAX_DEPTH:
                    raise SystemExit("Árbol más profundo que el límite del cliente.")
                index = node["feature_index"]
                node = (
                    node["left"]
                    if features[index] <= node["threshold"]
                    else node["right"]
                )
            votes += node["value"]
        return votes / len(self.trees)

    def is_threat(self, host: str, threshold: float | None = None) -> bool:
        return self.score(host) >= (self.threshold if threshold is None else threshold)


def load_common_domains() -> list[str]:
    if not COMMON_DOMAINS_PATH.exists():
        return []
    source = COMMON_DOMAINS_PATH.read_text(encoding="utf-8")
    return [
        domain
        for domain in re.findall(r"'([a-z0-9.\-]+)'", source)
        if "." in domain
    ]


def allowlisted(host: str) -> bool:
    return any(host == suffix or host.endswith("." + suffix) for suffix in STATIC_WHITELIST)


REVIEW_FLOOR = 0.35
HIGH_FLOOR = 0.65


def risk_band(host_score: float, registrable_score: float) -> str:
    """Réplica de la política del cliente (AuraHostPolicy).

    Se mantiene aquí para medir el efecto de la banda de revisión sin depender
    de Flutter. Los valores deben coincidir con lib/inference/aura_host_policy.dart.
    """
    if host_score >= HIGH_FLOOR and registrable_score >= HIGH_FLOOR:
        return "high"
    if host_score >= REVIEW_FLOOR or registrable_score >= REVIEW_FLOOR:
        return "review"
    return "clear"


def etld1(host: str) -> str:
    """Aproximación conservadora: dos últimas etiquetas.

    No usa la Public Suffix List; por eso se documenta como aproximación. Basta
    para comparar el efecto de puntuar el dominio registrable en lugar del host
    completo, que es lo que hace hoy el cliente.
    """
    labels = host.split(".")
    return ".".join(labels[-2:]) if len(labels) >= 2 else host


def synthetic_corpora(seed: int = 7) -> dict[str, list[str]]:
    rng = random.Random(seed)

    def dga(count: int = 500) -> list[str]:
        alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
        return [
            "".join(rng.choice(alphabet) for _ in range(rng.randint(8, 20)))
            + rng.choice([".com", ".net", ".xyz", ".top", ".info"])
            for _ in range(count)
        ]

    def consonant(count: int = 300) -> list[str]:
        alphabet = "bcdfghjklmnpqrstvwxz"
        return [
            "".join(rng.choice(alphabet) for _ in range(rng.randint(7, 16)))
            + rng.choice([".com", ".cc", ".tk"])
            for _ in range(count)
        ]

    def typosquat(count: int = 200) -> list[str]:
        bases = [
            "google.com", "facebook.com", "paypal.com", "netflix.com",
            "instagram.com", "whatsapp.com", "bancolombia.com", "mercadolibre.com",
        ]
        substitutions = {"o": "0", "l": "1", "i": "1", "e": "3", "a": "4", "s": "5"}
        results: set[str] = set()
        while len(results) < count:
            name, _, tld = rng.choice(bases).partition(".")
            choice = rng.random()
            if choice < 0.4 and name:
                index = rng.randrange(len(name))
                name = (
                    name[:index]
                    + substitutions.get(name[index], name[index])
                    + name[index + 1:]
                )
            elif choice < 0.7:
                name += rng.choice(["-secure", "-login", "-verify", "-update", "-auth"])
            else:
                name += rng.choice(["-", ""]) + rng.choice(
                    ["support", "service", "account"]
                )
            chosen_tld = tld if rng.random() < 0.5 else rng.choice(
                ["xyz", "top", "cc", "info", "click"]
            )
            results.add(f"{name}.{chosen_tld}")
        return sorted(results)

    def phishing(count: int = 300) -> list[str]:
        brands = [
            "paypal", "apple", "amazon", "netflix", "banco", "daviplata", "nequi",
            "bancolombia", "bbva", "santander", "whatsapp", "instagram", "facebook",
            "microsoft", "office365",
        ]
        tails = [
            "secure-login", "verify-account", "update-payment", "account-recovery",
            "auth-check", "confirm-identity",
        ]
        tlds = ["xyz", "top", "cc", "click", "info", "tk", "gq", "zip", "support"]
        results: set[str] = set()
        while len(results) < count:
            results.add(f"{rng.choice(brands)}-{rng.choice(tails)}.{rng.choice(tlds)}")
        return sorted(results)

    return {
        "dga_synthetic": dga(),
        "consonant_random_synthetic": consonant(),
        "typosquat_synthetic": typosquat(),
        "phishing_pattern_synthetic": phishing(),
    }


def rate(values: list[bool]) -> float:
    return (sum(values) / len(values)) if values else 0.0


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(len(ordered) * fraction)))
    return ordered[index]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Emite solo JSON.")
    parser.add_argument("--seed", type=int, default=7, help="Semilla de los conjuntos sintéticos.")
    args = parser.parse_args(argv)

    if not MODEL_PATH.exists():
        print(f"Falta el modelo: {MODEL_PATH}", file=sys.stderr)
        return 2

    model = json.loads(MODEL_PATH.read_text(encoding="utf-8"))
    forest = Forest(model)
    common_all = load_common_domains()
    common = [host for host in common_all if not allowlisted(host)]
    if not common:
        print("No se pudo cargar la lista de dominios populares.", file=sys.stderr)
        return 2

    scores = [forest.score(host) for host in common]
    flagged = [score >= forest.threshold for score in scores]

    buckets: dict[str, dict[str, float]] = {}
    for host, score in zip(common, scores):
        length = len(host)
        if length <= 15:
            label = "<=15"
        elif length <= 25:
            label = "16-25"
        elif length <= 35:
            label = "26-35"
        else:
            label = ">35"
        bucket = buckets.setdefault(
            label, {"total": 0, "flagged": 0, "sum": 0.0}
        )
        bucket["total"] += 1
        bucket["flagged"] += int(score >= forest.threshold)
        bucket["sum"] += score

    bucket_report = {
        label: {
            "domains": int(values["total"]),
            "false_positive_rate": values["flagged"] / values["total"],
            "mean_score": values["sum"] / values["total"],
        }
        for label, values in sorted(buckets.items())
    }

    band_counts = {"high": 0, "review": 0, "clear": 0}
    for host, host_score in zip(common, scores):
        band_counts[risk_band(host_score, forest.score(etld1(host)))] += 1
    banded_legitimate = {
        "hosts_total": len(common),
        "high": band_counts["high"],
        "review": band_counts["review"],
        "clear": band_counts["clear"],
        "false_positive_rate_high": band_counts["high"] / len(common),
        "review_or_high_share": (band_counts["high"] + band_counts["review"])
        / len(common),
    }

    corpora = synthetic_corpora(seed=args.seed)
    synthetic_report = {}
    for name, hosts in corpora.items():
        corpus_scores = [forest.score(host) for host in hosts]
        bands = [
            risk_band(score, forest.score(etld1(host)))
            for host, score in zip(hosts, corpus_scores)
        ]
        synthetic_report[name] = {
            "domains": len(hosts),
            "detection_rate": rate([s >= forest.threshold for s in corpus_scores]),
            "mean_score": statistics.mean(corpus_scores),
            "banded_high_detection_rate": bands.count("high") / len(hosts),
            "banded_review_or_high_share": (
                bands.count("high") + bands.count("review")
            )
            / len(hosts),
        }

    sweep = []
    for threshold in (0.3, 0.4, 0.5, 0.6, 0.7, 0.8):
        sweep.append(
            {
                "threshold": threshold,
                "false_positive_rate_common": rate([s >= threshold for s in scores]),
                "detection_rate_dga_synthetic": rate(
                    [forest.score(host) >= threshold
                     for host in corpora["dga_synthetic"]]
                ),
            }
        )

    ablation = {}
    for label, zero_tld, transform in (
        ("full_host", False, lambda host: host),
        ("etld1_only", False, etld1),
        ("full_host_no_tld_feature", True, lambda host: host),
    ):
        corpus_scores = [forest.score(transform(host), zero_tld=zero_tld) for host in common]
        dga_scores = [
            forest.score(transform(host), zero_tld=zero_tld)
            for host in corpora["dga_synthetic"]
        ]
        ablation[label] = {
            "false_positive_rate_common": rate([s >= forest.threshold for s in corpus_scores]),
            "detection_rate_dga_synthetic": rate([s >= forest.threshold for s in dga_scores]),
        }

    worst = sorted(zip(scores, common), reverse=True)[:20]

    report = {
        "model": {
            "model_name": model.get("model_name"),
            "model_version": model.get("model_version"),
            "training_status": model.get("training_status"),
            "training_samples": model.get("training_samples"),
            "feature_order": forest.feature_order,
            "declared_decision_threshold": model.get("decision_threshold"),
            "effective_decision_threshold": forest.threshold,
        },
        "structure": forest.structure,
        "legitimate_corpus": {
            "source": "lib/inference/aura_common_domains.dart",
            "domains_total": len(common_all),
            "domains_after_static_allowlist": len(common),
            "false_positive_rate": rate(flagged),
            "score_percentiles": {
                "p50": percentile(scores, 0.50),
                "p90": percentile(scores, 0.90),
                "p95": percentile(scores, 0.95),
                "p99": percentile(scores, 0.99),
            },
            "score_exactly_0_share": rate([s == 0.0 for s in scores]),
            "score_exactly_1_share": rate([s == 1.0 for s in scores]),
            "by_length": bucket_report,
            "banded": banded_legitimate,
            "highest_scoring_legitimate_hosts": worst,
        },
        "synthetic_corpora": synthetic_report,
        "threshold_sweep": sweep,
        "ablation": ablation,
    }

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0

    print("AURA — auditoría de calidad del clasificador léxico")
    print("=" * 58)
    print(f"Modelo: {report['model']['model_name']} {report['model']['model_version']}")
    print(f"Estado de entrenamiento: {report['model']['training_status']}")
    print(
        "Umbral declarado en el asset: "
        f"{report['model']['declared_decision_threshold']!r} "
        f"(efectivo {forest.threshold:.2f})"
    )
    print(
        f"Bosque: {forest.structure['trees']} árboles, profundidad de hoja "
        f"máxima {forest.structure['max_leaf_depth']}, media "
        f"{forest.structure['mean_leaf_depth']:.2f}"
    )
    print("Uso de características (reparto de bifurcaciones):")
    for name, share in forest.structure["split_share_by_feature"].items():
        print(f"  {name:28s} {share * 100:5.1f}%")
    print(
        f"Votos de amenaza en hojas: {forest.structure['threat_leaf_share'] * 100:.1f}%"
    )
    print()
    print(
        "Corpus legítimo (top-5000, sin allowlist): "
        f"{len(common)} hosts, FPR {rate(flagged) * 100:.2f}% "
        f"({sum(flagged)} marcados)"
    )
    for label, values in bucket_report.items():
        print(
            f"  longitud {label:6s} n={values['domains']:4d} "
            f"FPR {values['false_positive_rate'] * 100:6.2f}% "
            f"score medio {values['mean_score']:.3f}"
        )
    print("Conjuntos sintéticos (no equivalen a una evaluación real):")
    for name, values in synthetic_report.items():
        print(
            f"  {name:32s} detección {values['detection_rate'] * 100:5.1f}% "
            f"score medio {values['mean_score']:.3f}"
        )
    print("Barrido de umbral (FPR popular / detección DGA sintética):")
    for row in sweep:
        print(
            f"  {row['threshold']:.1f} -> "
            f"{row['false_positive_rate_common'] * 100:5.2f}% / "
            f"{row['detection_rate_dga_synthetic'] * 100:5.1f}%"
        )
    print("Ablación:")
    for label, values in ablation.items():
        print(
            f"  {label:24s} FPR {values['false_positive_rate_common'] * 100:5.2f}% "
            f"detección {values['detection_rate_dga_synthetic'] * 100:5.1f}%"
        )
    print()
    print("Hosts legítimos con mayor puntuación (revisar falsos positivos):")
    for score, host in worst[:10]:
        print(f"  {score:.3f}  {host}")
    print()
    print(
        "Nota: el corpus popular está sesgado hacia hosts cortos y de marca; "
        "la navegación real incluye más subdominios largos."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
