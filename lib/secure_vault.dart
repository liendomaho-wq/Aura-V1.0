import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuraSecureVault {
  static const String _auditLogsKey = 'aura_audit_logs_v1';
  static const String _modelMasterKeyStorageKey = 'aura_model_master_key_v1';
  static const int maxAuditLogs = 500;
  static int _modelKeyGeneration = 0;
  static Future<String>? _sharedModelMasterKeyLoad;
  // v10 migrates the legacy v9 EncryptedSharedPreferences data to
  // RSA-OAEP key wrapping + AES-GCM storage. Keep a crash-safe backup during
  // migration and never silently erase secrets if the keystore reports an error.
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  );
  static Future<void> _writeQueue = Future<void>.value();

  /// Serializes mutations and key creation across every vault instance.
  /// The queue itself never remains failed; each caller receives its own error.
  static Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completion = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completion.complete(await operation());
      } on Object catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }

  final FlutterSecureStorage _storage;
  final bool _usesDefaultStorage;
  Future<String>? _modelMasterKeyLoad;
  int _cachedModelKeyGeneration = -1;

  AuraSecureVault({FlutterSecureStorage? storage})
      : _usesDefaultStorage = storage == null,
        _storage = storage ??
            const FlutterSecureStorage(aOptions: _androidOptions);

  Future<String> getOrCreateModelMasterKey() {
    if (_usesDefaultStorage) {
      return _sharedModelMasterKeyLoad ??=
          _enqueue(_loadOrCreateModelMasterKey);
    }
    if (_modelMasterKeyLoad == null ||
        _cachedModelKeyGeneration != _modelKeyGeneration) {
      _cachedModelKeyGeneration = _modelKeyGeneration;
      _modelMasterKeyLoad = _enqueue(_loadOrCreateModelMasterKey);
    }
    return _modelMasterKeyLoad!;
  }

  Future<String> _loadOrCreateModelMasterKey() async {
    final existingKey = await _storage.read(key: _modelMasterKeyStorageKey);
    if (existingKey != null && _isValidModelMasterKey(existingKey)) {
      return existingKey;
    }

    final random = math.Random.secure();
    final keyBytes = List<int>.generate(
      32,
      (_) => random.nextInt(256),
      growable: false,
    );
    final generatedKey = base64UrlEncode(keyBytes).replaceAll('=', '');
    keyBytes.fillRange(0, keyBytes.length, 0);
    await _storage.write(
      key: _modelMasterKeyStorageKey,
      value: generatedKey,
    );
    final persistedKey = await _storage.read(key: _modelMasterKeyStorageKey);
    if (persistedKey != generatedKey || !_isValidModelMasterKey(persistedKey)) {
      throw StateError(
        'No se pudo inicializar una clave aleatoria de 256 bits en SecureVault.',
      );
    }
    return persistedKey!;
  }

  bool _isValidModelMasterKey(String? value) {
    if (value == null || value.isEmpty) return false;
    try {
      return base64Url.decode(base64Url.normalize(value)).length == 32;
    } on FormatException {
      return false;
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
        await _storage.write(
          key: _auditLogsKey,
          value: jsonEncode(bounded),
        );
      });

  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    final encoded = await _storage.read(key: _auditLogsKey);
    if (encoded == null || encoded.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.any((entry) => entry is! Map)) {
      throw const FormatException('El historial de auditoría almacenado no es válido.');
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
    // Invalidate cached futures immediately. Any key request arriving after
    // this point is queued behind the purge and cannot resurrect a pre-purge
    // key while deleteAll() is in progress.
    _modelKeyGeneration++;
    _sharedModelMasterKeyLoad = null;
    _modelMasterKeyLoad = null;
    _cachedModelKeyGeneration = -1;

    return _enqueue(() async {
      await _storage.deleteAll();
      if ((await _storage.readAll()).isNotEmpty) {
        throw StateError('SecureVault conserva datos después de la purga.');
      }
    });
  }
}
