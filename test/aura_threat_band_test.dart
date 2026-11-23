import 'package:flutter_test/flutter_test.dart';

import 'package:aura_mobile_defens/inference/aura_ai_inference.dart';
import 'package:aura_mobile_defens/inference/aura_host_policy.dart';
import 'package:aura_mobile_defens/models/aura_ai_brain.dart' as model_inference;

/// Bosque determinista: vota amenaza si el host tiene más de 15 caracteres.
Map<String, Object> _lengthForest() {
  final tree = <String, Object>{
    'root': <String, Object>{
      'type': 'split',
      'feature_index': 0,
      'threshold': 15.0,
      'left': <String, Object>{'type': 'leaf', 'value': 0},
      'right': <String, Object>{'type': 'leaf', 'value': 1},
    },
  };
  return <String, Object>{
    'trees': List<Object>.generate(500, (_) => tree, growable: false),
    'feature_order': AuraAIInference.legacyFeatureOrder,
  };
}

Future<model_inference.AuraInferenceResult> _analyze(String host) async {
  final results = await model_inference.AuraAIInference.analyzeThreatPayload(
    rawData: host,
    modelStructure: _lengthForest(),
    suspiciousTlds: const <String>[],
    blocklistChecked: true,
  );
  expect(results, hasLength(1));
  return results.single;
}

void main() {
  test('un subdominio largo de un dominio limpio pide revisión', () async {
    final result = await _analyze('noticias.caracoltv.com');

    expect(result.host, 'noticias.caracoltv.com');
    expect(result.registrableDomain, 'caracoltv.com');
    expect(result.threatScore, 1.0);
    expect(result.registrableScore, 0.0);
    expect(result.riskBand, AuraRiskBand.review);
    expect(result.isThreat, isFalse);
  });

  test(
    'un host opaco con dominio registrable opaco sube a prioridad alta',
    () async {
      final result = await _analyze('x921llmzaqp0182ncnw.xyz');

      expect(result.registrableDomain, 'x921llmzaqp0182ncnw.xyz');
      expect(result.riskBand, AuraRiskBand.high);
      expect(result.isThreat, isTrue);
    },
  );

  test('un dominio corto y conocido queda sin señal', () async {
    final result = await _analyze('google.com');

    expect(result.threatScore, 0.0);
    expect(result.registrableScore, 0.0);
    expect(result.riskBand, AuraRiskBand.clear);
    expect(result.isThreat, isFalse);
  });

  test('el veredicto del isolate nunca contradice la banda', () async {
    for (final host in <String>[
      'google.com',
      'pubmed.ncbi.nlm.nih.gov',
      'x921llmzaqp0182ncnw.xyz',
    ]) {
      final result = await _analyze(host);
      expect(result.isThreat, result.riskBand == AuraRiskBand.high);
    }
  });
}
