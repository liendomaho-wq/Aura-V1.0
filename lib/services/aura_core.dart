import 'package:flutter/services.dart';

import 'ai_brain.dart';

class AuraCore {
  static const MethodChannel _telemetryChannel = MethodChannel(
    'com.ciberdefensa.aura/telemetry',
  );
  static const String _privacyAuditEvent =
      'AUDITORÍA_DE_VECTORES_DE_PRIVACIDAD_DISPOSITIVO';

  final AiBrain _aiBrain;

  AuraCore({AiBrain? aiBrain}) : _aiBrain = aiBrain ?? AiBrain();

  Future<String> ejecutarAnalisisProactivoDispositivo() async {
    try {
      final List<dynamic>? rawTelemetry = await _telemetryChannel
          .invokeMethod<List<dynamic>>('captureRiskTelemetry');

      // An empty inventory is not evidence that the device is safe. It may
      // mean Android denied visibility or the native collector failed.
      if (rawTelemetry == null || rawTelemetry.isEmpty) {
        return 'AUDITORÍA INCOMPLETA: Android no proporcionó telemetría. '
            'Aura no puede confirmar que el dispositivo esté seguro.';
      }

      final decoded = rawTelemetry.map((entry) {
        if (entry is! Map) {
          throw const FormatException(
            'La telemetría nativa tiene un formato inválido.',
          );
        }

        return entry.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }).toList();
      final inventoryWarnings = decoded
          .map((entry) => entry['inventory_warning'])
          .whereType<String>()
          .toList(growable: false);
      final List<Map<String, dynamic>> telemetry = decoded
          .where((entry) => !entry.containsKey('inventory_warning'))
          .toList(growable: false);

      if (telemetry.isEmpty) {
        return <String>[
          'AUDITORÍA INCOMPLETA: no se recibieron datos de aplicaciones para analizar.',
          ...inventoryWarnings,
        ].join('\\n');
      }

      final analysis = await _aiBrain.analizarAmenazaReal(
        tipoEvento: _privacyAuditEvent,
        logsDispositivo: telemetry,
      );
      return <String>[...inventoryWarnings, analysis].join('\\n');
    } on PlatformException {
      // Do not surface native exception messages: they can contain device-
      // specific details. Most importantly, never convert failure to "safe".
      return 'AUDITORÍA INCOMPLETA: no se pudo consultar la telemetría Android. '
          'No es posible confirmar el estado de seguridad.';
    } catch (_) {
      return 'AUDITORÍA INCOMPLETA: no se pudo procesar la telemetría. '
          'No es posible confirmar el estado de seguridad.';
    }
  }
}
