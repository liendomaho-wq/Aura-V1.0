import 'dart:async';

import 'package:flutter/material.dart';

import '../llm/aura_llm_model_info.dart';
import '../llm/aura_llm_model_manager.dart';
import '../llm/local_llm_setup_controller.dart';
import '../theme/aura_tokens.dart';

/// Opens the operator-facing preparation dialog for the on-device model.
///
/// The controller lives in the screen state, so closing the dialog does not
/// cancel an in-flight verified download.
Future<void> showLocalAiDialog(
  BuildContext context,
  LocalLlmSetupController controller,
) {
  unawaited(controller.refresh());
  return showDialog<void>(
    context: context,
    builder: (_) => _LocalAiDialog(controller: controller),
  );
}

class _LocalAiDialog extends StatelessWidget {
  const _LocalAiDialog({required this.controller});

  final LocalLlmSetupController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = controller.status;
        final canPrepare =
            controller.isConfigured &&
            status != LocalLlmSetupStatus.preparing &&
            status != LocalLlmSetupStatus.ready;
        return AlertDialog(
          backgroundColor: AuraTokens.bg,
          title: const Text(
            'Motor de IA local',
            style: TextStyle(color: AuraTokens.accent),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _modelLine('Modelo', AuraLlmModelInfo.displayLabel),
                if (AuraLlmModelInfo.sizeLabel != null)
                  _modelLine('Descarga', AuraLlmModelInfo.sizeLabel!),
                _modelLine('Licencia', AuraLlmModelInfo.licenseLabel),
                const SizedBox(height: 12),
                Text(
                  _statusText(status),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                if (status == LocalLlmSetupStatus.preparing) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: controller.fraction,
                    backgroundColor: AuraTokens.surfaceAlt,
                    color: AuraTokens.accent,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _progressText(controller),
                    style: const TextStyle(
                      color: AuraTokens.textMuted,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ],
                if (status == LocalLlmSetupStatus.failed &&
                    controller.errorCode != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Código: ${controller.errorCode}',
                    style: const TextStyle(
                      color: AuraTokens.textMuted,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'La descarga viaja por HTTPS desde el repositorio fijado y se '
                  'verifica con SHA-256 antes de cargarse. El modelo se ejecuta '
                  'en este dispositivo: tus órdenes no se envían a ningún '
                  'servidor. Sin modelo, Aura sigue resolviendo órdenes con el '
                  'NLU determinista y falla cerrado.',
                  style: TextStyle(
                    color: AuraTokens.textMuted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (canPrepare)
              TextButton(
                onPressed: () => unawaited(controller.prepare()),
                child: Text(
                  status == LocalLlmSetupStatus.failed
                      ? 'Reintentar'
                      : 'Preparar motor',
                  style: const TextStyle(color: AuraTokens.accent),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cerrar',
                style: TextStyle(color: AuraTokens.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _modelLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: AuraTokens.textPrimary,
          fontFamily: 'monospace',
          fontSize: 11,
        ),
      ),
    );
  }

  String _statusText(LocalLlmSetupStatus status) {
    return switch (status) {
      LocalLlmSetupStatus.checking => 'Verificando modelo instalado…',
      LocalLlmSetupStatus.unconfigured =>
        'Esta compilación no incluye un modelo verificado. La IA generativa '
            'queda desactivada.',
      LocalLlmSetupStatus.idle =>
        'Modelo fijado pero aún no preparado. La descarga se verifica antes '
            'de cargarse.',
      LocalLlmSetupStatus.preparing => 'Preparando el motor local…',
      LocalLlmSetupStatus.ready =>
        'Modelo verificado y cargado. IA local lista.',
      LocalLlmSetupStatus.failed =>
        'No se pudo preparar el motor. Aura conserva el NLU determinista.',
    };
  }

  Color _statusColor(LocalLlmSetupStatus status) {
    return switch (status) {
      LocalLlmSetupStatus.ready => AuraTokens.success,
      LocalLlmSetupStatus.failed => AuraTokens.danger,
      LocalLlmSetupStatus.preparing => AuraTokens.warning,
      _ => AuraTokens.accent,
    };
  }

  String _progressText(LocalLlmSetupController controller) {
    return switch (controller.phase) {
      AuraLlmModelPhase.verifying => 'Verificando SHA-256…',
      AuraLlmModelPhase.ready => 'Cargando el modelo en el motor local…',
      _ => _downloadText(controller),
    };
  }

  String _downloadText(LocalLlmSetupController controller) {
    final total = controller.totalBytes;
    if (total == null) return 'Descargando…';
    final received = _mebibytes(controller.receivedBytes);
    return '$received de ${_mebibytes(total)} MiB';
  }

  String _mebibytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);
}
