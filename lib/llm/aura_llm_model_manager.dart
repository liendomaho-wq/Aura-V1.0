import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Observable phase of the on-device model preparation.
enum AuraLlmModelPhase { downloading, verifying, ready, failed }

/// One progress sample for the model download.
///
/// The UI only needs [fraction] and the phase; byte counters stay available for
/// diagnostics. A failed sample carries a stable [errorCode], never a path.
class AuraLlmModelProgress {
  const AuraLlmModelProgress(
    this.phase, {
    this.receivedBytes = 0,
    this.totalBytes,
    this.errorCode,
  });

  final AuraLlmModelPhase phase;
  final int receivedBytes;
  final int? totalBytes;
  final String? errorCode;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }
}

/// Resolves, downloads and verifies the optional local GGUF model.
///
/// Fail-closed rules:
///  * Without a build-time trusted SHA-256 (and a URL or an already installed
///    file) no path is ever returned, so llama.cpp is never pointed at an
///    unverified file.
///  * Downloads go to a `.partial` file inside the app support directory and
///    are renamed only after the SHA-256 matches.
///  * Size and scheme are bounded; no path is accepted from the model output
///    or the network. The final path is always app-private.
///
/// Configuration is intentionally build-time only:
///   flutter build apk --dart-define=AURA_LLM_MODEL_URL=<https url> \
///                     --dart-define=AURA_LLM_MODEL_SHA256=<64 hex chars>
///
/// [shared] is the process-wide instance. The agent planner and the preparation
/// UI must use the same instance so two callers never write the same `.partial`
/// file with independent single-flight state.
class AuraLlmModelManager {
  AuraLlmModelManager({
    String downloadUrl = const String.fromEnvironment('AURA_LLM_MODEL_URL'),
    String expectedSha256 = const String.fromEnvironment(
      'AURA_LLM_MODEL_SHA256',
    ),
    this.maxBytes = 4 * 1024 * 1024 * 1024,
    Future<Directory> Function()? resolveDirectory,
    http.Client Function()? clientFactory,
  }) : _downloadUrl = downloadUrl.trim(),
       _expectedSha256 = expectedSha256.trim().toLowerCase(),
       _resolveDirectory = resolveDirectory ?? getApplicationSupportDirectory,
       _clientFactory = clientFactory ?? http.Client.new;

  /// Process-wide default. Tests build isolated managers explicitly.
  static final AuraLlmModelManager shared = AuraLlmModelManager();

  static const String _installedFileName = 'aura-local.gguf';
  static const Duration _downloadTimeout = Duration(minutes: 15);
  static final RegExp _digestPattern = RegExp(r'^[0-9a-f]{64}$');
  static const int _progressChunkBytes = 1024 * 1024;

  final String _downloadUrl;
  final String _expectedSha256;
  final int maxBytes;
  final Future<Directory> Function() _resolveDirectory;
  final http.Client Function() _clientFactory;

  /// Single-flight: an abandoned caller must not start a second download or
  /// delete the `.partial` file another resolution is still writing.
  Future<String?>? _resolveFuture;

  final StreamController<AuraLlmModelProgress> _progressController =
      StreamController<AuraLlmModelProgress>.broadcast();

  /// Download and verification samples. Broadcast; late listeners only see the
  /// next sample, so the preparation UI asks [resolveInstalledModel] on open.
  Stream<AuraLlmModelProgress> get progress => _progressController.stream;

  /// True only when a trusted build-time digest is configured. A URL is only
  /// needed when the verified file is not installed yet.
  bool get isConfigured => _digestPattern.hasMatch(_expectedSha256);

  /// Returns the absolute path of a digest-verified GGUF, or null.
  Future<String?> resolveVerifiedModel() {
    final pending = _resolveFuture;
    if (pending != null) return pending;
    final future = _resolveOrDownload().whenComplete(() {
      _resolveFuture = null;
    });
    _resolveFuture = future;
    return future;
  }

  /// Returns an already installed and digest-verified model without any
  /// network access. Used to warm the runtime at app start.
  Future<String?> resolveInstalledModel() async {
    if (!isConfigured) return null;
    try {
      final target = await _installedFile();
      if (!await target.exists()) return null;
      return await _matchesDigest(target) ? target.path : null;
    } on Object {
      return null;
    }
  }

  Future<String?> _resolveOrDownload() async {
    if (!isConfigured) return null;
    final File target;
    try {
      target = await _installedFile();
    } on Object {
      _report(
        const AuraLlmModelProgress(
          AuraLlmModelPhase.failed,
          errorCode: 'model_directory_unavailable',
        ),
      );
      return null;
    }
    if (await target.exists()) {
      if (await _matchesDigest(target)) {
        _report(const AuraLlmModelProgress(AuraLlmModelPhase.ready));
        return target.path;
      }
      // A file that no longer matches the trusted digest is never loaded.
      try {
        await target.delete();
      } on Object {
        _report(
          const AuraLlmModelProgress(
            AuraLlmModelPhase.failed,
            errorCode: 'tampered_model_not_removable',
          ),
        );
        return null;
      }
    }
    if (_downloadUrl.isEmpty) {
      _report(
        const AuraLlmModelProgress(
          AuraLlmModelPhase.failed,
          errorCode: 'model_url_missing',
        ),
      );
      return null;
    }
    return _downloadVerified(target);
  }

  Future<File> _installedFile() async {
    final directory = await _modelDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}$_installedFileName',
    );
  }

  Future<Directory> _modelDirectory() async {
    final base = await _resolveDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}models');
    await directory.create(recursive: true);
    return directory;
  }

  Future<String?> _downloadVerified(File target) async {
    final uri = Uri.tryParse(_downloadUrl);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
      _report(
        const AuraLlmModelProgress(
          AuraLlmModelPhase.failed,
          errorCode: 'model_url_not_https',
        ),
      );
      return null;
    }
    final temporary = File('${target.path}.partial');
    try {
      if (await temporary.exists()) await temporary.delete();
      final client = _clientFactory();
      var downloaded = false;
      final download = _download(client, uri, temporary);
      try {
        downloaded = await download.timeout(_downloadTimeout);
      } on TimeoutException {
        // Abort the response stream, then wait for the writer to finish before
        // deleting the partial file so no late chunk can recreate it.
        client.close();
        try {
          await download;
        } on Object {
          // Expected: closing the client surfaces a stream error.
        }
        downloaded = false;
      } finally {
        client.close();
      }
      if (!downloaded) {
        _report(
          const AuraLlmModelProgress(
            AuraLlmModelPhase.failed,
            errorCode: 'model_download_failed',
          ),
        );
        await _deleteIfPresent(temporary);
        return null;
      }
      _report(const AuraLlmModelProgress(AuraLlmModelPhase.verifying));
      if (!await _matchesDigest(temporary)) {
        _report(
          const AuraLlmModelProgress(
            AuraLlmModelPhase.failed,
            errorCode: 'model_digest_mismatch',
          ),
        );
        await _deleteIfPresent(temporary);
        return null;
      }
      await temporary.rename(target.path);
      _report(
        const AuraLlmModelProgress(
          AuraLlmModelPhase.ready,
          receivedBytes: 1,
          totalBytes: 1,
        ),
      );
      return target.path;
    } on Object {
      _report(
        const AuraLlmModelProgress(
          AuraLlmModelPhase.failed,
          errorCode: 'model_install_failed',
        ),
      );
      await _deleteIfPresent(temporary);
      return null;
    }
  }

  Future<bool> _download(http.Client client, Uri uri, File temporary) async {
    final response = await client.send(http.Request('GET', uri));
    if (response.statusCode != 200) return false;
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) return false;
    _report(
      AuraLlmModelProgress(AuraLlmModelPhase.downloading, totalBytes: declared),
    );
    final sink = temporary.openWrite();
    var received = 0;
    var lastReported = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > maxBytes) return false;
        sink.add(chunk);
        if (received - lastReported >= _progressChunkBytes) {
          lastReported = received;
          _report(
            AuraLlmModelProgress(
              AuraLlmModelPhase.downloading,
              receivedBytes: received,
              totalBytes: declared,
            ),
          );
        }
      }
      await sink.flush();
      return true;
    } finally {
      await sink.close();
    }
  }

  Future<bool> _matchesDigest(File file) async {
    try {
      // Hash off the UI isolate: the pinned GGUF is ~491 MiB and a slow phone
      // would otherwise keep the Dart UI isolate busy for several seconds at
      // startup and whenever the preparation dialog refreshes.
      final path = file.path;
      final digest = await Isolate.run(() async {
        final computed = await sha256.bind(File(path).openRead()).first;
        return computed.toString();
      });
      return digest == _expectedSha256;
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

  void _report(AuraLlmModelProgress progress) {
    if (!_progressController.isClosed) _progressController.add(progress);
  }
}
