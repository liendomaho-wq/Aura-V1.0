import '../services/aura_threat_correlator.dart';
import 'aura_finding.dart';

/// Acción que la interfaz puede ofrecer para un caso. Ninguna se ejecuta sin
/// confirmación explícita y todas pasan por el mismo agente y sus guardas.
enum AuraThreatCaseAction { none, reviewApp, emergencyIsolation }

/// Estado honesto del caso: una conexión bloqueada por DNS está contenida en
/// ese canal, no «eliminada» del dispositivo.
enum AuraThreatCaseState { dnsContained, needsReview, informational }

/// Caso de amenaza derivado de evidencia real.
///
/// No inventa señales ni agrega datos que el correlador o el motor de hallazgos
/// no hayan producido. Es una proyección de solo lectura: la acción se ejecuta
/// fuera del caso, con confirmación del usuario.
class AuraThreatCase {
  const AuraThreatCase({
    required this.id,
    required this.category,
    required this.severity,
    required this.state,
    required this.title,
    required this.summary,
    required this.evidence,
    required this.limitations,
    required this.recommendedAction,
    required this.action,
    required this.observedAt,
    this.domain,
    this.packageName,
    this.appName,
    this.signalCount = 1,
  });

  final String id;
  final AuraFindingCategory category;
  final AuraFindingSeverity severity;
  final AuraThreatCaseState state;
  final String title;
  final String summary;
  final List<String> evidence;
  final List<String> limitations;
  final String recommendedAction;
  final AuraThreatCaseAction action;
  final int observedAt;
  final String? domain;
  final String? packageName;
  final String? appName;
  final int signalCount;

  bool get isActionable =>
      action != AuraThreatCaseAction.none &&
      (action == AuraThreatCaseAction.emergencyIsolation ||
          (packageName != null && packageName!.isNotEmpty));

  String get actionLabel => switch (action) {
    AuraThreatCaseAction.none => 'Sin acción automática',
    AuraThreatCaseAction.reviewApp => 'Revisar app',
    AuraThreatCaseAction.emergencyIsolation => 'Cortar red',
  };

  String get stateLabel => switch (state) {
    AuraThreatCaseState.dnsContained => 'DNS bloqueado',
    AuraThreatCaseState.needsReview => 'requiere revisión',
    AuraThreatCaseState.informational => 'informativa',
  };

  String get subjectLabel => appName ?? packageName ?? domain ?? 'dispositivo';
}

/// Convierte alertas correlacionadas y hallazgos del motor local en una lista
/// acotada de casos ordenados por severidad y actualidad.
class AuraThreatCaseBuilder {
  AuraThreatCaseBuilder._();

  static const int maxCases = 40;
  static const int _maxEvidence = 8;

  static final RegExp _domainPattern = RegExp(
    r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+'
    r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  );
  static final RegExp _packagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  static List<AuraThreatCase> build({
    required List<AuraThreatAlert> alerts,
    required AuraFindingsReport report,
  }) {
    final cases = <String, AuraThreatCase>{};

    for (final alert in alerts) {
      final domain = _domain(alert.domain);
      final packageName = _package(alert.sourceAppPackage);
      final appName = _clean(alert.sourceAppName, 80);
      final app = appName ?? packageName;
      final severity = _alertSeverity(alert.severity);
      final title = domain != null
          ? app == null
                ? 'Conexiones bloqueadas a $domain'
                : '$app intentó conectarse a $domain'
          : 'Conexiones bloqueadas desde '
                '${app ?? 'una app no identificada'}';
      final evidence = <String>[
        '${alert.blockedConnectionCount} conexiones bloqueadas en la ventana '
            'de correlación.',
        if (domain != null) 'Dominio bloqueado: $domain',
        if (alert.domains.length > 1)
          'También se bloquearon: ${alert.domains.take(5).join(', ')}',
        if (appName != null) 'App de origen: $appName',
        if (packageName != null) 'Paquete: $packageName',
        ...alert.appScanIndicators.take(4).map(
          (indicator) => 'Contexto del escáner: $indicator',
        ),
      ];
      final action = packageName != null
          ? AuraThreatCaseAction.reviewApp
          : severity == AuraFindingSeverity.high
          ? AuraThreatCaseAction.emergencyIsolation
          : AuraThreatCaseAction.none;
      final id = 'network:${domain ?? packageName ?? 'unknown'}:'
          '${alert.firstSeenTimestamp}';
      cases[id] = AuraThreatCase(
        id: id,
        category: AuraFindingCategory.networkActivity,
        severity: severity,
        state: AuraThreatCaseState.dnsContained,
        title: title,
        summary: alert.summary,
        evidence: List<String>.unmodifiable(evidence.take(_maxEvidence)),
        limitations: const <String>[
          'El bloqueo DNS impide la resolución observada; no garantiza que la '
              'app no use QUIC, ECH, IP directa u otro canal.',
          'La atribución de la app depende de lo que Android expone al túnel.',
        ],
        recommendedAction: packageName != null
            ? 'Revisa la app de origen en Ajustes. Aura no desinstala ni '
                  'modifica aplicaciones por su cuenta.'
            : 'Si el bloqueo se repite, considera el aislamiento de emergencia '
                  'mientras revisas el dispositivo.',
        action: action,
        observedAt: alert.lastSeenTimestamp,
        domain: domain,
        packageName: packageName,
        appName: appName,
        signalCount: alert.blockedConnectionCount,
      );
    }

    for (final finding in report.findings) {
      // Los hallazgos de red ya están representados por las alertas del
      // correlador. Evita duplicar el mismo evento con dos identificadores.
      if (finding.category == AuraFindingCategory.networkActivity) continue;
      final packageName = _packageFromFinding(finding);
      final action = packageName != null && finding.category ==
              AuraFindingCategory.installedApps
          ? AuraThreatCaseAction.reviewApp
          : AuraThreatCaseAction.none;
      final state = action != AuraThreatCaseAction.none
          ? AuraThreatCaseState.needsReview
          : finding.severity.index >= AuraFindingSeverity.high.index
          ? AuraThreatCaseState.needsReview
          : AuraThreatCaseState.informational;
      final title = finding.category == AuraFindingCategory.installedApps
          ? 'Revisar ${finding.subject}'
          : finding.title;
      final id = 'finding:${finding.id}';
      cases[id] = AuraThreatCase(
        id: id,
        category: finding.category,
        severity: finding.severity,
        state: state,
        title: title,
        summary: finding.summary,
        evidence: List<String>.unmodifiable(
          finding.evidence.take(_maxEvidence),
        ),
        limitations: List<String>.unmodifiable(finding.limitations),
        recommendedAction: finding.recommendedAction,
        action: action,
        observedAt: finding.observedAt,
        packageName: packageName,
        signalCount: finding.evidence.length,
      );
    }

    final ordered = cases.values.toList(growable: false)
      ..sort((left, right) {
        final bySeverity = right.severity.index.compareTo(left.severity.index);
        if (bySeverity != 0) return bySeverity;
        final byTime = right.observedAt.compareTo(left.observedAt);
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
    return List<AuraThreatCase>.unmodifiable(ordered.take(maxCases));
  }

  static AuraFindingSeverity _alertSeverity(AuraThreatSeverity severity) =>
      switch (severity) {
        AuraThreatSeverity.low => AuraFindingSeverity.low,
        AuraThreatSeverity.medium => AuraFindingSeverity.medium,
        AuraThreatSeverity.high => AuraFindingSeverity.high,
      };

  static String? _domain(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || !_domainPattern.hasMatch(normalized)) return null;
    return normalized;
  }

  static String? _package(String? value) {
    final normalized = value?.trim();
    if (normalized == null || !_packagePattern.hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  static String? _packageFromFinding(AuraFinding finding) {
    if (!finding.id.startsWith('app-')) return null;
    return _package(finding.id.substring(4));
  }

  static String? _clean(String? value, int maxLength) {
    final collapsed = value
        ?.replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    if (collapsed == null || collapsed.isEmpty) return null;
    if (collapsed.length <= maxLength) return collapsed;
    return '${collapsed.substring(0, maxLength - 1)}…';
  }
}
