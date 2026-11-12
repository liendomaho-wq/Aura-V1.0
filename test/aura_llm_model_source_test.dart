import 'package:aura_mobile_defens/llm/aura_llm_model_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the built-in pin is complete and immutable', () {
    const source = AuraLlmModelSource.builtIn;

    expect(source.isConfigured, isTrue);
    expect(source.downloadUrl, startsWith('https://huggingface.co/'));
    expect(source.downloadUrl, contains(source.revision));
    expect(source.downloadUrl, endsWith('.gguf'));
    expect(source.sha256, hasLength(64));
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(source.sha256), isTrue);
    expect(source.sizeBytes, 1117321312);
    expect(source.license, 'Apache-2.0');
    expect(source.publisher, 'unsloth');
  });

  test('fromEnvironment falls back to the reviewed pin', () {
    final source = AuraLlmModelSource.fromEnvironment();

    expect(source.downloadUrl, AuraLlmModelSource.builtIn.downloadUrl);
    expect(source.sha256, AuraLlmModelSource.builtIn.sha256);
    expect(source.sizeBytes, AuraLlmModelSource.builtIn.sizeBytes);
  });

  test('rejects unconfigured or non-HTTPS sources', () {
    const insecure = AuraLlmModelSource(
      displayName: 'x',
      parameters: '',
      quantization: '',
      license: '',
      downloadUrl: 'http://example.test/model.gguf',
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sizeBytes: 1,
      publisher: '',
      revision: '',
    );
    const missingDigest = AuraLlmModelSource(
      displayName: 'x',
      parameters: '',
      quantization: '',
      license: '',
      downloadUrl: 'https://example.test/model.gguf',
      sha256: 'abc',
      sizeBytes: 1,
      publisher: '',
      revision: '',
    );

    expect(insecure.isConfigured, isFalse);
    expect(missingDigest.isConfigured, isFalse);
  });

  test('labels stay bounded for display', () {
    const source = AuraLlmModelSource.builtIn;

    expect(source.shortSha256, contains('…'));
    expect(source.shortSha256.length, lessThan(source.sha256.length));
    expect(source.identityLabel, contains('1.5B'));
    expect(source.sizeLabel, '1,04 GiB');
  });

  test('formats byte sizes without binary noise', () {
    expect(formatAuraBytes(-1), '—');
    expect(formatAuraBytes(0), '0 B');
    expect(formatAuraBytes(1023), '1023 B');
    expect(formatAuraBytes(1024), '1,00 KiB');
    expect(formatAuraBytes(1536), '1,50 KiB');
    expect(formatAuraBytes(1048576), '1,00 MiB');
    expect(formatAuraBytes(1117321312), '1,04 GiB');
  });
}
