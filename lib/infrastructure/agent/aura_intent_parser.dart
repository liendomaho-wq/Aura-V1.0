import '../../agent/agent_controller.dart';
import '../../agent/agent_event.dart';

enum AuraIntent {
  blockDomain,
  isolateApp,
  panicIsolation,
  resumeNetwork,
  cryptographicPurge,
  updateModel,
  toggleDefenses,
  help,
  conversation,
  status,
  unknown,
}

class AuraIntentParser {
  AuraIntentParser._();

  static Future<Map<String, dynamic>> executeCommand(String input) async {
    final command = input.trim();
    if (command.isEmpty) {
      return <String, dynamic>{
        'intent': AuraIntent.unknown,
        'success': false,
        'response': '[WARN] Escribe una orden o consulta antes de enviarla.',
      };
    }

    final controller = AgentController.instance;
    final previousEvents = Set<AgentEvent>.identity()
      ..addAll(controller.history);
    try {
      await controller.run(command);
    } on Object catch (error) {
      final response = '[CRIT] No se pudo ejecutar la orden: $error';
      controller.reportError(response);
      return <String, dynamic>{
        'intent': AuraIntent.unknown,
        'success': false,
        'response': response,
        'event': controller.history.last,
      };
    }

    final generatedEvents = controller.history
        .where((event) => !previousEvents.contains(event))
        .toList(growable: false);
    final responseEvent = generatedEvents.isEmpty ? null : generatedEvents.last;
    if (responseEvent == null) {
      const response = '[WARN] No se generó un resultado para la orden.';
      controller.reportError(response);
      return <String, dynamic>{
        'intent': AuraIntent.unknown,
        'success': false,
        'response': response,
        'event': controller.history.last,
      };
    }

    final intentEvent = generatedEvents.firstWhere(
      (event) => event.data?['confidence'] is num,
      orElse: () => responseEvent,
    );
    final responseData = responseEvent.data;
    final intentName = responseData?['protected_host'] == true ||
            responseData?['allowlist_check_failed'] == true
        ? 'block_domain'
        : responseEvent.kind == AgentEventKind.warning &&
                responseData?['instruction'] is String &&
                identical(intentEvent, responseEvent)
            ? 'unknown'
            : (responseData?['intent'] as String?) ?? intentEvent.message;
    final intent = _intentFromName(intentName);
    final prefix = switch (responseEvent.kind) {
      AgentEventKind.success => '[OK]',
      AgentEventKind.warning ||
      AgentEventKind.thought ||
      AgentEventKind.action =>
        '[WARN]',
      AgentEventKind.error => '[CRIT]',
    };

    return <String, dynamic>{
      'intent': intent,
      'success': responseEvent.kind == AgentEventKind.success,
      'response': '$prefix ${responseEvent.message}',
      'event': responseEvent,
    };
  }

  static AuraIntent _intentFromName(String name) => switch (name) {
        'block_domain' => AuraIntent.blockDomain,
        'isolate_app' => AuraIntent.isolateApp,
        'panic_isolation' => AuraIntent.panicIsolation,
        'resume_network' => AuraIntent.resumeNetwork,
        'cryptographic_purge' => AuraIntent.cryptographicPurge,
        'update_defenses' => AuraIntent.updateModel,
        'toggle_defenses' => AuraIntent.toggleDefenses,
        'help' => AuraIntent.help,
        'status' => AuraIntent.status,
        'unknown' => AuraIntent.unknown,
        _ => AuraIntent.conversation,
      };
}
