import 'dart:async';

import 'package:flutter/foundation.dart';

import 'aura_llm_model_manager.dart';
import 'local_llm_planner.dart';

/// Lifecycle of the optional local AI engine as seen by the operator.
enum LocalLlmSetupStatus {
  /// Reading the installed file and asking the native runtime.
  checking,

  /// This build has no trusted model URL + SHA-256; nothing can be prepared.
  unconfigured,

  /// Configured but not downloaded, or downloaded but not loaded yet.
  idle,

  /// Downloading, verifying or loading.
  preparing,

  /// Verified and loaded in the native runtime.
  ready,

  /// Download, digest or load failed. The app stays on deterministic NLU.
  failed,
}

/// Coordinates the one-time model preparation shown to the operator.
///
/// It reuses [AuraLlmModelManager.shared] and the same planner boundary as the
/// agent, so a download started here is the only writer of the `.partial` file
/// and the model is loaded into the process-wide native runtime.
class LocalLlmSetupController extends ChangeNotifier {
  LocalLlmSetupController({
    AuraLlmModelManager? modelManager,
    LocalLlmPlanner? planner,
  }) : _modelManager = modelManager ?? AuraLlmModelManager.shared,
       _planner =
           planner ??
           LocalLlmPlanner(
             modelManager: modelManager ?? AuraLlmModelManager.shared,
           ) {
    _progressSubscription = _modelManager.progress.listen(_onProgress);
  }

  final AuraLlmModelManager _modelManager;
  final LocalLlmPlanner _planner;
  late final StreamSubscription<AuraLlmModelProgress> _progressSubscription;

  LocalLlmSetupStatus _status = LocalLlmSetupStatus.checking;
  AuraLlmModelProgress? _progress;
  String? _errorCode;
  bool _preparing = false;
  bool _disposed = false;

  LocalLlmSetupStatus get status => _status;
  AuraLlmModelPhase? get phase => _progress?.phase;
  bool get isConfigured => _modelManager.isConfigured;
  bool get isPreparing => _preparing;
  String? get errorCode => _errorCode;
  int get receivedBytes => _progress?.receivedBytes ?? 0;
  int? get totalBytes => _progress?.totalBytes;
  double? get fraction => _progress?.fraction;

  /// Inspects what is already installed without touching the network.
  Future<void> refresh() async {
    if (!_modelManager.isConfigured) {
      _setStatus(LocalLlmSetupStatus.unconfigured);
      return;
    }
    _setStatus(LocalLlmSetupStatus.checking);
    final installed = await _modelManager.resolveInstalledModel();
    if (installed == null) {
      _setStatus(LocalLlmSetupStatus.idle);
      return;
    }
    final ready = await _planner.isModelReady();
    _setStatus(ready ? LocalLlmSetupStatus.ready : LocalLlmSetupStatus.idle);
  }

  /// Downloads (if needed), verifies and loads the pinned model.
  ///
  /// Safe to call twice: a second call is ignored while one is in flight. The
  /// underlying manager is single-flight even across callers.
  Future<void> prepare() async {
    if (_preparing) return;
    if (!_modelManager.isConfigured) {
      _setStatus(LocalLlmSetupStatus.unconfigured);
      return;
    }
    _preparing = true;
    _errorCode = null;
    _setStatus(LocalLlmSetupStatus.preparing);
    try {
      final path = await _modelManager.resolveVerifiedModel();
      if (path == null) {
        _errorCode = _errorCode ?? 'model_unavailable';
        _setStatus(LocalLlmSetupStatus.failed);
        return;
      }
      await _planner.prefetchModel();
      final ready = await _planner.isModelReady();
      _errorCode = ready ? null : 'model_load_failed';
      _setStatus(
        ready ? LocalLlmSetupStatus.ready : LocalLlmSetupStatus.failed,
      );
    } on Object {
      _errorCode = 'model_prepare_failed';
      _setStatus(LocalLlmSetupStatus.failed);
    } finally {
      _preparing = false;
      _notify();
    }
  }

  void _onProgress(AuraLlmModelProgress progress) {
    _progress = progress;
    if (progress.phase == AuraLlmModelPhase.failed) {
      _errorCode = progress.errorCode ?? _errorCode;
    }
    _notify();
  }

  void _setStatus(LocalLlmSetupStatus status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_progressSubscription.cancel());
    super.dispose();
  }
}
