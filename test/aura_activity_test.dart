import 'package:flutter_test/flutter_test.dart';

import 'package:aura_mobile_defens/agent/agent_event.dart';
import 'package:aura_mobile_defens/agent/aura_activity.dart';

AgentEvent _toolStart({
  required String tool,
  required String operationId,
  required DateTime ts,
}) => AgentEvent(
  kind: AgentEventKind.thought,
  message: 'El motor local inició $tool.',
  ts: ts,
  data: <String, dynamic>{
    'phase': 'started',
    'tool': tool,
    'operation_id': operationId,
    'argument_names': <String>['domain'],
    'argument_count': 1,
  },
);

AgentEvent _toolEnd({
  required String tool,
  required String operationId,
  required DateTime ts,
  required bool ok,
}) => AgentEvent(
  kind: ok ? AgentEventKind.success : AgentEventKind.error,
  message: ok
      ? 'El motor local completó $tool.'
      : 'El motor local no confirmó $tool.',
  ts: ts,
  data: <String, dynamic>{
    'phase': 'completed',
    'tool': tool,
    'operation_id': operationId,
    'ok': ok,
    if (!ok) 'error': 'timeout',
  },
);

void main() {
  test('une inicio y resultado en una sola entrada con duración real', () {
    final start = DateTime(2026, 11, 22, 10, 0, 0);
    final feed = AuraActivityFeed.build(
      agentEvents: <AgentEvent>[
        _toolStart(tool: 'audit_device', operationId: 'op-1', ts: start),
        _toolEnd(
          tool: 'audit_device',
          operationId: 'op-1',
          ts: start.add(const Duration(seconds: 2)),
          ok: true,
        ),
      ],
      networkEvents: const <Map<String, dynamic>>[],
    );

    expect(feed, hasLength(1));
    final entry = feed.single;
    expect(entry.title, 'Auditoría del dispositivo');
    expect(entry.status, AuraActivityStatus.succeeded);
    expect(entry.duration, const Duration(seconds: 2));
    expect(entry.evidence['ok'], isTrue);
  });

  test('un resultado no confirmado se muestra como fallo, no como éxito', () {
    final start = DateTime(2026, 11, 22, 10, 0, 0);
    final feed = AuraActivityFeed.build(
      agentEvents: <AgentEvent>[
        _toolStart(tool: 'block_domain', operationId: 'op-2', ts: start),
        _toolEnd(
          tool: 'block_domain',
          operationId: 'op-2',
          ts: start.add(const Duration(milliseconds: 750)),
          ok: false,
        ),
      ],
      networkEvents: const <Map<String, dynamic>>[],
    );

    expect(feed.single.status, AuraActivityStatus.failed);
    expect(feed.single.evidence['error'], 'timeout');
    expect(feed.single.detail, contains('no confirmó'));
  });

  test('un resultado sin inicio registrado conserva el dato, sin inventar '
      'progreso', () {
    final end = DateTime(2026, 11, 22, 10, 0, 0);
    final feed = AuraActivityFeed.build(
      agentEvents: <AgentEvent>[
        _toolEnd(tool: 'scan_apps', operationId: 'op-3', ts: end, ok: true),
      ],
      networkEvents: const <Map<String, dynamic>>[],
    );

    expect(feed, hasLength(1));
    expect(feed.single.status, AuraActivityStatus.succeeded);
    expect(feed.single.startedAt, end);
    expect(feed.single.duration, Duration.zero);
  });

  test('no convierte una etiqueta de "pensando" en una operación', () {
    final feed = AuraActivityFeed.build(
      agentEvents: <AgentEvent>[
        AgentEvent(
          kind: AgentEventKind.thought,
          message: 'PENSANDO...',
          ts: DateTime(2026, 11, 22, 10),
          data: const <String, dynamic>{'terminal_thinking': true},
        ),
      ],
      networkEvents: const <Map<String, dynamic>>[],
    );

    expect(feed, isEmpty);
  });

  test('traduce los eventos de red con su estado real', () {
    final timestamp = DateTime(2026, 11, 22, 10).millisecondsSinceEpoch;
    Map<String, dynamic> event(
      String action, {
      String domain = 'tracker.example',
      int offset = 0,
    }) => <String, dynamic>{
      'action': action,
      'requested_domain': domain,
      'source_app': 'com.example.app',
      'timestamp': timestamp + offset,
      'destination_port': 443,
      'transport_protocol': 'tcp',
    };

    final feed = AuraActivityFeed.build(
      agentEvents: const <AgentEvent>[],
      networkEvents: <Map<String, dynamic>>[
        event('BLOCKED'),
        event('ALLOWED', domain: 'api.example', offset: 1000),
        event('VPN_REVOKED', offset: 2000),
        event('DGA_ALERT', offset: 3000),
      ],
    );

    expect(feed, hasLength(4));
    final byTitle = <String, AuraActivityEntry>{
      for (final entry in feed) entry.title: entry,
    };
    expect(byTitle['Conexión bloqueada']!.status, AuraActivityStatus.succeeded);
    expect(byTitle['Conexión observada']!.status, AuraActivityStatus.observed);
    expect(
      byTitle['Permiso de VPN revocado']!.status,
      AuraActivityStatus.failed,
    );
    expect(
      byTitle['Alerta de dominio generado']!.status,
      AuraActivityStatus.info,
    );
    expect(byTitle['Conexión bloqueada']!.detail, contains('tracker.example'));
    expect(byTitle['Conexión bloqueada']!.detail, contains('puerto 443'));
  });

  test('recupera operaciones de la auditoría cifrada entre sesiones', () {
    final feed = AuraActivityFeed.build(
      agentEvents: const <AgentEvent>[],
      networkEvents: const <Map<String, dynamic>>[],
      auditEvents: <Map<String, dynamic>>[
        <String, dynamic>{
          'schema': 1,
          'event': 'agent_operation_started',
          'operation_id': 'op-9',
          'tool': 'block_domain',
          'argument_names': <String>['domain'],
          'timestamp_utc': '2026-11-22T10:00:00.000',
        },
        <String, dynamic>{
          'schema': 1,
          'event': 'agent_operation_completed',
          'operation_id': 'op-9',
          'tool': 'block_domain',
          'argument_names': <String>['domain'],
          'succeeded': false,
          'error_code': 'TIMEOUT',
          'timestamp_utc': '2026-11-22T10:00:03.000',
        },
      ],
    );

    expect(feed, hasLength(1));
    expect(feed.single.title, 'Bloqueo de dominio');
    expect(feed.single.status, AuraActivityStatus.failed);
    expect(feed.single.duration, const Duration(seconds: 3));
    expect(feed.single.evidence['error'], 'TIMEOUT');
  });

  test('la sesión viva enriquece una entrada recuperada del disco', () {
    final start = DateTime(2026, 11, 22, 10, 0, 0);
    final feed = AuraActivityFeed.build(
      agentEvents: <AgentEvent>[
        _toolEnd(
          tool: 'audit_device',
          operationId: 'op-10',
          ts: start.add(const Duration(seconds: 4)),
          ok: true,
        ),
      ],
      networkEvents: const <Map<String, dynamic>>[],
      auditEvents: <Map<String, dynamic>>[
        <String, dynamic>{
          'event': 'agent_operation_started',
          'operation_id': 'op-10',
          'tool': 'audit_device',
          'timestamp_utc': '2026-11-22T10:00:00.000',
        },
      ],
    );

    expect(feed, hasLength(1));
    expect(feed.single.status, AuraActivityStatus.succeeded);
    expect(feed.single.startedAt, start);
  });

  test('ordena de más reciente a más antiguo y respeta el límite', () {
    final base = DateTime(2026, 11, 22, 10).millisecondsSinceEpoch;
    final events = List<Map<String, dynamic>>.generate(
      250,
      (index) => <String, dynamic>{
        'action': 'ALLOWED',
        'requested_domain': 'host$index.example',
        'timestamp': base + index * 1000,
      },
      growable: false,
    );

    final feed = AuraActivityFeed.build(
      agentEvents: const <AgentEvent>[],
      networkEvents: events,
    );

    expect(feed, hasLength(AuraActivityFeed.maxEntries));
    for (var index = 1; index < feed.length; index++) {
      expect(feed[index - 1].startedAt.isAfter(feed[index].startedAt), isTrue);
    }
  });

  test('un límite no positivo devuelve una lista vacía', () {
    expect(
      AuraActivityFeed.build(
        agentEvents: const <AgentEvent>[],
        networkEvents: const <Map<String, dynamic>>[],
        limit: 0,
      ),
      isEmpty,
    );
  });
}
