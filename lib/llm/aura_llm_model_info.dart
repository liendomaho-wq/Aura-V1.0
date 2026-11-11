/// Human-readable metadata for the build-time pinned GGUF.
///
/// The URL and digest stay in `AuraLlmModelManager` (fail-closed, never shown);
/// these labels are only displayed so the operator knows what is being
/// downloaded, its size and its license. Values are injected by
/// `tool/aura_llm_model.env` through `--dart-define`; without them the UI shows
/// a neutral label instead of inventing a model identity.
class AuraLlmModelInfo {
  const AuraLlmModelInfo._();

  static const String label = String.fromEnvironment('AURA_LLM_MODEL_LABEL');
  static const String license = String.fromEnvironment(
    'AURA_LLM_MODEL_LICENSE',
  );
  static const int sizeBytes = int.fromEnvironment('AURA_LLM_MODEL_SIZE_BYTES');

  static String get displayLabel =>
      label.isEmpty ? 'modelo local verificado' : label;

  /// Size in MiB with a single decimal place, or null when unknown.
  static String? get sizeLabel {
    if (sizeBytes <= 0) return null;
    final mebibytes = sizeBytes / (1024 * 1024);
    return '${mebibytes.toStringAsFixed(0)} MiB';
  }

  static String get licenseLabel =>
      license.isEmpty ? 'licencia declarada' : license;
}
