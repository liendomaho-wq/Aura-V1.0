import 'package:aura_mobile_defens/security/aura_finding.dart';
import 'package:aura_mobile_defens/security/aura_findings_engine.dart';
import 'package:aura_mobile_defens/services/aura_threat_correlator.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> deviceAudit({
  bool rooted = false,
  bool emulator = false,
  bool instrumented = false,
  bool debugger = false,
  bool overlay = false,
  List<String> accessibility = const <String>[],
  List<String> errors = const <String>[],
}) {
  return <String, dynamic>{
    'ok': true,
    'tool': 'audit_device',
    'audit_status': errors.isEmpty ? 'no_indicators_observed' : 'incomplete',
    'is_emulator': emulator,
    'emulator_confidence': emulator ? 80 : 0,
    'emulator_indicators': emulator
        ? <String>['emulator_fingerprint', 'emulator_model']
        : <String>[],
    'is_rooted': rooted,
    'root_confidence': rooted ? 90 : 0,
    'root_indicators': rooted
        ? <String>['su_binary:/system/bin/su', 'su_command_available']
        : <String>[],
    'is_instrumented': instrumented,
    'instrumentation_indicators': instrumented
        ? <String>['library:frida-gadget', 'frida_port:27042']
        : <String>[],
    'is_debugger_connected': debugger,
    'screen_overlay_detected': overlay,
    'screen_overlay_indicators': overlay
        ? <String>['overlay_permission_granted:com.example.overlay']
        : <String>[],
    'is_hostile': rooted || emulator || instrumented || debugger || overlay,
    'indicators': <String>[
      if (emulator) 'emulator_fingerprint',
      if (rooted) 'su_binary:/system/bin/su',
      if (instrumented) 'library:frida-gadget',
      if (overlay) 'overlay_permission_granted:com.example.overlay',
    ],
    'check_errors': errors,
    'untrusted_accessibility_packages': accessibility,
    'timestamp': 1000,
  };
}

Map<String, dynamic> appScan() {
  return <String, dynamic>{
    'ok': true,
    'scan_type': 'installed_app_static_review',
    'timestamp': 2000,
    'count': 1,
    'applications': <dynamic>[
      <String, dynamic>{
        'package_name': 'com.example.one',
        'app_name': 'One',
        'active_services': <dynamic>[
          <String, dynamic>{'type': 'ACCESSIBILITY'},
        ],
      },
    ],
    'special_access_count': 1,
    'active_special_access_count': 1,
    'special_access': <dynamic>[
      <String, dynamic>{
        'package_name': 'com.example.one',
        'app_name': 'One',
        'access': 'OVERLAY',
        'state': 'ACTIVE',
        'mode': 0,
      },
    ],
    'app_provenance_count': 0,
    'app_provenance': <dynamic>[],
    'suspicious_app_count': 1,
    'suspicious_apps': <dynamic>[
      <String, dynamic>{
        'package_name': 'com.example.one',
        'app_name': 'One',
        'target_sdk': 34,
        'high_risk_permissions': <String>[
          'android.permission.SYSTEM_ALERT_WINDOW',
        ],
        'medium_risk_permissions': <String>[],
      },
    ],
    'signature_issue_count': 1,
    'signature_issues': <dynamic>[
      <String, dynamic>{
        'package_name': 'com.example.one',
        'app_name': 'One',
        'problems': <String>['SIGNATURE_METADATA_UNAVAILABLE'],
        'signature_count': 0,
      },
    ],
    'obfuscated_app_count': 1,
    'obfuscated_apps': <dynamic>[
      <String, dynamic>{
        'package_name': 'com.example.one',
        'app_name': 'One',
        'dex_entropy': 7.8,
        'obfuscated_identifier_ratio': 0.6,
        'analyzed_dex_files': 3,
        'reasons': <String>['HIGH_DEX_ENTROPY'],
      },
    ],
  };
}

AuraThreatAlert networkAlert() => AuraThreatAlert(
  severity: AuraThreatSeverity.medium,
  blockedConnectionCount: 3,
  domain: 'bad.example',
  domains: <String>['bad.example'],
  sourceAppPackage: 'com.example.one',
  sourceAppName: 'One',
  firstSeenTimestamp: 3000,
  lastSeenTimestamp: 4000,
);

void main() {
  group('AuraFindingsEngine', () {
    test('no inventa hallazgos ni cobertura sin fuentes', () {
      final report = AuraFindingsEngine(clock: () => 9000).evaluate();

      expect(report.findings, isEmpty);
      expect(report.deviceCoverage, AuraFindingCoverage.notScanned);
      expect(report.appCoverage, AuraFindingCoverage.notScanned);
      expect(report.networkAlertCount, 0);
      expect(report.hasScanned, isFalse);
      expect(report.generatedAt, 9000);
    });

    test(
      'una auditoría completa sin señales no se convierte en certificado',
      () {
        final report = AuraFindingsEngine(
          clock: () => 9000,
        ).evaluate(deviceAudit: deviceAudit());

        expect(report.deviceCoverage, AuraFindingCoverage.complete);
        expect(report.findings, isEmpty);
        expect(report.hasScanned, isTrue);
      },
    );

    test('expone evidencia y límites de las señales de postura', () {
      final report = AuraFindingsEngine(clock: () => 9000).evaluate(
        deviceAudit: deviceAudit(
          rooted: true,
          emulator: true,
          instrumented: true,
          debugger: true,
          overlay: true,
          accessibility: <String>['com.example.accessibility'],
          errors: <String>['overlay_app_ops_unavailable'],
        ),
      );

      expect(report.deviceCoverage, AuraFindingCoverage.partial);
      expect(
        report.findings.map((finding) => finding.id),
        containsAll(<String>[
          'device-root-indicators',
          'device-emulator',
          'device-instrumentation',
          'device-debugger',
          'device-screen-overlay',
          'device-accessibility-services',
          'device-audit-partial',
        ]),
      );
      final root = report.findings.firstWhere(
        (finding) => finding.id == 'device-root-indicators',
      );
      expect(root.severity, AuraFindingSeverity.high);
      expect(root.confidence, AuraFindingConfidence.high);
      expect(root.status, AuraFindingStatus.observed);
      expect(
        root.evidence,
        contains('Indicadores: su_binary:/system/bin/su, su_command_available'),
      );
      expect(
        root.limitations,
        contains(
          'Root o Shizuku puede ocultarse a las comprobaciones de una app normal.',
        ),
      );
      expect(root.recommendedAction, contains('Aura no puede desrootear'));
      expect(root.toMap()['read_only'], isTrue);
      expect(root.toMap()['engine'], auraFindingsEngine);
      expect(root.toMap()['engine_version'], auraFindingsEngineVersion);
    });

    test('marca una auditoría inválida como no verificable', () {
      final report = AuraFindingsEngine(clock: () => 9000).evaluate(
        deviceAudit: <String, dynamic>{
          'ok': false,
          'error': 'invalid_device_audit_report',
        },
      );

      expect(report.deviceCoverage, AuraFindingCoverage.incomplete);
      final finding = report.findings.single;
      expect(finding.id, 'device-audit-incomplete');
      expect(finding.status, AuraFindingStatus.unresolved);
      expect(finding.evidence, <String>[
        'Código de error: invalid_device_audit_report',
      ]);
      expect(finding.summary, contains('No se interpretará'));
      expect(finding.summary, isNot(contains('certifica')));
    });

    test('agrupa las señales de una app sin acusarla de malware', () {
      final report = AuraFindingsEngine(
        clock: () => 9000,
      ).evaluate(appScan: appScan());

      expect(report.appCoverage, AuraFindingCoverage.complete);
      final app = report.findings.firstWhere(
        (finding) => finding.id == 'app-com.example.one',
      );
      expect(app.category, AuraFindingCategory.installedApps);
      expect(app.severity, AuraFindingSeverity.medium);
      expect(app.confidence, AuraFindingConfidence.high);
      expect(app.summary, contains('no prueban que la app sea malware'));
      expect(
        app.evidence,
        contains(
          'Permisos de alto riesgo concedidos: android.permission.SYSTEM_ALERT_WINDOW',
        ),
      );
      expect(
        app.evidence,
        contains('Acceso especial activo: OVERLAY (modo 0)'),
      );
      expect(
        app.limitations,
        contains('AppOps MODE_ALLOWED confirma el acceso, no el uso indebido.'),
      );
      expect(
        report.findings.where((finding) => finding.id == app.id),
        hasLength(1),
      );
      final activeServices = report.findings.firstWhere(
        (finding) => finding.id == 'apps-active-sensitive-services',
      );
      expect(activeServices.severity, AuraFindingSeverity.info);
      expect(
        activeServices.evidence.single,
        'One (com.example.one): ACCESSIBILITY',
      );
    });

    test('un escaneo de apps inválido no se interpreta como limpio', () {
      final report = AuraFindingsEngine(clock: () => 9000).evaluate(
        appScan: <String, dynamic>{'ok': false, 'error': 'invalid_scan_report'},
      );

      expect(report.appCoverage, AuraFindingCoverage.incomplete);
      final finding = report.findings.single;
      expect(finding.id, 'app-scan-incomplete');
      expect(finding.status, AuraFindingStatus.unresolved);
      expect(finding.summary, contains('cero riesgos'));
    });

    test('un escaneo ok sin superficies completas se marca incompleto', () {
      final report = AuraFindingsEngine(clock: () => 9000).evaluate(
        appScan: <String, dynamic>{
          'ok': true,
          'applications': <dynamic>[],
          'special_access': <dynamic>[],
          'suspicious_apps': <dynamic>[],
        },
      );

      expect(report.appCoverage, AuraFindingCoverage.incomplete);
      final finding = report.findings.single;
      expect(finding.id, 'app-scan-incomplete');
      expect(finding.evidence, <String>[
        'Código de error: invalid_scan_report',
      ]);
    });

    test('convierte alertas de red en hallazgos trazables', () {
      final report = AuraFindingsEngine(
        clock: () => 9000,
      ).evaluate(threatAlerts: <AuraThreatAlert>[networkAlert()]);

      expect(report.networkAlertCount, 1);
      expect(report.hasScanned, isTrue);
      final finding = report.findings.single;
      expect(finding.category, AuraFindingCategory.networkActivity);
      expect(finding.severity, AuraFindingSeverity.medium);
      expect(finding.observedAt, 4000);
      expect(finding.evidence, contains('Dominio: bad.example'));
      expect(finding.evidence, contains('Paquete: com.example.one'));
      expect(finding.limitations, contains(contains('no demuestra')));
    });

    test('ordena por severidad, confianza y fecha de forma estable', () {
      final report = AuraFindingsEngine(clock: () => 9000).evaluate(
        deviceAudit: deviceAudit(rooted: true),
        threatAlerts: <AuraThreatAlert>[
          AuraThreatAlert(
            severity: AuraThreatSeverity.high,
            blockedConnectionCount: 20,
            domain: 'critical.example',
            domains: <String>['critical.example'],
            firstSeenTimestamp: 5000,
            lastSeenTimestamp: 6000,
          ),
        ],
      );

      expect(report.findings.first.id, 'device-root-indicators');
      expect(
        report.findings.last.category,
        AuraFindingCategory.networkActivity,
      );
      expect(
        report.findings.map((finding) => finding.severity).toList(),
        <AuraFindingSeverity>[
          AuraFindingSeverity.high,
          AuraFindingSeverity.high,
        ],
      );
    });
  });
}
