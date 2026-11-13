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

  test('memoryInfo returns the Android memory snapshot', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'memoryInfo');
          return <String, Object>{
            'total_bytes': 8 * 1024 * 1024 * 1024,
            'available_bytes': 3 * 1024 * 1024 * 1024,
            'threshold_bytes': 256 * 1024 * 1024,
            'low_memory': false,
          };
        });

    final info = await AuraStorage().memoryInfo();

    expect(info?.totalBytes, 8 * 1024 * 1024 * 1024);
    expect(info?.availableBytes, 3 * 1024 * 1024 * 1024);
    expect(info?.thresholdBytes, 256 * 1024 * 1024);
    expect(info?.lowMemory, isFalse);
  });

  test('memoryInfo fails closed on malformed or unavailable data', () async {
    for (final response in <Object?>[
      null,
      <String, Object>{'total_bytes': -1},
      <String, Object>{
        'total_bytes': 1024,
        'available_bytes': 2048,
        'threshold_bytes': 128,
        'low_memory': false,
      },
      <String, Object>{
        'total_bytes': 2048,
        'available_bytes': 1024,
        'threshold_bytes': 128,
        'low_memory': 'no',
      },
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => response);

      expect(await AuraStorage().memoryInfo(), isNull, reason: '$response');
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'memory_unavailable');
        });

    expect(await AuraStorage().memoryInfo(), isNull);
  });
}
