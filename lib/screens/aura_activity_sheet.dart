import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_event.dart';
import '../agent/aura_activity.dart';
import '../providers/aura_state_provider.dart';
import '../security/aura_finding.dart';
import '../security/aura_threat_case.dart';
import '../theme/aura_tokens.dart';

/// Abre la hoja de actividad. La bitácora es de solo lectura; las acciones
/// sobre una amenaza exigen confirmación explícita y pasan por el agente, nunca
/// por un atajo de la interfaz.
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

enum _ActivityFilter { all, engine, network, threats, issues }

class AuraActivitySheet extends StatefulWidget {
  const AuraActivitySheet({super.key});

  @override
  State<AuraActivitySheet> createState() => _AuraActivitySheetState();
}

class _AuraActivitySheetState extends State<AuraActivitySheet> {
  _ActivityFilter _filter = _ActivityFilter.all;
  List<Map<String, dynamic>> _auditEvents = const <Map<String, dynamic>>[];
  String? _expandedThreatId;
  String? _runningThreatId;
  List<AuraThreatCase> _storedThreats = const <AuraThreatCase>[];
  List<AuraThreatCase> _latestThreats = const <AuraThreatCase>[];
  bool _threatStoreLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAudit();
    _loadStoredThreats();
  }

  @override
  void dispose() {
    final snapshot = _latestThreats;
    if (_threatStoreLoaded && snapshot.isNotEmpty) {
      unawaited(
        AgentController.instance.writeStoredThreatCases(
          snapshot.map((threat) => threat.toMap()).toList(growable: false),
        ),
      );
    }
    super.dispose();
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

  Future<bool> _confirmThreatAction(AuraThreatCase threatCase) async {
    final isPanic =
        threatCase.action == AuraThreatCaseAction.emergencyIsolation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AuraTokens.surface,
        title: Text(
          isPanic ? '¿Cortar toda la red?' : '¿Abrir Ajustes de la app?',
          style: const TextStyle(
            color: AuraTokens.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          isPanic
              ? 'Se descartará todo el tráfico del dispositivo hasta que '
                    'reanudes la red. Las conexiones actuales se interrumpirán.'
              : 'Se abrirá la ficha de ${threatCase.subjectLabel} en Ajustes. '
                    'Aura no desinstala ni modifica la aplicación: Android exige '
                    'que la decisión final la tome el usuario.',
          style: const TextStyle(
            color: AuraTokens.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isPanic ? 'Cortar red' : 'Abrir Ajustes'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _runThreatAction(AuraThreatCase threatCase) async {
    if (_runningThreatId != null || !threatCase.isActionable) return;
    final packageName = threatCase.packageName;
    if (threatCase.action == AuraThreatCaseAction.reviewApp &&
        (packageName == null || packageName.isEmpty)) {
      return;
    }
    if (!await _confirmThreatAction(threatCase) || !mounted) return;
    setState(() => _runningThreatId = threatCase.id);

    // El agente emite el resultado real de la herramienta. Solo marcamos el
    // caso como mitigado si Android confirmó el aislamiento; abrir Ajustes
    // deja el caso en revisión, no lo declara resuelto.
    var actionConfirmed = false;
    var isolationConfirmed = false;
    final subscription = AgentController.instance.events.listen((event) {
      final data = event.data;
      if (data == null) return;
      if (data['isolation_active'] == true) {
        isolationConfirmed = true;
        actionConfirmed = true;
      }
      if (data['user_action_required'] == true || data['ok'] == true) {
        actionConfirmed = true;
      }
    });
    try {
      final instruction = threatCase.action == AuraThreatCaseAction.reviewApp
          ? 'revisar la app $packageName'
          : 'aislamiento de emergencia';
      await AgentController.instance.run(instruction, confirmedByUser: true);
      if (!mounted) return;
      if (threatCase.action == AuraThreatCaseAction.emergencyIsolation &&
          isolationConfirmed) {
        await _setThreatStatus(
          threatCase,
          AuraThreatDisposition.mitigated,
          detail: 'Aislamiento de red confirmado por el agente.',
        );
      } else if (threatCase.action == AuraThreatCaseAction.reviewApp &&
          actionConfirmed) {
        await _setThreatStatus(
          threatCase,
          AuraThreatDisposition.inReview,
          detail: 'Ficha de Ajustes abierta; revisión pendiente.',
        );
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'La acción no confirmó un cambio. El caso sigue como estaba.',
            ),
          ),
        );
      }
    } finally {
      await subscription.cancel();
      if (mounted) setState(() => _runningThreatId = null);
    }
  }

  /// Carga los casos persistidos y descarta registros que no cumplan el
  /// esquema. Un almacén corrupto no se interpreta como «sin amenazas».
  Future<void> _loadStoredThreats() async {
    try {
      final records = await AgentController.instance.readStoredThreatCases();
      final restored = <AuraThreatCase>[];
      for (final record in records) {
        final threat = AuraThreatCase.fromMap(record);
        if (threat != null) restored.add(threat);
      }
      if (mounted) setState(() => _storedThreats = restored);
    } on Object {
      // La UI conserva los casos vivos; no inventa historial ni borra el
      // contenido que no pudo leer.
    } finally {
      _threatStoreLoaded = true;
    }
  }

  Future<void> _setThreatStatus(
    AuraThreatCase threatCase,
    AuraThreatDisposition disposition, {
    String? detail,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = threatCase.copyWith(
      disposition: disposition,
      statusChangedAt: now,
      statusDetail: detail,
      updatedAt: now,
    );
    setState(() {
      _storedThreats = <AuraThreatCase>[
        ..._storedThreats.where((stored) => stored.id != updated.id),
        updated,
      ];
      _latestThreats = <AuraThreatCase>[
        ..._latestThreats.where((stored) => stored.id != updated.id),
        updated,
      ];
    });
    try {
      await AgentController.instance.writeStoredThreatCases(
        _latestThreats.map((threat) => threat.toMap()).toList(growable: false),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo guardar la decisión en el almacén cifrado.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleThreat(AuraThreatCase threatCase) async {
    final opening = _expandedThreatId != threatCase.id;
    setState(() => _expandedThreatId = opening ? threatCase.id : null);
    if (opening && threatCase.disposition == AuraThreatDisposition.open) {
      await _setThreatStatus(
        threatCase,
        AuraThreatDisposition.inReview,
        detail: 'Evidencia abierta por el usuario.',
      );
    }
  }

  Future<void> _toggleDismissed(AuraThreatCase threatCase) async {
    await _setThreatStatus(
      threatCase,
      threatCase.isDismissed
          ? AuraThreatDisposition.open
          : AuraThreatDisposition.dismissed,
      detail: threatCase.isDismissed
          ? 'Restaurada por el usuario.'
          : 'Descartada por el usuario.',
    );
  }

  Future<void> _confirmMitigation(AuraThreatCase threatCase) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AuraTokens.surface,
        title: const Text(
          '¿Confirmar mitigación?',
          style: TextStyle(
            color: AuraTokens.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: const Text(
          'El bloqueo DNS ya está activo y confirmas que revisaste el origen. '
          'El caso pasará a mitigado, pero la app no se elimina y QUIC, ECH '
          'o una IP directa pueden seguir fuera de ese bloqueo.',
          style: TextStyle(
            color: AuraTokens.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar mitigación'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _setThreatStatus(
        threatCase,
        AuraThreatDisposition.mitigated,
        detail: 'Bloqueo DNS activo; revisión confirmada por el usuario.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final findings = state.findingsReport;
    final liveThreats = AuraThreatCaseBuilder.build(
      alerts: state.threatAlerts,
      report: findings,
    );
    final mergedThreats = AuraThreatCaseBuilder.merge(
      live: liveThreats,
      stored: _storedThreats,
      now: DateTime.now().millisecondsSinceEpoch,
      limit: AuraThreatCaseBuilder.maxStoredCases,
    );
    _latestThreats = mergedThreats;
    final threats = mergedThreats
        .take(AuraThreatCaseBuilder.maxCases)
        .toList(growable: false);
    final activeThreats = threats
        .where((threat) => !threat.isDismissed)
        .toList(growable: false);
    final containedThreats = activeThreats
        .where((threat) => threat.state == AuraThreatCaseState.dnsContained)
        .length;
    final reviewThreats = activeThreats
        .where((threat) => threat.state == AuraThreatCaseState.needsReview)
        .length;
    final dismissedThreats = threats.length - activeThreats.length;
    final mitigatedThreats = activeThreats
        .where((threat) => threat.isMitigated)
        .length;
    final maxSeverity = activeThreats.isEmpty
        ? null
        : activeThreats
              .map((threat) => threat.severity)
              .reduce(
                (left, right) => left.index >= right.index ? left : right,
              );
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
                      _NucleusBadge(
                        color: maxSeverity == null
                            ? AuraTokens.accent
                            : _severityColor(maxSeverity),
                        active: running > 0,
                      ),
                      const SizedBox(width: 12),
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
                      _SummaryChip(
                        label: activeThreats.isEmpty
                            ? 'sin detecciones'
                            : '${activeThreats.length} detecciones',
                        color: maxSeverity == null
                            ? AuraTokens.textMuted
                            : _severityColor(maxSeverity),
                      ),
                      if (entries.isEmpty && activeThreats.isEmpty)
                        const _SummaryChip(
                          label: 'sin actividad',
                          color: AuraTokens.textMuted,
                        ),
                    ],
                  ),
                ),
                if (activeThreats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: _ThreatRibbon(
                      threats: activeThreats,
                      contained: containedThreats,
                      review: reviewThreats,
                      mitigated: mitigatedThreats,
                      dismissed: dismissedThreats,
                      maxSeverity: maxSeverity!,
                      onOpen: () =>
                          setState(() => _filter = _ActivityFilter.threats),
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
                          label: 'Amenazas',
                          selected: _filter == _ActivityFilter.threats,
                          onTap: () =>
                              setState(() => _filter = _ActivityFilter.threats),
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
                  child: _filter == _ActivityFilter.threats
                      ? threats.isEmpty
                            ? const _EmptyThreats()
                            : ListView.separated(
                                key: const ValueKey<String>('threat-list'),
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  0,
                                  14,
                                  14,
                                ),
                                itemCount: threats.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final threat = threats[index];
                                  return _ThreatCaseTile(
                                    threatCase: threat,
                                    expanded: _expandedThreatId == threat.id,
                                    busy: _runningThreatId == threat.id,
                                    onToggle: () => _toggleThreat(threat),
                                    onAction: threat.isActionable
                                        ? () => _runThreatAction(threat)
                                        : null,
                                    onMitigate: threat.canConfirmMitigation
                                        ? () => _confirmMitigation(threat)
                                        : null,
                                    onDismiss: () => _toggleDismissed(threat),
                                  );
                                },
                              )
                      : filtered.isEmpty
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
                    'resultado; no hay progreso simulado. Las acciones sobre '
                    'amenazas piden confirmación y usan el mismo agente.',
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
    _ActivityFilter.threats => true,
    _ActivityFilter.issues =>
      entry.status == AuraActivityStatus.failed ||
          entry.evidence['requires_user_confirmation'] == true,
  };
}

Color _severityColor(AuraFindingSeverity severity) => switch (severity) {
  AuraFindingSeverity.info => AuraTokens.textMuted,
  AuraFindingSeverity.low => AuraTokens.accentBlue,
  AuraFindingSeverity.medium => AuraTokens.warning,
  AuraFindingSeverity.high || AuraFindingSeverity.critical => AuraTokens.danger,
};

class _NucleusBadge extends StatelessWidget {
  const _NucleusBadge({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            color.withValues(alpha: 0.85),
            color.withValues(alpha: 0.20),
            Colors.transparent,
          ],
          stops: const <double>[0, 0.42, 1],
        ),
        border: Border.all(color: color.withValues(alpha: 0.32)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: active ? 0.28 : 0.14),
            blurRadius: active ? 18 : 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: <BoxShadow>[
              BoxShadow(color: color, blurRadius: 8, spreadRadius: 2),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ThreatRibbon extends StatelessWidget {
  const _ThreatRibbon({
    required this.threats,
    required this.contained,
    required this.review,
    required this.mitigated,
    required this.dismissed,
    required this.maxSeverity,
    required this.onOpen,
  });

  final List<AuraThreatCase> threats;
  final int contained;
  final int review;
  final int mitigated;
  final int dismissed;
  final AuraFindingSeverity maxSeverity;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(maxSeverity);
    return Semantics(
      button: true,
      label:
          '${threats.length} detecciones locales. $contained con DNS bloqueado, '
          '$review por revisar, $mitigated mitigadas.',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.32)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.radar_rounded, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${threats.length} detecciones locales',
                      style: const TextStyle(
                        color: AuraTokens.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$contained con DNS bloqueado · $review por revisar'
                      '${mitigated > 0 ? ' · $mitigated mitigadas' : ''}'
                      '${dismissed > 0 ? ' · $dismissed descartadas' : ''}',
                      style: const TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                ),
                child: const Text(
                  'Ver',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyThreats extends StatelessWidget {
  const _EmptyThreats();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.radar_rounded,
            size: 30,
            color: AuraTokens.textMuted,
          ),
          const SizedBox(height: 10),
          const Text(
            'No hay amenazas correlacionadas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AuraTokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Esto no certifica que el dispositivo esté libre de riesgos. '
            'El detector solo muestra lo que el Escudo, el escáner y la '
            'postura del dispositivo reportaron.',
            textAlign: TextAlign.center,
            style: TextStyle(
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

class _ThreatCaseTile extends StatelessWidget {
  const _ThreatCaseTile({
    required this.threatCase,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onAction,
    required this.onMitigate,
    required this.onDismiss,
  });

  final AuraThreatCase threatCase;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback? onAction;
  final VoidCallback? onMitigate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(threatCase.severity);
    final stateColor = switch (threatCase.state) {
      AuraThreatCaseState.dnsContained => AuraTokens.success,
      AuraThreatCaseState.needsReview => AuraTokens.warning,
      AuraThreatCaseState.informational => AuraTokens.textMuted,
    };
    final statusColor = switch (threatCase.disposition) {
      AuraThreatDisposition.open => AuraTokens.warning,
      AuraThreatDisposition.inReview => AuraTokens.accent,
      AuraThreatDisposition.mitigated => AuraTokens.success,
      AuraThreatDisposition.dismissed => AuraTokens.textMuted,
    };
    return Container(
      decoration: BoxDecoration(
        color: AuraTokens.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        threatCase.title,
                        style: const TextStyle(
                          color: AuraTokens.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MiniTag(
                      label: threatCase.dispositionLabel,
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  threatCase.summary,
                  maxLines: expanded ? null : 3,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AuraTokens.textMuted,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _MiniTag(label: threatCase.stateLabel, color: stateColor),
                    _MiniTag(
                      label: threatCase.category.label,
                      color: AuraTokens.textMuted,
                    ),
                    _MiniTag(
                      label: '${threatCase.signalCount} señales',
                      color: AuraTokens.textMuted,
                    ),
                    if (threatCase.domain != null)
                      _MiniTag(
                        label: threatCase.domain!,
                        color: AuraTokens.accent,
                      ),
                  ],
                ),
                if (expanded) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(height: 1, color: AuraTokens.border),
                  const SizedBox(height: 9),
                  const Text(
                    'Evidencia',
                    style: TextStyle(
                      color: AuraTokens.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final line in threatCase.evidence)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '· $line',
                        style: const TextStyle(
                          color: AuraTokens.textMuted,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ),
                  if (threatCase.limitations.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    const Text(
                      'Límites',
                      style: TextStyle(
                        color: AuraTokens.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final line in threatCase.limitations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '· $line',
                          style: const TextStyle(
                            color: AuraTokens.textMuted,
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 7),
                  Text(
                    threatCase.recommendedAction,
                    style: const TextStyle(
                      color: AuraTokens.textPrimary,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                  if (threatCase.statusDetail != null) ...<Widget>[
                    const SizedBox(height: 7),
                    Text(
                      'Estado del caso: ${threatCase.dispositionLabel}. '
                      '${threatCase.statusDetail}',
                      style: const TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Plan de respuesta',
                    style: TextStyle(
                      color: AuraTokens.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (
                    var index = 0;
                    index < threatCase.playbook.length;
                    index++
                  )
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${index + 1}. ${threatCase.playbook[index].title}',
                            style: const TextStyle(
                              color: AuraTokens.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          Text(
                            threatCase.playbook[index].detail,
                            style: const TextStyle(
                              color: AuraTokens.textMuted,
                              fontSize: 10.8,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 2,
                  children: <Widget>[
                    TextButton(
                      onPressed: onToggle,
                      style: TextButton.styleFrom(
                        foregroundColor: AuraTokens.textMuted,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(
                        expanded ? 'Ocultar evidencia' : 'Ver evidencia',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    if (onMitigate != null && !threatCase.isDismissed)
                      TextButton(
                        onPressed: busy ? null : onMitigate,
                        style: TextButton.styleFrom(
                          foregroundColor: AuraTokens.success,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text(
                          'Confirmar mitigación',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        foregroundColor: AuraTokens.textMuted,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(
                        threatCase.isDismissed ? 'Restaurar' : 'Descartar',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    if (onAction != null && !threatCase.isDismissed)
                      TextButton(
                        onPressed: busy ? null : onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: color,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                        ),
                        child: busy
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: color,
                                ),
                              )
                            : Text(
                                threatCase.actionLabel,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
