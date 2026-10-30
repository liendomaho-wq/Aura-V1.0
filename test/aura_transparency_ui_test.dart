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
    const biometricChannel = MethodChannel('com.aura.cyberdefense/biometrics');
    const telemetryChannel = MethodChannel('com.ciberdefensa.aura/telemetry');
    const networkEventChannel =
        EventChannel('com.aura.cyberdefense/network_stream');
    final state = AuraStateProvider()
      ..addExplanation(
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
              description:
                  'Índice 6 · min_normalized_levenshtein; 0,10 frente a google.com.',
            ),
          ],
        ),
      );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(biometricChannel, null);
      messenger.setMockMethodCallHandler(telemetryChannel, null);
      messenger.setMockStreamHandler(networkEventChannel, null);
      state.dispose();
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

    await tester.scrollUntilVisible(
      find.text('¿Por qué se bloqueó?'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('¿Por qué se bloqueó?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>(
      'verdict-explanation-card-verdict-1',
    )));
    await _pumpAuraFrames(tester);

    expect(
        find.text('Índice 6 · min_normalized_levenshtein; '
            '0,10 frente a google.com.'),
        findsOneWidget);
    expect(find.text('Modelo v3.0.0'), findsOneWidget);
    expect(find.text('Reportar falso positivo'), findsOneWidget);
    expect(
      find.textContaining('Las señales son observaciones del vector'),
      findsOneWidget,
    );

    await tester.tap(find.text('SHA-256: d190dddf…'));
    await _pumpAuraFrames(tester);
    expect(
      find.text(
        'd190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cerrar'));
    await _pumpAuraFrames(tester);

    await tester.tap(find.text('Reportar falso positivo'));
    await _pumpAuraFrames(tester);
    expect(state.explanationHistory.single.reportedFalsePositive, isTrue);
    expect(find.text('Reportado localmente'), findsOneWidget);
    expect(
      find.textContaining('no se enviará telemetría'),
      findsNWidgets(2),
    );

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
    expect(find.text('¿Por qué se consideró seguro?'), findsOneWidget);
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'verdict-explanation-card-${safeExplanation.id}',
        ),
      ),
    );
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
    await tester.tap(find.text('Ejecutar autotest'));
    await _pumpAuraFrames(tester);
    expect(
        find.textContaining('No se generó tráfico de prueba.'), findsOneWidget);
  });
}
