import 'dart:async';

import 'package:aura_mobile_defens/infrastructure/storage/aura_storage.dart';
import 'package:aura_mobile_defens/llm/aura_llm_model_manager.dart';
import 'package:aura_mobile_defens/llm/aura_llm_model_source.dart';
import 'package:aura_mobile_defens/llm/aura_llm_setup_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _source = AuraLlmModelSource(
  displayName: 'Test model',
  parameters: '1.5B',
  quantization: 'Q4_K_M',
  license: 'Apache-2.0',
  downloadUrl: 'https://example.test/model.gguf',
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  sizeBytes: 1024,
  publisher: 'tests',
  revision: '0123456789abcdef',
);

class _FakeStorage extends AuraStorage {
  _FakeStorage(this.value);

  final int? value;

  @override
  Future<int?> freeBytes() async => value;
}

class _FakeProvisioner implements AuraLlmModelProvisioner {
  _FakeProvisioner({
    this.configured = true,
    this.installed = false,
    this.verify = true,
    this.partialBytes = 0,
    this.onInstall,
  });

  @override
  final AuraLlmModelSource source = _source;

  bool configured;
  bool installed;
  bool verify;
  int partialBytes;

  @override
  int get expectedBytes => 1024;

  @override
  int get minimumFreeSpaceBytes => 0;

  @override
  bool get isConfigured => configured;

  int installCalls = 0;
  int deleteCalls = 0;
  int resolveCalls = 0;

  Future<AuraLlmInstallResult> Function(
    AuraLlmDownloadProgressCallback? onProgress,
    AuraLlmCancellation? cancellation,
  )?
  onInstall;

  @override
  Future<AuraLlmModelSnapshot> inspect() async => AuraLlmModelSnapshot(
    configured: configured,
    expectedBytes: expectedBytes,
    installedBytes: installed ? 1024 : null,
    partialBytes: partialBytes,
  );

  @override
  Future<bool> verifyInstalled({
    AuraLlmHashProgressCallback? onHashProgress,
  }) async {
    if (onHashProgress != null && installed) {
      onHashProgress(1024, 1024);
    }
    return verify;
  }

  @override
  Future<AuraLlmInstallResult> installModel({
    AuraLlmDownloadProgressCallback? onProgress,
    AuraLlmCancellation? cancellation,
    AuraLlmHashProgressCallback? onHashProgress,
  }) async {
    installCalls++;
    final handler = onInstall;
    if (handler == null) {
      installed = true;
      onProgress?.call(
        const AuraLlmDownloadProgress(receivedBytes: 1024, totalBytes: 1024),
      );
      return const AuraLlmInstallResult.success('/fake/model.gguf');
    }
    final result = await handler(onProgress, cancellation);
    if (result.isSuccess) installed = true;
    return result;
  }

  @override
  Future<String?> resolveInstalledModel() async {
    resolveCalls++;
    return installed ? '/fake/model.gguf' : null;
  }

  @override
  Future<String?> resolveVerifiedModel() => resolveInstalledModel();

  @override
  Future<void> deleteInstalled() async {
    deleteCalls++;
    installed = false;
    partialBytes = 0;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<AuraLlmSetupController> build({
    _FakeProvisioner? provisioner,
    int? freeBytes = 1 << 20,
    Future<bool> Function()? warmUp,
    Future<void> Function()? unload,
  }) async {
    final controller = AuraLlmSetupController(
      source: _source,
      manager: provisioner ?? _FakeProvisioner(),
      storage: _FakeStorage(freeBytes),
      warmUp: warmUp,
      unload: unload,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    return controller;
  }

  test('reports Basic mode when no model is installed', () async {
    final controller = await build();

    expect(controller.status, AuraLlmSetupStatus.notInstalled);
    expect(controller.statusLabel, contains('preparar IA'));
    expect(controller.freeBytes, 1 << 20);
    expect(controller.receivedBytes, 0);
    expect(controller.minimumFreeSpaceBytes, 0);
    expect(controller.progress, isNull);
  });

  test('reports paused with the partial prefix already on disk', () async {
    final controller = await build(
      provisioner: _FakeProvisioner(partialBytes: 300),
    );

    expect(controller.status, AuraLlmSetupStatus.paused);
    expect(controller.receivedBytes, 300);
  });

  test('reports not configured when the build has no pin', () async {
    final controller = await build(
      provisioner: _FakeProvisioner(configured: false),
    );

    expect(controller.status, AuraLlmSetupStatus.notConfigured);
    expect(controller.statusLabel, 'Aura Básica');
  });

  test('verifies and warms up an installed model on startup', () async {
    var warmUps = 0;
    final controller = await build(
      provisioner: _FakeProvisioner(installed: true),
      warmUp: () async {
        warmUps++;
        return true;
      },
    );

    expect(warmUps, 1);
    expect(controller.status, AuraLlmSetupStatus.ready);
    expect(controller.runtimeReady, isTrue);
    expect(controller.statusLabel, 'IA local lista');
    expect(controller.hasConsent, isFalse);
  });

  test('does not warm up when prefetch is disabled', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aura.llm.prefetch.v1': false,
    });
    var warmUps = 0;
    final controller = await build(
      provisioner: _FakeProvisioner(installed: true),
      warmUp: () async {
        warmUps++;
        return true;
      },
    );

    expect(warmUps, 0);
    expect(controller.status, AuraLlmSetupStatus.ready);
    expect(controller.runtimeReady, isFalse);
  });

  test('keeps the file verified but flags a missing runtime', () async {
    final controller = await build(
      provisioner: _FakeProvisioner(installed: true),
      warmUp: () async => false,
    );

    expect(controller.status, AuraLlmSetupStatus.ready);
    expect(controller.runtimeReady, isFalse);
    expect(controller.errorCode, 'llm_runtime_unavailable');
    expect(controller.statusLabel, 'Modelo verificado');
  });

  test('requires explicit consent before moving bytes', () async {
    final provisioner = _FakeProvisioner();
    final controller = await build(provisioner: provisioner);

    await controller.startDownload(consent: false);

    expect(provisioner.installCalls, 0);
    expect(controller.errorCode, 'consent_required');
    expect(controller.hasConsent, isFalse);
  });

  test('persists consent, downloads and warms up the model', () async {
    var warmUps = 0;
    final provisioner = _FakeProvisioner();
    final controller = await build(
      provisioner: provisioner,
      warmUp: () async {
        warmUps++;
        return true;
      },
    );
    final statuses = <AuraLlmSetupStatus>[];
    controller.addListener(() => statuses.add(controller.status));

    await controller.startDownload(consent: true);

    expect(provisioner.installCalls, 1);
    expect(controller.hasConsent, isTrue);
    expect(controller.status, AuraLlmSetupStatus.ready);
    expect(controller.runtimeReady, isTrue);
    expect(controller.receivedBytes, 1024);
    expect(controller.errorCode, isNull);
    expect(warmUps, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('aura.llm.consent.v1'), isTrue);
    expect(statuses, contains(AuraLlmSetupStatus.downloading));
    expect(statuses, contains(AuraLlmSetupStatus.verifying));
    expect(statuses, contains(AuraLlmSetupStatus.loading));
  });

  test('maps installer failures to explicit Spanish messages', () async {
    final provisioner = _FakeProvisioner(
      onInstall: (onProgress, cancellation) async =>
          const AuraLlmInstallResult.failure(
            AuraLlmInstallError.insufficientStorage,
          ),
    );
    final controller = await build(provisioner: provisioner);

    await controller.startDownload(consent: true);

    expect(controller.status, AuraLlmSetupStatus.failed);
    expect(controller.errorCode, 'llm_insufficient_storage');
    expect(controller.errorMessage, contains('espacio libre'));
  });

  test('cancelling pauses and keeps the partial bytes', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final provisioner = _FakeProvisioner(
      partialBytes: 300,
      onInstall: (onProgress, cancellation) async {
        onProgress?.call(
          const AuraLlmDownloadProgress(receivedBytes: 300, totalBytes: 1024),
        );
        started.complete();
        await gate.future;
        if (cancellation?.isCancelled ?? false) {
          return const AuraLlmInstallResult.failure(
            AuraLlmInstallError.cancelled,
          );
        }
        return const AuraLlmInstallResult.success('/fake/model.gguf');
      },
    );
    final controller = await build(provisioner: provisioner);

    final download = controller.startDownload(consent: true);
    await started.future;
    expect(controller.status, AuraLlmSetupStatus.downloading);
    controller.cancelDownload();
    gate.complete();
    await download;

    expect(controller.status, AuraLlmSetupStatus.paused);
    expect(controller.receivedBytes, 300);
    expect(controller.errorCode, isNull);
  });

  test('cancelling does not start a second concurrent install', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final provisioner = _FakeProvisioner(
      partialBytes: 300,
      onInstall: (onProgress, cancellation) async {
        started.complete();
        await gate.future;
        if (cancellation?.isCancelled ?? false) {
          return const AuraLlmInstallResult.failure(
            AuraLlmInstallError.cancelled,
          );
        }
        return const AuraLlmInstallResult.success('/fake/model.gguf');
      },
    );
    final controller = await build(provisioner: provisioner);

    final first = controller.startDownload(consent: true);
    await started.future;
    controller.cancelDownload();
    await controller.startDownload(consent: true);

    expect(provisioner.installCalls, 1);
    gate.complete();
    await first;
    expect(controller.status, AuraLlmSetupStatus.paused);
  });

  test('deleting waits for a cancelled install to release the file', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final provisioner = _FakeProvisioner(
      partialBytes: 300,
      onInstall: (onProgress, cancellation) async {
        started.complete();
        await gate.future;
        return const AuraLlmInstallResult.failure(
          AuraLlmInstallError.cancelled,
        );
      },
    );
    final controller = await build(provisioner: provisioner);

    final download = controller.startDownload(consent: true);
    await started.future;
    controller.cancelDownload();
    final deletion = controller.deleteModel();
    await Future<void>.delayed(Duration.zero);

    expect(provisioner.deleteCalls, 0);
    gate.complete();
    await deletion;
    await download;

    expect(provisioner.deleteCalls, 1);
    expect(controller.status, AuraLlmSetupStatus.notInstalled);
    expect(controller.receivedBytes, 0);
  });

  test('deleting the model unloads the runtime before deleting it', () async {
    var unloads = 0;
    final provisioner = _FakeProvisioner(installed: true);
    final controller = await build(
      provisioner: provisioner,
      warmUp: () async => true,
      unload: () async {
        expect(provisioner.installed, isTrue);
        expect(provisioner.deleteCalls, 0);
        unloads++;
      },
    );
    expect(controller.isReady, isTrue);

    await controller.deleteModel();

    expect(unloads, 1);
    expect(provisioner.deleteCalls, 1);
    expect(controller.status, AuraLlmSetupStatus.notInstalled);
    expect(controller.receivedBytes, 0);
    expect(controller.runtimeReady, isFalse);
  });

  test('does not delete the model when the runtime cannot unload', () async {
    final provisioner = _FakeProvisioner(installed: true);
    final controller = await build(
      provisioner: provisioner,
      warmUp: () async => true,
      unload: () async => throw StateError('llm_busy'),
    );
    expect(controller.isReady, isTrue);

    await controller.deleteModel();

    expect(provisioner.deleteCalls, 0);
    expect(provisioner.installed, isTrue);
    expect(controller.status, AuraLlmSetupStatus.failed);
    expect(controller.errorCode, 'llm_unload_failed');
    expect(controller.errorMessage, contains('operación en curso'));
  });

  test('enabling prefetch loads an already verified model', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aura.llm.prefetch.v1': false,
    });
    var warmUps = 0;
    final controller = await build(
      provisioner: _FakeProvisioner(installed: true),
      warmUp: () async {
        warmUps++;
        return true;
      },
    );
    expect(controller.runtimeReady, isFalse);

    await controller.setPrefetchOnStartup(true);

    expect(warmUps, 1);
    expect(controller.runtimeReady, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('aura.llm.prefetch.v1'), isTrue);
  });

  test('drops an installed file whose digest no longer matches', () async {
    final controller = await build(
      provisioner: _FakeProvisioner(installed: true, verify: false),
    );

    expect(controller.status, AuraLlmSetupStatus.notInstalled);
    expect(controller.errorCode, 'llm_model_digest_mismatch');
    expect(controller.receivedBytes, 0);
  });
}
