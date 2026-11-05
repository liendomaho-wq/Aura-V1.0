import 'package:aura_mobile_defens/agent/agent_controller.dart';
import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('successful non-audit tools preserve the last device posture', () {
    expect(
      AgentController.resolveSecurityLevel(
        <String, dynamic>{'ok': true},
        AuraSecurityLevel.critical,
      ),
      AuraSecurityLevel.critical,
    );
    expect(
      AgentController.resolveSecurityLevel(
        <String, dynamic>{'ok': true},
        AuraSecurityLevel.warning,
      ),
      AuraSecurityLevel.warning,
    );
    expect(
      AgentController.resolveSecurityLevel(
        <String, dynamic>{
          'ok': true,
          'security_level': 'warning',
          'tool': 'analyze_domain',
        },
        AuraSecurityLevel.critical,
      ),
      AuraSecurityLevel.critical,
    );
    expect(
      AgentController.resolveSecurityLevel(
        <String, dynamic>{
          'ok': true,
          'security_level': 'safe',
          'tool': 'analyze_domain',
        },
        AuraSecurityLevel.warning,
      ),
      AuraSecurityLevel.warning,
    );
    expect(
      AgentController.resolveSecurityLevel(
        <String, dynamic>{
          'ok': true,
          'security_level': 'safe',
          'tool': 'audit_device',
        },
        AuraSecurityLevel.warning,
      ),
      AuraSecurityLevel.safe,
    );
    expect(
      AgentController.resolveSecurityLevel(
        <String, dynamic>{
          'ok': true,
          'security_level': 'safe',
          'tool': 'audit_device',
        },
        AuraSecurityLevel.critical,
      ),
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

  test('cancels a command before it crosses the tool execution boundary', () async {
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
  });

  test('rejects overlapping commands while one is being processed', () async {
    final controller = AgentController.instance;
    final previousLength = controller.history.length;

    final first = controller.run('audita dispositivo');
    await controller.run('escanea aplicaciones');
    controller.cancelCurrentOperation();
    await first;

    final events = controller.history.skip(previousLength).toList();
    expect(
      events.any((event) => event.data?['error'] == 'agent_busy'),
      isTrue,
    );
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
    expect(
      await controller.authenticateDeviceCredential(),
      isFalse,
    );
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
    const expected = 'ÓRDENES DISPONIBLES — ACTIVAR DEFENSAS · '
        'DESACTIVAR DEFENSAS · BLOQUEAR <dominio> · REVISAR APP <paquete> · '
        'AISLAMIENTO DE EMERGENCIA · REANUDAR LA RED · ACTUALIZAR '
        'DEFENSAS · AUDITAR DISPOSITIVO · ESCANEAR APLICACIONES · ANALIZAR DOMINIO <host> · ESTADO · PURGA CRIPTOGRÁFICA. '
        'REVISAR APP solo abre Ajustes de Android; no aísla automáticamente otras apps. Para confirmar cambios de VPN, bloqueos, revisión de apps o purga, inicia una segunda orden con CONFIRMO.';
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
}
