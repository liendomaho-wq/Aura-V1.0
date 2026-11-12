import 'package:aura_mobile_defens/infrastructure/storage/aura_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ciberdefensa.aura/storage');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('freeBytes returns the Android-reported capacity', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'freeBytes');
          return 4096;
        });

    expect(await AuraStorage().freeBytes(), 4096);
  });

  test('freeBytes fails closed when the platform is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'unavailable');
        });

    expect(await AuraStorage().freeBytes(), isNull);
  });

  test('freeBytes rejects negative capacity', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => -1);

    expect(await AuraStorage().freeBytes(), isNull);
  });
}
