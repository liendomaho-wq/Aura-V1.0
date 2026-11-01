import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile_defens/services/aura_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ciberdefensa.aura/telemetry');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('does not report a safe device when Android returns an empty inventory',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => <dynamic>[]);

    final result = await AuraCore().ejecutarAnalisisProactivoDispositivo();

    expect(result, contains('AUDITORÍA INCOMPLETA'));
    expect(result, isNot(contains('DISPOSITIVO SEGURO')));
  });

  test('does not report a safe device when the native inventory is null',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final result = await AuraCore().ejecutarAnalisisProactivoDispositivo();

    expect(result, contains('AUDITORÍA INCOMPLETA'));
    expect(result, isNot(contains('DISPOSITIVO SEGURO')));
  });

  test('does not expose native exception details in the audit result',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(
        code: 'NATIVE_FAILURE',
        message: 'private-device-path-marker',
      ),
    );

    final result = await AuraCore().ejecutarAnalisisProactivoDispositivo();

    expect(result, contains('AUDITORÍA INCOMPLETA'));
    expect(result, isNot(contains('private-device-path-marker')));
  });

  test('does not claim a clean audit when inventory contains warnings only',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => <dynamic>[
        <String, dynamic>{'inventory_warning': 'Inventario limitado por Android'},
      ],
    );

    final result = await AuraCore().ejecutarAnalisisProactivoDispositivo();

    expect(result, contains('AUDITORÍA INCOMPLETA'));
    expect(result, contains('Inventario limitado por Android'));
    expect(result, isNot(contains('DISPOSITIVO SEGURO')));
  });
}
