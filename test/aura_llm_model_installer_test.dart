import 'dart:async';
import 'dart:io';

import 'package:aura_mobile_defens/llm/aura_llm_model_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aura-llm-installer-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Directory models() => Directory('${root.path}/models');
  File installed() => File('${models().path}/aura-local.gguf');
  File partial() => File('${installed().path}.partial');

  AuraLlmModelManager manager({
    String downloadUrl = 'https://example.test/model.gguf',
    required String expectedSha256,
    required int expectedBytes,
    int minimumFreeSpaceBytes = 0,
    Future<int?> Function()? freeSpaceProvider,
    http.Client Function()? clientFactory,
  }) => AuraLlmModelManager(
    downloadUrl: downloadUrl,
    expectedSha256: expectedSha256,
    expectedBytes: expectedBytes,
    maxBytes: expectedBytes,
    minimumFreeSpaceBytes: minimumFreeSpaceBytes,
    resolveDirectory: () async => root,
    freeSpaceProvider: freeSpaceProvider ?? () async => null,
    clientFactory: clientFactory ?? http.Client.new,
  );

  test('resumes a partial download with a Range request', () async {
    final bytes = List<int>.generate(128, (index) => index * 5 % 256);
    await models().create(recursive: true);
    await partial().writeAsBytes(bytes.sublist(0, 64), flush: true);
    String? range;
    var requests = 0;
    final lastProgress = <AuraLlmDownloadProgress>[];
    final model = manager(
      expectedSha256: _digest(bytes),
      expectedBytes: bytes.length,
      clientFactory: () => MockClient((request) async {
        requests++;
        range = request.headers['range'] ?? request.headers['Range'];
        return http.Response.bytes(bytes.sublist(64), 206);
      }),
    );

    final result = await model.installModel(onProgress: lastProgress.add);

    expect(result.isSuccess, isTrue);
    expect(requests, 1);
    expect(range, 'bytes=64-');
    expect(await installed().readAsBytes(), bytes);
    expect(await partial().exists(), isFalse);
    expect(lastProgress.last.receivedBytes, bytes.length);
    expect(lastProgress.last.totalBytes, bytes.length);
  });

  test('restarts when the server ignores the Range request', () async {
    final bytes = List<int>.generate(96, (index) => index % 251);
    await models().create(recursive: true);
    await partial().writeAsBytes(bytes.sublist(0, 32), flush: true);
    final model = manager(
      expectedSha256: _digest(bytes),
      expectedBytes: bytes.length,
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(bytes, 200)),
    );

    final result = await model.installModel();

    expect(result.isSuccess, isTrue);
    expect(await installed().readAsBytes(), bytes);
  });

  test('cancellation keeps the verified prefix for a later resume', () async {
    final bytes = List<int>.generate(128, (index) => index * 3 % 256);
    final token = AuraLlmCancellation();
    final model = manager(
      expectedSha256: _digest(bytes),
      expectedBytes: bytes.length,
      clientFactory: () => _StreamingClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(<List<int>>[
            bytes.sublist(0, 32),
            bytes.sublist(32),
          ]),
          200,
          contentLength: bytes.length,
        ),
      ),
    );

    final result = await model.installModel(
      cancellation: token,
      onProgress: (progress) {
        if (progress.receivedBytes >= 32) token.cancel();
      },
    );

    expect(result.error, AuraLlmInstallError.cancelled);
    expect(await installed().exists(), isFalse);
    expect(await partial().exists(), isTrue);
    expect(await partial().length(), 32);
    expect(await partial().readAsBytes(), bytes.sublist(0, 32));
  });

  test('refuses to start without enough free space', () async {
    final bytes = List<int>.generate(64, (index) => index);
    var requested = false;
    final model = manager(
      expectedSha256: _digest(bytes),
      expectedBytes: bytes.length,
      freeSpaceProvider: () async => bytes.length - 1,
      clientFactory: () {
        requested = true;
        return MockClient((_) async => http.Response.bytes(bytes, 200));
      },
    );

    final result = await model.installModel();

    expect(result.error, AuraLlmInstallError.insufficientStorage);
    expect(requested, isFalse);
    expect(await models().list().toList(), isEmpty);
  });

  test('rejects a declared size that does not match the pin', () async {
    final bytes = List<int>.generate(64, (index) => index);
    final model = manager(
      expectedSha256: _digest(bytes),
      expectedBytes: 128,
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(bytes, 200)),
    );

    final result = await model.installModel();

    expect(result.error, AuraLlmInstallError.sizeMismatch);
    expect(await installed().exists(), isFalse);
    expect(await partial().exists(), isFalse);
  });

  test(
    'resolveInstalledModel never downloads or touches the network',
    () async {
      final bytes = List<int>.generate(64, (index) => index % 255);
      await models().create(recursive: true);
      await installed().writeAsBytes(bytes, flush: true);
      var requested = false;
      final model = manager(
        downloadUrl: '',
        expectedSha256: _digest(bytes),
        expectedBytes: bytes.length,
        clientFactory: () {
          requested = true;
          return MockClient((_) async => http.Response('', 500));
        },
      );

      expect(await model.resolveInstalledModel(), installed().path);
      expect(requested, isFalse);

      await installed().writeAsBytes(<int>[1, 2, 3], flush: true);
      expect(await model.resolveInstalledModel(), isNull);
      expect(await installed().exists(), isFalse);
    },
  );

  test('verifyInstalled hashes the complete file with progress', () async {
    final bytes = List<int>.generate(256, (index) => index % 253);
    await models().create(recursive: true);
    await installed().writeAsBytes(bytes, flush: true);
    final model = manager(
      downloadUrl: '',
      expectedSha256: _digest(bytes),
      expectedBytes: bytes.length,
    );

    final hashed = <int>[];
    expect(
      await model.verifyInstalled(
        onHashProgress: (value, total) {
          expect(total, bytes.length);
          hashed.add(value);
        },
      ),
      isTrue,
    );
    expect(hashed.last, bytes.length);
  });

  test('deleteInstalled removes both the model and its partial file', () async {
    final bytes = List<int>.generate(32, (index) => index);
    await models().create(recursive: true);
    await installed().writeAsBytes(bytes, flush: true);
    await partial().writeAsBytes(bytes, flush: true);
    final model = manager(
      downloadUrl: '',
      expectedSha256: _digest(bytes),
      expectedBytes: bytes.length,
    );

    await model.deleteInstalled();

    expect(await installed().exists(), isFalse);
    expect(await partial().exists(), isFalse);
  });
}
