import '../services/aura_threat_correlator.dart';
import 'aura_finding.dart';

/// Acción que la interfaz puede ofrecer para un caso. Ninguna se ejecuta sin
/// confirmación explícita y todas pasan por el mismo agente y sus guardas.
enum AuraThreatCaseAction { none, reviewApp, emergencyIsolation }

/// Estado honesto del caso: una conexión bloqueada por DNS está contenida en
/// ese canal, no «eliminada» del dispositivo.
enum AuraThreatCaseState { dnsContained, needsReview, informational }

/// Estado de gestión del caso. No cambia la evidencia ni la severidad.
///
/// `mitigated` solo se usa cuando una contención real ya está confirmada
/// (por ejemplo, el bloqueo DNS sigue activo o el agente confirmó el
/// aislamiento). No significa que la amenaza haya sido eliminada.
enum AuraThreatDisposition { open, inReview, mitigated, dismissed }

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
    int? firstSeenAt,
    this.domain,
    this.packageName,
    this.appName,
    this.signalCount = 1,
    this.disposition = AuraThreatDisposition.open,
    int? updatedAt,
    int? statusChangedAt,
    this.statusDetail,
  }) : firstSeenAt = firstSeenAt ?? observedAt,
       updatedAt = updatedAt ?? observedAt,
       statusChangedAt = statusChangedAt ?? updatedAt ?? observedAt;

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
  final int firstSeenAt;
  final int updatedAt;
  final String? domain;
  final String? packageName;
  final String? appName;
  final int signalCount;
  final AuraThreatDisposition disposition;
  final int statusChangedAt;
  final String? statusDetail;

  bool get isDismissed => disposition == AuraThreatDisposition.dismissed;

  bool get isInReview => disposition == AuraThreatDisposition.inReview;

  bool get isMitigated => disposition == AuraThreatDisposition.mitigated;

  /// Solo se ofrece cuando la contención ya es real: el bloqueo DNS está
  /// activo y el usuario confirma que revisó el origen. No se ofrece para
  /// casos que solo requieren revisión.
  bool get canConfirmMitigation =>
      state == AuraThreatCaseState.dnsContained &&
      disposition != AuraThreatDisposition.dismissed &&
      !isMitigated;

  String get dispositionLabel => switch (disposition) {
    AuraThreatDisposition.open => 'abierta',
    AuraThreatDisposition.inReview => 'en revisión',
    AuraThreatDisposition.mitigated => 'mitigada',
    AuraThreatDisposition.dismissed => 'descartada',
  };

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

  /// Plan de respuesta derivado de la evidencia. Son pasos para el usuario;
  /// ninguna acción se ejecuta sin su confirmación y ninguna promete eliminar
  /// una amenaza que Android no permita eliminar.
  List<AuraThreatPlaybookStep> get playbook => _playbookFor(this);

  AuraThreatCase copyWith({
    AuraThreatDisposition? disposition,
    int? observedAt,
    int? firstSeenAt,
    int? updatedAt,
    int? signalCount,
    int? statusChangedAt,
    String? statusDetail,
  }) => AuraThreatCase(
    id: id,
    category: category,
    severity: severity,
    state: state,
    title: title,
    summary: summary,
    evidence: evidence,
    limitations: limitations,
    recommendedAction: recommendedAction,
    action: action,
    observedAt: observedAt ?? this.observedAt,
    firstSeenAt: firstSeenAt ?? this.firstSeenAt,
    domain: domain,
    packageName: packageName,
    appName: appName,
    signalCount: signalCount ?? this.signalCount,
    disposition: disposition ?? this.disposition,
    updatedAt: updatedAt ?? this.updatedAt,
    statusChangedAt: statusChangedAt ?? this.statusChangedAt,
    statusDetail: statusDetail ?? this.statusDetail,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'schema': 2,
    'id': id,
    'category': category.name,
    'severity': severity.name,
    'state': state.name,
    'title': title,
    'summary': summary,
    'evidence': evidence,
    'limitations': limitations,
    'recommended_action': recommendedAction,
    'action': action.name,
    'observed_at': observedAt,
    'first_seen_at': firstSeenAt,
    'updated_at': updatedAt,
    'signal_count': signalCount,
    'disposition': disposition.name,
    'status_changed_at': statusChangedAt,
    if (statusDetail != null) 'status_detail': statusDetail!,
    if (domain != null) 'domain': domain!,
    if (packageName != null) 'package_name': packageName!,
    if (appName != null) 'app_name': appName!,
  };

  /// Reconstruye un caso almacenado y rechaza cualquier registro que no cumpla
  /// el esquema. El almacén es privado, pero no se confía en su contenido.
  static AuraThreatCase? fromMap(Map<String, dynamic> map) {
    final schema = map['schema'];
    if (schema != 1 && schema != 2) return null;
    final id = _boundedString(map['id'], 120);
    final title = _boundedString(map['title'], 300);
    final summary = _boundedString(map['summary'], 2000);
    final recommendedAction = _boundedString(map['recommended_action'], 1000);
    final observedAt = _positiveInt(map['observed_at']);
    final firstSeenAt = _positiveInt(map['first_seen_at']);
    final updatedAt = _positiveInt(map['updated_at']);
    final signalCount = _positiveInt(map['signal_count']);
    final category = _enumByName(AuraFindingCategory.values, map['category']);
    final severity = _enumByName(AuraFindingSeverity.values, map['severity']);
    final state = _enumByName(AuraThreatCaseState.values, map['state']);
    final action = _enumByName(AuraThreatCaseAction.values, map['action']);
    final disposition = _enumByName(
      AuraThreatDisposition.values,
      map['disposition'],
    );
    final statusChangedAt = schema == 2
        ? _positiveInt(map['status_changed_at'])
        : updatedAt;
    final statusDetail = schema == 2 && map['status_detail'] != null
        ? _boundedString(map['status_detail'], 300)
        : null;
    if (id == null ||
        title == null ||
        summary == null ||
        recommendedAction == null ||
        observedAt == null ||
        firstSeenAt == null ||
        updatedAt == null ||
        signalCount == null ||
        category == null ||
        severity == null ||
        state == null ||
        action == null ||
        disposition == null ||
        statusChangedAt == null) {
      return null;
    }
    if (schema == 2 && map['status_detail'] != null && statusDetail == null) {
      return null;
    }
    final evidence = _boundedStrings(map['evidence'], 8, 500);
    final limitations = _boundedStrings(map['limitations'], 12, 500);
    if (evidence == null || limitations == null) return null;
    final domain = _optionalDomain(map['domain']);
    final packageName = _optionalPackage(map['package_name']);
    final appName = _boundedString(map['app_name'], 80);
    if (map['domain'] != null && domain == null) return null;
    if (map['package_name'] != null && packageName == null) return null;
    if (map['app_name'] != null && appName == null) return null;
    return AuraThreatCase(
      id: id,
      category: category,
      severity: severity,
      state: state,
      title: title,
      summary: summary,
      evidence: List<String>.unmodifiable(evidence),
      limitations: List<String>.unmodifiable(limitations),
      recommendedAction: recommendedAction,
      action: action,
      observedAt: observedAt,
      firstSeenAt: firstSeenAt,
      domain: domain,
      packageName: packageName,
      appName: appName,
      signalCount: signalCount,
      disposition: disposition,
      updatedAt: updatedAt,
      statusChangedAt: statusChangedAt,
      statusDetail: statusDetail,
    );
  }

  static String? _boundedString(Object? value, int maxLength) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }

  static int? _positiveInt(Object? value) {
    if (value is! int || value <= 0) return null;
    return value;
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static List<String>? _boundedStrings(
    Object? value,
    int maxItems,
    int maxLength,
  ) {
    if (value is! List || value.length > maxItems) return null;
    final output = <String>[];
    for (final entry in value) {
      final text = _boundedString(entry, maxLength);
      if (text == null) return null;
      output.add(text);
    }
    return output;
  }

  static final RegExp _storedDomainPattern = RegExp(
    r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+'
    r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  );
  static final RegExp _storedPackagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  static String? _optionalDomain(Object? value) {
    if (value == null) return null;
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    return _storedDomainPattern.hasMatch(normalized) ? normalized : null;
  }

  static String? _optionalPackage(Object? value) {
    if (value == null) return null;
    if (value is! String) return null;
    final normalized = value.trim();
    return _storedPackagePattern.hasMatch(normalized) ? normalized : null;
  }
}

/// Paso de un plan de respuesta. `action` indica qué acción existente puede
/// acompañar el paso; no se ejecuta desde el playbook.
class AuraThreatPlaybookStep {
  const AuraThreatPlaybookStep({
    required this.title,
    required this.detail,
    this.action = AuraThreatCaseAction.none,
  });

  final String title;
  final String detail;
  final AuraThreatCaseAction action;
}

List<AuraThreatPlaybookStep> _playbookFor(AuraThreatCase threatCase) {
  final steps = <AuraThreatPlaybookStep>[];
  switch (threatCase.category) {
    case AuraFindingCategory.networkActivity:
      steps.add(
        AuraThreatPlaybookStep(
          title: 'Contención observada',
          detail: threatCase.state == AuraThreatCaseState.dnsContained
              ? 'Aura bloqueó ${threatCase.domain ?? 'el dominio'} en DNS '
                    'para el tráfico que pasa por su túnel. QUIC, ECH o una IP '
                    'directa pueden evitar ese bloqueo.'
              : 'La conexión apareció en la evidencia, pero no hay una '
                    'contención universal confirmada.',
        ),
      );
      steps.add(
        AuraThreatPlaybookStep(
          title: 'Identifica el origen',
          detail:
              'Origen observado: ${threatCase.subjectLabel}. Comprueba si esa '
              'aplicación debería estar conectándose a ese destino.',
        ),
      );
      if (threatCase.action == AuraThreatCaseAction.reviewApp) {
        steps.add(
          const AuraThreatPlaybookStep(
            title: 'Revisa la ficha de la app',
            detail:
                'Abre Ajustes y revisa permisos, accesos y uso de red. Aura no '
                'modifica la aplicación por su cuenta.',
            action: AuraThreatCaseAction.reviewApp,
          ),
        );
      }
      if (threatCase.action == AuraThreatCaseAction.emergencyIsolation) {
        steps.add(
          const AuraThreatPlaybookStep(
            title: 'Corta la red si el bloqueo se repite',
            detail:
                'El aislamiento detiene el forwarding del túnel y deja la VPN '
                'en modo de descarte. Interrumpe las conexiones actuales.',
            action: AuraThreatCaseAction.emergencyIsolation,
          ),
        );
      }
      steps.add(
        const AuraThreatPlaybookStep(
          title: 'Decide si la app sigue siendo confiable',
          detail:
              'Si no reconoces la aplicación, desinstálala desde Ajustes. '
              'Android exige que esa decisión la tome el usuario.',
        ),
      );
      break;
    case AuraFindingCategory.installedApps:
      steps.add(
        AuraThreatPlaybookStep(
          title: 'Abre la ficha de ${threatCase.subjectLabel}',
          detail:
              'Ajustes muestra permisos, accesos especiales y almacenamiento. '
              'Aura no puede aislar ni desinstalar otra app sin privilegios '
              'especiales.',
          action: threatCase.action,
        ),
      );
      steps.add(
        const AuraThreatPlaybookStep(
          title: 'Revisa permisos y accesos',
          detail:
              'Comprueba permisos sensibles, accesibilidad, superposición y '
              'servicios en segundo plano. Revoca solo lo que no necesites.',
        ),
      );
      steps.add(
        const AuraThreatPlaybookStep(
          title: 'Desinstala solo si no la reconoces',
          detail:
              'La desinstalación se hace desde Ajustes. Aura no la ejecuta en '
              'silencio ni conserva una copia de tus datos.',
        ),
      );
      break;
    case AuraFindingCategory.devicePosture:
      steps.add(
        AuraThreatPlaybookStep(
          title: 'Revisa el hallazgo en el dispositivo',
          detail: threatCase.recommendedAction,
        ),
      );
      steps.add(
        const AuraThreatPlaybookStep(
          title: 'Aplica el cambio en Ajustes',
          detail:
              'Aura solo puede leer las señales que Android expone. Los cambios '
              'de postura, depuración o permisos los aplica el usuario.',
        ),
      );
      steps.add(
        const AuraThreatPlaybookStep(
          title: 'Vuelve a auditar para confirmar',
          detail:
              'Una nueva auditoría compara el estado real; no se marca como '
              'mitigado por haber abierto esta pantalla.',
        ),
      );
      break;
  }
  return List<AuraThreatPlaybookStep>.unmodifiable(steps);
}

/// Convierte alertas correlacionadas y hallazgos del motor local en una lista
/// acotada de casos ordenados por severidad y actualidad.
class AuraThreatCaseBuilder {
  AuraThreatCaseBuilder._();

  static const int maxCases = 40;
  static const int maxStoredCases = 200;
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
        ...alert.appScanIndicators
            .take(4)
            .map((indicator) => 'Contexto del escáner: $indicator'),
      ];
      final action = packageName != null
          ? AuraThreatCaseAction.reviewApp
          : severity == AuraFindingSeverity.high
          ? AuraThreatCaseAction.emergencyIsolation
          : AuraThreatCaseAction.none;
      final id = 'network:${domain ?? ''}:${packageName ?? ''}';
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
        firstSeenAt: alert.firstSeenTimestamp,
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
      final action =
          packageName != null &&
              finding.category == AuraFindingCategory.installedApps
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
        firstSeenAt: finding.observedAt,
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

  /// Combina los casos vivos con los persistidos. Conserva la decisión del
  /// usuario y la primera observación; descarta lo que excedió la retención.
  static List<AuraThreatCase> merge({
    required List<AuraThreatCase> live,
    required List<AuraThreatCase> stored,
    required int now,
    Duration retention = const Duration(days: 30),
    int limit = maxCases,
  }) {
    final cutoff = now - retention.inMilliseconds;
    final merged = <String, AuraThreatCase>{};
    for (final storedCase in stored) {
      if (storedCase.updatedAt >= cutoff) {
        merged[storedCase.id] = storedCase;
      }
    }
    for (final liveCase in live) {
      final previous = merged[liveCase.id];
      var disposition = previous?.disposition ?? liveCase.disposition;
      var statusDetail = previous?.statusDetail;
      var statusChangedAt =
          previous?.statusChangedAt ?? liveCase.statusChangedAt;
      // Una mitigación no oculta actividad nueva: si el caso vuelve a
      // observarse después de la mitigación, vuelve a revisión con evidencia.
      if (previous != null &&
          previous.disposition == AuraThreatDisposition.mitigated &&
          liveCase.observedAt > previous.statusChangedAt) {
        disposition = AuraThreatDisposition.inReview;
        statusDetail = 'Nueva actividad observada después de la mitigación.';
        statusChangedAt = now;
      }
      merged[liveCase.id] = liveCase.copyWith(
        firstSeenAt: previous == null
            ? liveCase.firstSeenAt
            : (previous.firstSeenAt < liveCase.firstSeenAt
                  ? previous.firstSeenAt
                  : liveCase.firstSeenAt),
        disposition: disposition,
        statusDetail: statusDetail,
        statusChangedAt: statusChangedAt,
        updatedAt: now,
      );
    }
    final ordered = merged.values.toList(growable: false)
      ..sort((left, right) {
        if (left.isDismissed != right.isDismissed) {
          return left.isDismissed ? 1 : -1;
        }
        final bySeverity = right.severity.index.compareTo(left.severity.index);
        if (bySeverity != 0) return bySeverity;
        final byTime = right.updatedAt.compareTo(left.updatedAt);
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
    return List<AuraThreatCase>.unmodifiable(ordered.take(limit));
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
