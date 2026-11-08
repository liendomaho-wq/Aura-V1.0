import 'dart:async';
import 'dart:typed_data';

import 'package:aura_mobile_defens/secure_vault.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('AuraSecureVault memory hygiene', () {
    test('wipes the model key buffer after a successful operation', () async {
      final vault = AuraSecureVault();
      late Uint8List observedBuffer;

      await vault.withModelMasterKey((keyBytes) {
        observedBuffer = keyBytes;
        expect(keyBytes, hasLength(43));
      });

      expect(observedBuffer, everyElement(0));
    });

    test('wipes the model key buffer when the operation throws', () async {
      final vault = AuraSecureVault();
      late Uint8List observedBuffer;

      await expectLater(
        vault.withModelMasterKey((keyBytes) {
          observedBuffer = keyBytes;
          throw StateError('operation failed');
        }),
        throwsStateError,
      );

      expect(observedBuffer, everyElement(0));
    });

    test('wipes the domain HMAC key buffer after use', () async {
      final vault = AuraSecureVault();
      late Uint8List observedBuffer;

      await vault.withDomainTelemetryKey((keyBytes) {
        observedBuffer = keyBytes;
        expect(keyBytes, hasLength(32));
        return keyBytes.length;
      });

      expect(observedBuffer, everyElement(0));
    });

    test('serializes key access across separate vault instances', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final events = <String>[];
      late Uint8List firstBuffer;
      late Uint8List secondBuffer;
      final first = AuraSecureVault().withModelMasterKey((keyBytes) async {
        firstBuffer = keyBytes;
        events.add('first');
        entered.complete();
        await release.future;
        events.add('first finished');
      });
      await entered.future;
      final second = AuraSecureVault().withModelMasterKey((keyBytes) {
        secondBuffer = keyBytes;
        events.add('second');
      });
      await Future<void>.delayed(Duration.zero);
      final beforeRelease = List<String>.of(events);
      release.complete();
      await Future.wait([first, second]);

      expect(beforeRelease, <String>['first']);
      expect(events, <String>['first', 'first finished', 'second']);
      expect(firstBuffer, everyElement(0));
      expect(secondBuffer, everyElement(0));
    });

    test('propagates an error without poisoning the next caller', () async {
      final failed = AuraSecureVault().withModelMasterKey<void>((_) {
        throw StateError('expected operation failure');
      });
      final recovered = AuraSecureVault().withModelMasterKey(
        (keyBytes) => keyBytes.length,
      );

      await expectLater(failed, throwsStateError);
      expect(await recovered, 43);
    });

    // Each widget test owns a different scheduler zone. These use the existing
    // storage unit fixture above, not a replacement Keystore/migration result.
    for (final boot in const [1, 2]) {
      testWidgets('initializes the vault in boot scheduler $boot', (
        tester,
      ) async {
        var initialized = false;
        final pending = AuraSecureVault().initializeModelMasterKey().then((_) {
          initialized = true;
        });

        await tester.pump();

        expect(initialized, isTrue);
        await pending;
      });
    }

    test('configures crash-safe legacy migration without reset-on-error', () {
      final options = AuraSecureVault.androidMigrationOptions.toMap();

      expect(options['resetOnError'], 'false');
      expect(options['migrateOnAlgorithmChange'], 'true');
      expect(options['migrateWithBackup'], 'true');
      expect(options['encryptedSharedPreferences'], 'false');
    });
  });
}
