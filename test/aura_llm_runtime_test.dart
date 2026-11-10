import 'package:aura_mobile_defens/llm/aura_llm_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuraLlmRuntime input and response boundary', () {
    test(
      'rejects invalid model loading parameters before platform dispatch',
      () async {
        final runtime = AuraLlmRuntime();
        await expectLater(
          runtime.loadModel(
            absoluteModelPath: '../outside/model.gguf',
            contextTokens: 4096,
          ),
          throwsArgumentError,
        );
        await expectLater(
          runtime.loadModel(
            absoluteModelPath: '/data/model.gguf',
            contextTokens: 128,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'rejects invalid generation settings before platform dispatch',
      () async {
        final runtime = AuraLlmRuntime();
        await expectLater(
          runtime.startGeneration(prompt: '  '),
          throwsArgumentError,
        );
        await expectLater(
          runtime.startGeneration(prompt: 'hello', maxTokens: 0),
          throwsArgumentError,
        );
        await expectLater(
          runtime.startGeneration(prompt: 'hello', temperature: double.nan),
          throwsArgumentError,
        );
      },
    );

    test('rejects malformed capability payloads', () {
      expect(
        () => AuraLlmCapabilities.fromMap({
          'available': true,
          'loaded': false,
          'backend': 'llama.cpp',
          'abi': 'arm64-v8a',
          'max_context_tokens': '65536',
        }),
        throwsFormatException,
      );
    });

    test('rejects unknown or malformed native events', () {
      expect(
        () => AuraLlmEvent.fromMap({
          'operation_id': 'op-1',
          'type': 'execute_tool',
        }),
        throwsFormatException,
      );
      expect(
        () => AuraLlmEvent.fromMap({
          'operation_id': '',
          'type': 'token',
          'text': 'hello',
        }),
        throwsFormatException,
      );
    });

    test(
      'missing native channel fails closed instead of claiming availability',
      () async {
        const channel =
            MethodChannel('com.ciberdefensa.aura/llm.test.missing');
        final runtime = AuraLlmRuntime(methodChannel: channel);
        await expectLater(
          runtime.capabilities(),
          throwsA(isA<MissingPluginException>()),
        );
      },
    );
  });
}
