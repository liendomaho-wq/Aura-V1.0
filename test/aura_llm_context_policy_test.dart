import 'package:aura_mobile_defens/infrastructure/storage/aura_storage.dart';
import 'package:aura_mobile_defens/llm/aura_llm_context_policy.dart';
import 'package:flutter_test/flutter_test.dart';

AuraMemoryInfo _memory({
  required int totalBytes,
  required int availableBytes,
  bool lowMemory = false,
}) => AuraMemoryInfo(
  totalBytes: totalBytes,
  availableBytes: availableBytes,
  thresholdBytes: 256 * 1024 * 1024,
  lowMemory: lowMemory,
);

void main() {
  test('uses the 8K base when Android memory is unavailable', () {
    expect(
      AuraLlmContextPolicy.choose(),
      AuraLlmContextPolicy.baseContextTokens,
    );
  });

  test('falls back below 8K on low-memory devices', () {
    expect(
      AuraLlmContextPolicy.choose(
        memory: _memory(
          totalBytes: 8 * 1024 * 1024 * 1024,
          availableBytes: 6 * 1024 * 1024 * 1024,
          lowMemory: true,
        ),
      ),
      4096,
    );
    expect(
      AuraLlmContextPolicy.choose(
        memory: _memory(
          totalBytes: 2 * 1024 * 1024 * 1024,
          availableBytes: 1024 * 1024 * 1024,
        ),
      ),
      AuraLlmContextPolicy.minimumContextTokens,
    );
  });

  test('never exceeds the runtime cap', () {
    expect(
      AuraLlmContextPolicy.choose(
        memory: _memory(
          totalBytes: 16 * 1024 * 1024 * 1024,
          availableBytes: 12 * 1024 * 1024 * 1024,
        ),
        maxContextTokens: 8192,
      ),
      8192,
    );
    expect(
      AuraLlmContextPolicy.choose(
        memory: _memory(
          totalBytes: 16 * 1024 * 1024 * 1024,
          availableBytes: 12 * 1024 * 1024 * 1024,
        ),
        maxContextTokens: 512,
      ),
      AuraLlmContextPolicy.minimumContextTokens,
    );
  });

  test('scales context with available memory and headroom', () {
    expect(
      AuraLlmContextPolicy.choose(
        memory: _memory(
          totalBytes: 8 * 1024 * 1024 * 1024,
          availableBytes: 7 * 1024 * 1024 * 1024,
        ),
      ),
      65536,
    );
    expect(
      AuraLlmContextPolicy.choose(
        memory: _memory(
          totalBytes: 8 * 1024 * 1024 * 1024,
          availableBytes: 3 * 1024 * 1024 * 1024,
        ),
      ),
      16384,
    );
    expect(
      AuraLlmContextPolicy.choose(
        memory: _memory(
          totalBytes: 8 * 1024 * 1024 * 1024,
          availableBytes: 1500 * 1024 * 1024,
        ),
      ),
      AuraLlmContextPolicy.minimumContextTokens,
    );
  });

  test('fallback levels are bounded and end at the minimum', () {
    expect(AuraLlmContextPolicy.fallbackLevels(65536), <int>[
      65536,
      32768,
      16384,
    ]);
    expect(AuraLlmContextPolicy.fallbackLevels(4096), <int>[4096, 2048]);
  });
}
