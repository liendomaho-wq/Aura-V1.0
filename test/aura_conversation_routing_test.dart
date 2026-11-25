import 'dart:async';

import 'package:aura_mobile_defens/agent/agent_controller.dart';
import 'package:aura_mobile_defens/agent/agent_event.dart';
import 'package:aura_mobile_defens/agent/aura_conversation.dart';
import 'package:aura_mobile_defens/llm/aura_llm_runtime.dart';
import 'package:aura_mobile_defens/llm/local_llm_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Modelo de prueba que contesta en texto llano, como haría un GGUF real al que
/// no se le exige JSON.
class _PlainTextRuntime extends AuraLlmRuntime {
  _PlainTextRuntime(this.reply);

  final String reply;
  int generations = 0;

  final StreamController<AuraLlmEvent> _events =
      StreamController<AuraLlmEvent>.broadcast(sync: true);

  @override
  Stream<AuraLlmEvent> get events => _events.stream;

  @override
  Future<AuraLlmCapabilities> capabilities() async =>
      const AuraLlmCapabilities(
        available: true,
        loaded: true,
        backend: 'llama.cpp',
        abi: 'arm64-v8a',
        maxContextTokens: 8192,
      );

  @override
  Future<String> startGeneration({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.2,
  }) async {
    generations += 1;
    const operationId = 'op-plain';
    _events.add(
      AuraLlmEvent(operationId: operationId, type: 'token', text: reply),
    );
    _events.add(const AuraLlmEvent(operationId: operationId, type: 'completed'));
    return operationId;
  }

  Future<void> dispose() => _events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AuraConversationMemory.instance.reset());

  test('el modo conversacional acepta texto llano y lo devuelve', () async {
    final runtime = _PlainTextRuntime(
      'La ciberdefensa es el conjunto de medidas que protegen sistemas, redes '
      'y datos frente a ataques.',
    );
    addTearDown(runtime.dispose);
    final planner = LocalLlmPlanner(
      runtime: runtime,
      resolveModelPath: () async => '/data/model.gguf',
    );

    final result = await planner.plan(
      '¿qué es la ciberdefensa?',
      conversational: true,
    );

    expect(result.hasAnswer, isTrue);
    expect(result.answer, contains('ciberdefensa'));
    expect(result.status, LocalLlmPlanStatus.answer);
  });

  test('sin modo conversacional el mismo texto se descarta', () async {
    final runtime = _PlainTextRuntime('La ciberdefensa protege sistemas.');
    addTearDown(runtime.dispose);
    final planner = LocalLlmPlanner(
      runtime: runtime,
      resolveModelPath: () async => '/data/model.gguf',
    );

    final result = await planner.plan('¿qué es la ciberdefensa?');

    expect(result.hasAnswer, isFalse);
    expect(result.errorCode, 'llm_output_not_json');
  });

  test('el prompt conversacional no exige JSON y conserva la orden', () {
    final plain = AuraLlmPrompt.buildConversational(
      instruction: '¿qué es un ataque de intermediario?',
    );
    expect(plain, contains('sin JSON'));
    expect(plain, contains('¿qué es un ataque de intermediario?'));
    expect(plain, isNot(contains('Devolvé EXACTAMENTE un objeto JSON')));

    final schema = AuraLlmPrompt.build(instruction: 'auditá el dispositivo');
    expect(schema, contains('Devolvé EXACTAMENTE un objeto JSON'));
  });

  test('una pregunta de conversación la responde el motor local', () async {
    AuraConversationMemory.instance.reset();
    final runtime = _PlainTextRuntime(
      'Un ataque de intermediario ocurre cuando alguien se coloca entre dos '
      'extremos de la comunicación.',
    );
    final controller = AgentController.instance;
    controller.bindLocalLlmPlanner(
      LocalLlmPlanner(
        runtime: runtime,
        resolveModelPath: () async => '/data/model.gguf',
      ),
    );
    addTearDown(() {
      controller.bindLocalLlmPlanner(null);
      runtime.dispose();
    });

    final start = controller.history.length;
    await controller.run('hola aura');

    final events = controller.history.skip(start).toList();
    final answer = events.where(
      (event) =>
          event.kind == AgentEventKind.success &&
          event.data?['source'] == 'local_llm',
    );
    expect(answer, isNotEmpty);
    expect(answer.first.message, contains('intermediario'));
    expect(runtime.generations, 1);

    final turns = AuraConversationMemory.instance.turns;
    expect(turns.last.role, 'aura');
    expect(turns.last.source, 'local_llm');
  });

  test('sin modelo enlazado la conversación usa la capa determinista', () async {
    AuraConversationMemory.instance.reset();
    final controller = AgentController.instance;
    controller.bindLocalLlmPlanner(null);

    final start = controller.history.length;
    await controller.run('hola aura');

    final events = controller.history.skip(start).toList();
    final answer = events.where(
      (event) =>
          event.kind == AgentEventKind.success &&
          event.data?['source'] == 'system',
    );
    expect(answer, isNotEmpty);
    expect(
      events.any((event) => event.data?['source'] == 'local_llm'),
      isFalse,
    );
    expect(AuraConversationMemory.instance.turns.last.source, 'system');
  });

  test('el estado de seguridad nunca se le pregunta al modelo', () async {
    AuraConversationMemory.instance.reset();
    final runtime = _PlainTextRuntime('Respuesta inventada del modelo.');
    final controller = AgentController.instance;
    controller.bindLocalLlmPlanner(
      LocalLlmPlanner(
        runtime: runtime,
        resolveModelPath: () async => '/data/model.gguf',
      ),
    );
    addTearDown(() {
      controller.bindLocalLlmPlanner(null);
      runtime.dispose();
    });

    final start = controller.history.length;
    await controller.run('¿estoy protegido?');

    final events = controller.history.skip(start).toList();
    expect(runtime.generations, 0);
    expect(
      events.any((event) => event.message.contains('Respuesta inventada')),
      isFalse,
    );
  });
}
