import 'dart:async';
import 'dart:io';

import 'package:aura_mobile_defens/llm/aura_llm_model_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aura-llm-model-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> installedModel(List<int> bytes) async {
    final models = Directory('${root.path}/models');
    await models.create(recursive: true);
    final file = File('${models.path}/aura-local.gguf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  AuraLlmModelManager manager({
    String downloadUrl = '',
    required String expectedSha256,
    int maxBytes = 1024,
    http.Client Function()? clientFactory,
  }) => AuraLlmModelManager(
    downloadUrl: downloadUrl,
    expectedSha256: expectedSha256,
    maxBytes: maxBytes,
    resolveDirectory: () async => root,
    clientFactory: clientFactory ?? http.Client.new,
  );

  test('without a trusted build-time digest nothing is resolved', () async {
    var touched = false;
    final model = AuraLlmModelManager(
      downloadUrl: 'https://example.test/model.gguf',
      expectedSha256: 'not-a-digest',
      resolveDirectory: () async {
        touched = true;
        return root;
      },
    );

    expect(model.isConfigured, isFalse);
    expect(await model.resolveVerifiedModel(), isNull);
    expect(touched, isFalse);
  });

  test('reuses an installed file only when its digest matches', () async {
    final bytes = List<int>.generate(64, (index) => index);
    final file = await installedModel(bytes);
    var downloaded = false;
    final model = manager(
      expectedSha256: _digest(bytes),
      clientFactory: () {
        downloaded = true;
        return MockClient((_) async => http.Response('', 500));
      },
    );

    expect(model.isConfigured, isTrue);
    expect(await model.resolveVerifiedModel(), file.path);
    expect(downloaded, isFalse);
  });

  test('deletes an installed file whose digest no longer matches', () async {
    final file = await installedModel(<int>[1, 2, 3]);
    final model = manager(expectedSha256: _digest(<int>[9, 9, 9]));

    expect(await model.resolveVerifiedModel(), isNull);
    expect(await file.exists(), isFalse);
  });

  test('downloads, verifies and atomically installs the model', () async {
    final bytes = List<int>.generate(128, (index) => index * 7 % 256);
    var requests = 0;
    final model = manager(
      downloadUrl: 'https://example.test/model.gguf',
      expectedSha256: _digest(bytes),
      maxBytes: bytes.length,
      clientFactory: () => MockClient((request) async {
        requests++;
        expect(request.url.scheme, 'https');
        return http.Response.bytes(bytes, 200);
      }),
    );

    final path = await model.resolveVerifiedModel();

    expect(path, isNotNull);
    final file = File(path!);
    expect(await file.readAsBytes(), bytes);
    expect(await File('${file.path}.partial').exists(), isFalse);
    // A verified installed file is reused without a second download.
    expect(await model.resolveVerifiedModel(), path);
    expect(requests, 1);
  });

  test('a digest mismatch never installs the downloaded file', () async {
    final model = manager(
      downloadUrl: 'https://example.test/model.gguf',
      expectedSha256: _digest(<int>[1, 2, 3]),
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(<int>[4, 5, 6], 200)),
    );

    expect(await model.resolveVerifiedModel(), isNull);
    final models = Directory('${root.path}/models');
    expect(await models.exists(), isTrue);
    expect(await models.list().toList(), isEmpty);
  });

  test('rejects non-HTTPS delivery before any request', () async {
    final bytes = <int>[1, 2, 3];
    var requested = false;
    final model = manager(
      downloadUrl: 'http://example.test/model.gguf',
      expectedSha256: _digest(bytes),
      clientFactory: () => MockClient((_) async {
        requested = true;
        return http.Response.bytes(bytes, 200);
      }),
    );

    expect(await model.resolveVerifiedModel(), isNull);
    expect(requested, isFalse);
  });

  test('rejects a model larger than the configured limit', () async {
    final bytes = List<int>.generate(32, (index) => index);
    final model = manager(
      downloadUrl: 'https://example.test/model.gguf',
      expectedSha256: _digest(bytes),
      maxBytes: 8,
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(bytes, 200)),
    );

    expect(await model.resolveVerifiedModel(), isNull);
    final models = Directory('${root.path}/models');
    expect(await models.list().toList(), isEmpty);
  });

  test('concurrent resolutions share one download', () async {
    final bytes = List<int>.generate(96, (index) => index % 251);
    var requests = 0;
    final gate = Completer<void>();
    final model = manager(
      downloadUrl: 'https://example.test/model.gguf',
      expectedSha256: _digest(bytes),
      maxBytes: bytes.length,
      clientFactory: () => MockClient((_) async {
        requests++;
        await gate.future;
        return http.Response.bytes(bytes, 200);
      }),
    );

    final first = model.resolveVerifiedModel();
    final second = model.resolveVerifiedModel();
    expect(identical(first, second), isTrue);

    gate.complete();
    final paths = await Future.wait(<Future<String?>>[first, second]);

    expect(requests, 1);
    expect(paths.first, isNotNull);
    expect(paths.first, paths.last);
  });

  test('a non-200 response is not installed', () async {
    final model = manager(
      downloadUrl: 'https://example.test/model.gguf',
      expectedSha256: _digest(<int>[1, 2, 3]),
      clientFactory: () => MockClient((_) async => http.Response('', 404)),
    );

    expect(await model.resolveVerifiedModel(), isNull);
    final models = Directory('${root.path}/models');
    expect(await models.list().toList(), isEmpty);
  });
}
