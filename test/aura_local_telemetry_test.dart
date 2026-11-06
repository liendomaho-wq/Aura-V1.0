import 'dart:convert';

import 'package:aura_mobile_defens/services/aura_local_telemetry.dart';
import 'package:aura_mobile_defens/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    AuraLocalTelemetry.configure(
      endpointConfigured: false,
      secureVault: AuraSecureVault(),
    );
  });

  test('la telemetría local está desactivada por defecto', () async {
    expect(await AuraLocalTelemetry.isEnabled(), isFalse);

    final stored = await AuraLocalTelemetry.recordNetworkEvent(<String, Object>{
      'timestamp': 1800000000000,
      'requested_domain': 'example.com',
      'action': 'BLOCKED',
    });
    expect(stored, isFalse);
    expect(await AuraLocalTelemetry.loadEvents(), isEmpty);
  });

  test(
    'registra escaneos y dominios bloqueados solo tras habilitarla',
    () async {
      await AuraLocalTelemetry.setEnabled(true);
      final stored =
          await AuraLocalTelemetry.recordNetworkEvent(<String, Object>{
            'timestamp': 1800000000000,
            'requested_domain': 'malicioso.example',
            'action': 'BLOCKED',
            'destination_address': '203.0.113.5',
          });
      await AuraLocalTelemetry.recordNetworkEvent(<String, Object>{
        'timestamp': 1800000000001,
        'requested_domain': 'example.com',
        'action': 'ALLOWED',
      });

      final events = await AuraLocalTelemetry.loadEvents();
      expect(stored, isTrue);
      expect(events, hasLength(2));
      expect(events.first['type'], 'dominio_bloqueado');
      expect(events.first['requested_domain'], isNull);
      expect(events.first['domain_hash'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(events.first.values, isNot(contains('malicioso.example')));
      expect(events.first['timestamp'], 1800000000000);
      expect(events.first.containsKey('destination_address'), isFalse);
      expect(events.last['type'], 'escaneo');
    },
  );

  test(
    'no registra localmente cuando el endpoint remoto está configurado',
    () async {
      await AuraLocalTelemetry.setEnabled(true);
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

  test(
    'revocar consentimiento borra la cola y bloquea eventos posteriores',
    () async {
      await AuraLocalTelemetry.setEnabled(true);
      await AuraLocalTelemetry.recordNetworkEvent(<String, Object>{
        'timestamp': 1800000000000,
        'requested_domain': 'private.example',
        'action': 'BLOCKED',
      });

      await AuraLocalTelemetry.setEnabled(false);
      final storedAfterRevocation =
          await AuraLocalTelemetry.recordNetworkEvent(<String, Object>{
            'timestamp': 1800000000001,
            'requested_domain': 'later.example',
            'action': 'BLOCKED',
          });

      expect(await AuraLocalTelemetry.isEnabled(), isFalse);
      expect(await AuraLocalTelemetry.loadEvents(), isEmpty);
      expect(storedAfterRevocation, isFalse);
    },
  );

  test('migra eventos locales antiguos quitando dominios en claro', () async {
    await AuraLocalTelemetry.setEnabled(true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('aura_local_telemetry_events', <String>[
      jsonEncode(<String, Object>{
        'timestamp': 1800000000000,
        'requested_domain': 'legacy-private.example',
        'action': 'BLOCKED',
      }),
    ]);

    final events = await AuraLocalTelemetry.loadEvents();
    final storedJson = preferences
        .getStringList('aura_local_telemetry_events')!
        .single;

    expect(events.single['requested_domain'], isNull);
    expect(events.single['domain_hash'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(storedJson, isNot(contains('legacy-private.example')));
  });
}
