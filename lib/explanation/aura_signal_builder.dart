import '../inference/aura_ai_inference.dart';
import 'aura_verdict_explanation.dart';

class AuraSignalBuilder {
  AuraSignalBuilder._();

  static const int _maximumSignals = 6;
  static const int _maximumSafeSignals = 2;
  static const double _highEntropyThreshold = 3.8;
  static const double _suspiciousDigitRatioThreshold = 0.2;
  static const double _repeatedBigramThreshold = 0.2;
  static const int _suspiciousSubdomainDepth = 5;
  static const List<String> _suspiciousKeywords = <String>[
    'free',
    'reward',
    'update',
    'system',
    'unlock',
    'premium',
    'crack',
  ];

  static int _nextId = 0;

  static AuraVerdictExplanation buildExplanation({
    required String host,
    required bool esThreat,
    required List<double> features,
    required List<String> featureOrder,
    required String modelVersion,
    required String modelSha256,
    String source = 'ml',
    bool signatureVerified = false,
  }) {
    if (features.length != featureOrder.length || features.isEmpty) {
      throw const FormatException(
        'El vector y el orden de características no coinciden.',
      );
    }
    if (features.any((value) => !value.isFinite) ||
        featureOrder.toSet().length != featureOrder.length) {
      throw const FormatException(
        'El vector de características de la explicación no es válido.',
      );
    }
    if (source != 'ml' && source != 'blocklist' && source != 'allowlist') {
      throw const FormatException('La fuente de explicación no es válida.');
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(modelSha256)) {
      throw const FormatException(
        'El SHA-256 del modelo debe contener 64 dígitos hexadecimales.',
      );
    }

    final featureValues = <String, double>{
      for (var index = 0; index < featureOrder.length; index++)
        featureOrder[index]: features[index],
    };
    final signals = <AuraSignal>[];
    final entropyIndex = _indexOf(featureOrder, 'shannon_entropy');
    final typoIndex = _indexOf(featureOrder, 'min_normalized_levenshtein');
    final homographIndex = _indexOf(featureOrder, 'idn_homograph_indicator');
    final suspiciousTldIndex = _indexOf(featureOrder, 'suspicious_tld');
    final subdomainIndex = _indexOf(featureOrder, 'subdomain_depth');
    final keywordIndex = _indexOf(featureOrder, 'suspicious_keyword_indicator');
    final digitIndex = _indexOf(featureOrder, 'digit_ratio');
    final consecutiveDigitsIndex =
        _indexOf(featureOrder, 'consecutive_digits_indicator');
    final bigramIndex = _indexOf(featureOrder, 'bigram_repeat_ratio');

    final normalizedHost = host.trim().toLowerCase();
    final distance = typoIndex >= 0
        ? featureValues['min_normalized_levenshtein']
        : AuraAIInference.levenshteinDistanceToTopDomains(normalizedHost);
    if (distance != null &&
        distance > 0 &&
        AuraAIInference.isProbableTyposquatting(normalizedHost)) {
      final closestDomain =
          AuraAIInference.closestTopDomain(normalizedHost) ?? 'dominio popular';
      final isModelFeature = typoIndex >= 0;
      signals.add(
        AuraSignal(
          featureName: 'min_normalized_levenshtein',
          label: isModelFeature
              ? 'Posible typosquatting'
              : 'Posible typosquatting (señal auxiliar)',
          value: distance,
          description: isModelFeature
              ? 'Índice $typoIndex · min_normalized_levenshtein; ${distance.toStringAsFixed(2)} frente a $closestDomain.'
              : 'Auxiliar, fuera del vector · min_normalized_levenshtein; ${distance.toStringAsFixed(2)} frente a $closestDomain.',
        ),
      );
    }

    final homographValue = featureValues['idn_homograph_indicator'];
    if (homographIndex >= 0 && homographValue != null && homographValue > 0) {
      signals.add(
        AuraSignal(
          featureName: 'idn_homograph_indicator',
          label: 'Homoglifos IDN',
          value: homographValue,
          description:
              'Índice $homographIndex · idn_homograph_indicator; caracteres cirílicos confusables.',
        ),
      );
    }

    final entropyValue = featureValues['shannon_entropy'];
    if (entropyIndex >= 0 &&
        entropyValue != null &&
        entropyValue >= _highEntropyThreshold) {
      signals.add(
        AuraSignal(
          featureName: 'shannon_entropy',
          label: 'Entropía alta del dominio',
          value: entropyValue,
          description:
              'Índice $entropyIndex · shannon_entropy; umbral 3,8 de la regla local.',
        ),
      );
    }

    final tldValue = featureValues['suspicious_tld'];
    if (suspiciousTldIndex >= 0 && tldValue == 1) {
      final tld = normalizedHost.contains('.')
          ? normalizedHost.substring(normalizedHost.lastIndexOf('.') + 1)
          : '';
      signals.add(
        AuraSignal(
          featureName: 'suspicious_tld',
          label: 'TLD en lista sospechosa',
          value: tldValue!,
          description:
              'Índice $suspiciousTldIndex · suspicious_tld; TLD .$tld.',
        ),
      );
    }

    final subdomainValue = featureValues['subdomain_depth'];
    final subdomainDepth =
        subdomainValue == null ? 0 : (subdomainValue * 126).round();
    if (subdomainIndex >= 0 && subdomainDepth >= _suspiciousSubdomainDepth) {
      signals.add(
        AuraSignal(
          featureName: 'subdomain_depth',
          label: 'Profundidad anómala de subdominios',
          value: subdomainValue!,
          description:
              'Índice $subdomainIndex · subdomain_depth; $subdomainDepth niveles.',
        ),
      );
    }

    final keywordValue = featureValues['suspicious_keyword_indicator'];
    final keyword = _suspiciousKeywords.firstWhere(
      normalizedHost.contains,
      orElse: () => '',
    );
    if (keywordIndex >= 0 && keywordValue == 1 && keyword.isNotEmpty) {
      signals.add(
        AuraSignal(
          featureName: 'suspicious_keyword_indicator',
          label: 'Palabra clave de señuelo',
          value: keywordValue!,
          description:
              'Índice $keywordIndex · suspicious_keyword_indicator; "$keyword".',
        ),
      );
    }

    final consecutiveDigitsValue =
        featureValues['consecutive_digits_indicator'];
    if (consecutiveDigitsIndex >= 0 && consecutiveDigitsValue == 1) {
      signals.add(
        AuraSignal(
          featureName: 'consecutive_digits_indicator',
          label: 'Dígitos consecutivos',
          value: consecutiveDigitsValue!,
          description:
              'Índice $consecutiveDigitsIndex · consecutive_digits_indicator; patrón observado.',
        ),
      );
    }

    final bigramValue = featureValues['bigram_repeat_ratio'];
    if (bigramIndex >= 0 &&
        bigramValue != null &&
        bigramValue >= _repeatedBigramThreshold) {
      signals.add(
        AuraSignal(
          featureName: 'bigram_repeat_ratio',
          label: 'Bigramas repetidos',
          value: bigramValue,
          description:
              'Índice $bigramIndex · bigram_repeat_ratio; repetición ≥ 0,20.',
        ),
      );
    }

    final digitValue = featureValues['digit_ratio'];
    if (digitIndex >= 0 &&
        digitValue != null &&
        digitValue >= _suspiciousDigitRatioThreshold) {
      signals.add(
        AuraSignal(
          featureName: 'digit_ratio',
          label: 'Proporción de dígitos elevada',
          value: digitValue,
          description: 'Índice $digitIndex · digit_ratio; umbral 0,20.',
        ),
      );
    }

    final maximumSignals = esThreat ? _maximumSignals : _maximumSafeSignals;
    final selectedSignals =
        signals.take(maximumSignals).toList(growable: false);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return AuraVerdictExplanation(
      id: '$timestamp:${_nextId++}:$normalizedHost',
      host: normalizedHost,
      isThreat: esThreat,
      source: source,
      timestamp: timestamp,
      modelVersion: modelVersion,
      modelSha256: modelSha256.toLowerCase(),
      signals: selectedSignals,
      signatureVerified: signatureVerified,
    );
  }

  static int _indexOf(List<String> featureOrder, String featureName) =>
      featureOrder.indexOf(featureName);
}
