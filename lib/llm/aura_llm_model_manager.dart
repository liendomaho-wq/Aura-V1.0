import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../infrastructure/storage/aura_storage.dart';
import 'aura_llm_model_source.dart';

class AuraLlmDownloadProgress {
  const AuraLlmDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    final value = receivedBytes / total;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }
}

class AuraLlmCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

enum AuraLlmInstallError {
  notConfigured,
  storageUnavailable,
  insufficientStorage,
  network,
  httpStatus,
  sizeMismatch,
  digestMismatch,
  cancelled,
  io,
}

class AuraLlmInstallResult {
  const AuraLlmInstallResult.success(this.path) : error = null;

  const AuraLlmInstallResult.failure(this.error) : path = null;

  final String? path;
  final AuraLlmInstallError? error;

  bool get isSuccess => path != null;
}

class AuraLlmModelSnapshot {
  const AuraLlmModelSnapshot({
    required this.configured,
    required this.expectedBytes,
    required this.installedBytes,
    required this.partialBytes,
  });

  final bool configured;
  final int expectedBytes;
  final int? installedBytes;
  final int? partialBytes;

  bool get hasInstalledFile => installedBytes != null;

  bool get hasPartialDownload => (partialBytes ?? 0) > 0;
}

/// Boundary the setup controller depends on so tests can provide a
/// deterministic provisioner without touching files, network or Android.
abstract interface class AuraLlmModelProvisioner {
  AuraLlmModelSource get source;
  bool get isConfigured;
  int get expectedBytes;
  int get minimumFreeSpaceBytes;
  Future<AuraLlmModelSnapshot> inspect();
  Future<bool> verifyInstalled({AuraLlmHashProgressCallback? onHashProgress});
  Future<AuraLlmInstallResult> installModel({
    AuraLlmDownloadProgressCallback? onProgress,
    AuraLlmCancellation? cancellation,
    AuraLlmHashProgressCallback? onHashProgress,
  });
  Future<String?> resolveInstalledModel();
  Future<String?> resolveVerifiedModel();
  Future<void> deleteInstalled();
}

typedef AuraLlmDownloadProgressCallback =
    void Function(AuraLlmDownloadProgress progress);

typedef AuraLlmHashProgressCallback =
    void Function(int hashedBytes, int totalBytes);

/// Resolves, downloads and verifies the optional local GGUF model.
///
/// Fail-closed rules:
///  * Without a trusted SHA-256 (and a URL or an already installed file) no
///    path is ever returned, so llama.cpp is never pointed at an unverified
///    file.
///  * Downloads go to a `.partial` file inside the app support directory and
///    are renamed only after the SHA-256 matches.
///  * Size, scheme and free space are bounded; no path is accepted from the
///    model output or the network. The final path is always app-private.
///  * The agent order path never downloads. [resolveInstalledModel] only
///    returns an already verified file; the explicit setup flow uses
///    [installModel].
///
/// Configuration is build-time by default:
///   flutter build apk --dart-define=AURA_LLM_MODEL_URL=<https url> \
///                     --dart-define=AURA_LLM_MODEL_SHA256=<64 hex chars>
///                     --dart-define=AURA_LLM_MODEL_BYTES=<exact size>
class AuraLlmModelManager implements AuraLlmModelProvisioner {
  factory AuraLlmModelManager({
    AuraLlmModelSource? source,
    String? downloadUrl,
    String? expectedSha256,
    int? expectedBytes,
    int maxBytes = 4 * 1024 * 1024 * 1024,
    int minimumFreeSpaceBytes = 128 * 1024 * 1024,
    Duration downloadInactivityTimeout = const Duration(seconds: 90),
    Duration connectionTimeout = const Duration(seconds: 30),
    Duration maxDownloadDuration = const Duration(minutes: 60),
    Future<Directory> Function()? resolveDirectory,
    http.Client Function()? clientFactory,
    Future<int?> Function()? freeSpaceProvider,
  }) {
    final resolvedSource = source ?? AuraLlmModelSource.fromEnvironment();
    final useSourceDefaults =
        source != null || (downloadUrl == null && expectedSha256 == null);
    return AuraLlmModelManager._(
      source: resolvedSource,
      downloadUrl:
          (downloadUrl ?? (useSourceDefaults ? resolvedSource.downloadUrl : ''))
              .trim(),
      expectedSha256:
          (expectedSha256 ?? (useSourceDefaults ? resolvedSource.sha256 : ''))
              .trim()
              .toLowerCase(),
      expectedBytes:
          expectedBytes ?? (useSourceDefaults ? resolvedSource.sizeBytes : 0),
      maxBytes: maxBytes,
      minimumFreeSpaceBytes: minimumFreeSpaceBytes,
      downloadInactivityTimeout: downloadInactivityTimeout,
      connectionTimeout: connectionTimeout,
      maxDownloadDuration: maxDownloadDuration,
      resolveDirectory: resolveDirectory ?? getApplicationSupportDirectory,
      clientFactory: clientFactory ?? http.Client.new,
      freeSpaceProvider: freeSpaceProvider ?? AuraStorage().freeBytes,
    );
  }

  AuraLlmModelManager._({
    required this.source,
    required String downloadUrl,
    required String expectedSha256,
    required int expectedBytes,
    required this.maxBytes,
    required this.minimumFreeSpaceBytes,
    required this.downloadInactivityTimeout,
    required this.connectionTimeout,
    required this.maxDownloadDuration,
    required Future<Directory> Function() resolveDirectory,
    required http.Client Function() clientFactory,
    required Future<int?> Function()? freeSpaceProvider,
  }) : _downloadUrl = downloadUrl,
       _expectedSha256 = expectedSha256,
       _expectedBytes = expectedBytes,
       _resolveDirectory = resolveDirectory,
       _clientFactory = clientFactory,
       _freeSpaceProvider = freeSpaceProvider;

  static final RegExp _digestPattern = RegExp(r'^[0-9a-f]{64}$');
  static const String _installedFileName = AuraLlmModelSource.installedFileName;

  final AuraLlmModelSource source;
  final int maxBytes;
  final int minimumFreeSpaceBytes;
  final Duration downloadInactivityTimeout;
  final Duration connectionTimeout;
  final Duration maxDownloadDuration;
  final String _downloadUrl;
  final String _expectedSha256;
  final int _expectedBytes;
  final Future<Directory> Function() _resolveDirectory;
  final http.Client Function() _clientFactory;
  final Future<int?> Function()? _freeSpaceProvider;

  Future<AuraLlmInstallResult>? _installFuture;
  Future<String?>? _resolveFuture;

  String? _verifiedPath;
  int? _verifiedLength;
  DateTime? _verifiedModified;

  bool get isConfigured => _digestPattern.hasMatch(_expectedSha256);

  int get expectedBytes => _expectedBytes;

  String get expectedSha256 => _expectedSha256;

  String get downloadUrl => _downloadUrl;

  Future<String?> resolveVerifiedModel() {
    final pending = _resolveFuture;
    if (pending != null) return pending;
    final mapped = installModel().then((result) => result.path);
    _resolveFuture = mapped;
    return mapped;
  }

  Future<AuraLlmInstallResult> installModel({
    AuraLlmDownloadProgressCallback? onProgress,
    AuraLlmCancellation? cancellation,
    AuraLlmHashProgressCallback? onHashProgress,
  }) {
    final pending = _installFuture;
    if (pending != null) return pending;
    final future =
        _resolveOrDownload(
          onProgress: onProgress,
          cancellation: cancellation,
          onHashProgress: onHashProgress,
        ).whenComplete(() {
          _installFuture = null;
          _resolveFuture = null;
        });
    _installFuture = future;
    return future;
  }

  /// Returns the installed model only if its pinned size and SHA-256 match.
  ///
  /// Never performs network I/O. This is the path used by the agent.
  Future<String?> resolveInstalledModel() async {
    if (!isConfigured) return null;
    final Directory directory;
    try {
      directory = await _modelDirectory();
    } on Object {
      return null;
    }
    final target = File(
      '${directory.path}${Platform.pathSeparator}$_installedFileName',
    );
    try {
      if (!await target.exists()) return null;
      if (_expectedBytes > 0 && await target.length() != _expectedBytes) {
        await _deleteIfPresent(target);
        _clearVerifiedCache();
        return null;
      }
      if (await _isCachedVerified(target)) return target.path;
      if (await _matchesDigest(target)) return target.path;
      await _deleteIfPresent(target);
      _clearVerifiedCache();
      return null;
    } on Object {
      return null;
    }
  }

  Future<bool> verifyInstalled({
    AuraLlmHashProgressCallback? onHashProgress,
  }) async {
    if (!isConfigured) return false;
    final Directory directory;
    try {
      directory = await _modelDirectory();
    } on Object {
      return false;
    }
    final target = File(
      '${directory.path}${Platform.pathSeparator}$_installedFileName',
    );
    try {
      if (!await target.exists()) return false;
      if (_expectedBytes > 0 && await target.length() != _expectedBytes) {
        await _deleteIfPresent(target);
        _clearVerifiedCache();
        return false;
      }
      if (await _isCachedVerified(target)) return true;
      if (await _matchesDigest(target, onHashProgress: onHashProgress)) {
        return true;
      }
      await _deleteIfPresent(target);
      _clearVerifiedCache();
      return false;
    } on Object {
      return false;
    }
  }

  Future<AuraLlmModelSnapshot> inspect() async {
    final Directory directory;
    try {
      directory = await _modelDirectory();
    } on Object {
      return AuraLlmModelSnapshot(
        configured: isConfigured,
        expectedBytes: _expectedBytes,
        installedBytes: null,
        partialBytes: null,
      );
    }
    final target = File(
      '${directory.path}${Platform.pathSeparator}$_installedFileName',
    );
    final partial = File('${target.path}.partial');
    int? installedBytes;
    int? partialBytes;
    try {
      if (await target.exists()) installedBytes = await target.length();
      if (await partial.exists()) partialBytes = await partial.length();
    } on Object {
      // A transient stat failure is reported as an unknown size.
    }
    return AuraLlmModelSnapshot(
      configured: isConfigured,
      expectedBytes: _expectedBytes,
      installedBytes: installedBytes,
      partialBytes: partialBytes,
    );
  }

  Future<void> deleteInstalled() async {
    final Directory directory;
    try {
      directory = await _modelDirectory();
    } on Object {
      _clearVerifiedCache();
      return;
    }
    final target = File(
      '${directory.path}${Platform.pathSeparator}$_installedFileName',
    );
    await _deleteIfPresent(target);
    await _deleteIfPresent(File('${target.path}.partial'));
    _clearVerifiedCache();
  }

  Future<AuraLlmInstallResult> _resolveOrDownload({
    AuraLlmDownloadProgressCallback? onProgress,
    AuraLlmCancellation? cancellation,
    AuraLlmHashProgressCallback? onHashProgress,
  }) async {
    if (!isConfigured) {
      return const AuraLlmInstallResult.failure(
        AuraLlmInstallError.notConfigured,
      );
    }
    final Directory directory;
    try {
      directory = await _modelDirectory();
    } on Object {
      return const AuraLlmInstallResult.failure(
        AuraLlmInstallError.storageUnavailable,
      );
    }
    final target = File(
      '${directory.path}${Platform.pathSeparator}$_installedFileName',
    );
    try {
      if (await _isCachedVerified(target)) {
        final length = await target.length();
        onProgress?.call(
          AuraLlmDownloadProgress(
            receivedBytes: length,
            totalBytes: _expectedBytes > 0 ? _expectedBytes : length,
          ),
        );
        return AuraLlmInstallResult.success(target.path);
      }
      if (await target.exists()) {
        if (await _matchesDigest(target, onHashProgress: onHashProgress)) {
          final length = await target.length();
          onProgress?.call(
            AuraLlmDownloadProgress(
              receivedBytes: length,
              totalBytes: _expectedBytes > 0 ? _expectedBytes : length,
            ),
          );
          return AuraLlmInstallResult.success(target.path);
        }
        await _deleteIfPresent(target);
        _clearVerifiedCache();
      }
    } on Object {
      await _deleteIfPresent(target);
      _clearVerifiedCache();
      return const AuraLlmInstallResult.failure(AuraLlmInstallError.io);
    }
    if (_downloadUrl.isEmpty) {
      return const AuraLlmInstallResult.failure(
        AuraLlmInstallError.notConfigured,
      );
    }
    return _downloadVerified(
      target,
      onProgress: onProgress,
      cancellation: cancellation,
      onHashProgress: onHashProgress,
    );
  }

  Future<AuraLlmInstallResult> _downloadVerified(
    File target, {
    AuraLlmDownloadProgressCallback? onProgress,
    AuraLlmCancellation? cancellation,
    AuraLlmHashProgressCallback? onHashProgress,
  }) async {
    final uri = Uri.tryParse(_downloadUrl);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
      return const AuraLlmInstallResult.failure(
        AuraLlmInstallError.notConfigured,
      );
    }
    final temporary = File('${target.path}.partial');
    http.Client? client;
    IOSink? sink;
    var keepPartial = true;
    try {
      var startAt = 0;
      if (await temporary.exists()) startAt = await temporary.length();
      if (_expectedBytes > 0 && startAt > _expectedBytes) {
        await _deleteIfPresent(temporary);
        startAt = 0;
      }
      if (_expectedBytes > 0 && startAt == _expectedBytes) {
        if (await _matchesDigest(temporary, onHashProgress: onHashProgress)) {
          await temporary.rename(target.path);
          await _rememberVerified(target);
          onProgress?.call(
            AuraLlmDownloadProgress(
              receivedBytes: _expectedBytes,
              totalBytes: _expectedBytes,
            ),
          );
          return AuraLlmInstallResult.success(target.path);
        }
        await _deleteIfPresent(temporary);
        startAt = 0;
      }

      int? free;
      try {
        free = await _freeSpaceProvider?.call();
      } on Object {
        free = null;
      }
      if (free != null && _expectedBytes > 0) {
        final remaining = _expectedBytes - startAt;
        if (remaining > 0 && free < remaining + minimumFreeSpaceBytes) {
          return const AuraLlmInstallResult.failure(
            AuraLlmInstallError.insufficientStorage,
          );
        }
      }
      if (cancellation?.isCancelled == true) {
        return const AuraLlmInstallResult.failure(
          AuraLlmInstallError.cancelled,
        );
      }

      client = _clientFactory();
      final request = http.Request('GET', uri);
      if (startAt > 0) request.headers['Range'] = 'bytes=$startAt-';
      final response = await client.send(request).timeout(connectionTimeout);

      var append = startAt > 0;
      if (append) {
        if (response.statusCode == 200) {
          append = false;
          startAt = 0;
          await _deleteIfPresent(temporary);
        } else if (response.statusCode != 206) {
          keepPartial = false;
          await _deleteIfPresent(temporary);
          return const AuraLlmInstallResult.failure(
            AuraLlmInstallError.httpStatus,
          );
        }
      } else if (response.statusCode != 200) {
        keepPartial = false;
        await _deleteIfPresent(temporary);
        return const AuraLlmInstallResult.failure(
          AuraLlmInstallError.httpStatus,
        );
      }

      final declared = response.contentLength;
      int? total;
      if (declared != null) {
        total = startAt + declared;
        if (total > maxBytes ||
            (_expectedBytes > 0 && total != _expectedBytes)) {
          keepPartial = false;
          await _deleteIfPresent(temporary);
          return const AuraLlmInstallResult.failure(
            AuraLlmInstallError.sizeMismatch,
          );
        }
      } else if (_expectedBytes > 0) {
        total = _expectedBytes;
      }

      sink = temporary.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      var received = startAt;
      onProgress?.call(
        AuraLlmDownloadProgress(receivedBytes: received, totalBytes: total),
      );
      final transfer = await _transfer(
        response,
        sink,
        startAt: startAt,
        total: total,
        cancellation: cancellation,
        onProgress: onProgress,
      ).timeout(maxDownloadDuration);
      received = transfer.receivedBytes;
      await sink.flush();
      await sink.close();
      sink = null;

      final outcome = transfer.outcome;
      if (outcome != _TransferOutcome.complete) {
        if (outcome == _TransferOutcome.cancelled) {
          return const AuraLlmInstallResult.failure(
            AuraLlmInstallError.cancelled,
          );
        }
        if (outcome == _TransferOutcome.sizeMismatch ||
            outcome == _TransferOutcome.tooLarge) {
          keepPartial = false;
          await _deleteIfPresent(temporary);
          return const AuraLlmInstallResult.failure(
            AuraLlmInstallError.sizeMismatch,
          );
        }
        return const AuraLlmInstallResult.failure(AuraLlmInstallError.network);
      }
      if (_expectedBytes > 0 && received != _expectedBytes) {
        keepPartial = false;
        await _deleteIfPresent(temporary);
        return const AuraLlmInstallResult.failure(
          AuraLlmInstallError.sizeMismatch,
        );
      }

      if (!await _matchesDigest(temporary, onHashProgress: onHashProgress)) {
        keepPartial = false;
        await _deleteIfPresent(temporary);
        return const AuraLlmInstallResult.failure(
          AuraLlmInstallError.digestMismatch,
        );
      }
      await temporary.rename(target.path);
      await _rememberVerified(target);
      onProgress?.call(
        AuraLlmDownloadProgress(
          receivedBytes: received,
          totalBytes: total ?? received,
        ),
      );
      return AuraLlmInstallResult.success(target.path);
    } on TimeoutException {
      client?.close();
      keepPartial = true;
      return const AuraLlmInstallResult.failure(AuraLlmInstallError.network);
    } on Object {
      client?.close();
      if (!keepPartial) await _deleteIfPresent(temporary);
      return const AuraLlmInstallResult.failure(AuraLlmInstallError.io);
    } finally {
      try {
        await sink?.close();
      } on Object {
        // A failed close after a terminal decision is already reflected there.
      }
      client?.close();
      if (!keepPartial) await _deleteIfPresent(temporary);
    }
  }

  Future<_TransferResult> _transfer(
    http.StreamedResponse response,
    IOSink sink, {
    required int startAt,
    required int? total,
    AuraLlmCancellation? cancellation,
    AuraLlmDownloadProgressCallback? onProgress,
  }) async {
    var received = startAt;
    _TransferResult finish(_TransferOutcome outcome) =>
        _TransferResult(outcome, received);
    try {
      await for (final chunk in response.stream.timeout(
        downloadInactivityTimeout,
      )) {
        if (cancellation?.isCancelled == true) {
          return finish(_TransferOutcome.cancelled);
        }
        received += chunk.length;
        if (received > maxBytes) return finish(_TransferOutcome.tooLarge);
        if (_expectedBytes > 0 && received > _expectedBytes) {
          return finish(_TransferOutcome.sizeMismatch);
        }
        sink.add(chunk);
        onProgress?.call(
          AuraLlmDownloadProgress(receivedBytes: received, totalBytes: total),
        );
      }
      return finish(_TransferOutcome.complete);
    } on TimeoutException {
      return finish(_TransferOutcome.network);
    } on Object {
      return finish(_TransferOutcome.network);
    }
  }

  Future<bool> _isCachedVerified(File file) async {
    if (_verifiedPath != file.path) return false;
    try {
      final stat = await file.stat();
      return stat.type == FileSystemEntityType.file &&
          stat.size == _verifiedLength &&
          stat.modified == _verifiedModified;
    } on Object {
      return false;
    }
  }

  Future<void> _rememberVerified(File file) async {
    try {
      final stat = await file.stat();
      _verifiedPath = file.path;
      _verifiedLength = stat.size;
      _verifiedModified = stat.modified;
    } on Object {
      _clearVerifiedCache();
    }
  }

  void _clearVerifiedCache() {
    _verifiedPath = null;
    _verifiedLength = null;
    _verifiedModified = null;
  }

  Future<Directory> _modelDirectory() async {
    final base = await _resolveDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}models');
    await directory.create(recursive: true);
    return directory;
  }

  Future<bool> _matchesDigest(
    File file, {
    AuraLlmHashProgressCallback? onHashProgress,
  }) async {
    try {
      final total = await file.length();
      final output = _DigestSink();
      final input = sha256.startChunkedConversion(output);
      var hashed = 0;
      await for (final chunk in file.openRead()) {
        input.add(chunk);
        hashed += chunk.length;
        onHashProgress?.call(hashed, total);
      }
      input.close();
      final digest = output.value;
      if (digest == null || digest.toString() != _expectedSha256) return false;
      await _rememberVerified(file);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // Best effort: a leftover .partial file is never loaded.
    }
  }
}

enum _TransferOutcome { complete, cancelled, network, tooLarge, sizeMismatch }

class _TransferResult {
  const _TransferResult(this.outcome, this.receivedBytes);

  final _TransferOutcome outcome;
  final int receivedBytes;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
