import 'dart:isolate';

import '../inference/aura_ai_inference.dart' as shared_features;

class AuraInferenceResult {
  const AuraInferenceResult({
    required this.host,
    required this.threatScore,
    required this.isThreat,
    required this.computedFeatures,
    this.featureVector = const <double>[],
    this.featureOrder = const <String>[],
  });

  final String host;
  final double threatScore;
  final bool isThreat;
  final Map<String, double> computedFeatures;
  final List<double> featureVector;
  final List<String> featureOrder;
}

abstract final class AuraAIInference {
  static const int _expectedTreeCount = 500;
  static const int _maximumTreeDepth = 32;
  static Future<List<AuraInferenceResult>> analyzeThreatPayload({
    required String rawData,
    required Map<String, dynamic> modelStructure,
    required List<String> suspiciousTlds,
    bool blocklistChecked = false,
  }) async {
    final domains =
        shared_features.AuraAIInference.extractDomainsForBlocklist(rawData);
    final blockedDomains = blocklistChecked
        ? <String>{}
        : await shared_features.AuraAIInference.findBlocklistedDomains(domains);
    final serializedResult = await Isolate.run<Map<String, Object?>>(
      () => _processInBackground(
        rawData,
        modelStructure,
        suspiciousTlds,
        blockedDomains.toList(growable: false),
      ),
    );
    final rawResults = serializedResult['results'];
    if (rawResults is! List) {
      throw const FormatException('El resultado del isolate no es válido.');
    }
    return rawResults.map((rawResult) {
      if (rawResult is! Map) {
        throw const FormatException('Resultado de inferencia inválido.');
      }
      final result = Map<String, Object?>.from(rawResult);
      final host = result['host'];
      final score = result['threat_score'];
      final threat = result['is_threat'];
      final rawFeatures = result['features'];
      final rawFeatureVector = result['feature_vector'];
      final rawFeatureOrder = result['feature_order'];
      if (host is! String ||
          score is! num ||
          threat is! bool ||
          rawFeatures is! Map ||
          rawFeatureVector is! List ||
          rawFeatureOrder is! List) {
        throw const FormatException('Campos de inferencia incompletos.');
      }
      final features = <String, double>{};
      for (final entry in rawFeatures.entries) {
        if (entry.key is! String || entry.value is! num) {
          throw const FormatException(
            'Las características devueltas por el isolate no son válidas.',
          );
        }
        features[entry.key as String] = (entry.value as num).toDouble();
      }
      if (rawFeatureVector.any((value) => value is! num) ||
          rawFeatureOrder.any((value) => value is! String)) {
        throw const FormatException(
          'El vector u orden de características devuelto por el isolate no es válido.',
        );
      }
      return AuraInferenceResult(
        host: host,
        threatScore: score.toDouble(),
        isThreat: threat,
        computedFeatures: Map<String, double>.unmodifiable(features),
        featureVector: List<double>.unmodifiable(
          rawFeatureVector.cast<num>().map((value) => value.toDouble()),
        ),
        featureOrder: List<String>.unmodifiable(
          rawFeatureOrder.cast<String>(),
        ),
      );
    }).toList(growable: false);
  }

  static Map<String, Object?> _processInBackground(
    String rawData,
    Map<String, dynamic> modelStructure,
    List<String> suspiciousTlds,
    List<String> blockedDomains,
  ) {
    final hosts =
        shared_features.AuraAIInference.extractDomainsForBlocklist(rawData);
    if (hosts.isEmpty) return <String, Object?>{'results': <Object?>[]};

    final blocked = blockedDomains.toSet();
    final requiresModel = hosts.any((host) => !blocked.contains(host));
    final trees = modelStructure['trees'];
    if (requiresModel &&
        (trees is! List || trees.length != _expectedTreeCount)) {
      throw const FormatException(
        'El modelo local no contiene exactamente 500 árboles.',
      );
    }
    final suspicious = suspiciousTlds.map((tld) => tld.toLowerCase()).toSet();
    final featureOrder = modelStructure['feature_order'];
    final usesEnhancedFeatures = featureOrder is List &&
        _matchesFeatureOrder(
          featureOrder,
          shared_features.AuraAIInference.enhancedFeatureOrder,
        );
    final results = <Map<String, Object?>>[];
    for (final host in hosts) {
      if (blocked.contains(host)) {
        results.add(<String, Object?>{
          'host': host,
          'threat_score': 1.0,
          'is_threat': true,
          'features': <String, double>{'blocklist_match': 1.0},
          'feature_vector': <double>[],
          'feature_order': <String>[],
        });
        continue;
      }
      final features = shared_features.AuraAIInference.extractFeaturesForModel(
        host,
        featureOrder,
      );
      features[5] =
          suspicious.contains(host.substring(host.lastIndexOf('.') + 1))
              ? 1.0
              : 0.0;
      var threatVotes = 0;
      for (final tree in trees as List) {
        if (tree is! Map || !tree.containsKey('root')) {
          throw const FormatException('Raíz de árbol inválida en el bosque.');
        }
        threatVotes += _evaluateNode(tree['root'], features);
      }
      final threatScore = threatVotes / trees.length;
      final maximumConsonantStreak = _maximumConsonantStreak(host);
      final activeFeatureOrder = usesEnhancedFeatures
          ? shared_features.AuraAIInference.enhancedFeatureOrder
          : shared_features.AuraAIInference.legacyFeatureOrder;
      results.add(<String, Object?>{
        'host': host,
        'threat_score': threatScore,
        'is_threat': threatScore >= 0.5,
        'features': <String, double>{
          'length': features[0],
          'entropy': features[1],
          'digit_ratio': features[2],
          'vowel_ratio': features[3],
          'consonant_sequence_ratio': features[4],
          'suspicious_tld': features[5],
          for (var index = 6;
              usesEnhancedFeatures &&
                  index <
                      shared_features
                          .AuraAIInference.enhancedFeatureOrder.length;
              index++)
            shared_features.AuraAIInference.enhancedFeatureOrder[index]:
                features[index],
          'maximum_consonant_streak': maximumConsonantStreak.toDouble(),
          'maximum_consonant_streak_ratio':
              host.isEmpty ? 0.0 : maximumConsonantStreak / host.runes.length,
        },
        'feature_vector': features,
        'feature_order': activeFeatureOrder,
      });
    }
    return <String, Object?>{'results': results};
  }

  static bool _matchesFeatureOrder(
    List<dynamic> actual,
    List<String> expected,
  ) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  static int _maximumConsonantStreak(String host) {
    var current = 0;
    var maximum = 0;
    for (final character in host.runes) {
      if (_isAsciiLetter(character) && !_isVowel(character | 0x20)) {
        current++;
        if (current > maximum) maximum = current;
      } else {
        current = 0;
      }
    }
    return maximum;
  }

  static int _evaluateNode(
    Object? rawNode,
    List<double> features, [
    int depth = 0,
  ]) {
    if (rawNode is! Map || depth > _maximumTreeDepth) {
      throw const FormatException('Nodo inválido en el modelo local.');
    }
    if (rawNode['type'] == 'leaf') {
      final value = rawNode['value'];
      if (value is! int || (value != 0 && value != 1)) {
        throw const FormatException('La hoja debe contener un voto binario.');
      }
      return value;
    }
    final featureIndex = rawNode['feature_index'];
    final threshold = rawNode['threshold'];
    if (rawNode['type'] != 'split' ||
        featureIndex is! int ||
        featureIndex < 0 ||
        featureIndex >= features.length ||
        threshold is! num ||
        !threshold.toDouble().isFinite) {
      throw const FormatException('Nodo de bifurcación inválido.');
    }
    final branch = features[featureIndex] <= threshold.toDouble()
        ? rawNode['left']
        : rawNode['right'];
    return _evaluateNode(branch, features, depth + 1);
  }

  static bool _isAsciiLetter(int character) =>
      (character >= 65 && character <= 90) ||
      (character >= 97 && character <= 122);

  static bool _isVowel(int character) =>
      character == 0x61 ||
      character == 0x65 ||
      character == 0x69 ||
      character == 0x6f ||
      character == 0x75;
}
