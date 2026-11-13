import 'package:flutter/services.dart';

class AuraMemoryInfo {
  const AuraMemoryInfo({
    required this.totalBytes,
    required this.availableBytes,
    required this.thresholdBytes,
    required this.lowMemory,
  });

  final int totalBytes;
  final int availableBytes;
  final int thresholdBytes;
  final bool lowMemory;
}

/// Read-only storage and memory capacity reported by Android.
///
/// Failures are reported as `null`; the caller never assumes free space when
/// the platform cannot confirm it.
class AuraStorage {
  AuraStorage({MethodChannel channel = const MethodChannel(_channelName)})
    : _channel = channel;

  static const String _channelName = 'com.ciberdefensa.aura/storage';

  final MethodChannel _channel;

  Future<int?> freeBytes() async {
    try {
      final value = await _channel.invokeMethod<int>('freeBytes');
      if (value == null || value < 0) return null;
      return value;
    } on Object {
      return null;
    }
  }

  Future<AuraMemoryInfo?> memoryInfo() async {
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'memoryInfo',
      );
      if (value == null) return null;
      final total = value['total_bytes'];
      final available = value['available_bytes'];
      final threshold = value['threshold_bytes'];
      final lowMemory = value['low_memory'];
      if (total is! int ||
          available is! int ||
          threshold is! int ||
          lowMemory is! bool ||
          total <= 0 ||
          available < 0 ||
          available > total ||
          threshold < 0) {
        return null;
      }
      return AuraMemoryInfo(
        totalBytes: total,
        availableBytes: available,
        thresholdBytes: threshold,
        lowMemory: lowMemory,
      );
    } on Object {
      return null;
    }
  }
}
