import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum SystemThreatLevel { secure, warning, critical }

class AuraSecurityEngine {
  static const MethodChannel _channel =
      MethodChannel('com.ciberdefensa.aura/telemetry');
  static const MethodChannel _antiTamperingChannel =
      MethodChannel('com.ciberdefensa.aura/anti_tampering');
    static const MethodChannel _securityChannel =
      MethodChannel('com.ciberdefensa.aura/security');
  static const List<String> _rootBinaryPaths = [
    '/sbin/su',
    '/system/bin/su',
    '/system/xbin/su',
  ];

  Future<Map<String, dynamic>> checkDeviceIntegrity() async {
    Map<dynamic, dynamic>? nativeReport;
    Map<dynamic, dynamic>? antiTamperingReport;
    Map<String, dynamic> hostileEnvironmentReport = const {};
    var nativeCheckFailed = false;

    try {
      nativeReport = await _channel.invokeMapMethod<dynamic, dynamic>(
        'checkAppIntegrity',
      );
      nativeCheckFailed = nativeReport == null;
    } on PlatformException {
      nativeCheckFailed = true;
    } on MissingPluginException {
      nativeCheckFailed = true;
    }

    try {
      antiTamperingReport =
          await _antiTamperingChannel.invokeMapMethod<dynamic, dynamic>(
        'checkIntegrity',
      );
      nativeCheckFailed = nativeCheckFailed || antiTamperingReport == null;
    } on PlatformException {
      nativeCheckFailed = true;
    } on MissingPluginException {
      nativeCheckFailed = true;
    }

    hostileEnvironmentReport = await checkHostileEnvironment();
    nativeCheckFailed = nativeCheckFailed ||
        hostileEnvironmentReport['environmentCheckFailed'] == true;

    final rootBinaryFound = await _hasRootBinary();
    final debuggerDetected = nativeReport?['isDebuggerConnected'] == true ||
        antiTamperingReport?['isDebuggerConnected'] == true;
    final alteredEnvironment = nativeReport?['isVirtualEnvironment'] == true;
    final fridaDetected = antiTamperingReport?['fridaDetected'] == true;
    final adbBlocked = antiTamperingReport?['adbBlocked'] == true;
    final debuggerBlocked = antiTamperingReport?['debuggerBlocked'] == true;
    final signatureValid = antiTamperingReport?['signatureValid'] == true;
    // Treat a missing/invalid release signature as a compromised state even
    // if a native report incorrectly claims that the environment is secure.
    final signatureCheckFailed = antiTamperingReport != null && !signatureValid;
    final antiTamperingFailed = antiTamperingReport?['isSecure'] == false;
    final hostileEnvironment = hostileEnvironmentReport['isHostile'] == true;
    final compromised =
        rootBinaryFound ||
        debuggerBlocked ||
        alteredEnvironment ||
        fridaDetected ||
        adbBlocked ||
        signatureCheckFailed ||
        antiTamperingFailed ||
        hostileEnvironment;
    final level = compromised
        ? SystemThreatLevel.critical
        : nativeCheckFailed
            ? SystemThreatLevel.warning
            : SystemThreatLevel.secure;

    return {
      'level': level,
        'logs': hostileEnvironment
          ? 'ALERTA MÁXIMA: entorno emulado o depurador activo detectado.'
          : compromised
          ? 'ALERTA: indicador de root, debugger o entorno alterado detectado.'
          : nativeCheckFailed
              ? 'AVISO: no se pudo completar la comprobación nativa de integridad.'
              : 'Aura Core: comprobaciones de integridad completadas.',
      'rootBinaryFound': rootBinaryFound,
      'isDebuggerConnected': debuggerDetected,
      'debuggerBlocked': debuggerBlocked,
      'isVirtualEnvironment': alteredEnvironment,
      'fridaDetected': fridaDetected,
      'adbEnabled': antiTamperingReport?['adbEnabled'] == true,
      'adbBlocked': adbBlocked,
      'signatureValid': signatureValid,
      'signatureCheckFailed': signatureCheckFailed,
      'antiTamperingCheckFailed': antiTamperingFailed,
      'localDebugFallback':
          antiTamperingReport?['localDebugFallback'] == true,
      'hostileEnvironment': hostileEnvironment,
      'isEmulator': hostileEnvironmentReport['isEmulator'] == true,
      'environmentDebuggerConnected':
          hostileEnvironmentReport['isDebuggerConnected'] == true,
      'environmentIndicators':
          hostileEnvironmentReport['indicators'] ?? const <String>[],
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> checkHostileEnvironment() async {
    try {
      final report = await _securityChannel.invokeMapMethod<String, dynamic>(
        'checkHostileEnvironment',
      );
      if (report == null) throw const FormatException('Informe nativo vacío.');
      return report;
    } on PlatformException {
      return const {'isHostile': false, 'environmentCheckFailed': true};
    } on MissingPluginException {
      return const {'isHostile': false, 'environmentCheckFailed': true};
    }
  }

  Future<Map<String, dynamic>> scanActiveSensitiveServices() async {
    final report = await _securityChannel.invokeMapMethod<String, dynamic>(
      'scanActiveSensitiveServices',
    );
    if (report == null) {
      throw const FormatException('El escáner de aplicaciones devolvió un informe vacío.');
    }
    return report;
  }

  Stream<Map<String, dynamic>> monitorDeviceIntegrity({
    Duration interval = const Duration(seconds: 5),
  }) async* {
    while (true) {
      yield await checkDeviceIntegrity();
      await Future<void>.delayed(interval);
    }
  }

  Future<bool> _hasRootBinary() async {
    for (final path in _rootBinaryPaths) {
      try {
        if (await File(path).exists()) return true;
      } on FileSystemException {
        continue;
      }
    }
    return false;
  }
}
