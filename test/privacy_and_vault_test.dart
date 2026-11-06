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

    test('configures crash-safe legacy migration without reset-on-error', () {
      final options = AuraSecureVault.androidMigrationOptions.toMap();

      expect(options['resetOnError'], 'false');
      expect(options['migrateOnAlgorithmChange'], 'true');
      expect(options['migrateWithBackup'], 'true');
      expect(options['encryptedSharedPreferences'], 'false');
    });
  });
}
