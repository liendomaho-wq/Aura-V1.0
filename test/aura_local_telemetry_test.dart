import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aura_mobile_defens/services/aura_local_telemetry.dart';
import 'package:aura_mobile_defens/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PausedTelemetryVault extends AuraSecureVault {
  final started = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<T> withDomainTelemetryKey<T>(
    FutureOr<T> Function(Uint8List keyBytes) action,
  ) async {
    started.complete();
    await resume.future;
    final keyBytes = Uint8List.fromList(List<int>.filled(32, 7));
    try {
      return await action(keyBytes);
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }
}

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

  test('la migración elimina ambos campos de dominio heredados', () async {
    await AuraLocalTelemetry.setEnabled(true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('aura_local_telemetry_events', <String>[
      jsonEncode(<String, Object>{
        'timestamp': 1800000000000,
        'requested_domain': 'private-one.example',
        'domain': 'private-two.example',
        'action': 'BLOCKED',
      }),
    ]);

    final event = (await AuraLocalTelemetry.loadEvents()).single;
    final stored = preferences
        .getStringList('aura_local_telemetry_events')!
        .single;
    expect(event.containsKey('requested_domain'), isFalse);
    expect(event.containsKey('domain'), isFalse);
    expect(event['domain_hash'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(stored, isNot(contains('private-one.example')));
    expect(stored, isNot(contains('private-two.example')));
  });

  for (final recordType in <String>['red', 'resultado de dominio']) {
    for (final resetType in <String>['revocación', 'borrado']) {
      test(
        'un evento de $recordType anterior a $resetType no reaparece',
        () async {
          final vault = _PausedTelemetryVault();
          addTearDown(() {
            if (!vault.resume.isCompleted) vault.resume.complete();
          });
          AuraLocalTelemetry.configure(
            endpointConfigured: false,
            secureVault: vault,
          );
          await AuraLocalTelemetry.setEnabled(true);

          final pending = recordType == 'red'
              ? AuraLocalTelemetry.recordNetworkEvent(<String, Object>{
                  'requested_domain': 'private.example',
                  'action': 'BLOCKED',
                })
              : AuraLocalTelemetry.recordDomainOutcome(
                  domain: 'private.example',
                  securityScore: 50,
                  prediction: 'suspicious',
                  action: 'BLOCKED',
                );
          await vault.started.future;
          if (resetType == 'revocación') {
            await AuraLocalTelemetry.setEnabled(false);
            await AuraLocalTelemetry.setEnabled(true);
          } else {
            await AuraLocalTelemetry.clearEvents();
          }
          vault.resume.complete();
          expect(await pending, isFalse);
          expect(await AuraLocalTelemetry.loadEvents(), isEmpty);
        },
      );
    }
  }

  test(
    'la revocación espera la migración y no restaura la cola borrada',
    () async {
      final vault = _PausedTelemetryVault();
      addTearDown(() {
        if (!vault.resume.isCompleted) vault.resume.complete();
      });
      AuraLocalTelemetry.configure(
        endpointConfigured: false,
        secureVault: vault,
      );
      await AuraLocalTelemetry.setEnabled(true);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList('aura_local_telemetry_events', <String>[
        jsonEncode(<String, Object>{
          'requested_domain': 'legacy-private.example',
          'timestamp': 1800000000000,
        }),
      ]);

      final migration = AuraLocalTelemetry.loadEvents();
      await vault.started.future;
      var revoked = false;
      final revocation = AuraLocalTelemetry.setEnabled(false).then((result) {
        revoked = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(revoked, isFalse);
      vault.resume.complete();
      await migration;
      expect(await revocation, isFalse);
      expect(await AuraLocalTelemetry.isEnabled(), isFalse);
      expect(preferences.getStringList('aura_local_telemetry_events'), isNull);
    },
  );
}
