/// Immutable description of the optional on-device GGUF model.
///
/// The built-in source is pinned to an immutable Hugging Face revision and a
/// SHA-256 digest. The URL and digest are trusted build inputs: the runtime
/// never loads a file that does not match them.
class AuraLlmModelSource {
  const AuraLlmModelSource({
    required this.displayName,
    required this.parameters,
    required this.quantization,
    required this.license,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.publisher,
    required this.revision,
    this.runtimeContextTokens = 8192,
  });

  static const String installedFileName = 'aura-local.gguf';

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  static const AuraLlmModelSource builtIn = AuraLlmModelSource(
    displayName: 'DeepSeek-R1-Distill-Qwen-1.5B',
    parameters: '1.5B',
    quantization: 'Q4_K_M',
    license: 'Apache-2.0',
    downloadUrl:
        'https://huggingface.co/unsloth/'
        'DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/'
        '3cb4d15544a2a5e07439592b9a0965b6445fbd34/'
        'DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf',
    sha256:
        'f3bdf9cf31dee4b57ae4e455a1cb0d01'
        'b5c2c1b50d72d3112141c195506c2840',
    sizeBytes: 1117321312,
    publisher: 'unsloth',
    revision: '3cb4d15544a2a5e07439592b9a0965b6445fbd34',
  );

  final String displayName;
  final String parameters;
  final String quantization;
  final String license;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;
  final String publisher;
  final String revision;
  final int runtimeContextTokens;

  /// Honors the build-time override without silently accepting a partial pin.
  ///
  /// Both environment values are required for an override. When absent, the
  /// reviewed built-in source is used.
  factory AuraLlmModelSource.fromEnvironment() {
    const url = String.fromEnvironment('AURA_LLM_MODEL_URL');
    const sha = String.fromEnvironment('AURA_LLM_MODEL_SHA256');
    const size = int.fromEnvironment('AURA_LLM_MODEL_BYTES');
    const name = String.fromEnvironment('AURA_LLM_MODEL_NAME');
    if (url.isEmpty || sha.isEmpty) return builtIn;
    return AuraLlmModelSource(
      displayName: name.isEmpty ? 'Modelo local Aura' : name,
      parameters: '',
      quantization: '',
      license: '',
      downloadUrl: url.trim(),
      sha256: sha.trim().toLowerCase(),
      sizeBytes: size,
      publisher: '',
      revision: '',
    );
  }

  bool get isConfigured {
    final uri = Uri.tryParse(downloadUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        _sha256Pattern.hasMatch(sha256);
  }

  String get shortSha256 {
    if (sha256.length < 24) return sha256;
    return '${sha256.substring(0, 12)}…${sha256.substring(sha256.length - 8)}';
  }

  String get sizeLabel => formatAuraBytes(sizeBytes);

  String get identityLabel {
    final parts = <String>[
      displayName,
      if (parameters.isNotEmpty) parameters,
      if (quantization.isNotEmpty) quantization,
    ];
    return parts.join(' · ');
  }
}

/// Binary byte formatting shared by the setup UI and diagnostics.
String formatAuraBytes(int bytes) {
  if (bytes < 0) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final fixed = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return '${fixed.replaceAll('.', ',')} ${units[unit]}';
}
