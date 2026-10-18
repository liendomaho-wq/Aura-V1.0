import 'dart:io';

import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/screens/aura_core_screen.dart';
import 'package:aura_mobile_defens/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const biometricChannel = MethodChannel('com.aura.cyberdefense/biometrics');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const networkEventChannel =
      EventChannel('com.aura.cyberdefense/network_stream');

  Future<List<String>> pumpSplash(
    WidgetTester tester, {
    required bool hasStrongBiometric,
    required bool deviceSecure,
  }) async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final state = AuraStateProvider();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    messenger.setMockMethodCallHandler(biometricChannel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getLocalAuthStatus':
          return <String, bool>{
            'hasStrongBiometric': hasStrongBiometric,
            'deviceSecure': deviceSecure,
          };
        case 'authenticateFingerprint':
        case 'authenticateDeviceCredential':
          return true;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(
      pathProviderChannel,
      (_) async => Directory.systemTemp.path,
    );
    messenger.setMockStreamHandler(
      networkEventChannel,
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      messenger.setMockMethodCallHandler(biometricChannel, null);
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      messenger.setMockStreamHandler(networkEventChannel, null);
      state.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AuraStateProvider>.value(
        value: state,
        child: const MaterialApp(home: SplashScreen()),
      ),
    );
    return calls;
  }

  Future<void> pumpBootToCore(WidgetTester tester) async {
    for (var frame = 0;
        frame < 20 && find.byType(AuraCoreScreen).evaluate().isEmpty;
        frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('strong biometric authentication advances past the splash', (
    tester,
  ) async {
    final calls = await pumpSplash(
      tester,
      hasStrongBiometric: true,
      deviceSecure: true,
    );

    await pumpBootToCore(tester);

    expect(calls, contains('authenticateFingerprint'));
    expect(find.byType(AuraCoreScreen), findsOneWidget);
    expect(find.text('CONFIGURAR BLOQUEO DEL TELÉFONO'), findsNothing);
  });

  testWidgets('device credential is used when strong biometrics are absent', (
    tester,
  ) async {
    final calls = await pumpSplash(
      tester,
      hasStrongBiometric: false,
      deviceSecure: true,
    );

    await pumpBootToCore(tester);

    expect(calls, contains('authenticateDeviceCredential'));
    expect(
      find.text('ACCESO LOCAL VALIDADO; INICIALIZANDO BÓVEDA SEGURA...'),
      findsOneWidget,
    );
    expect(find.text('CONFIGURAR BLOQUEO DEL TELÉFONO'), findsNothing);
  });

  testWidgets('an unsecured device shows choices and keeps the splash mounted',
      (
    tester,
  ) async {
    final calls = await pumpSplash(
      tester,
      hasStrongBiometric: false,
      deviceSecure: false,
    );

    await tester.pump();
    expect(find.text('CONFIGURAR BLOQUEO DEL TELÉFONO'), findsOneWidget);
    expect(find.text('REINTENTAR'), findsOneWidget);
    expect(
      find.text('CONTINUAR SIN BLOQUEO LOCAL (INSEGURO)'),
      findsOneWidget,
    );
    expect(
      find.text('ALTO RIESGO: CONFIGURA UN PIN PARA PROTEGER AURA.'),
      findsOneWidget,
    );
    expect(find.byType(Scaffold), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));

    expect(calls, <String>['getLocalAuthStatus']);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AuraCoreScreen), findsNothing);
  });
}
