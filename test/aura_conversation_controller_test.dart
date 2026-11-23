import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_mobile_defens/agent/agent_controller.dart';
import 'package:aura_mobile_defens/agent/aura_conversation.dart';
import 'package:aura_mobile_defens/agent/aura_intent_parser.dart';
import 'package:aura_mobile_defens/explanation/aura_verdict_explanation.dart';
import 'package:aura_mobile_defens/inference/aura_host_policy.dart';
import 'package:aura_mobile_defens/providers/aura_state_provider.dart';

AuraIntent _lastAnalyzedDomain(String host) => AuraIntent(
  name: 'analyze_domain',
  kind: AuraIntentKind.analyzeDomain,
  entities: <String, dynamic>{'domain': host},
  confidence: 0.96,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuraStateProvider state;

  setUp(() async {
    AuraConversationMemory.instance.reset();
    const channel = MethodChannel('com.ciberdefensa.aura/shield');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    state = AuraStateProvider();
    AgentController.instance.bindSecurityState(state);
    // Limpia cualquier autorización pendiente de una prueba anterior.
    await AgentController.instance.run('texto neutral');
  });

  tearDown(() {
    const channel = MethodChannel('com.ciberdefensa.aura/shield');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    state.dispose();
  });

  test('"bloquéalo" retoma el último dominio y exige confirmación', () async {
    final controller = AgentController.instance;
    AuraConversationMemory.instance.recordIntent(
      _lastAnalyzedDomain('tracker.example'),
    );
    final start = controller.history.length;

    await controller.run('bloquéalo');

    final events = controller.history.skip(start).toList(growable: false);
    expect(
      events.any((event) => event.data?['follow_up'] == 'blockLastHost'),
      isTrue,
    );
    expect(
      events.any((event) => event.data?['error'] == 'user_confirmation_required'),
      isTrue,
    );
    expect(controller.history.last.data?['confirmation_pending'], isTrue);
  });

  test('un "sí" completo autoriza la acción reversible pendiente', () async {
    final controller = AgentController.instance;
    AuraConversationMemory.instance.recordIntent(
      _lastAnalyzedDomain('tracker.example'),
    );
    await controller.run('bloquéalo');
    final start = controller.history.length;

    await controller.run('sí');

    final events = controller.history.skip(start).toList(growable: false);
    expect(
      events.any((event) => event.data?['error'] == 'no_pending_confirmation'),
      isFalse,
    );
    expect(
      events.any((event) => event.data?['error'] == 'explicit_confirmation_required'),
      isFalse,
    );
  });

  test('una purga pendiente no se autoriza con "sí"', () async {
    final controller = AgentController.instance;
    await controller.run('purga criptográfica');
    expect(controller.history.last.data?['confirmation_pending'], isTrue);
    final start = controller.history.length;

    await controller.run('sí');

    final events = controller.history.skip(start).toList(growable: false);
    expect(
      events.any(
        (event) => event.data?['error'] == 'explicit_confirmation_required',
      ),
      isTrue,
    );
    // La solicitud sigue armada: el usuario todavía puede escribir CONFIRMO.
    expect(controller.history.last.data?['confirmation_pending'], isTrue);
  });

  test('"¿por qué?" explica el último veredicto con sus señales reales', () async {
    final controller = AgentController.instance;
    AuraConversationMemory.instance.recordIntent(
      _lastAnalyzedDomain('tracker.example'),
    );
    state.addExplanation(
      AuraVerdictExplanation(
        id: 'conv-explain',
        host: 'tracker.example',
        isThreat: true,
        source: 'ml',
        timestamp: 1,
        modelVersion: '3.0.0',
        modelSha256:
            'd190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2',
        decisionThreshold: 0.5,
        riskBand: AuraRiskBand.review,
        signals: const <AuraSignal>[
          AuraSignal(
            featureName: 'digit_ratio',
            label: 'Proporción de dígitos elevada',
            value: 0.42,
            description: 'Índice 2 · digit_ratio.',
          ),
        ],
      ),
    );
    final start = controller.history.length;

    await controller.run('¿por qué?');

    final events = controller.history.skip(start).toList(growable: false);
    final explanation = events.firstWhere(
      (event) => event.data?['intent'] == 'explain',
    );
    expect(explanation.message, contains('tracker.example'));
    expect(explanation.message, contains('revisión'));
    expect(explanation.message, contains('Proporción de dígitos elevada'));
    expect(explanation.message, contains('no inspecciona'));
  });

  test('"¿qué has hecho?" resume solo eventos registrados', () async {
    final controller = AgentController.instance;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    state.addTelemetryEvent(<String, dynamic>{
      'action': 'BLOCKED',
      'timestamp': timestamp,
      'requested_domain': 'tracker.example',
    });
    state.addTelemetryEvent(<String, dynamic>{
      'action': 'BLOCKED',
      'timestamp': timestamp + 1,
      'requested_domain': 'ads.example',
    });
    state.addTelemetryEvent(<String, dynamic>{
      'action': 'DGA_ALERT',
      'timestamp': timestamp + 2,
      'requested_domain': 'x921llmzaqp0182ncnw.example',
    });
    final start = controller.history.length;

    await controller.run('¿qué has hecho?');

    final events = controller.history.skip(start).toList(growable: false);
    final summary = events.firstWhere(
      (event) => event.data?['intent'] == 'session_summary',
    );
    expect(summary.message, contains('3 eventos de red'));
    expect(summary.message, contains('2 bloqueos'));
    expect(summary.message, contains('1 alertas de dominio generado'));
  });
}
