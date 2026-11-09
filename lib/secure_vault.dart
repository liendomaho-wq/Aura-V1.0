import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuraSecureVault {
  static const String _auditLogsKey = 'aura_audit_logs_v1';
  static const String _modelMasterKeyStorageKey = 'aura_model_master_key_v1';
  static const String _domainHashKeyStorageKey = 'aura_domain_hash_key_v1';
  static const int maxAuditLogs = 500;
  // These options request backup-protected v9-to-v10 migration and disable
  // silent reset. They do not guarantee migration: Android instrumentation
  // exposed a v10.3.4 legacy ESP failure (see REVISION_SEGURIDAD_PENDIENTE.md).
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  );

  @visibleForTesting
  static AndroidOptions get androidMigrationOptions => _androidOptions;
  static Future<void>? _writeQueue;

  /// Serializes mutations and key creation across every vault instance.
  /// The queue itself never remains failed; each caller receives its own error.
  static Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completion = Completer<T>();
    final previous = _writeQueue;
    late final Future<void> queued;
    queued = Future<void>.microtask(() async {
      try {
        if (previous != null) await previous;
        completion.complete(await operation());
      } on Object catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      } finally {
        // A completed Future schedules late listeners in its original zone.
        // Do not retain an idle tail from a disposed boot/test scheduler, and
        // never clear a newer caller's still-pending reservation.
        if (identical(_writeQueue, queued)) _writeQueue = null;
      }
    });
    _writeQueue = queued;
    return completion.future;
  }

  final FlutterSecureStorage _storage;

  AuraSecureVault({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: _androidOptions);

  Future<T> withModelMasterKey<T>(
    FutureOr<T> Function(Uint8List secureKeyBytes) action,
  ) => _enqueue(() async {
    final encodedKey = await _loadOrCreateModelMasterKey();
    final secureKeyBytes = Uint8List.fromList(utf8.encode(encodedKey));
    try {
      return await action(secureKeyBytes);
    } finally {
      secureKeyBytes.fillRange(0, secureKeyBytes.length, 0);
    }
  });

  Future<void> initializeModelMasterKey() => withModelMasterKey<void>((_) {});

  Future<T> withDomainTelemetryKey<T>(
    FutureOr<T> Function(Uint8List keyBytes) action,
  ) => _enqueue(() async {
    final keyBytes = await _loadOrCreateRandomKey(_domainHashKeyStorageKey);
    try {
      return await action(keyBytes);
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  });

  Future<String> _loadOrCreateModelMasterKey() async {
    final existingKey = await _storage.read(key: _modelMasterKeyStorageKey);
    if (existingKey != null) {
      if (!_isValidModelMasterKey(existingKey)) {
        throw StateError(
          'SecureVault encontró una clave maestra existente no válida; '
          'se conserva para evitar perder datos cifrados.',
        );
      }
      return existingKey;
    }

    final random = math.Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256), growable: false),
    );
    try {
      final generatedKey = base64UrlEncode(keyBytes).replaceAll('=', '');
      await _storage.write(key: _modelMasterKeyStorageKey, value: generatedKey);
      final persistedKey = await _storage.read(key: _modelMasterKeyStorageKey);
      if (persistedKey != generatedKey ||
          !_isValidModelMasterKey(persistedKey)) {
        throw StateError(
          'No se pudo inicializar una clave aleatoria de 256 bits en SecureVault.',
        );
      }
      return persistedKey!;
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  Future<Uint8List> _loadOrCreateRandomKey(String storageKey) async {
    final existingKey = await _storage.read(key: storageKey);
    if (existingKey != null) {
      try {
        final decoded = Uint8List.fromList(
          base64Url.decode(base64Url.normalize(existingKey)),
        );
        if (decoded.length == 32) return decoded;
        decoded.fillRange(0, decoded.length, 0);
      } on FormatException {
        // Preserve invalid stored data and fail closed below.
      }
      throw StateError(
        'SecureVault encontró una clave de privacidad no válida; '
        'se conserva para evitar cambiar el hash de datos existentes.',
      );
    }

    final random = math.Random.secure();
    final generated = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256), growable: false),
    );
    try {
      final encoded = base64UrlEncode(generated).replaceAll('=', '');
      await _storage.write(key: storageKey, value: encoded);
      final persisted = await _storage.read(key: storageKey);
      if (persisted != encoded) {
        throw StateError('No se pudo verificar la clave local de privacidad.');
      }
      final decoded = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(persisted!)),
      );
      if (decoded.length != 32) {
        decoded.fillRange(0, decoded.length, 0);
        throw StateError('La clave local de privacidad no tiene 256 bits.');
      }
      return decoded;
    } finally {
      generated.fillRange(0, generated.length, 0);
    }
  }

  bool _isValidModelMasterKey(String? value) {
    if (value == null || value.isEmpty) return false;
    Uint8List? decoded;
    try {
      decoded = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      return decoded.length == 32;
    } on FormatException {
      return false;
    } finally {
      if (decoded != null) decoded.fillRange(0, decoded.length, 0);
    }
  }

  Future<void> saveAuditLogs(List<Map<String, dynamic>> newLogs) =>
      _enqueue(() async {
        final history = await getAuditLogs();
        final combined = <Map<String, dynamic>>[
          ...history,
          ...newLogs.map((log) => Map<String, dynamic>.from(log)),
        ];
        final bounded = combined.length > maxAuditLogs
            ? combined.sublist(combined.length - maxAuditLogs)
            : combined;
        await _storage.write(key: _auditLogsKey, value: jsonEncode(bounded));
      });

  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    final encoded = await _storage.read(key: _auditLogsKey);
    if (encoded == null || encoded.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.any((entry) => entry is! Map)) {
      throw const FormatException(
        'El historial de auditoría almacenado no es válido.',
      );
    }
    final records = decoded
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    return records.length > maxAuditLogs
        ? records.sublist(records.length - maxAuditLogs)
        : records;
  }

  Future<void> writeLogSecurely(String logText) => writeLogsSecurely([logText]);

  Future<void> writeLogsSecurely(Iterable<String> logTexts) {
    final now = DateTime.now().toUtc().toIso8601String();
    return saveAuditLogs([
      for (final text in logTexts) {'event': text, 'timestamp': now},
    ]);
  }

  Future<List<Map<String, dynamic>>> readLogsSecurely() => getAuditLogs();

  Future<void> clearLogsSecurely() =>
      _enqueue(() => _storage.delete(key: _auditLogsKey));

  Future<void> purgeSensitiveData() {
    return _enqueue(() async {
      await _storage.deleteAll();
      if ((await _storage.readAll()).isNotEmpty) {
        throw StateError('SecureVault conserva datos después de la purga.');
      }
    });
  }
}
