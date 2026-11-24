import 'agent_event.dart';

/// Origen de una entrada de actividad.
enum AuraActivitySource { agent, network }

/// Estado observable de un proceso.
///
/// [running] solo se usa mientras el motor no informó un resultado. No existe
/// un estado "simulado" ni una barra de progreso inventada: si el resultado no
/// llegó, la entrada sigue en curso y la UI lo dice.
enum AuraActivityStatus { running, succeeded, failed, observed, info }

/// Una operación real registrada por Aura durante la sesión.
class AuraActivityEntry {
  AuraActivityEntry({
    required this.id,
    required this.source,
    required this.status,
    required this.title,
    required this.startedAt,
    this.detail,
    this.finishedAt,
    this.tool,
    this.operationId,
    Map<String, Object?> evidence = const <String, Object?>{},
  }) : evidence = Map<String, Object?>.unmodifiable(evidence);

  final String id;
  final AuraActivitySource source;
  final AuraActivityStatus status;
  final String title;
  final String? detail;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? tool;
  final String? operationId;

  /// Evidencia reducida: nunca guarda valores de argumentos ni contenido de
  /// páginas. Sirve para que la persona pueda distinguir un resultado
  /// confirmado de una propuesta pendiente.
  final Map<String, Object?> evidence;

  bool get isRunning => status == AuraActivityStatus.running;

  Duration? get duration =>
      finishedAt == null ? null : finishedAt!.difference(startedAt);

  AuraActivityEntry close({
    required AuraActivityStatus status,
    required DateTime finishedAt,
    String? detail,
    Map<String, Object?>? evidence,
  }) => AuraActivityEntry(
    id: id,
    source: source,
    status: status,
    title: title,
    detail: detail ?? this.detail,
    startedAt: startedAt,
    finishedAt: finishedAt,
    tool: tool,
    operationId: operationId,
    evidence: evidence ?? this.evidence,
  );
}

/// Convierte eventos del agente y de la red en una lista acotada y ordenada.
///
/// Es una función pura: no lee relojes globales ni canales, no fabrica
/// entradas y no modifica sus argumentos. La UI la vuelve a ejecutar cuando
/// llega un evento nuevo.
class AuraActivityFeed {
  AuraActivityFeed._();

  /// Límite de memoria. Las entradas más antiguas se descartan primero.
  static const int maxEntries = 200;
  static const int _maxTextLength = 220;
  static const int _maxDetailLength = 260;

  static List<AuraActivityEntry> build({
    required Iterable<AgentEvent> agentEvents,
    required Iterable<Map<String, dynamic>> networkEvents,
    Iterable<Map<String, dynamic>> auditEvents = const <Map<String, dynamic>>[],
    int limit = maxEntries,
  }) {
    if (limit <= 0) return const <AuraActivityEntry>[];
    final entries = <String, AuraActivityEntry>{};
    var sequence = 0;
    // La auditoría cifrada va primero: los eventos vivos de la sesión tienen
    // más contexto y la sobrescriben cuando describen la misma operación.
    for (final event in auditEvents) {
      _ingestAudit(event, entries, sequence++);
    }
    for (final event in agentEvents) {
      _ingestAgent(event, entries, sequence++);
    }
    for (final event in networkEvents) {
      _ingestNetwork(event, entries, sequence++);
    }
    final ordered = entries.values.toList(growable: false)
      ..sort((left, right) {
        final byTime = right.startedAt.compareTo(left.startedAt);
        return byTime != 0 ? byTime : right.id.compareTo(left.id);
      });
    return ordered.take(limit).toList(growable: false);
  }

  static void _ingestAgent(
    AgentEvent event,
    Map<String, AuraActivityEntry> entries,
    int sequence,
  ) {
    final data = event.data ?? const <String, dynamic>{};
    final tool = data['tool'];
    final operationId = data['operation_id'] is String
        ? data['operation_id'] as String
        : null;
    final phase = data['phase'];
    final message = _clean(event.message, _maxDetailLength) ?? '';

    if (tool is String && tool.isNotEmpty) {
      final isStart =
          phase == 'started' ||
          (phase == null && message.startsWith('El motor local inició '));
      final isEnd =
          phase == 'completed' ||
          (phase == null &&
              (message.startsWith('El motor local completó ') ||
                  message.startsWith('El motor local no confirmó ')));
      final key = 'tool:${operationId ?? '-'}:$tool';
      if (isStart) {
        entries[key] = AuraActivityEntry(
          id: key,
          source: AuraActivitySource.agent,
          status: AuraActivityStatus.running,
          title: toolLabel(tool),
          detail: 'El motor local inició la operación.',
          startedAt: event.ts,
          tool: tool,
          operationId: operationId,
          evidence: _agentEvidence(data),
        );
        return;
      }
      if (isEnd) {
        final succeeded = data['ok'] == true;
        final previous = entries[key];
        entries[key] = AuraActivityEntry(
          id: key,
          source: AuraActivitySource.agent,
          status: succeeded
              ? AuraActivityStatus.succeeded
              : AuraActivityStatus.failed,
          title: toolLabel(tool),
          detail: message,
          startedAt: previous?.startedAt ?? event.ts,
          finishedAt: event.ts,
          tool: tool,
          operationId: operationId,
          evidence: _agentEvidence(data),
        );
        return;
      }
    }

    // A fake "thinking" label would be exactly the kind of simulation this
    // feed must not show. Real pending work is represented by [running].
    if (data['terminal_thinking'] == true) return;

    final status = switch (event.kind) {
      AgentEventKind.error => AuraActivityStatus.failed,
      AgentEventKind.warning => AuraActivityStatus.info,
      AgentEventKind.success => AuraActivityStatus.info,
      AgentEventKind.thought => AuraActivityStatus.info,
      AgentEventKind.action => AuraActivityStatus.info,
    };
    final title = switch (event.kind) {
      AgentEventKind.error => 'Error del agente',
      AgentEventKind.warning => 'Aviso del agente',
      AgentEventKind.success => 'Respuesta del agente',
      AgentEventKind.thought =>
        data['terminal_prefix'] == '[USER]'
            ? 'Instrucción recibida'
            : 'Actividad del agente',
      AgentEventKind.action => 'Acción del agente',
    };
    final id = 'agent:${event.ts.microsecondsSinceEpoch}:$sequence';
    entries[id] = AuraActivityEntry(
      id: id,
      source: AuraActivitySource.agent,
      status: status,
      title: title,
      detail: message.isEmpty ? null : message,
      startedAt: event.ts,
      finishedAt: event.kind == AgentEventKind.thought ? null : event.ts,
      evidence: _agentEvidence(data),
    );
  }

  static void _ingestAudit(
    Map<String, dynamic> event,
    Map<String, AuraActivityEntry> entries,
    int sequence,
  ) {
    final name = event['event'];
    final tool = event['tool'];
    if (tool is! String || tool.isEmpty) return;
    final isStart = name == 'agent_operation_started';
    final isEnd = name == 'agent_operation_completed';
    if (!isStart && !isEnd) return;
    final timestamp = _isoTimestamp(event['timestamp_utc']);
    if (timestamp == null) return;
    final operationId = event['operation_id'] is String
        ? event['operation_id'] as String
        : null;
    final key = 'tool:${operationId ?? '-'}:$tool';
    final previous = entries[key];
    if (isStart) {
      entries.putIfAbsent(
        key,
        () => AuraActivityEntry(
          id: key,
          source: AuraActivitySource.agent,
          status: AuraActivityStatus.running,
          title: toolLabel(tool),
          detail: 'Inicio registrado en la auditoría cifrada.',
          startedAt: timestamp,
          tool: tool,
          operationId: operationId,
          evidence: <String, Object?>{
            if (event['schema'] is int) 'schema': event['schema'],
          },
        ),
      );
      return;
    }
    final succeeded = event['succeeded'] == true;
    entries[key] = AuraActivityEntry(
      id: key,
      source: AuraActivitySource.agent,
      status: succeeded
          ? AuraActivityStatus.succeeded
          : AuraActivityStatus.failed,
      title: toolLabel(tool),
      detail: succeeded
          ? 'Resultado confirmado y guardado en la auditoría cifrada.'
          : 'Fallo guardado en la auditoría cifrada '
                '(${event['error_code'] ?? 'sin código'}).',
      startedAt: previous?.startedAt ?? timestamp,
      finishedAt: timestamp,
      tool: tool,
      operationId: operationId,
      evidence: <String, Object?>{
        'ok': succeeded,
        if (event['error_code'] is String) 'error': event['error_code'],
        if (event['argument_names'] is List)
          'argument_names': List<String>.unmodifiable(
            (event['argument_names'] as List).whereType<String>(),
          ),
      },
    );
  }

  static void _ingestNetwork(
    Map<String, dynamic> event,
    Map<String, AuraActivityEntry> entries,
    int sequence,
  ) {
    final action = event['action'];
    if (action is! String || action.isEmpty) return;
    final timestamp = _eventTimestamp(event['timestamp']);
    if (timestamp == null) return;
    final domain = event['requested_domain'] is String
        ? event['requested_domain'] as String
        : 'sin dominio';
    final sourceApp = event['source_app'] is String
        ? event['source_app'] as String
        : '';
    final details = <String>[
      _clean(domain, _maxTextLength) ?? domain,
      if (sourceApp.isNotEmpty) _clean(sourceApp, _maxTextLength) ?? sourceApp,
      if (event['transport_protocol'] is String)
        event['transport_protocol'] as String,
      if (event['destination_port'] is num)
        'puerto ${event['destination_port']}',
      if (event['public_dns_resolver'] == true) 'resolutor público',
    ];
    final id = 'network:${timestamp.microsecondsSinceEpoch}:$sequence:$action';
    entries[id] = AuraActivityEntry(
      id: id,
      source: AuraActivitySource.network,
      status: switch (action) {
        'BLOCKED' => AuraActivityStatus.succeeded,
        'ENCRYPTED_DNS_BLOCKED' => AuraActivityStatus.succeeded,
        'QUIC_BLOCKED' => AuraActivityStatus.succeeded,
        'VPN_REVOKED' => AuraActivityStatus.failed,
        'DGA_ALERT' => AuraActivityStatus.info,
        _ => AuraActivityStatus.observed,
      },
      title: networkLabel(action),
      detail: details.join(' · '),
      startedAt: timestamp,
      finishedAt: timestamp,
      evidence: <String, Object?>{
        'action': action,
        if (event['destination_address'] is String)
          'destination_address': event['destination_address'],
        if (event['destination_port'] is num)
          'destination_port': event['destination_port'],
        if (event['transport_protocol'] is String)
          'transport_protocol': event['transport_protocol'],
        if (event['public_dns_resolver'] is bool)
          'public_dns_resolver': event['public_dns_resolver'],
      },
    );
  }

  static Map<String, Object?> _agentEvidence(Map<String, dynamic> data) {
    // La bitácora ya reduce los argumentos a sus nombres. La pantalla repite
    // esa regla: no guarda valores crudos ni contenido.
    return <String, Object?>{
      if (data['ok'] is bool) 'ok': data['ok'],
      if (data['error'] is String) 'error': data['error'],
      if (data['requires_user_confirmation'] is bool)
        'requires_user_confirmation': data['requires_user_confirmation'],
      if (data['action_available'] is String)
        'action_available': data['action_available'],
      if (data['enforcement_scope'] is String)
        'enforcement_scope': data['enforcement_scope'],
      if (data['argument_names'] is List)
        'argument_names': List<String>.unmodifiable(
          (data['argument_names'] as List).whereType<String>(),
        ),
      if (data['argument_count'] is int)
        'argument_count': data['argument_count'],
    };
  }

  static DateTime? _isoTimestamp(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  static DateTime? _eventTimestamp(Object? value) {
    if (value is! num || !value.isFinite) return null;
    final raw = value.toInt();
    if (raw <= 0) return null;
    // El canal nativo usa milisegundos; se acepta segundos por robustez.
    final milliseconds = raw > 100000000000 ? raw : raw * 1000;
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ).toLocal();
    } on Object {
      return null;
    }
  }

  static String? _clean(String? value, int maxLength) {
    if (value == null) return null;
    final collapsed = value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    if (collapsed.isEmpty) return null;
    if (collapsed.length <= maxLength) return collapsed;
    return '${collapsed.substring(0, maxLength - 1)}…';
  }

  static String toolLabel(String tool) => switch (tool) {
    'audit_device' => 'Auditoría del dispositivo',
    'scan_apps' => 'Análisis de aplicaciones',
    'analyze_domain' => 'Análisis de dominio',
    'analyze_threats' => 'Análisis de amenazas',
    'block_domain' => 'Bloqueo de dominio',
    'isolate_app' => 'Revisión de aplicación',
    'panic_isolation' => 'Aislamiento de emergencia',
    'resume_network' => 'Reanudación de red',
    'update_defenses' => 'Actualización de defensas',
    'cryptographic_purge' => 'Purga criptográfica',
    'toggle_defenses' => 'Cambio del Escudo',
    'mitigate_network_threat' => 'Propuesta de mitigación',
    _ => 'Operación local ($tool)',
  };

  static String networkLabel(String action) => switch (action) {
    'BLOCKED' => 'Conexión bloqueada',
    'DGA_ALERT' => 'Alerta de dominio generado',
    'ALLOWED' => 'Conexión observada',
    'SNI_OBSERVED' => 'SNI observado',
    'SNI_ENCRYPTED' => 'SNI cifrado',
    'DIRECT_IP' => 'Conexión directa por IP',
    'ENCRYPTED_DNS_BLOCKED' => 'DNS cifrado bloqueado',
    'QUIC_BLOCKED' => 'Paquete QUIC descartado',
    'VPN_REVOKED' => 'Permiso de VPN revocado',
    _ => 'Evento de red',
  };
}
