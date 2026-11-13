const String auraFindingsEngine = 'aura_local_findings';
const String auraFindingsEngineVersion = '1.0.0';

enum AuraFindingSeverity { info, low, medium, high, critical }

extension AuraFindingSeverityLabel on AuraFindingSeverity {
  String get label => switch (this) {
    AuraFindingSeverity.info => 'informativa',
    AuraFindingSeverity.low => 'baja',
    AuraFindingSeverity.medium => 'media',
    AuraFindingSeverity.high => 'alta',
    AuraFindingSeverity.critical => 'crítica',
  };
}

enum AuraFindingConfidence { low, medium, high }

extension AuraFindingConfidenceLabel on AuraFindingConfidence {
  String get label => switch (this) {
    AuraFindingConfidence.low => 'baja',
    AuraFindingConfidence.medium => 'media',
    AuraFindingConfidence.high => 'alta',
  };
}

enum AuraFindingStatus {
  observed,
  confirmed,
  mitigated,
  falsePositive,
  unresolved,
}

extension AuraFindingStatusWireName on AuraFindingStatus {
  String get wireName => switch (this) {
    AuraFindingStatus.observed => 'observed',
    AuraFindingStatus.confirmed => 'confirmed',
    AuraFindingStatus.mitigated => 'mitigated',
    AuraFindingStatus.falsePositive => 'false_positive',
    AuraFindingStatus.unresolved => 'unresolved',
  };
}

enum AuraFindingCoverage { notScanned, complete, partial, incomplete }

extension AuraFindingCoverageLabel on AuraFindingCoverage {
  String get label => switch (this) {
    AuraFindingCoverage.notScanned => 'sin analizar',
    AuraFindingCoverage.complete => 'completa',
    AuraFindingCoverage.partial => 'parcial',
    AuraFindingCoverage.incomplete => 'incompleta',
  };

  bool get hasScanned => this != AuraFindingCoverage.notScanned;
}

enum AuraFindingCategory { devicePosture, installedApps, networkActivity }

extension AuraFindingCategoryLabel on AuraFindingCategory {
  String get label => switch (this) {
    AuraFindingCategory.devicePosture => 'postura del dispositivo',
    AuraFindingCategory.installedApps => 'aplicaciones instaladas',
    AuraFindingCategory.networkActivity => 'actividad de red',
  };
}

class AuraFinding {
  const AuraFinding({
    required this.id,
    required this.category,
    required this.severity,
    required this.confidence,
    required this.status,
    required this.observedAt,
    required this.title,
    required this.summary,
    required this.subject,
    required this.scope,
    required this.evidence,
    required this.limitations,
    required this.recommendedAction,
    this.requiresUserConsent = false,
    this.engine = auraFindingsEngine,
    this.engineVersion = auraFindingsEngineVersion,
  });

  final String id;
  final AuraFindingCategory category;
  final AuraFindingSeverity severity;
  final AuraFindingConfidence confidence;
  final AuraFindingStatus status;
  final int observedAt;
  final String title;
  final String summary;
  final String subject;
  final String scope;
  final List<String> evidence;
  final List<String> limitations;
  final String recommendedAction;
  final bool requiresUserConsent;
  final String engine;
  final String engineVersion;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'engine': engine,
    'engine_version': engineVersion,
    'category': category.name,
    'severity': severity.name,
    'confidence': confidence.name,
    'status': status.wireName,
    'observed_at': observedAt,
    'title': title,
    'summary': summary,
    'subject': subject,
    'scope': scope,
    'evidence': evidence,
    'limitations': limitations,
    'recommended_action': recommendedAction,
    'requires_user_consent': requiresUserConsent,
    'read_only': true,
  };
}

class AuraFindingsReport {
  const AuraFindingsReport({
    required this.findings,
    required this.deviceCoverage,
    required this.appCoverage,
    required this.networkAlertCount,
    required this.generatedAt,
  });

  const AuraFindingsReport.empty()
    : findings = const <AuraFinding>[],
      deviceCoverage = AuraFindingCoverage.notScanned,
      appCoverage = AuraFindingCoverage.notScanned,
      networkAlertCount = 0,
      generatedAt = 0;

  final List<AuraFinding> findings;
  final AuraFindingCoverage deviceCoverage;
  final AuraFindingCoverage appCoverage;
  final int networkAlertCount;
  final int generatedAt;

  bool get hasScanned =>
      deviceCoverage.hasScanned ||
      appCoverage.hasScanned ||
      networkAlertCount > 0;

  int get findingCount => findings.length;
}
