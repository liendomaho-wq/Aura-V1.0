import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../secure_vault.dart';

class AuraLocalTelemetry {
  AuraLocalTelemetry._();

  static const MethodChannel _telemetryChannel = MethodChannel(
    'com.ciberdefensa.aura/telemetry',
  );
  static const String _eventsKey = 'aura_local_telemetry_events';
  static const String _enabledKey = 'aura_local_telemetry_enabled';
  static const int _maxEvents = 500;

  static bool? _endpointConfigured;
  static Future<bool>? _endpointCheck;
  static Future<void> _writeTail = Future<void>.value();
  // Invalidate events captured before a consent or storage reset, even if
  // asynchronous hashing completes after the user enables telemetry again.
  static int _recordingGeneration = 0;
  static AuraSecureVault _secureVault = AuraSecureVault();

  static void configure({
    required bool endpointConfigured,
    AuraSecureVault? secureVault,
  }) {
    if (_endpointConfigured != endpointConfigured) _recordingGeneration++;
    _endpointConfigured = endpointConfigured;
    _endpointCheck = Future<bool>.value(endpointConfigured);
    if (secureVault != null) _secureVault = secureVault;
  }

  /// Local telemetry is opt-in: a fresh installation records nothing until
  /// the user explicitly enables it.
  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  static Future<bool> setEnabled(bool enabled) => _serializeWrites(() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(_enabledKey, enabled)) {
      throw StateError(
        'No se pudo guardar el consentimiento de telemetría local.',
      );
    }
    _recordingGeneration++;
    if (!enabled && !await preferences.remove(_eventsKey)) {
      throw StateError('No se pudo borrar la cola de telemetría local.');
    }
    return enabled;
  });

  // Loading may migrate and rewrite legacy events. Serialize it with consent
  // changes and appends so revocation cannot be undone by a stale migration.
  static Future<List<Map<String, dynamic>>>
  loadEvents() => _serializeWrites(() async {
    final preferences = await SharedPreferences.getInstance();
    if (!(preferences.getBool(_enabledKey) ?? false)) {
      if (!await preferences.remove(_eventsKey)) {
        throw StateError('No se pudo borrar la cola de telemetría local.');
      }
      return const <Map<String, dynamic>>[];
    }
    final encodedEvents = preferences.getStringList(_eventsKey) ?? const [];
    final events = <Map<String, dynamic>>[];
    var containsLegacyDomains = false;
    for (final encoded in encodedEvents) {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException(
          'Un evento de telemetría local no es un mapa.',
        );
      }
      final event = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final hadLegacyDomain =
          event.containsKey('requested_domain') || event.containsKey('domain');
      // Remove both fields even when the first one is present. A legacy record
      // can contain both, and short-circuiting would leave one in plaintext.
      final requestedDomain = event.remove('requested_domain');
      final domain = event.remove('domain');
      final legacyDomain = requestedDomain is String
          ? requestedDomain
          : domain is String
          ? domain
          : null;
      if (legacyDomain != null) {
        event['domain_hash'] = await _hashDomain(legacyDomain);
      }
      containsLegacyDomains = containsLegacyDomains || hadLegacyDomain;
      events.add(event);
    }
    if (containsLegacyDomains) {
      if (!await preferences.setStringList(
        _eventsKey,
        events.map(jsonEncode).toList(growable: false),
      )) {
        throw StateError(
          'No se pudieron sanear los dominios de la telemetría local.',
        );
      }
    }
    return List<Map<String, dynamic>>.unmodifiable(events);
  });

  static Future<void> clearEvents() => _serializeWrites(() async {
    _recordingGeneration++;
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(_eventsKey)) {
      throw StateError('No se pudo borrar la cola de telemetría local.');
    }
  });

  static Future<bool> recordNetworkEvent(Map<String, Object> event) async {
    final generation = _recordingGeneration;
    if (!await _shouldRecordLocally() || !await isEnabled()) return false;
    final action = event['action'];
    final item = <String, Object?>{
      'type': action == 'BLOCKED' ? 'dominio_bloqueado' : 'escaneo',
      'timestamp': event['timestamp'],
      'action': action,
      if (event['requested_domain'] case final String domain)
        'domain_hash': await _hashDomain(domain),
    };
    return _append(item, generation);
  }

  static Future<bool> recordDomainOutcome({
    required String domain,
    required String outcome,
    required String source,
    String? modelVersion,
  }) async {
    final generation = _recordingGeneration;
    if (!await _shouldRecordLocally() || !await isEnabled()) return false;
    return _append(<String, Object?>{
      'type': outcome == 'blocked' ? 'dominio_bloqueado' : 'escaneo',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'domain_hash': await _hashDomain(domain),
      'outcome': outcome,
      'source': source,
      if (modelVersion != null) 'model_version': modelVersion,
    }, generation);
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

  static Future<bool> _append(Map<String, Object?> event, int generation) =>
      _serializeWrites(() async {
        if (generation != _recordingGeneration ||
            !await _shouldRecordLocally() ||
            !await isEnabled()) {
          return false;
        }
        final preferences = await SharedPreferences.getInstance();
        if (generation != _recordingGeneration) return false;
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
        return true;
      });

  static Future<String> _hashDomain(String domain) {
    final normalized = domain
        .trim()
        .replaceFirst(RegExp(r'\.$'), '')
        .toLowerCase();
    return _secureVault.withDomainTelemetryKey((keyBytes) {
      return Hmac(sha256, keyBytes).convert(utf8.encode(normalized)).toString();
    });
  }

  static Future<String> hashDomain(String domain) => _hashDomain(domain);

  static Future<T> _serializeWrites<T>(Future<T> Function() operation) async {
    final previousWrite = _writeTail;
    final completer = Completer<void>();
    _writeTail = completer.future;
    try {
      await previousWrite;
      return await operation();
    } finally {
      completer.complete();
    }
  }
}
