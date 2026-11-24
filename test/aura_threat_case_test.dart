import 'package:flutter_test/flutter_test.dart';

import 'package:aura_mobile_defens/security/aura_finding.dart';
import 'package:aura_mobile_defens/security/aura_threat_case.dart';
import 'package:aura_mobile_defens/services/aura_threat_correlator.dart';

AuraThreatAlert _alert({
  String? domain,
  String? packageName,
  String? appName,
  AuraThreatSeverity severity = AuraThreatSeverity.medium,
  int count = 3,
  int firstSeen = 1000,
  int lastSeen = 2000,
}) => AuraThreatAlert(
  severity: severity,
  blockedConnectionCount: count,
  domain: domain,
  domains: <String>[if (domain != null) domain else 'unknown.example'],
  firstSeenTimestamp: firstSeen,
  lastSeenTimestamp: lastSeen,
  sourceAppPackage: packageName,
  sourceAppName: appName,
);

AuraFinding _finding({
  required String id,
  AuraFindingCategory category = AuraFindingCategory.installedApps,
  AuraFindingSeverity severity = AuraFindingSeverity.medium,
  String subject = 'App de prueba',
  int observedAt = 3000,
}) => AuraFinding(
  id: id,
  category: category,
  severity: severity,
  confidence: AuraFindingConfidence.medium,
  status: AuraFindingStatus.observed,
  observedAt: observedAt,
  title: 'Hallazgo $id',
  summary: 'Resumen del hallazgo $id.',
  subject: subject,
  scope: 'Alcance acotado.',
  evidence: const <String>['Evidencia uno.', 'Evidencia dos.'],
  limitations: const <String>['Limitación verificable.'],
  recommendedAction: 'Revisar manualmente.',
);

AuraFindingsReport _report(List<AuraFinding> findings) => AuraFindingsReport(
  findings: findings,
  deviceCoverage: AuraFindingCoverage.complete,
  appCoverage: AuraFindingCoverage.complete,
  networkAlertCount: 0,
  generatedAt: 4000,
);

void main() {
  test('una conexión bloqueada se muestra como contenida en DNS, no como '
      'amenaza eliminada', () {
    final cases = AuraThreatCaseBuilder.build(
      alerts: <AuraThreatAlert>[
        _alert(
          domain: 'tracker.example',
          packageName: 'com.example.browser',
          appName: 'Navegador',
        ),
      ],
      report: _report(const <AuraFinding>[]),
    );

    expect(cases, hasLength(1));
    final threatCase = cases.single;
    expect(threatCase.state, AuraThreatCaseState.dnsContained);
    expect(threatCase.stateLabel, 'DNS bloqueado');
    expect(threatCase.action, AuraThreatCaseAction.reviewApp);
    expect(threatCase.packageName, 'com.example.browser');
    expect(threatCase.title, 'Navegador intentó conectarse a tracker.example');
    expect(threatCase.evidence, contains('Dominio bloqueado: tracker.example'));
    expect(threatCase.limitations.join(' '), contains('QUIC'));
  });

  test('una alerta alta sin paquete ofrece aislamiento de emergencia', () {
    final cases = AuraThreatCaseBuilder.build(
      alerts: <AuraThreatAlert>[
        _alert(domain: 'evil.example', severity: AuraThreatSeverity.high),
      ],
      report: _report(const <AuraFinding>[]),
    );

    expect(cases.single.action, AuraThreatCaseAction.emergencyIsolation);
    expect(cases.single.isActionable, isTrue);
  });

  test('no duplica el hallazgo de red que ya cubre la alerta', () {
    final cases = AuraThreatCaseBuilder.build(
      alerts: <AuraThreatAlert>[_alert(domain: 'evil.example')],
      report: _report(<AuraFinding>[
        _finding(
          id: 'network-evil.example-1000',
          category: AuraFindingCategory.networkActivity,
        ),
      ]),
    );

    expect(cases, hasLength(1));
    expect(cases.single.category, AuraFindingCategory.networkActivity);
  });

  test('una app señalada por el escáner se puede revisar en Ajustes', () {
    final cases = AuraThreatCaseBuilder.build(
      alerts: const <AuraThreatAlert>[],
      report: _report(<AuraFinding>[
        _finding(id: 'app-com.example.reader', subject: 'Lector'),
      ]),
    );

    expect(cases, hasLength(1));
    final threatCase = cases.single;
    expect(threatCase.title, 'Revisar Lector');
    expect(threatCase.packageName, 'com.example.reader');
    expect(threatCase.action, AuraThreatCaseAction.reviewApp);
    expect(threatCase.state, AuraThreatCaseState.needsReview);
  });

  test('una señal de postura no inventa una acción automática', () {
    final cases = AuraThreatCaseBuilder.build(
      alerts: const <AuraThreatAlert>[],
      report: _report(<AuraFinding>[
        _finding(
          id: 'device-root-indicators',
          category: AuraFindingCategory.devicePosture,
          severity: AuraFindingSeverity.high,
          subject: 'Dispositivo Android',
        ),
      ]),
    );

    expect(cases.single.action, AuraThreatCaseAction.none);
    expect(cases.single.state, AuraThreatCaseState.needsReview);
    expect(cases.single.isActionable, isFalse);
  });

  test('un identificador de paquete inválido no habilita acciones', () {
    final cases = AuraThreatCaseBuilder.build(
      alerts: <AuraThreatAlert>[
        _alert(
          domain: 'evil.example',
          packageName: 'no-es-un-paquete',
          severity: AuraThreatSeverity.high,
        ),
      ],
      report: _report(const <AuraFinding>[]),
    );

    expect(cases.single.packageName, isNull);
    expect(cases.single.action, AuraThreatCaseAction.emergencyIsolation);
  });

  test('ordena por severidad y luego por actualidad', () {
    final cases = AuraThreatCaseBuilder.build(
      alerts: <AuraThreatAlert>[
        _alert(
          domain: 'low.example',
          severity: AuraThreatSeverity.low,
          lastSeen: 5000,
        ),
        _alert(
          domain: 'high.example',
          severity: AuraThreatSeverity.high,
          lastSeen: 1000,
        ),
        _alert(
          domain: 'medium.example',
          severity: AuraThreatSeverity.medium,
          lastSeen: 4000,
        ),
      ],
      report: _report(const <AuraFinding>[]),
    );

    expect(cases.map((threatCase) => threatCase.domain), <String>[
      'high.example',
      'medium.example',
      'low.example',
    ]);
  });
}
