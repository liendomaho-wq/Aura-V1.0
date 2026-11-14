import 'dart:convert';

import 'package:aura_mobile_defens/secure_vault.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const keystore = MethodChannel('com.ciberdefensa.aura/vault_keystore');

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keystore, null);
  });

  test('a truncated audit log is an error, not an empty history', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'aura_audit_logs_v1': '{"event":',
    });
    await expectLater(AuraSecureVault().getAuditLogs(), throwsFormatException);
  });

  test('a non-list audit payload is an error, not an empty history', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'aura_audit_logs_v1': '"texto"',
    });
    await expectLater(AuraSecureVault().getAuditLogs(), throwsFormatException);
  });

  test('a truncated model key is kept and is not treated as missing', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'aura_model_master_key_v1': 'abc',
    });
    await expectLater(
      AuraSecureVault().withModelMasterKey((_) {}),
      throwsStateError,
    );
    expect(
      await FlutterSecureStorage().read(key: 'aura_model_master_key_v1'),
      'abc',
    );
  });

  test('rotation replaces the model key with a different value', () async {
    final vault = AuraSecureVault();
    String? first;
    await vault.withModelMasterKey((bytes) {
      first = base64UrlEncode(bytes).replaceAll('=', '');
    });
    await vault.rotateModelMasterKey();
    String? second;
    await vault.withModelMasterKey((bytes) {
      second = base64UrlEncode(bytes).replaceAll('=', '');
    });
    expect(second, isNotNull);
    expect(second, isNot(first));
  });

  test('an illegible model key is not rotated away', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'aura_model_master_key_v1': 'abc',
    });
    await expectLater(
      AuraSecureVault().rotateModelMasterKey(),
      throwsStateError,
    );
    expect(
      await FlutterSecureStorage().read(key: 'aura_model_master_key_v1'),
      'abc',
    );
  });

  test(
    'purge deletes stored values and asks to delete the Keystore key',
    () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'aura_model_master_key_v1': 'abc',
      });
      var deletedKeystoreKey = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keystore, (call) async {
            expect(call.method, 'deleteVaultKeystoreKeys');
            deletedKeystoreKey = true;
            return true;
          });
      await AuraSecureVault().purgeSensitiveData();
      expect(deletedKeystoreKey, isTrue);
      expect(await FlutterSecureStorage().readAll(), isEmpty);
    },
  );

  test('purge fails when the Keystore alias is still present', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keystore, (call) async => false);
    await expectLater(AuraSecureVault().purgeSensitiveData(), throwsStateError);
  });
}
