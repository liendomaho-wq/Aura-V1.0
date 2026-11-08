import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/services/aura_local_telemetry.dart';
import 'package:aura_mobile_defens/screens/aura_core_screen.dart';
import 'package:aura_mobile_defens/widgets/aura_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

Future<void> _pumpUntilVpnEnabled(WidgetTester tester) async {
  final vpnToggle = find.byKey(const ValueKey<String>('vpn-toggle'));
  for (var frame = 0; frame < 40; frame++) {
    if (tester.widget<TextButton>(vpnToggle).onPressed != null) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(tester.widget<TextButton>(vpnToggle).onPressed, isNotNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('activates and stops VPN through the native shield channel', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    const shieldChannel = MethodChannel('com.ciberdefensa.aura/shield');
    const telemetryChannel = MethodChannel('com.ciberdefensa.aura/telemetry');
    const securityChannel = MethodChannel('com.ciberdefensa.aura/security');
    const biometricChannel = MethodChannel('com.aura.cyberdefense/biometrics');
    const networkEventChannel = EventChannel(
      'com.aura.cyberdefense/network_stream',
    );
    final calls = <String>[];
    var vpnActive = false;
    var vpnServiceActive = false;
    var statusVerified = true;
    final state = AuraStateProvider();
    MockStreamHandlerEventSink? networkEventSink;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(shieldChannel, null);
      messenger.setMockMethodCallHandler(telemetryChannel, null);
      messenger.setMockMethodCallHandler(securityChannel, null);
      messenger.setMockMethodCallHandler(biometricChannel, null);
      messenger.setMockStreamHandler(networkEventChannel, null);
      state.dispose();
    });
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      if (call.method == 'checkHostileEnvironment') {
        return <String, Object>{
          'untrustedAccessibilityServicePackages': <String>[],
        };
      }
      return true;
    });
    messenger.setMockMethodCallHandler(biometricChannel, (_) async => true);
    messenger.setMockMethodCallHandler(shieldChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'startShield') {
        vpnServiceActive = true;
        vpnActive = true;
        return true;
      }
      if (call.method == 'stopShield') {
        vpnServiceActive = false;
        vpnActive = false;
        return true;
      }
      if (call.method == 'getShieldStatus') {
        return <String, dynamic>{
          'service_active': vpnServiceActive,
          'vpn_interface_active': vpnServiceActive,
          'forwarding_active': vpnActive,
          'isolation_active': false,
          'status_verified': statusVerified,
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(telemetryChannel, (call) async {
      if (call.method == 'domainTelemetryStatus') {
        return <String, Object>{'optedIn': false, 'endpointConfigured': false};
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

    // The console jumps to the newest event. The local telemetry panel is the
    // first child of a lazy ListView, so bring it back into the viewport
    // instead of assuming that an off-screen widget remains mounted.
    final eventList = find.byKey(const ValueKey<String>('aura-event-list'));
    final telemetryPanel = find.byKey(
      const ValueKey<String>('local-telemetry-panel'),
    );
    expect(eventList, findsOneWidget);
    await tester.dragUntilVisible(
      telemetryPanel,
      eventList,
      const Offset(0, 240),
    );
    await tester.ensureVisible(telemetryPanel);
    await tester.pump();
    expect(telemetryPanel, findsOneWidget);
    expect(find.text('TELEMETRÍA LOCAL'), findsOneWidget);
    expect(find.text('REGISTRO LOCAL PAUSADO'), findsOneWidget);
    // Network events remain available to the live session, but opt-out means
    // they must not be persisted in local telemetry storage.
    expect(await AuraLocalTelemetry.loadEvents(), isEmpty);

    // Inspecting the console scrolls the overview off stage. A real downward
    // gesture must restore it; do not bypass the visible-widget assertions.
    await tester.dragUntilVisible(
      find.text('Hola, soy Aura.'),
      eventList,
      const Offset(0, 240),
    );
    await tester.pump();

    expect(find.text('DEFENSA: OFF'), findsOneWidget);
    expect(find.text('Hola, soy Aura.'), findsOneWidget);
    expect(find.byType(AuraAvatar), findsOneWidget);
    expect(find.textContaining('VPN local opcional'), findsOneWidget);
    await _pumpUntilVpnEnabled(tester);

    state.setSecurityLevel(AuraSecurityLevel.warning);
    await tester.pump();
    expect(
      tester.widget<AuraAvatar>(find.byType(AuraAvatar)).effectiveMode,
      AuraAvatarMode.warning,
    );
    state.setSecurityLevel(AuraSecurityLevel.safe);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('vpn-toggle')));
    await _pumpAuraFrames(tester);
    expect(calls.where((call) => call != 'getShieldStatus'), <String>[
      'startShield',
    ]);
    expect(state.isVpnActive, isTrue);
    // The status is rendered as one complete label, not a standalone 'ON'.
    expect(find.text('DEFENSA: ON'), findsOneWidget);

    // Reopening the app must not retain a stale active state after native failure.
    vpnActive = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpAuraFrames(tester);
    expect(state.isVpnActive, isFalse);
    expect(find.text('DEFENSA: SIN FLUJO'), findsOneWidget);

    // An unverifiable native status is not presented as an active or stopped VPN.
    statusVerified = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpAuraFrames(tester);
    expect(find.text('DEFENSA: ?'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey<String>('vpn-toggle')))
          .onPressed,
      isNull,
    );

    statusVerified = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpAuraFrames(tester);
    expect(find.text('DEFENSA: SIN FLUJO'), findsOneWidget);
    // A still-running service must be stopped before attempting a new start.
    await tester.tap(find.byKey(const ValueKey<String>('vpn-toggle')));
    await _pumpAuraFrames(tester);
    expect(vpnServiceActive, isFalse);
    expect(find.text('DEFENSA: OFF'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('vpn-toggle')));
    await _pumpAuraFrames(tester);
    expect(state.isVpnActive, isTrue);
    expect(find.text('DEFENSA: ON'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('vpn-toggle')));
    await _pumpAuraFrames(tester);
    expect(calls.where((call) => call != 'getShieldStatus'), <String>[
      'startShield',
      'stopShield',
      'startShield',
      'stopShield',
    ]);
    expect(state.isVpnActive, isFalse);

    await tester.tap(find.byKey(const ValueKey<String>('vpn-toggle')));
    await _pumpAuraFrames(tester);
    expect(state.isVpnActive, isTrue);
    // Revocation is observed before teardown completes; no verified stop yet.
    statusVerified = false;
    vpnActive = false;
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
    expect(find.text('DEFENSA: ?'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey<String>('vpn-toggle')))
          .onPressed,
      isNull,
    );
    statusVerified = true;
    vpnServiceActive = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpAuraFrames(tester);
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
        const MaterialApp(home: Scaffold(body: AuraAvatar(size: 96))),
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

  testWidgets('Aura avatar exposes live protection and alert modes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuraAvatar(size: 96, mode: AuraAvatarMode.protecting),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Aura está protegiendo el dispositivo'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuraAvatar(size: 96, mode: AuraAvatarMode.warning),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Aura detectó señales que requieren atención'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuraAvatar(size: 96, mode: AuraAvatarMode.alert),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Aura detectó una alerta de seguridad'),
        findsOneWidget,
      );
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
          child: MaterialApp(home: Scaffold(body: AuraAvatar(size: 96))),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.bySemanticsLabel('Aura está disponible'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
