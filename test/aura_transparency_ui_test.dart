import 'package:aura_mobile_defens/explanation/aura_verdict_explanation.dart';
import 'package:aura_mobile_defens/explanation/aura_signal_builder.dart';
import 'package:aura_mobile_defens/inference/aura_ai_inference.dart';
import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/screens/aura_core_screen.dart';
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

  testWidgets('muestra explicación, marca localmente y abre auditoría', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const securityChannel = MethodChannel('com.ciberdefensa.aura/security');
    const biometricChannel = MethodChannel('com.aura.cyberdefense/biometrics');
    const telemetryChannel = MethodChannel('com.ciberdefensa.aura/telemetry');
    const networkEventChannel =
        EventChannel('com.aura.cyberdefense/network_stream');
    final state = AuraStateProvider();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(securityChannel, null);
      messenger.setMockMethodCallHandler(biometricChannel, null);
      messenger.setMockMethodCallHandler(telemetryChannel, null);
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
      MockStreamHandler.inline(onListen: (_, __) {}),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuraStateProvider>.value(
        value: state,
        child: const MaterialApp(home: AuraCoreScreen()),
      ),
    );
    await _pumpAuraFrames(tester);

    // Seed the provider after the screen's authentication/initialization
    // lifecycle; those startup steps may reset per-session counters.
    for (final action in <String>[
      'SNI_OBSERVED',
      'BLOCKED',
      'DGA_ALERT',
      'ENCRYPTED_DNS_BLOCKED',
    ]) {
      state.addTelemetryEvent(<String, dynamic>{
        'timestamp': 1,
        'source_app': 'com.example.browser',
        'requested_domain': 'example.test',
        'action': action,
        if (action == 'SNI_OBSERVED') ...<String, Object>{
          'public_dns_resolver': true,
          'destination_address': '8.8.8.8',
          'destination_port': 443,
          'transport_protocol': 'TCP',
        },
      });
    }
    await _pumpAuraFrames(tester);

    // Authentication and telemetry initialization are asynchronous. Wait
    // for the authenticated console's event list instead of assuming eight
    // frames are always enough on slower CI workers.
    final eventList = find.byKey(
      const ValueKey<String>('aura-event-list'),
    );
    for (var frame = 0; frame < 40 && eventList.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(eventList, findsOneWidget);

    // Add verdict evidence only after authentication has completed. Startup may
    // rebind/reset session state, so seeding before this point is racy on CI.
    const threatDescription =
        'Índice 6 · min_normalized_levenshtein; 0,10 frente a google.com.';
    state.addExplanation(
      AuraVerdictExplanation(
        id: 'verdict-1',
        host: 'goggle.com',
        isThreat: true,
        source: 'ml',
        timestamp: 1,
        modelVersion: '3.0.0',
        modelSha256:
            'd190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2',
        signals: const <AuraSignal>[
          AuraSignal(
            featureName: 'min_normalized_levenshtein',
            label: 'Posible typosquatting',
            value: 0.1,
            description: threatDescription,
          ),
        ],
      ),
    );
    await _pumpAuraFrames(tester);
    final threatCard = find.byKey(
      const ValueKey<String>('verdict-explanation-card-verdict-1'),
    );
    // Aura intentionally scrolls the event list to the newest event after
    // every provider update. The explanation card is the first lazy ListView
    // child, so it may not exist in the widget tree until the list is scrolled
    // back to the top. Drag the specific event list until that card is built.
    await tester.dragUntilVisible(
      threatCard,
      eventList,
      const Offset(0, 300),
    );
    await tester.pump();
    expect(threatCard, findsOneWidget);
    // Evidence belongs to the expanded content, not to the collapsed subtitle.
    expect(find.text(threatDescription), findsNothing);
    final threatHeader = find.byKey(
      const ValueKey<String>('verdict-explanation-title-verdict-1'),
    );
    await tester.ensureVisible(threatHeader);
    await tester.pump();
    await tester.tap(threatHeader);
    await _pumpAuraFrames(tester);

    expect(find.text(threatDescription), findsOneWidget);
    expect(find.text('Modelo v3.0.0'), findsOneWidget);
    expect(find.text('Reportar falso positivo'), findsOneWidget);
    expect(
      find.textContaining('Las señales son observaciones del vector'),
      findsOneWidget,
    );

    final digestButton = find.byKey(
      const ValueKey<String>('verdict-explanation-sha256-verdict-1'),
    );
    await tester.dragUntilVisible(
      digestButton,
      eventList,
      const Offset(0, -240),
    );
    await tester.pump();
    await tester.tap(digestButton);
    await _pumpAuraFrames(tester);
    expect(
      find.text(
        'd190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cerrar'));
    await _pumpAuraFrames(tester);

    final reportButton = find.byKey(
      const ValueKey<String>('report-false-positive-verdict-1'),
    );
    expect(reportButton, findsOneWidget);
    // Target the actual button rather than its label so the gesture lands
    // inside the control's hit region on different CI viewport sizes.
    await tester.dragUntilVisible(
      reportButton,
      eventList,
      const Offset(0, -240),
    );
    await tester.pump();
    await tester.tap(reportButton);
    await _pumpAuraFrames(tester);
    final reportedExplanation = state.explanationHistory.firstWhere(
      (explanation) => explanation.id == 'verdict-1',
    );
    expect(reportedExplanation.reportedFalsePositive, isTrue);
    expect(find.text('Reportado localmente'), findsOneWidget);
    expect(
      find.textContaining('no se enviará telemetría'),
      findsNWidgets(2),
    );
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await _pumpAuraFrames(tester);

    final safeExplanation = AuraSignalBuilder.buildExplanation(
      host: 'goggle.com',
      esThreat: false,
      features: AuraAIInference.extractLegacyFeatures('goggle.com'),
      featureOrder: AuraAIInference.legacyFeatureOrder,
      modelVersion: '3.0.0',
      modelSha256:
          'd190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2',
    );
    state.addExplanation(safeExplanation);
    await _pumpAuraFrames(tester);
    final safeCard = find.byKey(
      ValueKey<String>('verdict-explanation-card-${safeExplanation.id}'),
    );
    await tester.dragUntilVisible(
      safeCard,
      eventList,
      const Offset(0, 300),
    );
    await tester.pump();
    expect(find.text('¿Por qué se consideró seguro?'), findsOneWidget);
    final safeHeader = find.byKey(
      ValueKey<String>(
        'verdict-explanation-title-${safeExplanation.id}',
      ),
    );
    await tester.ensureVisible(safeHeader);
    await tester.pump();
    await tester.tap(safeHeader);
    await _pumpAuraFrames(tester);
    expect(
      find.text('Posible typosquatting (señal auxiliar) · 0.10'),
      findsOneWidget,
    );
    expect(find.text('Reportar falso positivo'), findsNothing);
    expect(
      find.textContaining(
        'La distancia de edición es auxiliar y no forma parte',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('coverage-audit-toggle')),
    );
    await _pumpAuraFrames(tester);
    expect(find.text('Auditoría de cobertura'), findsOneWidget);
    expect(
        find.textContaining('1 SNI observados, 1 bloqueo, '
            '1 alerta DGA y 1 bloqueo de DNS cifrado y '
            '0 paquetes QUIC descartados.'),
        findsOneWidget);
    expect(find.text('8.8.8.8'), findsOneWidget);
    final runAutotestButton = find.text('Ejecutar autotest');
    await tester.ensureVisible(runAutotestButton);
    await tester.pump();
    await tester.tap(runAutotestButton);
    await _pumpAuraFrames(tester);
    expect(
        find.textContaining('No se generó tráfico de prueba.'), findsOneWidget);
  });
}
