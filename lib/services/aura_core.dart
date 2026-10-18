import 'package:flutter/services.dart';

import 'ai_brain.dart';

class AuraCore {
  static const MethodChannel _telemetryChannel =
      MethodChannel('com.ciberdefensa.aura/telemetry');
  static const String _privacyAuditEvent =
      'AUDITORÍA_DE_VECTORES_DE_PRIVACIDAD_DISPOSITIVO';

  final AiBrain _aiBrain;

  AuraCore({AiBrain? aiBrain}) : _aiBrain = aiBrain ?? AiBrain();

  Future<String> ejecutarAnalisisProactivoDispositivo() async {
    try {
      final List<dynamic>? rawTelemetry = await _telemetryChannel
          .invokeMethod<List<dynamic>>('captureRiskTelemetry');

      if (rawTelemetry == null || rawTelemetry.isEmpty) {
        return 'DISPOSITIVO SEGURO: No se detectaron permisos abusivos en aplicaciones de terceros.';
      }

      final decoded = rawTelemetry.map((entry) {
        if (entry is! Map) {
          throw const FormatException('La telemetría nativa tiene un formato inválido.');
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

      if (telemetry.isEmpty && inventoryWarnings.isNotEmpty) {
        return inventoryWarnings.join('\n');
      }

      final analysis = await _aiBrain.analizarAmenazaReal(
        tipoEvento: _privacyAuditEvent,
        logsDispositivo: telemetry,
      );
      return <String>[...inventoryWarnings, analysis].join('\n');
    } on PlatformException catch (exception) {
      return 'ERROR DE TELEMETRÍA: ${exception.message ?? 'No se pudo consultar el hardware Android.'}';
    } catch (_) {
      return 'ERROR DE ANÁLISIS: No se pudo procesar la telemetría del dispositivo.';
    }
  }
}
