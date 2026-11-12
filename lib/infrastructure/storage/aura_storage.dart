import 'package:flutter/services.dart';

/// Read-only storage capacity reported by Android for the app-private volume.
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
}
