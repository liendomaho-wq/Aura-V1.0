import 'package:aura_mobile_defens/explanation/aura_verdict_explanation.dart';
import 'package:aura_mobile_defens/inference/aura_ai_inference.dart';
import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/screens/aura_places.dart';
import 'package:aura_mobile_defens/widgets/aura_avatar.dart';
import 'package:aura_mobile_defens/widgets/aura_neural_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the particle budget stays small enough for a mid-range phone', () {
    expect(
      auraCoreParticleBudget(size: 320, reducedMotion: false),
      lessThanOrEqualTo(36),
    );
    expect(
      auraCoreParticleBudget(size: 48, reducedMotion: false),
      lessThanOrEqualTo(12),
    );
    expect(
      auraCoreParticleBudget(size: 220, reducedMotion: true),
      lessThanOrEqualTo(12),
    );
  });

  test('avatar activity maps onto the four core motions', () {
    expect(
      auraCoreStateForAvatar(mode: AuraAvatarMode.available, speaking: false),
      AuraCoreVisualState.calm,
    );
    expect(
      auraCoreStateForAvatar(mode: AuraAvatarMode.protecting, speaking: false),
      AuraCoreVisualState.calm,
    );
    expect(
      auraCoreStateForAvatar(mode: AuraAvatarMode.alert, speaking: false),
      AuraCoreVisualState.alert,
    );
    expect(
      auraCoreStateForAvatar(mode: AuraAvatarMode.warning, speaking: false),
      AuraCoreVisualState.alert,
    );
    expect(
      auraCoreStateForAvatar(mode: AuraAvatarMode.analyzing, speaking: false),
      AuraCoreVisualState.scanning,
    );
    expect(
      auraCoreStateForAvatar(mode: AuraAvatarMode.available, speaking: true),
      AuraCoreVisualState.speaking,
    );
  });

  testWidgets('neural core exposes calm, alert, speaking and scanning', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      Future<void> expectState(AuraCoreVisualState state, String label) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AuraNeuralCore(state: state, size: 120)),
          ),
        );
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }

      await expectState(AuraCoreVisualState.calm, 'Aura en calma');
      await expectState(AuraCoreVisualState.alert, 'Aura en alerta');
      await expectState(AuraCoreVisualState.speaking, 'Aura está hablando');
      await expectState(AuraCoreVisualState.scanning, 'Aura está escaneando');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('neural core stays still when motion is reduced', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: AuraNeuralCore(state: AuraCoreVisualState.calm, size: 96),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.bySemanticsLabel('Aura en calma'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('domain analysis shows real features and no invented score', (
    tester,
  ) async {
    final state = AuraStateProvider();
    addTearDown(state.dispose);
    final features = AuraAIInference.extractFeatures('xyz-login.tk');

    await tester.pumpWidget(
      ChangeNotifierProvider<AuraStateProvider>.value(
        value: state,
        child: MaterialApp(
          home: AuraDomainPlace(
            initialHost: 'xyz-login.tk',
            commandsEnabled: false,
            onCommand: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('aura-domain-features')),
      findsOneWidget,
    );
    expect(find.text(_shown(features['length'])), findsWidgets);
    expect(find.text(_shown(features['shannon_entropy'])), findsOneWidget);
    expect(find.text('Sí'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('aura-domain-no-score')),
      findsOneWidget,
    );
    expect(find.text('0.91'), findsNothing);

    state.addExplanation(
      AuraVerdictExplanation(
        id: 'score-1',
        host: 'xyz-login.tk',
        isThreat: true,
        source: 'ml',
        timestamp: 1,
        modelVersion: 'test',
        modelSha256: 'ab' * 32,
        decisionThreshold: 0.5,
        signals: const <AuraSignal>[],
        threatScore: 0.42,
      ),
    );
    await tester.pump();

    expect(find.textContaining('0.42'), findsOneWidget);
    expect(find.text('0.91'), findsNothing);
  });

  testWidgets('live feed stays empty until a real network event arrives', (
    tester,
  ) async {
    final state = AuraStateProvider()..setVpnActive(true);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuraStateProvider>.value(
        value: state,
        child: const MaterialApp(home: AuraLivePlace()),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('aura-live-empty')),
      findsOneWidget,
    );
    expect(find.text('Túnel activo, esperando tráfico.'), findsOneWidget);

    state.addTelemetryEvent(<String, dynamic>{
      'timestamp': 1,
      'requested_domain': 'example.com',
      'action': 'ALLOWED',
      'source_app': 'com.example.app',
    });
    await tester.pump();

    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Permitido'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('aura-live-empty')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

String _shown(double? value) {
  if (value == null) return '';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2);
}
