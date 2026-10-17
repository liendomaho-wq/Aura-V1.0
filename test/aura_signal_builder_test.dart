import 'package:aura_mobile_defens/explanation/aura_signal_builder.dart';
import 'package:aura_mobile_defens/inference/aura_ai_inference.dart';
import 'package:test/test.dart';

void main() {
  const modelSha256 =
      'd190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2';

  group('AuraSignalBuilder', () {
    test('builds traceable typo signal from the observed feature vector', () {
      final features = AuraAIInference.extractEnhancedFeatures('goggle.com');
      final explanation = AuraSignalBuilder.buildExplanation(
        host: 'goggle.com',
        esThreat: true,
        features: features,
        featureOrder: AuraAIInference.enhancedFeatureOrder,
        modelVersion: '4.0.0',
        modelSha256: modelSha256,
        signatureVerified: true,
      );

      expect(explanation.host, 'goggle.com');
      expect(explanation.source, 'ml');
      expect(explanation.modelVersion, '4.0.0');
      expect(explanation.modelSha256, modelSha256);
      expect(explanation.signatureVerified, isTrue);
      expect(explanation.signals, hasLength(1));
      expect(
          explanation.signals.single.featureName, 'min_normalized_levenshtein');
      expect(explanation.signals.single.value, closeTo(0.1, 1e-12));
      expect(explanation.signals.single.description, contains('Índice 6'));
      expect(explanation.signals.single.description, contains('google.com'));
      expect(explanation.signals.single.description.length,
          lessThanOrEqualTo(120));
    });

    test('labels typo signal as auxiliary for the published six-feature model',
        () {
      final explanation = AuraSignalBuilder.buildExplanation(
        host: 'goggle.com',
        esThreat: true,
        features: AuraAIInference.extractLegacyFeatures('goggle.com'),
        featureOrder: AuraAIInference.legacyFeatureOrder,
        modelVersion: '3.0.0',
        modelSha256: modelSha256,
      );

      expect(explanation.signals, hasLength(1));
      expect(
        explanation.signals.single.label,
        'Posible typosquatting (señal auxiliar)',
      );
      expect(
        explanation.signals.single.description,
        contains('Auxiliar, fuera del vector'),
      );
      expect(
        explanation.signals.single.description,
        contains('min_normalized_levenshtein'),
      );
      expect(explanation.signals.single.description.length,
          lessThanOrEqualTo(120));
    });

    test('limits threat signals to six and safe signals to two', () {
      final threatFeatures =
          AuraAIInference.extractEnhancedFeatures('free1234.xyz').toList()
            ..[5] = 1
            ..[7] = 0.5
            ..[9] = 5 / 126
            ..[11] = 1
            ..[13] = 1
            ..[17] = 1;
      final threat = AuraSignalBuilder.buildExplanation(
        host: 'free1234.xyz',
        esThreat: true,
        features: threatFeatures,
        featureOrder: AuraAIInference.enhancedFeatureOrder,
        modelVersion: '4.0.0',
        modelSha256: modelSha256,
      );
      expect(threat.signals, hasLength(6));

      final safe = AuraSignalBuilder.buildExplanation(
        host: 'example.com',
        esThreat: false,
        features: threatFeatures,
        featureOrder: AuraAIInference.enhancedFeatureOrder,
        modelVersion: '4.0.0',
        modelSha256: modelSha256,
      );
      expect(safe.signals.length, lessThanOrEqualTo(2));
    });

    test('rejects malformed vectors and digests', () {
      expect(
        () => AuraSignalBuilder.buildExplanation(
          host: 'goggle.com',
          esThreat: true,
          features: <double>[1],
          featureOrder: AuraAIInference.enhancedFeatureOrder,
          modelVersion: '4.0.0',
          modelSha256: modelSha256,
        ),
        throwsFormatException,
      );
      expect(
        () => AuraSignalBuilder.buildExplanation(
          host: 'goggle.com',
          esThreat: true,
          features: AuraAIInference.extractEnhancedFeatures('goggle.com'),
          featureOrder: AuraAIInference.enhancedFeatureOrder,
          modelVersion: '4.0.0',
          modelSha256: 'invalid',
        ),
        throwsFormatException,
      );
    });
  });
}
