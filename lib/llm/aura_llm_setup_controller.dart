import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/storage/aura_storage.dart';
import 'aura_llm_model_manager.dart';
import 'aura_llm_model_source.dart';

enum AuraLlmSetupStatus {
  unknown,
  notConfigured,
  notInstalled,
  paused,
  downloading,
  verifying,
  loading,
  ready,
  failed,
}

/// Owns the explicit, consent-based provisioning of the local GGUF model.
///
/// The agent never downloads: this controller is the only path that can move
/// bytes, and it verifies the pinned SHA-256 before reporting [ready].
class AuraLlmSetupController extends ChangeNotifier {
  factory AuraLlmSetupController({
    AuraLlmModelSource? source,
    AuraLlmModelProvisioner? manager,
    AuraStorage? storage,
    Future<bool> Function()? warmUp,
    Future<void> Function()? unload,
    Future<SharedPreferences> Function()? preferences,
  }) {
    final resolvedSource =
        source ?? manager?.source ?? AuraLlmModelSource.fromEnvironment();
    return AuraLlmSetupController._(
      source: resolvedSource,
      manager: manager ?? AuraLlmModelManager(source: resolvedSource),
      storage: storage ?? AuraStorage(),
      warmUp: warmUp,
      unload: unload,
      preferences: preferences ?? SharedPreferences.getInstance,
    );
  }

  AuraLlmSetupController._({
    required this.source,
    required AuraLlmModelProvisioner manager,
    required AuraStorage storage,
    required Future<bool> Function()? warmUp,
    required Future<void> Function()? unload,
    required Future<SharedPreferences> Function() preferences,
  }) : _manager = manager,
       _storage = storage,
       _warmUp = warmUp,
       _unload = unload,
       _preferences = preferences;

  static const String _consentKey = 'aura.llm.consent.v1';
  static const String _prefetchKey = 'aura.llm.prefetch.v1';

  final AuraLlmModelSource source;
  final AuraLlmModelProvisioner _manager;
  final AuraStorage _storage;
  final Future<bool> Function()? _warmUp;
  final Future<void> Function()? _unload;
  final Future<SharedPreferences> Function() _preferences;

  AuraLlmSetupStatus _status = AuraLlmSetupStatus.unknown;
  int _receivedBytes = 0;
  int? _totalBytes;
  int? _freeBytes;
  String? _errorCode;
  bool _hasConsent = false;
  bool _prefetchOnStartup = true;
  bool _runtimeReady = false;
  bool _initialized = false;
  bool _initializing = false;
  bool _disposed = false;
  AuraLlmCancellation? _cancellation;
  DateTime? _lastProgressAt;
  int _lastProgressBytes = 0;
  double _bytesPerSecond = 0;

  AuraLlmSetupStatus get status => _status;
  int get receivedBytes => _receivedBytes;
  int? get totalBytes =>
      _totalBytes ?? (source.sizeBytes > 0 ? source.sizeBytes : null);
  int? get freeBytes => _freeBytes;
  int get minimumFreeSpaceBytes => _manager.minimumFreeSpaceBytes;
  String? get errorCode => _errorCode;
  bool get hasConsent => _hasConsent;
  bool get prefetchOnStartup => _prefetchOnStartup;
  bool get runtimeReady => _runtimeReady;
  bool get isReady => _status == AuraLlmSetupStatus.ready;
  bool get isBusy =>
      _status == AuraLlmSetupStatus.downloading ||
      _status == AuraLlmSetupStatus.verifying ||
      _status == AuraLlmSetupStatus.loading;
  double get bytesPerSecond => _bytesPerSecond;

  double? get progress {
    final total = totalBytes;
    if (_status != AuraLlmSetupStatus.downloading ||
        total == null ||
        total <= 0) {
      return null;
    }
    final value = _receivedBytes / total;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  String get statusLabel => switch (_status) {
    AuraLlmSetupStatus.unknown => 'IA local: comprobando',
    AuraLlmSetupStatus.notConfigured => 'Aura Básica',
    AuraLlmSetupStatus.notInstalled => 'Aura Básica · preparar IA',
    AuraLlmSetupStatus.paused => 'Descarga en pausa',
    AuraLlmSetupStatus.downloading => 'Descargando IA local…',
    AuraLlmSetupStatus.verifying => 'Verificando modelo…',
    AuraLlmSetupStatus.loading => 'Cargando IA local…',
    AuraLlmSetupStatus.ready =>
      _runtimeReady ? 'IA local lista' : 'Modelo verificado',
    AuraLlmSetupStatus.failed => 'IA local: revisar',
  };

  String? get errorMessage => switch (_errorCode) {
    null => null,
    'consent_required' => 'Confirmá la descarga para continuar.',
    'llm_model_not_configured' =>
      'Este build no tiene un modelo fijado con SHA-256.',
    'llm_storage_unavailable' =>
      'Android no pudo confirmar el espacio libre del almacenamiento.',
    'llm_insufficient_storage' =>
      'No hay espacio libre suficiente para el modelo y su verificación.',
    'llm_download_network' =>
      'La descarga se interrumpió. Podés reanudarla sin perder el progreso.',
    'llm_download_http' => 'El servidor del modelo rechazó la descarga.',
    'llm_model_size_mismatch' =>
      'El tamaño del archivo no coincide con el fijado; no se instaló.',
    'llm_model_digest_mismatch' =>
      'El SHA-256 no coincide con el fijado; el archivo fue descartado.',
    'llm_download_io' =>
      'No se pudo escribir el modelo en el almacenamiento privado.',
    'llm_runtime_unavailable' =>
      'El modelo está verificado, pero el runtime llama.cpp no está '
          'disponible en este dispositivo.',
    'setup_initialization_failed' =>
      'No se pudo comprobar el estado del modelo local.',
    _ =>
      'La preparación de Aura IA falló. Revisá el estado e intentá de nuevo.',
  };

  Future<void> initialize({bool force = false}) async {
    if (_disposed || _initializing) return;
    if (_initialized && !force) return;
    if (_status == AuraLlmSetupStatus.downloading) return;
    _initializing = true;
    try {
      final prefs = await _preferences();
      _hasConsent = prefs.getBool(_consentKey) ?? false;
      _prefetchOnStartup = prefs.getBool(_prefetchKey) ?? true;
      _freeBytes = await _storage.freeBytes();
      if (!_manager.isConfigured) {
        _setStatus(AuraLlmSetupStatus.notConfigured);
        return;
      }
      final snapshot = await _manager.inspect();
      if (!snapshot.hasInstalledFile) {
        _receivedBytes = snapshot.partialBytes ?? 0;
        _totalBytes = source.sizeBytes > 0 ? source.sizeBytes : null;
        _setStatus(
          snapshot.hasPartialDownload
              ? AuraLlmSetupStatus.paused
              : AuraLlmSetupStatus.notInstalled,
        );
        return;
      }
      _setStatus(AuraLlmSetupStatus.verifying);
      final verified = await _manager.verifyInstalled();
      if (!verified) {
        _receivedBytes = 0;
        _errorCode = 'llm_model_digest_mismatch';
        _setStatus(AuraLlmSetupStatus.notInstalled);
        return;
      }
      _errorCode = null;
      _receivedBytes =
          snapshot.installedBytes ??
          (source.sizeBytes > 0 ? source.sizeBytes : 0);
      _totalBytes = _receivedBytes;
      _setStatus(AuraLlmSetupStatus.ready);
      if (_prefetchOnStartup) await _warmUpModel();
    } on Object {
      if (!_disposed) {
        _errorCode = 'setup_initialization_failed';
        _setStatus(AuraLlmSetupStatus.failed);
      }
    } finally {
      _initializing = false;
      _initialized = true;
    }
  }

  Future<void> refresh() => initialize(force: true);

  Future<void> startDownload({required bool consent}) async {
    if (_disposed || _status == AuraLlmSetupStatus.downloading) return;
    if (!_manager.isConfigured) {
      _errorCode = 'llm_model_not_configured';
      _setStatus(AuraLlmSetupStatus.notConfigured);
      return;
    }
    if (!consent) {
      _errorCode = 'consent_required';
      _notify();
      return;
    }
    try {
      final prefs = await _preferences();
      await prefs.setBool(_consentKey, true);
    } on Object {
      // Consent is still honored for this session; persistence is best effort.
    }
    _hasConsent = true;
    _cancellation = AuraLlmCancellation();
    _errorCode = null;
    _runtimeReady = false;
    _receivedBytes = 0;
    _totalBytes = source.sizeBytes > 0 ? source.sizeBytes : null;
    _bytesPerSecond = 0;
    _lastProgressAt = null;
    _lastProgressBytes = 0;
    _setStatus(AuraLlmSetupStatus.downloading);

    final result = await _manager.installModel(
      onProgress: _onProgress,
      cancellation: _cancellation,
    );
    if (_disposed) return;
    if (result.isSuccess) {
      _receivedBytes = source.sizeBytes > 0 ? source.sizeBytes : _receivedBytes;
      _totalBytes = _receivedBytes;
      _bytesPerSecond = 0;
      _setStatus(AuraLlmSetupStatus.ready);
      await _warmUpModel();
      return;
    }
    if (result.error == AuraLlmInstallError.cancelled) {
      final snapshot = await _manager.inspect();
      _receivedBytes = snapshot.partialBytes ?? _receivedBytes;
      _errorCode = null;
      _bytesPerSecond = 0;
      _setStatus(
        snapshot.hasPartialDownload
            ? AuraLlmSetupStatus.paused
            : AuraLlmSetupStatus.notInstalled,
      );
      return;
    }
    _errorCode = _errorFor(result.error);
    final snapshot = await _manager.inspect();
    _receivedBytes = snapshot.partialBytes ?? 0;
    _bytesPerSecond = 0;
    _setStatus(AuraLlmSetupStatus.failed);
  }

  void cancelDownload() {
    if (_disposed) return;
    _cancellation?.cancel();
    if (_status == AuraLlmSetupStatus.downloading) {
      _bytesPerSecond = 0;
      _setStatus(AuraLlmSetupStatus.paused);
    }
  }

  Future<void> setPrefetchOnStartup(bool value) async {
    if (_disposed || _prefetchOnStartup == value) return;
    _prefetchOnStartup = value;
    try {
      final prefs = await _preferences();
      await prefs.setBool(_prefetchKey, value);
    } on Object {
      // Best effort; the in-memory preference still applies this session.
    }
    if (value && _status == AuraLlmSetupStatus.ready && !_runtimeReady) {
      await _warmUpModel();
    } else {
      _notify();
    }
  }

  Future<void> deleteModel() async {
    if (_disposed) return;
    _cancellation?.cancel();
    await _manager.deleteInstalled();
    try {
      await _unload?.call();
    } on Object {
      // The runtime may not exist on this build; deletion still succeeds.
    }
    _runtimeReady = false;
    _receivedBytes = 0;
    _totalBytes = null;
    _bytesPerSecond = 0;
    _errorCode = null;
    final snapshot = await _manager.inspect();
    _receivedBytes = snapshot.partialBytes ?? 0;
    _setStatus(
      snapshot.hasPartialDownload
          ? AuraLlmSetupStatus.paused
          : AuraLlmSetupStatus.notInstalled,
    );
  }

  Future<void> _warmUpModel() async {
    final warmUp = _warmUp;
    if (warmUp == null) {
      _runtimeReady = false;
      _notify();
      return;
    }
    _errorCode = null;
    _setStatus(AuraLlmSetupStatus.loading);
    try {
      final ready = await warmUp();
      if (_disposed) return;
      _runtimeReady = ready;
      if (!ready) _errorCode = 'llm_runtime_unavailable';
      _setStatus(AuraLlmSetupStatus.ready);
    } on Object {
      if (_disposed) return;
      _runtimeReady = false;
      _errorCode = 'llm_runtime_unavailable';
      _setStatus(AuraLlmSetupStatus.ready);
    }
  }

  void _onProgress(AuraLlmDownloadProgress progress) {
    if (_disposed) return;
    final now = DateTime.now();
    final previousAt = _lastProgressAt;
    if (previousAt != null) {
      final elapsedMicros = now.difference(previousAt).inMicroseconds;
      final delta = progress.receivedBytes - _lastProgressBytes;
      if (elapsedMicros > 0 && delta > 0) {
        final instant = delta / (elapsedMicros / 1000000);
        _bytesPerSecond = _bytesPerSecond == 0
            ? instant
            : (_bytesPerSecond * 0.7 + instant * 0.3);
      }
    }
    _lastProgressAt = now;
    _lastProgressBytes = progress.receivedBytes;
    _receivedBytes = progress.receivedBytes;
    _totalBytes = progress.totalBytes ?? _totalBytes;
    final total = _totalBytes;
    if (_status == AuraLlmSetupStatus.downloading &&
        total != null &&
        total > 0 &&
        progress.receivedBytes >= total) {
      _bytesPerSecond = 0;
      _setStatus(AuraLlmSetupStatus.verifying);
    } else {
      _notify();
    }
  }

  String _errorFor(AuraLlmInstallError? error) => switch (error) {
    AuraLlmInstallError.notConfigured => 'llm_model_not_configured',
    AuraLlmInstallError.storageUnavailable => 'llm_storage_unavailable',
    AuraLlmInstallError.insufficientStorage => 'llm_insufficient_storage',
    AuraLlmInstallError.network => 'llm_download_network',
    AuraLlmInstallError.httpStatus => 'llm_download_http',
    AuraLlmInstallError.sizeMismatch => 'llm_model_size_mismatch',
    AuraLlmInstallError.digestMismatch => 'llm_model_digest_mismatch',
    AuraLlmInstallError.io => 'llm_download_io',
    AuraLlmInstallError.cancelled => 'download_cancelled',
    null => 'llm_download_io',
  };

  void _setStatus(AuraLlmSetupStatus value) {
    if (_disposed) return;
    _status = value;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    super.dispose();
  }
}
