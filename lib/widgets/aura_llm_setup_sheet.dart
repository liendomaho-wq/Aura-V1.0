import 'package:flutter/material.dart';

import '../llm/aura_llm_model_source.dart';
import '../llm/aura_llm_setup_controller.dart';
import '../theme/aura_tokens.dart';

Future<void> showAuraLlmSetupSheet(
  BuildContext context,
  AuraLlmSetupController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AuraLlmSetupSheet(controller: controller),
  );
}

class AuraLlmSetupSheet extends StatefulWidget {
  const AuraLlmSetupSheet({super.key, required this.controller});

  final AuraLlmSetupController controller;

  @override
  State<AuraLlmSetupSheet> createState() => _AuraLlmSetupSheetState();
}

class _AuraLlmSetupSheetState extends State<AuraLlmSetupSheet> {
  late bool _consent;

  @override
  void initState() {
    super.initState();
    _consent = widget.controller.hasConsent;
    widget.controller.addListener(_syncConsent);
    widget.controller.initialize();
  }

  void _syncConsent() {
    if (!mounted || _consent) return;
    if (widget.controller.hasConsent) {
      setState(() => _consent = true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncConsent);
    super.dispose();
  }

  bool get _hasEnoughSpace {
    final free = widget.controller.freeBytes;
    final expected = widget.controller.source.sizeBytes;
    if (free == null || expected <= 0) return true;
    return free >= expected + widget.controller.minimumFreeSpaceBytes;
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AuraTokens.surfaceAlt,
        title: const Text('Eliminar modelo local'),
        content: const Text(
          'Se borrará el GGUF verificado y su descarga parcial. '
          'Aura seguirá funcionando en modo Básico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey<String>('aura-llm-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteModel();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    return Container(
      key: const ValueKey<String>('aura-llm-setup-sheet'),
      constraints: BoxConstraints(maxHeight: media.height * 0.92),
      decoration: const BoxDecoration(
        color: AuraTokens.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x3339D9FF))),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AuraTokens.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preparar Aura IA local',
                              style: TextStyle(
                                color: AuraTokens.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Modelo opcional · inferencia en el dispositivo',
                              style: TextStyle(
                                color: AuraTokens.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.close,
                          color: AuraTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ModelCard(controller: widget.controller),
                  const SizedBox(height: 14),
                  _StatusPanel(controller: widget.controller),
                  const SizedBox(height: 14),
                  if (widget.controller.status ==
                          AuraLlmSetupStatus.notInstalled ||
                      widget.controller.status == AuraLlmSetupStatus.paused ||
                      widget.controller.status == AuraLlmSetupStatus.failed ||
                      widget.controller.status ==
                          AuraLlmSetupStatus.downloading)
                    _DownloadControls(
                      controller: widget.controller,
                      consent: _consent,
                      enoughSpace: _hasEnoughSpace,
                      onConsentChanged: (value) =>
                          setState(() => _consent = value ?? false),
                    ),
                  if (widget.controller.status ==
                      AuraLlmSetupStatus.notConfigured)
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text(
                        'Este build no incluye un modelo fijado con URL y '
                        'SHA-256. Aura sigue funcionando en modo Básico. Para '
                        'habilitar la IA local, compilá con '
                        'AURA_LLM_MODEL_URL y AURA_LLM_MODEL_SHA256.',
                        style: TextStyle(
                          color: AuraTokens.textMuted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (widget.controller.status == AuraLlmSetupStatus.ready)
                    _ReadyControls(
                      controller: widget.controller,
                      onDelete: _confirmDelete,
                    ),
                  if (widget.controller.status == AuraLlmSetupStatus.ready)
                    const SizedBox(height: 10),
                  if (widget.controller.errorCode == 'llm_runtime_unavailable')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'El modelo quedó verificado. La inferencia se habilitará '
                        'solo cuando el runtime nativo esté disponible.',
                        style: TextStyle(
                          color: AuraTokens.warning,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aura Básica sigue funcionando sin el modelo. La descarga solo '
                    'solicita el archivo a huggingface.co; no envía análisis, '
                    'telemetría ni datos del dispositivo.',
                    style: TextStyle(
                      color: AuraTokens.textMuted,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.controller});

  final AuraLlmSetupController controller;

  @override
  Widget build(BuildContext context) {
    final source = controller.source;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AuraTokens.accentViolet.withValues(alpha: 0.3),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141F3D), Color(0xFF0B1730)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.memory_rounded,
                color: AuraTokens.accentViolet,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source.identityLabel,
                  style: const TextStyle(
                    color: AuraTokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _FactRow(label: 'Tamaño', value: source.sizeLabel),
          _FactRow(
            label: 'Licencia',
            value: source.license.isEmpty
                ? 'Build personalizado'
                : source.license,
          ),
          _FactRow(
            label: 'Origen',
            value: source.publisher.isEmpty
                ? 'Configuración de compilación'
                : '${source.publisher} · revisión fija',
          ),
          _FactRow(
            label: 'SHA-256',
            value: source.shortSha256,
            monospace: true,
          ),
          const SizedBox(height: 8),
          const Text(
            'La URL apunta a una revisión inmutable. El archivo solo se carga '
            'después de verificar su SHA-256 completo.',
            style: TextStyle(
              color: AuraTokens.textMuted,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: AuraTokens.textMuted,
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AuraTokens.textPrimary,
                fontSize: 10.5,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final AuraLlmSetupController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final error = controller.errorMessage;
    final progress = controller.progress;
    final received = controller.receivedBytes;
    final total = controller.totalBytes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AuraTokens.bg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (status) {
                  AuraLlmSetupStatus.ready => Icons.verified_rounded,
                  AuraLlmSetupStatus.downloading ||
                  AuraLlmSetupStatus.verifying ||
                  AuraLlmSetupStatus.loading => Icons.downloading_rounded,
                  AuraLlmSetupStatus.failed => Icons.error_outline_rounded,
                  _ => Icons.shield_outlined,
                },
                color: switch (status) {
                  AuraLlmSetupStatus.ready => AuraTokens.success,
                  AuraLlmSetupStatus.failed => AuraTokens.danger,
                  AuraLlmSetupStatus.downloading ||
                  AuraLlmSetupStatus.verifying ||
                  AuraLlmSetupStatus.loading => AuraTokens.accent,
                  _ => AuraTokens.textMuted,
                },
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  controller.statusLabel,
                  style: const TextStyle(
                    color: AuraTokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (status == AuraLlmSetupStatus.downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AuraTokens.surfaceAlt,
              color: AuraTokens.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              <String>[
                if (received > 0) formatAuraBytes(received),
                if (total != null) 'de ${formatAuraBytes(total)}',
                if (controller.bytesPerSecond > 0)
                  '· ${formatAuraBytes(controller.bytesPerSecond.round())}/s',
              ].join(' '),
              style: const TextStyle(
                color: AuraTokens.textMuted,
                fontSize: 10.5,
              ),
            ),
          ] else if (status == AuraLlmSetupStatus.verifying ||
              status == AuraLlmSetupStatus.loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              minHeight: 6,
              backgroundColor: AuraTokens.surfaceAlt,
              color: AuraTokens.accentViolet,
            ),
          ] else if (status == AuraLlmSetupStatus.paused) ...[
            const SizedBox(height: 8),
            Text(
              total != null
                  ? 'Progreso conservado: ${formatAuraBytes(received)} de '
                        '${formatAuraBytes(total)}.'
                  : 'Progreso conservado en el almacenamiento privado.',
              style: const TextStyle(
                color: AuraTokens.textMuted,
                fontSize: 10.5,
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                color: status == AuraLlmSetupStatus.ready
                    ? AuraTokens.warning
                    : AuraTokens.danger,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
          if (status == AuraLlmSetupStatus.ready) ...[
            const SizedBox(height: 6),
            Text(
              controller.runtimeReady
                  ? 'Runtime local cargado y listo para inferencia.'
                  : 'Modelo verificado. El runtime se cargará al usarlo.',
              style: const TextStyle(
                color: AuraTokens.textMuted,
                fontSize: 10.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DownloadControls extends StatelessWidget {
  const _DownloadControls({
    required this.controller,
    required this.consent,
    required this.enoughSpace,
    required this.onConsentChanged,
  });

  final AuraLlmSetupController controller;
  final bool consent;
  final bool enoughSpace;
  final ValueChanged<bool?> onConsentChanged;

  @override
  Widget build(BuildContext context) {
    final free = controller.freeBytes;
    final busy = controller.isBusy;
    final downloading = controller.status == AuraLlmSetupStatus.downloading;
    final resuming = controller.status == AuraLlmSetupStatus.paused;
    final label = resuming
        ? 'Reanudar descarga'
        : controller.status == AuraLlmSetupStatus.failed
        ? 'Reintentar descarga'
        : 'Descargar y verificar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          key: const ValueKey<String>('aura-llm-consent'),
          value: consent,
          onChanged: busy ? null : onConsentChanged,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeColor: AuraTokens.accent,
          title: Text(
            'Autorizo la descarga de ${controller.source.sizeLabel} desde '
            'huggingface.co',
            style: const TextStyle(
              color: AuraTokens.textPrimary,
              fontSize: 11.5,
            ),
          ),
          subtitle: const Text(
            'Solo se solicita el archivo del modelo. No se envían datos de '
            'análisis.',
            style: TextStyle(color: AuraTokens.textMuted, fontSize: 10),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          free == null
              ? 'Espacio libre: no confirmado por Android'
              : 'Espacio libre: ${formatAuraBytes(free)}',
          style: TextStyle(
            color: free == null || enoughSpace
                ? AuraTokens.textMuted
                : AuraTokens.warning,
            fontSize: 10.5,
          ),
        ),
        if (!enoughSpace)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Liberá espacio antes de descargar el modelo.',
              style: TextStyle(color: AuraTokens.warning, fontSize: 10.5),
            ),
          ),
        const SizedBox(height: 12),
        if (downloading)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey<String>('aura-llm-cancel'),
              onPressed: controller.cancelDownload,
              icon: const Icon(Icons.pause_rounded),
              label: const Text('Pausar descarga'),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('aura-llm-download'),
              onPressed: !consent || busy || !enoughSpace
                  ? null
                  : () => controller.startDownload(consent: true),
              icon: const Icon(Icons.download_rounded),
              label: Text(label),
            ),
          ),
      ],
    );
  }
}

class _ReadyControls extends StatelessWidget {
  const _ReadyControls({required this.controller, required this.onDelete});

  final AuraLlmSetupController controller;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          key: const ValueKey<String>('aura-llm-prefetch'),
          value: controller.prefetchOnStartup,
          onChanged: controller.setPrefetchOnStartup,
          contentPadding: EdgeInsets.zero,
          activeColor: AuraTokens.accent,
          title: const Text(
            'Cargar Aura IA al iniciar',
            style: TextStyle(color: AuraTokens.textPrimary, fontSize: 12),
          ),
          subtitle: const Text(
            'Consume memoria mientras la app está abierta. Desactivalo en '
            'dispositivos con poca RAM.',
            style: TextStyle(color: AuraTokens.textMuted, fontSize: 10),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('aura-llm-delete'),
            onPressed: controller.isBusy ? null : onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Eliminar modelo local'),
          ),
        ),
      ],
    );
  }
}
