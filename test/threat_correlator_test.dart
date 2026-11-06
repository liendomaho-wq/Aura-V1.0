import 'package:aura_mobile_defens/services/aura_threat_correlator.dart';
import 'package:aura_mobile_defens/agent/agent_controller.dart';
import 'package:aura_mobile_defens/agent/agent_event.dart';
import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const packageName = 'com.example.suspicious';
  const baseTimestamp = 1794000000000;

  Map<String, dynamic> blockedEvent({
    required int timestamp,
    required String domain,
    String sourceApp = packageName,
    String action = 'BLOCKED',
  }) => <String, dynamic>{
    'timestamp': timestamp,
    'source_app': sourceApp,
    'requested_domain': domain,
    'action': action,
  };

  Map<String, dynamic> appScanResult() => <String, dynamic>{
    'ok': true,
    'scan_type': 'installed_app_static_review',
    'timestamp': baseTimestamp,
    'applications': <Map<String, dynamic>>[
      <String, dynamic>{
        'package_name': packageName,
        'app_name': 'Aplicacion de prueba',
      },
    ],
    'signature_issues': <Map<String, dynamic>>[
      <String, dynamic>{
        'package_name': packageName,
        'app_name': 'Aplicacion de prueba',
      },
    ],
  };

  group('AuraThreatCorrelator', () {
    test('consolida intentos bloqueados repetidos y usa datos del escaner', () {
      final correlator = AuraThreatCorrelator();
      expect(correlator.recordAppScanResult(appScanResult()), isTrue);
      for (var index = 0; index < 3; index++) {
        expect(
          correlator.recordNetworkEvent(
            blockedEvent(
              timestamp: baseTimestamp + index * 120000,
              domain: 'Blocked.Example',
            ),
          ),
          isTrue,
        );
      }

      final alerts = correlator.alerts;
      expect(alerts, hasLength(1));
      expect(alerts.single.domain, 'blocked.example');
      expect(alerts.single.blockedConnectionCount, 3);
      expect(alerts.single.severity, AuraThreatSeverity.low);
      expect(alerts.single.sourceAppPackage, packageName);
      expect(alerts.single.sourceAppName, 'Aplicacion de prueba');
      expect(
        alerts.single.appScanIndicators,
        contains('incidencia de firma reportada por el escáner'),
      );
      expect(
        alerts.single.summary,
        'Se bloquearon 3 conexiones al dominio blocked.example desde la app Aplicacion de prueba.',
      );
      expect(correlator.buildReport(), contains(alerts.single.summary));
    });

    test('no alerta por debajo del umbral ni por SNI permitido', () {
      final correlator = AuraThreatCorrelator();
      correlator.recordNetworkEvent(
        blockedEvent(timestamp: baseTimestamp, domain: 'blocked.example'),
      );
      correlator.recordNetworkEvent(
        blockedEvent(
          timestamp: baseTimestamp + 1000,
          domain: 'blocked.example',
          action: 'SNI_OBSERVED',
        ),
      );

      expect(correlator.alerts, isEmpty);
      expect(correlator.buildReport(), contains('sin alcanzar los umbrales'));
    });

    test('correlaciona varios dominios solo con atribucion de app unica', () {
      final correlator = AuraThreatCorrelator();
      correlator.recordAppScanResult(appScanResult());
      correlator.recordNetworkEvent(
        blockedEvent(timestamp: baseTimestamp, domain: 'one.example'),
      );
      correlator.recordNetworkEvent(
        blockedEvent(timestamp: baseTimestamp + 30000, domain: 'two.example'),
      );
      correlator.recordNetworkEvent(
        blockedEvent(
          timestamp: baseTimestamp + 40000,
          domain: 'three.example',
          sourceApp: '$packageName,com.example.shared',
        ),
      );

      final appAlert = correlator.alerts.single;
      expect(appAlert.domain, isNull);
      expect(appAlert.domains, <String>['one.example', 'two.example']);
      expect(appAlert.sourceAppPackage, packageName);
      expect(appAlert.sourceAppName, 'Aplicacion de prueba');
      expect(appAlert.severity, AuraThreatSeverity.low);
      expect(appAlert.summary, contains('a 2 dominios bloqueados'));
    });

    test('eleva severidad con frecuencia alta y acota la ventana temporal', () {
      var now = baseTimestamp;
      final correlator = AuraThreatCorrelator(clock: () => now);
      for (var index = 0; index < 3; index++) {
        correlator.recordNetworkEvent(
          blockedEvent(
            timestamp: baseTimestamp + index * 10000,
            domain: 'burst.example',
          ),
        );
      }
      expect(correlator.alerts.single.severity, AuraThreatSeverity.medium);
      now = baseTimestamp +
          AuraThreatCorrelator.correlationWindow.inMilliseconds +
          21000;
      expect(correlator.alerts, isEmpty);
      expect(correlator.retainedBlockedEventCount, 0);
    });

    test('no atribuye eventos de UID compartida o desconocida a una app', () {
      final correlator = AuraThreatCorrelator();
      for (var index = 0; index < 3; index++) {
        correlator.recordNetworkEvent(
          blockedEvent(
            timestamp: baseTimestamp + index * 120000,
            domain: 'blocked.example',
            sourceApp: 'uid-unavailable',
          ),
        );
      }

      expect(correlator.alerts.single.sourceAppPackage, isNull);
      expect(correlator.alerts.single.summary, isNot(contains('desde la app')));
    });

    test(
      'el agente consulta alertas reales en analizar amenazas y estado',
      () async {
        final state = AuraStateProvider();
        addTearDown(state.dispose);
        for (var index = 0; index < 3; index++) {
          state.addTelemetryEvent(
            blockedEvent(
              timestamp: baseTimestamp + index * 120000,
              domain: 'blocked.example',
            ),
          );
        }

        final controller = AgentController.instance;
        controller.bindSecurityState(state);
        final historyLength = controller.history.length;
        await controller.run('analizar amenazas');
        final analysis = controller.history
            .skip(historyLength)
            .where((event) => event.data?['intent'] == 'analyze_threats')
            .single;

        expect(analysis.message, contains('Se bloquearon 3 conexiones'));
        expect(analysis.data?['correlated_alert_count'], 1);
        expect(analysis.kind, AgentEventKind.warning);

        final statusHistoryLength = controller.history.length;
        await controller.run('estado');
        final status = controller.history
            .skip(statusHistoryLength)
            .where((event) => event.data?['intent'] == 'status')
            .single;
        expect(status.message, contains('blocked.example'));
      },
    );
  });
}
