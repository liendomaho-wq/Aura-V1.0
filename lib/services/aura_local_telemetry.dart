import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuraLocalTelemetry {
  AuraLocalTelemetry._();

  static const MethodChannel _telemetryChannel =
      MethodChannel('com.ciberdefensa.aura/telemetry');
  static const String _eventsKey = 'aura_local_telemetry_events';
  static const String _enabledKey = 'aura_local_telemetry_enabled';
  static const int _maxEvents = 500;

  static bool? _endpointConfigured;
  static Future<bool>? _endpointCheck;
  static Future<void> _writeTail = Future<void>.value();

  static void configure({required bool endpointConfigured}) {
    _endpointConfigured = endpointConfigured;
    _endpointCheck = Future<bool>.value(endpointConfigured);
  }

  /// Local telemetry is opt-in: a fresh installation records nothing until
  /// the user explicitly enables it.
  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  static Future<bool> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(_enabledKey, enabled)) {
      throw StateError('No se pudo guardar el ajuste de telemetría local.');
    }
    return enabled;
  }

  static Future<List<Map<String, dynamic>>> loadEvents() async {
    final preferences = await SharedPreferences.getInstance();
    final encodedEvents = preferences.getStringList(_eventsKey) ?? const [];
    return List<Map<String, dynamic>>.unmodifiable(
      encodedEvents.map((encoded) {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map) {
          throw const FormatException(
            'Un evento de telemetría local no es un mapa.',
          );
        }
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }),
    );
  }

  static Future<void> clearEvents() => _serializeWrites(() async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(_eventsKey);
      });

  static Future<bool> recordNetworkEvent(Map<String, Object> event) async {
    if (!await _shouldRecordLocally() || !await isEnabled()) return false;
    final action = event['action'];
    final item = <String, Object?>{
      'type': action == 'BLOCKED' ? 'dominio_bloqueado' : 'escaneo',
      'timestamp': event['timestamp'],
      'requested_domain': event['requested_domain'],
      'action': action,
    };
    await _append(item);
    return true;
  }

  static Future<bool> recordDomainOutcome({
    required String domain,
    required String outcome,
    required String source,
    String? modelVersion,
  }) async {
    if (!await _shouldRecordLocally() || !await isEnabled()) return false;
    await _append(<String, Object?>{
      'type': outcome == 'blocked' ? 'dominio_bloqueado' : 'escaneo',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'domain': domain,
      'outcome': outcome,
      'source': source,
      if (modelVersion != null) 'model_version': modelVersion,
    });
    return true;
  }

  static Future<bool> _shouldRecordLocally() async {
    final knownStatus = _endpointConfigured;
    if (knownStatus != null) return !knownStatus;
    _endpointCheck ??= _readEndpointStatus();
    return !(await _endpointCheck!);
  }

  static Future<bool> _readEndpointStatus() async {
    final rawStatus = await _telemetryChannel.invokeMethod<Object?>(
      'domainTelemetryStatus',
    );
    if (rawStatus is! Map || rawStatus['endpointConfigured'] is! bool) {
      throw const FormatException(
        'Android devolvió un estado de telemetría inválido.',
      );
    }
    final configured = rawStatus['endpointConfigured'] as bool;
    _endpointConfigured = configured;
    return configured;
  }

  static Future<void> _append(Map<String, Object?> event) =>
      _serializeWrites(() async {
        final preferences = await SharedPreferences.getInstance();
        final events = List<String>.of(
          preferences.getStringList(_eventsKey) ?? const <String>[],
        );
        events.add(jsonEncode(event));
        if (events.length > _maxEvents) {
          events.removeRange(0, events.length - _maxEvents);
        }
        if (!await preferences.setStringList(_eventsKey, events)) {
          throw StateError('No se pudo guardar la telemetría local.');
        }
      });

  static Future<void> _serializeWrites(
    Future<void> Function() operation,
  ) async {
    final previousWrite = _writeTail;
    final completer = Completer<void>();
    _writeTail = completer.future;
    try {
      await previousWrite;
      await operation();
    } finally {
      completer.complete();
    }
  }
}
