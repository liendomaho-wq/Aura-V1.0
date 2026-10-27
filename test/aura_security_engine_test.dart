import 'package:aura_mobile_defens/security_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const appIntegrity = MethodChannel('com.ciberdefensa.aura/telemetry');
  const antiTampering = MethodChannel('com.ciberdefensa.aura/anti_tampering');
  const hostileEnvironment = MethodChannel('com.ciberdefensa.aura/security');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(appIntegrity, null);
    messenger.setMockMethodCallHandler(antiTampering, null);
    messenger.setMockMethodCallHandler(hostileEnvironment, null);
  });

  Future<Map<String, dynamic>> checkWith({
    required Map<String, Object?> antiTamperingReport,
  }) async {
    messenger.setMockMethodCallHandler(
      appIntegrity,
      (_) async => <String, Object>{'isVirtualEnvironment': false},
    );
    messenger.setMockMethodCallHandler(
      antiTampering,
      (_) async => antiTamperingReport,
    );
    messenger.setMockMethodCallHandler(
      hostileEnvironment,
      (_) async => <String, Object>{
        'isHostile': false,
        'environmentCheckFailed': false,
        'isEmulator': false,
        'isDebuggerConnected': false,
        'indicators': <String>[],
      },
    );

    return AuraSecurityEngine().checkDeviceIntegrity();
  }

  test('invalid signature is critical even if native report says secure',
      () async {
    final report = await checkWith(
      antiTamperingReport: <String, Object?>{
        'isSecure': true,
        'signatureValid': false,
        'localDebugFallback': false,
        'fridaDetected': false,
        'debuggerBlocked': false,
        'adbBlocked': false,
        'isDebuggerConnected': false,
      },
    );

    expect(report['level'], SystemThreatLevel.critical);
    expect(report['signatureCheckFailed'], isTrue);
  });

  test('missing signature verdict fails closed', () async {
    final report = await checkWith(
      antiTamperingReport: <String, Object?>{
        'isSecure': true,
        'localDebugFallback': false,
        'fridaDetected': false,
        'debuggerBlocked': false,
        'adbBlocked': false,
        'isDebuggerConnected': false,
      },
    );

    expect(report['level'], SystemThreatLevel.critical);
    expect(report['signatureValid'], isFalse);
    expect(report['signatureCheckFailed'], isTrue);
  });

  test('valid release signature does not trigger signature failure', () async {
    final report = await checkWith(
      antiTamperingReport: <String, Object?>{
        'isSecure': true,
        'signatureValid': true,
        'localDebugFallback': false,
        'fridaDetected': false,
        'debuggerBlocked': false,
        'adbBlocked': false,
        'isDebuggerConnected': false,
      },
    );

    expect(report['level'], SystemThreatLevel.secure);
    expect(report['signatureCheckFailed'], isFalse);
  });
}
