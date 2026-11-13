import 'dart:async';

import 'package:aura_mobile_defens/agent/agent_controller.dart';
import 'package:aura_mobile_defens/agent/agent_event.dart';
import 'package:aura_mobile_defens/llm/aura_llm_runtime.dart';
import 'package:aura_mobile_defens/llm/local_llm_planner.dart';
import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuditOnlyLlmRuntime extends AuraLlmRuntime {
  final StreamController<AuraLlmEvent> _events =
      StreamController<AuraLlmEvent>.broadcast(sync: true);

  @override
  Stream<AuraLlmEvent> get events => _events.stream;

  @override
  Future<AuraLlmCapabilities> capabilities() async => const AuraLlmCapabilities(
    available: true,
    loaded: true,
    backend: 'llama.cpp',
    abi: 'arm64-v8a',
    maxContextTokens: 2048,
  );

  @override
  Future<String> startGeneration({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.2,
  }) async {
    const operationId = 'op-integration';
    _events.add(
      const AuraLlmEvent(
        operationId: operationId,
        type: 'token',
        text: '{"tool":"audit_device","arguments":{}}',
      ),
    );
    _events.add(
      const AuraLlmEvent(operationId: operationId, type: 'completed'),
    );
    return operationId;
  }

  Future<void> dispose() => _events.close();
}

class _AnswerOnlyLlmRuntime extends AuraLlmRuntime {
  final StreamController<AuraLlmEvent> _events =
      StreamController<AuraLlmEvent>.broadcast(sync: true);

  @override
  Stream<AuraLlmEvent> get events => _events.stream;

  @override
  Future<AuraLlmCapabilities> capabilities() async => const AuraLlmCapabilities(
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
    const operationId = 'op-answer';
    _events.add(
      const AuraLlmEvent(
        operationId: operationId,
        type: 'token',
        text:
            '{"answer":"No puedo verificar el tráfico sin un evento '
            'observable. Revisá el estado del túnel."}',
      ),
    );
    _events.add(
      const AuraLlmEvent(operationId: operationId, type: 'completed'),
    );
    return operationId;
  }

  Future<void> dispose() => _events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('successful non-audit tools preserve the last device posture', () {
    expect(
      AgentController.resolveSecurityLevel(<String, dynamic>{
        'ok': true,
      }, AuraSecurityLevel.critical),
      AuraSecurityLevel.critical,
    );
    expect(
      AgentController.resolveSecurityLevel(<String, dynamic>{
        'ok': true,
      }, AuraSecurityLevel.warning),
      AuraSecurityLevel.warning,
    );
    expect(
      AgentController.resolveSecurityLevel(<String, dynamic>{
        'ok': true,
        'security_level': 'warning',
        'tool': 'analyze_domain',
      }, AuraSecurityLevel.critical),
      AuraSecurityLevel.critical,
    );
    expect(
      AgentController.resolveSecurityLevel(<String, dynamic>{
        'ok': true,
        'security_level': 'safe',
        'tool': 'analyze_domain',
      }, AuraSecurityLevel.warning),
      AuraSecurityLevel.warning,
    );
    expect(
      AgentController.resolveSecurityLevel(<String, dynamic>{
        'ok': true,
        'security_level': 'safe',
        'tool': 'audit_device',
      }, AuraSecurityLevel.warning),
      AuraSecurityLevel.safe,
    );
    expect(
      AgentController.resolveSecurityLevel(<String, dynamic>{
        'ok': true,
        'security_level': 'safe',
        'tool': 'audit_device',
      }, AuraSecurityLevel.critical),
      AuraSecurityLevel.critical,
    );
  });

  test('rejects oversized instructions before parsing or execution', () async {
    final controller = AgentController.instance;
    final previousLength = controller.history.length;

    await controller.run(List<String>.filled(2049, 'x').join());

    final events = controller.history.skip(previousLength).toList();
    expect(events, hasLength(1));
    expect(events.single.data?['error'], 'instruction_too_long');
    expect(controller.isRunning, isFalse);
  });

  test(
    'cancels a command before it crosses the tool execution boundary',
    () async {
      final controller = AgentController.instance;
      final previousLength = controller.history.length;

      final pending = controller.run('audita dispositivo');
      expect(controller.isRunning, isTrue);
      expect(controller.cancelCurrentOperation(), isTrue);
      await pending;

      final events = controller.history.skip(previousLength).toList();
      expect(
        events.any((event) => event.data?['error'] == 'operation_cancelled'),
        isTrue,
      );
      expect(
        events.any((event) => event.kind == AgentEventKind.action),
        isFalse,
      );
      expect(controller.isRunning, isFalse);
    },
  );

  test('rejects overlapping commands while one is being processed', () async {
    final controller = AgentController.instance;
    final previousLength = controller.history.length;

    final first = controller.run('audita dispositivo');
    await controller.run('escanea aplicaciones');
    controller.cancelCurrentOperation();
    await first;

    final events = controller.history.skip(previousLength).toList();
    expect(events.any((event) => event.data?['error'] == 'agent_busy'), isTrue);
  });

  test(
    'la confirmación escrita dentro de la primera orden no autoriza la VPN',
    () async {
      const channel = MethodChannel('com.ciberdefensa.aura/shield');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      var starts = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'startShield') starts++;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final controller = AgentController.instance;
      await controller.run(
        'texto neutral',
      ); // Clears any earlier pending action.
      final start = controller.history.length;
      await controller.run('CONFIRMO activar las defensas');
      expect(starts, 0);
      expect(
        controller.history
            .skip(start)
            .any(
              (event) => event.data?['error'] == 'user_confirmation_required',
            ),
        isTrue,
      );

      await controller.run('CONFIRMO');
      expect(starts, 1);
      await controller.run('CONFIRMO');
      expect(starts, 1); // The authorization is one-shot.
    },
  );

  test('una orden negada no queda pendiente de autorización', () async {
    const channel = MethodChannel('com.ciberdefensa.aura/shield');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var starts = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      starts++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final controller = AgentController.instance;
    final start = controller.history.length;
    await controller.run('no quiero activar las defensas');
    expect(
      controller.history
          .skip(start)
          .any((event) => event.data?['error'] == 'user_denied_operation'),
      isTrue,
    );
    await controller.run('CONFIRMO');
    expect(starts, 0);
    expect(controller.history.last.data?['error'], 'no_pending_confirmation');
  });

  test('una negativa prevalece incluso con confirmación de UI', () async {
    const channel = MethodChannel('com.ciberdefensa.aura/shield');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var starts = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      starts++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = AgentController.instance;
    await controller.run(
      'no quiero activar las defensas',
      confirmedByUser: true,
    );
    expect(starts, 0);
    expect(controller.history.last.data?['error'], 'user_denied_operation');
  });

  test('una orden excesiva invalida la confirmación previa', () async {
    final controller = AgentController.instance;
    await controller.run('activar las defensas');
    await controller.run(List<String>.filled(2049, 'x').join());
    await controller.run('CONFIRMO');
    expect(controller.history.last.data?['error'], 'no_pending_confirmation');
  });

  test(
    'un identificador que contiene no no se interpreta como negativa',
    () async {
      final controller = AgentController.instance;
      final start = controller.history.length;
      await controller.run('bloquea no.example');
      expect(
        controller.history
            .skip(start)
            .any(
              (event) => event.data?['error'] == 'user_confirmation_required',
            ),
        isTrue,
      );
      await controller.run('texto neutral');
    },
  );

  test('una instrucción nueva invalida la autorización pendiente', () async {
    final controller = AgentController.instance;
    await controller.run('activar las defensas');
    await controller.run('texto neutral');
    await controller.run('CONFIRMO');
    expect(controller.history.last.data?['error'], 'no_pending_confirmation');
  });

  test('missing native authentication channel fails closed', () async {
    const channel = MethodChannel('com.aura.cyberdefense/biometrics');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final controller = AgentController.instance;
    final status = await controller.getLocalAuthStatus();

    expect(status['nativeAuthAvailable'], isFalse);
    expect(status['deviceSecure'], isTrue);
    expect(await controller.authenticateDeviceCredential(), isFalse);
  });

  test('empty native authentication status also fails closed', () async {
    const channel = MethodChannel('com.aura.cyberdefense/biometrics');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final status = await AgentController.instance.getLocalAuthStatus();

    expect(status['nativeAuthAvailable'], isFalse);
    expect(status['deviceSecure'], isTrue);
  });

  test('help devuelve exactamente la lista de órdenes solicitada', () async {
    const expected =
        'ÓRDENES DISPONIBLES — ACTIVAR DEFENSAS · '
        'DESACTIVAR DEFENSAS · BLOQUEAR <dominio> · REVISAR APP <paquete> · '
        'AISLAMIENTO DE EMERGENCIA · REANUDAR LA RED · ACTUALIZAR '
        'DEFENSAS · AUDITAR DISPOSITIVO · ESCANEAR APLICACIONES · ANALIZAR DOMINIO <host> · ESTADO · PURGA CRIPTOGRÁFICA. '
        'REVISAR APP solo abre Ajustes de Android; no aísla automáticamente otras apps. Para confirmar cambios de VPN, bloqueos, revisión de apps o purga, responde únicamente CONFIRMO a la solicitud pendiente.';
    final controller = AgentController.instance;
    final previousLength = controller.history.length;

    await controller.run('ayuda');

    expect(
      controller.history.skip(previousLength).map((event) => event.message),
      contains(expected),
    );
  });

  test('descarta eventos antiguos al superar 400 entradas', () {
    final controller = AgentController.instance;
    controller.history.clear();

    for (var index = 0; index < 405; index++) {
      controller.reportWarning('evento-$index');
    }

    expect(AgentController.historyCapacity, 400);
    expect(controller.history, hasLength(400));
    expect(controller.history.first.message, 'evento-5');
    expect(controller.history.last.message, 'evento-404');
    controller.history.clear();
  });

  test(
    'una orden desconocida usa el planificador local solo para lectura',
    () async {
      const securityChannel = MethodChannel('com.ciberdefensa.aura/security');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      messenger.setMockMethodCallHandler(securityChannel, (call) async {
        if (call.method != 'checkHostileEnvironment') return null;
        return <String, dynamic>{
          'isEmulator': false,
          'isRooted': false,
          'rootConfidence': 0.0,
          'isInstrumented': false,
          'isScreenOverlayDetected': false,
          'isHostile': false,
          'indicators': <String>[],
          'environmentCheckErrors': <String>[],
          'untrustedAccessibilityServicePackages': <String>[],
          'timestamp': '2026-01-01T00:00:00Z',
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(securityChannel, null),
      );

      final runtime = _AuditOnlyLlmRuntime();
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
      await controller.run('qwertyuiop zxcvbnm');

      final events = controller.history.skip(start).toList();
      expect(
        events.any((event) => event.data?['source'] == 'local_llm'),
        isTrue,
      );
      expect(
        events.any(
          (event) =>
              event.kind == AgentEventKind.action &&
              event.message == 'audit_device',
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) => event.data?['error'] == 'user_confirmation_required',
        ),
        isFalse,
      );
      expect(
        events.any((event) => event.data?['tool'] == 'audit_device'),
        isTrue,
      );
      expect(controller.isRunning, isFalse);
    },
  );

  test(
    'una pregunta desconocida muestra la respuesta local sin ejecutar tools',
    () async {
      const securityChannel = MethodChannel('com.ciberdefensa.aura/security');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      messenger.setMockMethodCallHandler(securityChannel, (call) async {
        if (call.method != 'checkHostileEnvironment') return null;
        return <String, dynamic>{
          'isEmulator': false,
          'isRooted': false,
          'rootConfidence': 0.0,
          'isInstrumented': false,
          'isScreenOverlayDetected': false,
          'isHostile': false,
          'indicators': <String>[],
          'environmentCheckErrors': <String>[],
          'untrustedAccessibilityServicePackages': <String>[],
          'timestamp': '2026-01-01T00:00:00Z',
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(securityChannel, null),
      );

      final runtime = _AnswerOnlyLlmRuntime();
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
      await controller.run('qwertyuiop zxcvbnm');

      final events = controller.history.skip(start).toList();
      final answer = events.where(
        (event) => event.data?['answer_is_unverified'] == true,
      );
      expect(answer, hasLength(1));
      expect(answer.single.kind, AgentEventKind.success);
      expect(answer.single.message, contains('No puedo verificar'));
      expect(
        events.any((event) => event.kind == AgentEventKind.action),
        isFalse,
      );
      expect(events.any((event) => event.data?['tool'] != null), isFalse);
      expect(controller.isRunning, isFalse);
    },
  );

  test(
    'una orden con error de tipeo sugiere la forma canónica sin ejecutarla',
    () async {
      final controller = AgentController.instance;
      controller.bindLocalLlmPlanner(null);
      addTearDown(() => controller.bindLocalLlmPlanner(null));

      final start = controller.history.length;
      await controller.run('activaar las defensas');

      final events = controller.history.skip(start).toList();
      expect(
        events.any(
          (event) => event.data?['suggested_command'] == 'ACTIVAR DEFENSAS',
        ),
        isTrue,
      );
      expect(
        events.any((event) => event.kind == AgentEventKind.action),
        isFalse,
      );
      expect(controller.isRunning, isFalse);
    },
  );
}
