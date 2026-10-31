import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/services/aura_local_telemetry.dart';
import 'package:aura_mobile_defens/screens/aura_core_screen.dart';
import 'package:aura_mobile_defens/widgets/aura_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpAuraFrames(WidgetTester tester) async {
  // Aura's avatar intentionally loops forever; settle() can never complete.
  // Advance a bounded number of frames while allowing async startup work to run.
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('activates and stops VPN through the native shield channel', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const shieldChannel = MethodChannel('com.ciberdefensa.aura/shield');
    const telemetryChannel = MethodChannel('com.ciberdefensa.aura/telemetry');
    const biometricChannel = MethodChannel('com.aura.cyberdefense/biometrics');
    const networkEventChannel =
        EventChannel('com.aura.cyberdefense/network_stream');
    final calls = <String>[];
    final state = AuraStateProvider();
    MockStreamHandlerEventSink? networkEventSink;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(shieldChannel, null);
      messenger.setMockMethodCallHandler(telemetryChannel, null);
      messenger.setMockMethodCallHandler(biometricChannel, null);
      messenger.setMockStreamHandler(networkEventChannel, null);
      state.dispose();
    });
    messenger.setMockMethodCallHandler(biometricChannel, (_) async => true);
    messenger.setMockMethodCallHandler(shieldChannel, (call) async {
      calls.add(call.method);
      return true;
    });
    messenger.setMockMethodCallHandler(telemetryChannel, (call) async {
      if (call.method == 'domainTelemetryStatus') {
        return <String, Object>{
          'optedIn': false,
          'endpointConfigured': false,
        };
      }
      return true;
    });
    messenger.setMockStreamHandler(
      networkEventChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          networkEventSink = events;
        },
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuraStateProvider>.value(
        value: state,
        child: const MaterialApp(home: AuraCoreScreen()),
      ),
    );
    await _pumpAuraFrames(tester);

    expect(networkEventSink, isNotNull);
    networkEventSink!.success(<String, Object>{
      'timestamp': 1,
      'source_app': 'com.example.app',
      'requested_domain': 'example.com',
      'action': 'ALLOWED',
    });
    await tester.pump();
    await _pumpAuraFrames(tester);
    expect(state.telemetryEvents.single['requested_domain'], 'example.com');
    expect(find.text('TELEMETRÍA LOCAL'), findsOneWidget);
    expect(find.text('REGISTRO LOCAL PAUSADO'), findsOneWidget);
    // Network events remain available to the live session, but opt-out means
    // they must not be persisted in local telemetry storage.
    expect(await AuraLocalTelemetry.loadEvents(), isEmpty);

    expect(find.text('DEFENSA: OFF'), findsOneWidget);
    expect(find.text('Hola, soy Aura.'), findsOneWidget);
    expect(find.byType(AuraAvatar), findsOneWidget);
    expect(find.textContaining('VPN local opcional'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('vpn-toggle')));
    await _pumpAuraFrames(tester);
    expect(calls, <String>['startShield']);
    expect(state.isVpnActive, isTrue);
    // The status is rendered as one complete label, not a standalone 'ON'.
    expect(find.text('DEFENSA: ON'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('vpn-toggle')));
    await _pumpAuraFrames(tester);
    expect(calls, <String>['startShield', 'stopShield']);
    expect(state.isVpnActive, isFalse);

    await tester.tap(find.byKey(const ValueKey<String>('vpn-toggle')));
    await _pumpAuraFrames(tester);
    expect(state.isVpnActive, isTrue);
    networkEventSink!.success(<String, Object>{
      'timestamp': 2,
      'source_app': 'android',
      'requested_domain':
          '[CRIT] TÚNEL REVOCADO POR ANDROID O POR EL OPERADOR — '
          'LAS DEFENSAS ESTÁN INACTIVAS. Remedio: reactive la defensa.',
      'action': 'VPN_REVOKED',
    });
    await tester.pump();
    await _pumpAuraFrames(tester);
    expect(state.isVpnActive, isFalse);
    expect(find.text('DEFENSA: OFF'), findsOneWidget);
    expect(
      find.textContaining(
        '[CRIT] TÚNEL REVOCADO POR ANDROID O POR EL OPERADOR',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Aura avatar exposes its idle state to accessibility', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AuraAvatar(size: 96)),
        ),
      );
      expect(find.bySemanticsLabel('Aura está disponible'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Aura está disponible'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Aura avatar announces its analysis state', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AuraAvatar(size: 96, isThinking: true)),
        ),
      );
      expect(find.bySemanticsLabel('Aura está analizando'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Aura avatar respects reduced-motion accessibility settings', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: AuraAvatar(size: 96)),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.bySemanticsLabel('Aura está disponible'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
