import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

  static const String _installedFileName = 'aura-local.gguf';
  static const Duration _downloadTimeout = Duration(minutes: 15);
  static final RegExp _digestPattern = RegExp(r'^[0-9a-f]{64}$');

  final String _downloadUrl;
  final String _expectedSha256;
  final int maxBytes;
  final Future<Directory> Function() _resolveDirectory;
  final http.Client Function() _clientFactory;

  /// Single-flight: an abandoned caller must not start a second download or
  /// delete the `.partial` file another resolution is still writing.
  Future<String?>? _resolveFuture;

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

  Future<String?> _resolveOrDownload() async {
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
    if (await target.exists()) {
      if (await _matchesDigest(target)) return target.path;
      // A file that no longer matches the trusted digest is never loaded.
      try {
        await target.delete();
      } on Object {
        return null;
      }
    }
    if (_downloadUrl.isEmpty) return null;
    return _downloadVerified(target);
  }

  Future<Directory> _modelDirectory() async {
    final base = await _resolveDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}models',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String?> _downloadVerified(File target) async {
    final uri = Uri.tryParse(_downloadUrl);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
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
        await _deleteIfPresent(temporary);
        return null;
      }
      if (!await _matchesDigest(temporary)) {
        await _deleteIfPresent(temporary);
        return null;
      }
      await temporary.rename(target.path);
      return target.path;
    } on Object {
      await _deleteIfPresent(temporary);
      return null;
    }
  }

  Future<bool> _download(http.Client client, Uri uri, File temporary) async {
    final response = await client.send(http.Request('GET', uri));
    if (response.statusCode != 200) return false;
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) return false;
    final sink = temporary.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > maxBytes) return false;
        sink.add(chunk);
      }
      await sink.flush();
      return true;
    } finally {
      await sink.close();
    }
  }

  Future<bool> _matchesDigest(File file) async {
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == _expectedSha256;
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
