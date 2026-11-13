import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/explanation/aura_verdict_explanation.dart';
import 'package:aura_mobile_defens/security/aura_finding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuraStateProvider telemetry severity', () {
    test('does not downgrade a critical state', () {
      final provider = AuraStateProvider();
      provider.setSecurityLevel(AuraSecurityLevel.critical);

      provider.addTelemetryEvent(<String, dynamic>{
        'action': 'BLOCKED',
        'requested_domain': 'malicious.example',
      });

      expect(provider.securityLevel, AuraSecurityLevel.critical);
      provider.dispose();
    });

    test('promotes safe state to warning for a blocked event', () {
      final provider = AuraStateProvider();

      provider.addTelemetryEvent(<String, dynamic>{
        'action': 'DGA_ALERT',
        'requested_domain': 'suspicious.example',
      });

      expect(provider.securityLevel, AuraSecurityLevel.warning);
      provider.dispose();
    });

    test('keeps the latest 50 explanations and marks reports locally', () {
      final provider = AuraStateProvider();
      for (var index = 0; index < 51; index++) {
        provider.addExplanation(
          AuraVerdictExplanation(
            id: 'verdict-$index',
            host: 'domain$index.example',
            isThreat: true,
            source: 'ml',
            timestamp: index,
            modelVersion: '3.0.0',
            modelSha256:
                'd190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2',
            signals: const <AuraSignal>[],
          ),
        );
      }

      expect(provider.explanationHistory, hasLength(50));
      expect(provider.explanationHistory.first.id, 'verdict-1');
      provider.markExplanationAsFalsePositive('verdict-1');
      expect(provider.explanationHistory.first.reportedFalsePositive, isTrue);
      provider.dispose();
    });

    test('counts session event types and public resolvers', () {
      final provider = AuraStateProvider();
      provider.addTelemetryEvent(<String, dynamic>{
        'action': 'SNI_OBSERVED',
        'public_dns_resolver': true,
        'destination_address': '8.8.8.8',
      });
      provider.addTelemetryEvent(<String, dynamic>{'action': 'BLOCKED'});
      provider.addTelemetryEvent(<String, dynamic>{'action': 'DGA_ALERT'});
      provider.addTelemetryEvent(<String, dynamic>{
        'action': 'ENCRYPTED_DNS_BLOCKED',
      });

      expect(provider.sniObservedEvents, 1);
      expect(provider.blockedEvents, 1);
      expect(provider.dgaAlertEvents, 1);
      expect(provider.encryptedDnsBlocks, 1);
      expect(provider.observedPublicDnsResolvers, <String>['8.8.8.8']);
      provider.clearTelemetryHistory();
      expect(provider.sniObservedEvents, 0);
      expect(provider.observedPublicDnsResolvers, isEmpty);
      provider.dispose();
    });

    test('counts blocked QUIC events and clears the session counter', () {
      final provider = AuraStateProvider();
      provider.addTelemetryEvent(<String, dynamic>{
        'action': 'QUIC_BLOCKED',
        'destination_port': 443,
        'transport_protocol': 'UDP',
      });

      expect(provider.quicBlocked, 1);
      provider.clearTelemetryHistory();
      expect(provider.quicBlocked, 0);
      provider.dispose();
    });

    test('records audit and app scans as verifiable findings', () {
      final provider = AuraStateProvider();
      provider.recordDeviceAuditResult(<String, dynamic>{
        'ok': true,
        'tool': 'audit_device',
        'is_rooted': true,
        'is_emulator': false,
        'is_instrumented': false,
        'is_debugger_connected': false,
        'screen_overlay_detected': false,
        'root_confidence': 90,
        'root_indicators': <String>['su_binary:/system/bin/su'],
        'untrusted_accessibility_packages': <String>[],
        'check_errors': <String>[],
        'timestamp': 1000,
      });
      provider.recordAppScanResult(<String, dynamic>{
        'ok': true,
        'scan_type': 'installed_app_static_review',
        'timestamp': 2000,
        'applications': <dynamic>[],
        'special_access': <dynamic>[],
        'suspicious_apps': <dynamic>[
          <String, dynamic>{
            'package_name': 'com.example.app',
            'app_name': 'Example',
            'high_risk_permissions': <String>[
              'android.permission.SYSTEM_ALERT_WINDOW',
            ],
          },
        ],
        'signature_issues': <dynamic>[],
        'obfuscated_apps': <dynamic>[],
      });

      final report = provider.findingsReport;
      expect(report.deviceCoverage, AuraFindingCoverage.complete);
      expect(report.appCoverage, AuraFindingCoverage.complete);
      expect(
        report.findings.map((finding) => finding.id),
        containsAll(<String>['device-root-indicators', 'app-com.example.app']),
      );

      provider.clearTelemetryHistory();
      expect(provider.latestDeviceAudit, isNull);
      expect(provider.latestAppScan, isNull);
      expect(provider.findingsReport.findings, isEmpty);
      provider.dispose();
    });

    test(
      'retains the active model threshold and clears it with session data',
      () {
        final provider = AuraStateProvider();
        provider.setActiveDecisionThreshold(0.62);

        expect(provider.activeDecisionThreshold, 0.62);
        provider.clearTelemetryHistory();
        expect(provider.activeDecisionThreshold, isNull);
        provider.dispose();
      },
    );
  });
}
