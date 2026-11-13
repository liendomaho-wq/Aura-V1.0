import '../infrastructure/storage/aura_storage.dart';

class AuraLlmContextPolicy {
  static const int minimumContextTokens = 2048;
  static const int baseContextTokens = 8192;
  static const int maximumContextTokens = 65536;
  static const int kvCacheBytesPerToken = 28 * 1024;
  static const int runtimeOverheadBytes = 384 * 1024 * 1024;
  static const int defaultModelBytes = 1117321312;

  static const List<int> levels = <int>[65536, 32768, 16384, 8192, 4096, 2048];

  static int choose({
    AuraMemoryInfo? memory,
    int modelBytes = defaultModelBytes,
    int maxContextTokens = maximumContextTokens,
  }) {
    final cap = maxContextTokens.clamp(
      minimumContextTokens,
      maximumContextTokens,
    );
    int capped(int value) => value < cap ? value : cap;

    if (memory == null) return capped(baseContextTokens);
    if (memory.lowMemory) return capped(4096);
    if (memory.totalBytes < 3 * 1024 * 1024 * 1024) {
      return capped(minimumContextTokens);
    }
    if (memory.totalBytes < 4 * 1024 * 1024 * 1024) return capped(4096);

    final usableBytes = memory.availableBytes * 70 ~/ 100;
    final weightBytes =
        (modelBytes > 0 ? modelBytes : defaultModelBytes) +
        runtimeOverheadBytes;
    for (final level in levels) {
      if (level > cap) continue;
      if (weightBytes + level * kvCacheBytesPerToken <= usableBytes) {
        return level;
      }
    }
    return capped(minimumContextTokens);
  }

  static List<int> fallbackLevels(
    int selected, {
    int attempts = 3,
    int minContextTokens = minimumContextTokens,
  }) {
    final values = <int>[];
    var candidate = selected.clamp(minContextTokens, maximumContextTokens);
    while (values.length < attempts) {
      values.add(candidate);
      if (candidate <= minContextTokens) break;
      final next = candidate ~/ 2;
      candidate = next < minContextTokens ? minContextTokens : next;
    }
    return List<int>.unmodifiable(values);
  }
}
