class AuraSignal {
  const AuraSignal({
    required this.featureName,
    required this.label,
    required this.value,
    required this.description,
  });

  final String featureName;
  final String label;
  final double value;
  final String description;
}

class AuraVerdictExplanation {
  AuraVerdictExplanation({
    required this.id,
    required this.host,
    required this.isThreat,
    required this.source,
    required this.timestamp,
    required this.modelVersion,
    required this.modelSha256,
    this.decisionThreshold = 0.5,
    required List<AuraSignal> signals,
    this.signatureVerified = false,
    this.reportedFalsePositive = false,
  }) : signals = List<AuraSignal>.unmodifiable(signals);

  final String id;
  final String host;
  final bool isThreat;
  final String source;
  final int timestamp;
  final String modelVersion;
  final String modelSha256;
  final double decisionThreshold;
  final List<AuraSignal> signals;
  final bool signatureVerified;
  final bool reportedFalsePositive;

  AuraVerdictExplanation copyWith({bool? reportedFalsePositive}) =>
      AuraVerdictExplanation(
        id: id,
        host: host,
        isThreat: isThreat,
        source: source,
        timestamp: timestamp,
        modelVersion: modelVersion,
        modelSha256: modelSha256,
        decisionThreshold: decisionThreshold,
        signals: signals,
        signatureVerified: signatureVerified,
        reportedFalsePositive:
            reportedFalsePositive ?? this.reportedFalsePositive,
      );
}
