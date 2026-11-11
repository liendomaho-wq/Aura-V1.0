import 'dart:io';

import 'package:aura_mobile_defens/llm/aura_llm_model_manager.dart';
import 'package:aura_mobile_defens/llm/aura_llm_runtime.dart';
import 'package:aura_mobile_defens/llm/local_llm_planner.dart';
import 'package:aura_mobile_defens/llm/local_llm_setup_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

class _FakeRuntime extends AuraLlmRuntime {
  bool loaded = false;
  int loadCalls = 0;

  @override
  Stream<AuraLlmEvent> get events => const Stream<AuraLlmEvent>.empty();

  @override
  Future<AuraLlmCapabilities> capabilities() async => AuraLlmCapabilities(
    available: true,
    loaded: loaded,
    backend: 'llama.cpp',
    abi: 'arm64-v8a',
    maxContextTokens: 2048,
  );

  @override
  Future<void> loadModel({
    required String absoluteModelPath,
    required int contextTokens,
    int threads = 2,
  }) async {
    loadCalls++;
    loaded = true;
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aura-llm-setup-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> install(List<int> bytes) async {
    final models = Directory('${root.path}/models');
    await models.create(recursive: true);
    final file = File('${models.path}/aura-local.gguf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  LocalLlmSetupController controller({
    required AuraLlmModelManager manager,
    required _FakeRuntime runtime,
  }) {
    final planner = LocalLlmPlanner(runtime: runtime, modelManager: manager);
    final setup = LocalLlmSetupController(
      modelManager: manager,
      planner: planner,
    );
    addTearDown(setup.dispose);
    return setup;
  }

  test('an unconfigured build never loads a model', () async {
    final runtime = _FakeRuntime();
    final manager = AuraLlmModelManager(
      downloadUrl: '',
      expectedSha256: '',
      resolveDirectory: () async => root,
    );
    final setup = controller(manager: manager, runtime: runtime);

    await setup.refresh();
    expect(setup.status, LocalLlmSetupStatus.unconfigured);
    expect(setup.isConfigured, isFalse);

    await setup.prepare();
    expect(setup.status, LocalLlmSetupStatus.unconfigured);
    expect(runtime.loadCalls, 0);
  });

  test('an installed verified model is prepared and loaded once', () async {
    final bytes = List<int>.generate(64, (index) => index);
    await install(bytes);
    final runtime = _FakeRuntime();
    final manager = AuraLlmModelManager(
      downloadUrl: '',
      expectedSha256: _digest(bytes),
      resolveDirectory: () async => root,
    );
    final setup = controller(manager: manager, runtime: runtime);

    await setup.refresh();
    expect(setup.status, LocalLlmSetupStatus.idle);

    await setup.prepare();
    expect(setup.status, LocalLlmSetupStatus.ready);
    expect(runtime.loadCalls, 1);

    await setup.prepare();
    expect(runtime.loadCalls, 1);
  });

  test('a failed download leaves the deterministic NLU active', () async {
    final runtime = _FakeRuntime();
    final manager = AuraLlmModelManager(
      downloadUrl: 'https://example.test/model.gguf',
      expectedSha256: _digest(<int>[1, 2, 3]),
      resolveDirectory: () async => root,
      clientFactory: () => MockClient((_) async => http.Response('', 503)),
    );
    final setup = controller(manager: manager, runtime: runtime);

    await setup.prepare();

    expect(setup.status, LocalLlmSetupStatus.failed);
    expect(setup.errorCode, isNotNull);
    expect(runtime.loadCalls, 0);
  });
}
