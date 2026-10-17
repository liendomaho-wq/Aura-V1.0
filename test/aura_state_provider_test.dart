import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/explanation/aura_verdict_explanation.dart';
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
      expect(
        provider.explanationHistory.first.reportedFalsePositive,
        isTrue,
      );
      provider.dispose();
    });

    test('counts session event types and public resolvers', () {
      final provider = AuraStateProvider();
      provider.addTelemetryEvent(<String, dynamic>{
        'action': 'SNI_OBSERVED',
        'public_dns_resolver': true,
        'destination_address': '8.8.8.8',
      });
      provider.addTelemetryEvent(<String, dynamic>{
        'action': 'BLOCKED',
      });
      provider.addTelemetryEvent(<String, dynamic>{
        'action': 'DGA_ALERT',
      });
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
  });
}
