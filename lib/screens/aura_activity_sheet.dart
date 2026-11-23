import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_event.dart';
import '../agent/aura_activity.dart';
import '../providers/aura_state_provider.dart';
import '../theme/aura_tokens.dart';

/// Abre la hoja de actividad. Es una superficie de solo lectura: no pausa el
/// agente, no detiene el Escudo y no ejecuta ninguna acción.
Future<void> showAuraActivitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C03060C),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.84,
      alignment: Alignment.bottomCenter,
      child: AuraActivitySheet(),
    ),
  );
}

enum _ActivityFilter { all, engine, network, issues }

class AuraActivitySheet extends StatefulWidget {
  const AuraActivitySheet({super.key});

  @override
  State<AuraActivitySheet> createState() => _AuraActivitySheetState();
}

class _AuraActivitySheetState extends State<AuraActivitySheet> {
  _ActivityFilter _filter = _ActivityFilter.all;
  List<Map<String, dynamic>> _auditEvents = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadAudit();
  }

  /// La auditoría cifrada vive en disco y sobrevive a la sesión. Si el
  /// almacén no está disponible, la hoja sigue mostrando la actividad viva;
  /// no se inventan entradas para rellenar el hueco.
  Future<void> _loadAudit() async {
    try {
      final audit = await AgentController.instance.readSecureOperationAudit();
      if (mounted) setState(() => _auditEvents = audit);
    } on Object {
      // Se conserva la lista vacía; la UI no afirma que no hubo operaciones.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    return StreamBuilder<AgentEvent>(
      stream: AgentController.instance.events,
      builder: (context, snapshot) {
        final entries = AuraActivityFeed.build(
          agentEvents: AgentController.instance.history,
          networkEvents: state.telemetryEvents,
          auditEvents: _auditEvents,
        );
        final running = entries
            .where((entry) => entry.status == AuraActivityStatus.running)
            .length;
        final failed = entries
            .where((entry) => entry.status == AuraActivityStatus.failed)
            .length;
        final done = entries
            .where((entry) => entry.status == AuraActivityStatus.succeeded)
            .length;
        final filtered = entries.where(_matchesFilter).toList(growable: false);

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFF0C1626), Color(0xFF05080F)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: AuraTokens.border)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 9),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AuraTokens.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 10, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Actividad de Aura',
                              style: TextStyle(
                                color: AuraTokens.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              running > 0
                                  ? '$running proceso en curso · se actualiza en vivo'
                                  : 'Procesos reales de esta sesión · se actualiza en vivo',
                              style: const TextStyle(
                                color: AuraTokens.textMuted,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey<String>('activity-close'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        tooltip: 'Cerrar actividad',
                        icon: const Icon(Icons.close_rounded, size: 19),
                        color: AuraTokens.textMuted,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      _SummaryChip(
                        label: '$done completados',
                        color: AuraTokens.success,
                      ),
                      if (running > 0)
                        _SummaryChip(
                          label: '$running en curso',
                          color: AuraTokens.accent,
                        ),
                      if (failed > 0)
                        _SummaryChip(
                          label: '$failed con fallo',
                          color: AuraTokens.danger,
                        ),
                      if (entries.isEmpty)
                        const _SummaryChip(
                          label: 'sin actividad',
                          color: AuraTokens.textMuted,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        _FilterChip(
                          label: 'Todo',
                          selected: _filter == _ActivityFilter.all,
                          onTap: () =>
                              setState(() => _filter = _ActivityFilter.all),
                        ),
                        _FilterChip(
                          label: 'Motor',
                          selected: _filter == _ActivityFilter.engine,
                          onTap: () =>
                              setState(() => _filter = _ActivityFilter.engine),
                        ),
                        _FilterChip(
                          label: 'Red',
                          selected: _filter == _ActivityFilter.network,
                          onTap: () =>
                              setState(() => _filter = _ActivityFilter.network),
                        ),
                        _FilterChip(
                          label: 'Incidencias',
                          selected: _filter == _ActivityFilter.issues,
                          onTap: () =>
                              setState(() => _filter = _ActivityFilter.issues),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyActivity(filtered: _filter != _ActivityFilter.all)
                      : ListView.separated(
                          key: const ValueKey<String>('activity-list'),
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) =>
                              _ActivityTile(entry: filtered[index]),
                        ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AuraTokens.border)),
                  ),
                  child: const Text(
                    'Solo se muestra lo que el agente y el Escudo registraron. '
                    'Una operación sigue «en curso» hasta que el motor informa su '
                    'resultado; no hay progreso simulado.',
                    style: TextStyle(
                      color: AuraTokens.textMuted,
                      fontSize: 10.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matchesFilter(AuraActivityEntry entry) => switch (_filter) {
    _ActivityFilter.all => true,
    _ActivityFilter.engine => entry.source == AuraActivitySource.agent,
    _ActivityFilter.network => entry.source == AuraActivitySource.network,
    _ActivityFilter.issues =>
      entry.status == AuraActivityStatus.failed ||
          entry.evidence['requires_user_confirmation'] == true,
  };
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Semantics(
      button: true,
      selected: selected,
      label: 'Filtro $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AuraTokens.accent.withValues(alpha: 0.16)
                : AuraTokens.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AuraTokens.accent.withValues(alpha: 0.55)
                  : AuraTokens.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AuraTokens.accent : AuraTokens.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            filtered ? Icons.filter_alt_off_rounded : Icons.timeline_rounded,
            size: 30,
            color: AuraTokens.textMuted,
          ),
          const SizedBox(height: 10),
          Text(
            filtered
                ? 'No hay entradas para este filtro.'
                : 'Todavía no hay procesos en esta sesión.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AuraTokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Cambiá el filtro para ver el resto de la actividad registrada.'
                : 'Cuando Aura audite el dispositivo, analice un dominio o el '
                      'Escudo reciba un evento de red, aparecerá aquí con su hora '
                      'y su resultado real.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AuraTokens.textMuted,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.entry});

  final AuraActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(entry.status);
    final icon = _statusIcon(entry.status);
    return Semantics(
      container: true,
      label:
          '${entry.title}. ${_statusLabel(entry.status)}. ${entry.detail ?? ''}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: AuraTokens.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AuraTokens.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.36)),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.title,
                    style: const TextStyle(
                      color: AuraTokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  if (entry.detail != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      entry.detail!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _MiniTag(label: _statusLabel(entry.status), color: color),
                      _MiniTag(
                        label: entry.source == AuraActivitySource.agent
                            ? 'motor local'
                            : 'red',
                        color: AuraTokens.textMuted,
                      ),
                      if (entry.evidence['requires_user_confirmation'] == true)
                        const _MiniTag(
                          label: 'requiere confirmación',
                          color: AuraTokens.warning,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  _clock(entry.startedAt),
                  style: const TextStyle(
                    color: AuraTokens.textMuted,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
                if (entry.duration != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    _duration(entry.duration!),
                    style: const TextStyle(
                      color: AuraTokens.textMuted,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Color _statusColor(AuraActivityStatus status) => switch (status) {
    AuraActivityStatus.running => AuraTokens.accent,
    AuraActivityStatus.succeeded => AuraTokens.success,
    AuraActivityStatus.failed => AuraTokens.danger,
    AuraActivityStatus.observed => AuraTokens.accentBlue,
    AuraActivityStatus.info => AuraTokens.textMuted,
  };

  static IconData _statusIcon(AuraActivityStatus status) => switch (status) {
    AuraActivityStatus.running => Icons.pending_outlined,
    AuraActivityStatus.succeeded => Icons.check_rounded,
    AuraActivityStatus.failed => Icons.priority_high_rounded,
    AuraActivityStatus.observed => Icons.visibility_outlined,
    AuraActivityStatus.info => Icons.info_outline_rounded,
  };

  static String _statusLabel(AuraActivityStatus status) => switch (status) {
    AuraActivityStatus.running => 'en curso',
    AuraActivityStatus.succeeded => 'confirmado',
    AuraActivityStatus.failed => 'falló',
    AuraActivityStatus.observed => 'observado',
    AuraActivityStatus.info => 'informativo',
  };

  static String _clock(DateTime value) =>
      '${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';

  static String _duration(Duration value) {
    if (value.inSeconds < 1) return '${value.inMilliseconds} ms';
    if (value.inMinutes < 1) {
      return '${(value.inMilliseconds / 1000).toStringAsFixed(1)} s';
    }
    return '${value.inMinutes}m ${value.inSeconds % 60}s';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.32)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    ),
  );
}
