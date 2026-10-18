import 'package:aura_mobile_defens/services/aura_local_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuraLocalTelemetry.configure(endpointConfigured: false);
  });

  test(
    'registra escaneos y dominios bloqueados con marcas de tiempo',
    () async {
      final stored = await AuraLocalTelemetry.recordNetworkEvent(
        <String, Object>{
          'timestamp': 1_800_000_000_000,
          'requested_domain': 'malicioso.example',
          'action': 'BLOCKED',
          'destination_address': '203.0.113.5',
        },
      );
      await AuraLocalTelemetry.recordNetworkEvent(
        <String, Object>{
          'timestamp': 1_800_000_000_001,
          'requested_domain': 'example.com',
          'action': 'ALLOWED',
        },
      );

      final events = await AuraLocalTelemetry.loadEvents();
      expect(stored, isTrue);
      expect(events, hasLength(2));
      expect(events.first['type'], 'dominio_bloqueado');
      expect(events.first['requested_domain'], 'malicioso.example');
      expect(events.first['timestamp'], 1_800_000_000_000);
      expect(events.first.containsKey('destination_address'), isFalse);
      expect(events.last['type'], 'escaneo');
    },
  );

  test(
    'no registra localmente cuando el endpoint remoto está configurado',
    () async {
      AuraLocalTelemetry.configure(endpointConfigured: true);

      final stored = await AuraLocalTelemetry.recordDomainOutcome(
        domain: 'example.com',
        outcome: 'allowed',
        source: 'ml',
      );

      expect(stored, isFalse);
      expect(await AuraLocalTelemetry.loadEvents(), isEmpty);
    },
  );
}
