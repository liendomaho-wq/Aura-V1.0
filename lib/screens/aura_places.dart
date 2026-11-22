import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_event.dart';
import '../explanation/aura_verdict_explanation.dart';
import '../inference/aura_ai_inference.dart';
import '../providers/aura_state_provider.dart';
import '../theme/aura_tokens.dart';
import '../widgets/aura_llm_setup_scope.dart';
import '../widgets/aura_llm_setup_sheet.dart';
import '../widgets/aura_neural_core.dart';
import '../widgets/aura_neural_field.dart';
import 'aura_firewall_page.dart';

/// Entry points that sit on Inicio. Each one opens a real screen.
class AuraPlaceRail extends StatelessWidget {
  const AuraPlaceRail({
    super.key,
    required this.onCommand,
    required this.commandsEnabled,
    required this.onTelemetry,
    required this.defenseActive,
    required this.onRestartDefense,
    required this.onShowIntro,
    required this.voiceMuted,
    required this.onVoiceMuted,
  });

  final Future<void> Function(String command) onCommand;
  final bool commandsEnabled;
  final VoidCallback onTelemetry;
  final bool defenseActive;
  final Future<void> Function() onRestartDefense;
  final VoidCallback onShowIntro;
  final bool voiceMuted;
  final ValueChanged<bool> onVoiceMuted;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final waiting = state.isVpnActive && state.telemetryEvents.isEmpty;
    final links = <_PlaceLink>[
      _PlaceLink('Bienvenida', const AuraWelcomePlace()),
      _PlaceLink('En vivo', const AuraLivePlace()),
      _PlaceLink(
        'Amenaza',
        AuraThreatPlace(onCommand: onCommand, commandsEnabled: commandsEnabled),
      ),
      _PlaceLink(
        'Dominio',
        AuraDomainPlace(onCommand: onCommand, commandsEnabled: commandsEnabled),
      ),
      _PlaceLink(
        'Escaneo',
        AuraScanPlace(onCommand: onCommand, commandsEnabled: commandsEnabled),
      ),
      _PlaceLink('Mis apps', const AuraAppsPlace()),
      _PlaceLink('Tu día', const AuraDayPlace()),
      _PlaceLink(
        'Bóveda',
        AuraVaultPlace(onCommand: onCommand, commandsEnabled: commandsEnabled),
      ),
      _PlaceLink(
        'Firewall',
        AuraFirewallPage(
          defenseActive: defenseActive,
          commandsEnabled: commandsEnabled,
          onRestartDefense: onRestartDefense,
        ),
      ),
      _PlaceLink(
        'Ajustes',
        AuraSettingsPlace(
          onTelemetry: onTelemetry,
          onShowIntro: onShowIntro,
          voiceMuted: voiceMuted,
          onVoiceMuted: onVoiceMuted,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (waiting)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Túnel activo, esperando tráfico.',
              style: TextStyle(color: AuraTokens.accent, fontSize: 12),
            ),
          ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: links.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final link = links[index];
              return ActionChip(
                label: Text(link.label),
                labelStyle: const TextStyle(
                  color: AuraTokens.textPrimary,
                  fontSize: 12,
                ),
                backgroundColor: AuraTokens.surfaceAlt,
                side: const BorderSide(color: AuraTokens.border),
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => link.page));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaceLink {
  const _PlaceLink(this.label, this.page);

  final String label;
  final Widget page;
}

class AuraPlaceFrame extends StatelessWidget {
  const AuraPlaceFrame({
    super.key,
    required this.title,
    required this.child,
    this.coreState = AuraCoreVisualState.calm,
  });

  final String title;
  final Widget child;
  final AuraCoreVisualState coreState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraTokens.bg,
      appBar: AppBar(title: Text(title)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuraNeuralField(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                Center(child: AuraNeuralCore(state: coreState, size: 148)),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AuraWelcomePlace extends StatelessWidget {
  const AuraWelcomePlace({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraPlaceFrame(
      title: 'Bienvenida',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Text(
            'Hola, soy Aura.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AuraTokens.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w300,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Voy a vigilar el tráfico que pase por el túnel de este teléfono '
            'y lo que Android me deje ver de las apps. Ese trabajo se queda '
            'en el dispositivo, salvo que actives la telemetría.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AuraTokens.textMuted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'La defensa no arranca sola. Cuando vuelvas a Inicio, usa el '
            'control DEFENSA: Android pedirá el permiso de la VPN.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AuraTokens.accent,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          SizedBox(height: 22),
          _WelcomeButton(),
        ],
      ),
    );
  }
}

class _WelcomeButton extends StatelessWidget {
  const _WelcomeButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AuraTokens.accent,
        foregroundColor: const Color(0xFF041018),
        minimumSize: const Size.fromHeight(48),
      ),
      onPressed: () => Navigator.of(context).maybePop(),
      child: const Text('Comenzar'),
    );
  }
}

class AuraLivePlace extends StatefulWidget {
  const AuraLivePlace({super.key});

  @override
  State<AuraLivePlace> createState() => _AuraLivePlaceState();
}

class _AuraLivePlaceState extends State<AuraLivePlace> {
  static const MethodChannel _engine = MethodChannel(
    'com.aura.cyberdefense/engine',
  );

  Timer? _timer;
  List<int>? _stats;
  String? _statsNote;

  @override
  void initState() {
    super.initState();
    unawaited(_readStats());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_readStats());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _readStats() async {
    try {
      final raw = await _engine.invokeMethod<Object>('getTunnelStats');
      if (!mounted) return;
      if (raw is! List || raw.length < 4) {
        setState(
          () => _statsNote = 'El túnel no devolvió las cuatro métricas.',
        );
        return;
      }
      final stats = <int>[];
      for (final value in raw.take(4)) {
        if (value is! int || value < 0) {
          setState(
            () => _statsNote =
                'El túnel devolvió una métrica que no es un entero.',
          );
          return;
        }
        stats.add(value);
      }
      setState(() {
        _stats = stats;
        _statsNote = null;
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _statsNote = 'Métricas del túnel no disponibles aquí.');
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => _statsNote =
            error.message ?? 'No se pudieron leer las métricas del túnel.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final events = state.telemetryEvents.reversed.toList(growable: false);
    final core = state.blockedEvents + state.dgaAlertEvents > 0
        ? AuraCoreVisualState.alert
        : state.isVpnActive
        ? AuraCoreVisualState.calm
        : AuraCoreVisualState.scanning;
    return AuraPlaceFrame(
      title: 'En vivo',
      coreState: core,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.isVpnActive ? 'Túnel activo' : 'Túnel inactivo',
            style: const TextStyle(color: AuraTokens.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 6),
          if (_stats != null)
            Text(
              'TProxyGetStats · enviados ${_stats![1]} B · recibidos ${_stats![3]} B',
              style: const TextStyle(color: AuraTokens.textMuted, fontSize: 12),
            )
          else if (_statsNote != null)
            Text(
              _statsNote!,
              style: const TextStyle(color: AuraTokens.textMuted, fontSize: 12),
            ),
          const SizedBox(height: 14),
          if (events.isEmpty)
            Text(
              state.isVpnActive
                  ? 'Túnel activo, esperando tráfico.'
                  : 'No hay eventos de red en esta sesión.',
              key: const ValueKey<String>('aura-live-empty'),
              style: const TextStyle(
                color: AuraTokens.accent,
                fontSize: 15,
                height: 1.4,
              ),
            )
          else
            for (final event in events.take(40)) _EventTile(event: event),
        ],
      ),
    );
  }
}

class AuraThreatPlace extends StatelessWidget {
  const AuraThreatPlace({
    super.key,
    required this.onCommand,
    required this.commandsEnabled,
  });

  final Future<void> Function(String command) onCommand;
  final bool commandsEnabled;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final threat = _latestThreat(state.telemetryEvents);
    if (threat == null) {
      return const AuraPlaceFrame(
        title: 'Amenaza',
        child: Text(
          'No hay un bloqueo ni una alerta DGA en esta sesión.',
          style: TextStyle(
            color: AuraTokens.textPrimary,
            fontSize: 16,
            height: 1.4,
          ),
        ),
      );
    }
    final domain = threat['requested_domain'];
    final host = domain is String ? domain : '';
    final usable = _isHost(host);
    final action = threat['action'] == 'DGA_ALERT' ? 'Alerta DGA' : 'Bloqueado';
    final explanation = _explanationFor(state, host);
    return AuraPlaceFrame(
      title: 'Amenaza',
      coreState: AuraCoreVisualState.alert,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            usable ? host : (host.isEmpty ? 'Evento sin dominio' : host),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AuraTokens.gold,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            action,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AuraTokens.alert, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            _clockLabel(threat['timestamp']),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AuraTokens.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: usable
                ? () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AuraDomainPlace(
                          initialHost: host,
                          onCommand: onCommand,
                          commandsEnabled: commandsEnabled,
                        ),
                      ),
                    );
                  }
                : null,
            child: const Text('Ver por qué'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: explanation == null || explanation.reportedFalsePositive
                ? null
                : () {
                    context
                        .read<AuraStateProvider>()
                        .markExplanationAsFalsePositive(explanation.id);
                    _snack(
                      context,
                      'Falso positivo marcado localmente para revisión; no se enviará telemetría.',
                    );
                  },
            child: Text(
              explanation == null
                  ? 'Falso positivo (sin veredicto)'
                  : explanation.reportedFalsePositive
                  ? 'Reportado localmente'
                  : 'Falso positivo',
            ),
          ),
        ],
      ),
    );
  }
}

class AuraDomainPlace extends StatefulWidget {
  const AuraDomainPlace({
    super.key,
    required this.onCommand,
    required this.commandsEnabled,
    this.initialHost,
  });

  final Future<void> Function(String command) onCommand;
  final bool commandsEnabled;
  final String? initialHost;

  @override
  State<AuraDomainPlace> createState() => _AuraDomainPlaceState();
}

class _AuraDomainPlaceState extends State<AuraDomainPlace> {
  late final TextEditingController _hostController;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.initialHost ?? '');
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final typed = _hostController.text.trim().toLowerCase();
    Map<String, double>? features;
    String? featureError;
    if (_isHost(typed)) {
      try {
        features = AuraAIInference.extractFeatures(typed);
      } on FormatException catch (error) {
        featureError = error.message;
      }
    }
    final explanation = _explanationFor(state, typed);
    return AuraPlaceFrame(
      title: 'Análisis de dominio',
      coreState: explanation?.isThreat == true
          ? AuraCoreVisualState.alert
          : AuraCoreVisualState.scanning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _hostController,
            style: const TextStyle(color: AuraTokens.textPrimary),
            decoration: const InputDecoration(
              hintText: 'dominio real, por ejemplo ejemplo.com',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (typed.isEmpty)
            const Text(
              'Escribe un dominio para ver las seis características reales del extractor local.',
              style: TextStyle(color: AuraTokens.textMuted, height: 1.4),
            )
          else if (!_isHost(typed))
            const Text(
              'Ese texto no es un dominio que el extractor pueda medir.',
              style: TextStyle(color: AuraTokens.alert, height: 1.4),
            )
          else if (featureError != null)
            Text(featureError, style: const TextStyle(color: AuraTokens.alert))
          else if (features != null)
            _FeatureBoard(host: typed, features: features),
          const SizedBox(height: 14),
          if (explanation == null)
            const Text(
              'Sin veredicto del bosque en esta sesión. El análisis pide el modelo local; no inventa una puntuación.',
              key: ValueKey<String>('aura-domain-no-score'),
              style: TextStyle(color: AuraTokens.textMuted, height: 1.4),
            )
          else ...[
            Text(
              explanation.isThreat
                  ? 'El bosque marcó este dominio como posible amenaza.'
                  : 'El bosque no marcó este dominio como amenaza.',
              style: const TextStyle(
                color: AuraTokens.textPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              explanation.threatScore == null
                  ? 'Umbral ${explanation.decisionThreshold.toStringAsFixed(2)}. Esta explicación no guardó la fracción de votos.'
                  : 'Puntuación del bosque ${explanation.threatScore!.toStringAsFixed(2)} · umbral ${explanation.decisionThreshold.toStringAsFixed(2)}',
              key: const ValueKey<String>('aura-domain-score'),
              style: const TextStyle(color: AuraTokens.gold, fontSize: 16),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: !widget.commandsEnabled || !_isHost(typed)
                ? null
                : () => widget.onCommand('analizar dominio $typed'),
            child: const Text('Pedir análisis al bosque'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: !widget.commandsEnabled || !_isHost(typed)
                ? null
                : () => _runConfirmed(
                    context,
                    onCommand: widget.onCommand,
                    commandsEnabled: widget.commandsEnabled,
                    command: 'bloquear dominio $typed',
                    title: 'Bloquear dominio',
                    explanation:
                        'Esto pide una regla DNS local para $typed. No se aplica hasta que respondas CONFIRMO a la orden pendiente.',
                  ),
            child: const Text('Bloquear'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: explanation == null || explanation.reportedFalsePositive
                ? null
                : () {
                    context
                        .read<AuraStateProvider>()
                        .markExplanationAsFalsePositive(explanation.id);
                    _snack(
                      context,
                      'Falso positivo marcado localmente para revisión; no se enviará telemetría.',
                    );
                  },
            child: Text(
              explanation?.reportedFalsePositive == true
                  ? 'Reportado localmente'
                  : 'Falso positivo',
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBoard extends StatelessWidget {
  const _FeatureBoard({required this.host, required this.features});

  final String host;
  final Map<String, double> features;

  @override
  Widget build(BuildContext context) {
    final digits = host.runes
        .where((rune) => rune >= 0x30 && rune <= 0x39)
        .length;
    final vowels = host.toLowerCase().runes.where((rune) {
      return rune == 0x61 ||
          rune == 0x65 ||
          rune == 0x69 ||
          rune == 0x6f ||
          rune == 0x75;
    }).length;
    final letters = host.runes.where((rune) {
      final lower = rune | 0x20;
      return lower >= 0x61 && lower <= 0x7a;
    }).length;
    final cells = <(String, String)>[
      ('Longitud', _plain(features['length'])),
      ('Entropía', _plain(features['shannon_entropy'])),
      ('Dígitos', '$digits'),
      ('Vocales', '$vowels'),
      ('Consonantes', '${letters - vowels}'),
      ('TLD sospechoso', features['suspicious_tld'] == 1 ? 'Sí' : 'No'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          key: const ValueKey<String>('aura-domain-features'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cell in cells)
              Container(
                width: 104,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AuraTokens.surface,
                  borderRadius: BorderRadius.circular(AuraTokens.rMd),
                  border: Border.all(color: AuraTokens.border),
                ),
                child: Column(
                  children: [
                    Text(
                      cell.$2,
                      style: const TextStyle(
                        color: AuraTokens.accent,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cell.$1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Proporciones del modelo · dígitos ${_plain(features['digit_ratio'])} · '
          'vocales ${_plain(features['vowel_ratio'])} · '
          'secuencia de consonantes ${_plain(features['consonant_sequence_ratio'])}',
          style: const TextStyle(
            color: AuraTokens.textMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class AuraScanPlace extends StatefulWidget {
  const AuraScanPlace({
    super.key,
    required this.onCommand,
    required this.commandsEnabled,
  });

  final Future<void> Function(String command) onCommand;
  final bool commandsEnabled;

  @override
  State<AuraScanPlace> createState() => _AuraScanPlaceState();
}

class _AuraScanPlaceState extends State<AuraScanPlace> {
  bool _busy = false;

  Future<void> _scan() async {
    if (!widget.commandsEnabled || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onCommand('escanear aplicaciones');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = context.watch<AuraStateProvider>().latestAppScan;
    return AuraPlaceFrame(
      title: 'Escaneo de apps',
      coreState: _busy
          ? AuraCoreVisualState.scanning
          : AuraCoreVisualState.calm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) ...[
            const LinearProgressIndicator(
              minHeight: 3,
              color: AuraTokens.accentViolet,
              backgroundColor: AuraTokens.surfaceAlt,
            ),
            const SizedBox(height: 10),
            const Text(
              'Escaneo en curso. El escáner nativo no informa un avance parcial; el informe aparece cuando termina.',
              style: TextStyle(color: AuraTokens.accent, height: 1.4),
            ),
          ] else if (scan == null)
            const Text(
              'Todavía no hay un informe del escáner de apps en esta sesión.',
              style: TextStyle(color: AuraTokens.textPrimary, height: 1.4),
            )
          else
            _ScanReport(scan: scan),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.commandsEnabled && !_busy ? _scan : null,
            child: const Text('Escanear'),
          ),
        ],
      ),
    );
  }
}

class _ScanReport extends StatelessWidget {
  const _ScanReport({required this.scan});

  final Map<String, dynamic> scan;

  @override
  Widget build(BuildContext context) {
    if (scan['ok'] != true) {
      final error = scan['error'];
      return Text(
        'El escáner no entregó un informe utilizable'
        '${error is String ? ': $error' : '.'} '
        'No se mostrará como cero apps ni cero riesgos.',
        style: const TextStyle(color: AuraTokens.gold, height: 1.4),
      );
    }
    final lines = <String>[
      if (scan['active_service_app_count'] is int)
        'Apps con servicios sensibles activos: ${scan['active_service_app_count']}',
      if (scan['suspicious_app_count'] is int)
        'Combinación de permisos de alto riesgo: ${scan['suspicious_app_count']}',
      if (scan['active_special_access_count'] is int)
        'Accesos especiales confirmados: ${scan['active_special_access_count']}',
      if (scan['signature_issue_count'] is int)
        'Incidencias de firma: ${scan['signature_issue_count']}',
      if (scan['obfuscated_app_count'] is int)
        'Indicadores de ofuscación: ${scan['obfuscated_app_count']}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              line,
              style: const TextStyle(color: AuraTokens.textPrimary),
            ),
          ),
        const Text(
          'Son señales para revisar, no una prueba de malware.',
          style: TextStyle(
            color: AuraTokens.textMuted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class AuraAppsPlace extends StatelessWidget {
  const AuraAppsPlace({super.key});

  @override
  Widget build(BuildContext context) {
    final scan = context.watch<AuraStateProvider>().latestAppScan;
    final apps = _appsFromScan(scan);
    return AuraPlaceFrame(
      title: 'Mis apps',
      child: apps.isEmpty
          ? const Text(
              'No hay apps en el último informe. El escáner lista las que tienen servicios sensibles, no todo el teléfono.',
              style: TextStyle(color: AuraTokens.textPrimary, height: 1.4),
            )
          : Column(
              children: [
                for (final app in apps)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      app.name,
                      style: const TextStyle(color: AuraTokens.textPrimary),
                    ),
                    subtitle: Text(
                      '${app.packageName}\n${app.note}',
                      style: const TextStyle(
                        color: AuraTokens.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ListedApp {
  const _ListedApp(this.name, this.packageName, this.note);

  final String name;
  final String packageName;
  final String note;
}

class AuraDayPlace extends StatelessWidget {
  const AuraDayPlace({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final items = <_DayItem>[
      for (final event in state.telemetryEvents)
        if (_eventTime(event['timestamp']) != null)
          _DayItem(
            _eventTime(event['timestamp'])!,
            _actionLabel(event['action']),
            event['requested_domain'] is String
                ? event['requested_domain'] as String
                : '',
          ),
      for (final event in AgentController.instance.history)
        if (event.kind != AgentEventKind.thought)
          _DayItem(event.ts, _kindLabel(event.kind), event.message),
    ]..sort((a, b) => a.time.compareTo(b.time));
    final now = DateTime.now();
    final today = items.where((item) => _sameDay(item.time, now)).toList();
    final older = items.length - today.length;
    return AuraPlaceFrame(
      title: 'Tu día',
      child: today.isEmpty
          ? Text(
              older == 0
                  ? 'Hoy no hay eventos de red ni respuestas del agente.'
                  : 'Hoy no hay eventos. Hay $older de otra fecha en esta sesión.',
              style: const TextStyle(
                color: AuraTokens.textPrimary,
                height: 1.4,
              ),
            )
          : Column(
              children: [
                for (final item in today)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(
                      _hhmm(item.time),
                      style: const TextStyle(color: AuraTokens.accent),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(color: AuraTokens.textPrimary),
                    ),
                    subtitle: item.detail.isEmpty
                        ? null
                        : Text(
                            item.detail,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AuraTokens.textMuted),
                          ),
                  ),
              ],
            ),
    );
  }
}

class _DayItem {
  const _DayItem(this.time, this.title, this.detail);

  final DateTime time;
  final String title;
  final String detail;
}

class AuraVaultPlace extends StatelessWidget {
  const AuraVaultPlace({
    super.key,
    required this.onCommand,
    required this.commandsEnabled,
  });

  final Future<void> Function(String command) onCommand;
  final bool commandsEnabled;

  @override
  Widget build(BuildContext context) {
    return AuraPlaceFrame(
      title: 'Bóveda',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'La bitácora y las claves locales viven en SecureVault, cifradas en este teléfono.',
            style: TextStyle(color: AuraTokens.textPrimary, height: 1.45),
          ),
          const SizedBox(height: 8),
          const Text(
            'Al abrir Aura se pidió la huella o el bloqueo del teléfono, si estaban configurados. Este botón vuelve a pedir esa comprobación; no abre la bóveda con un atajo.',
            style: TextStyle(color: AuraTokens.textMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final ok = await AgentController.instance
                  .authenticateBiometricDevice();
              if (!context.mounted) return;
              _snack(
                context,
                ok
                    ? 'El teléfono confirmó la biometría.'
                    : 'El teléfono no confirmó la biometría.',
              );
            },
            child: const Text('Comprobar biometría'),
          ),
          const SizedBox(height: 18),
          const Text(
            'Borrado de emergencia',
            style: TextStyle(color: AuraTokens.alert, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pide la purga criptográfica real: borra la bitácora, las claves de la bóveda y el modelo en memoria. Hace falta una segunda respuesta CONFIRMO.',
            style: TextStyle(color: AuraTokens.textMuted, height: 1.4),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: AuraTokens.alert),
            onPressed: () => _runConfirmed(
              context,
              onCommand: onCommand,
              commandsEnabled: commandsEnabled,
              command: 'purga criptográfica',
              title: 'Borrado de emergencia',
              explanation:
                  'Se enviará la orden de purga criptográfica. No borra nada hasta que confirmes con CONFIRMO en el siguiente paso.',
            ),
            child: const Text('Pedir borrado'),
          ),
        ],
      ),
    );
  }
}

class AuraSettingsPlace extends StatelessWidget {
  const AuraSettingsPlace({
    super.key,
    required this.onTelemetry,
    required this.onShowIntro,
    required this.voiceMuted,
    required this.onVoiceMuted,
  });

  final VoidCallback onTelemetry;
  final VoidCallback onShowIntro;
  final bool voiceMuted;
  final ValueChanged<bool> onVoiceMuted;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final llm = AuraLlmSetupScope.maybeOf(context);
    return AuraPlaceFrame(
      title: 'Ajustes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingTile(
            title: 'Voz de Aura',
            detail: voiceMuted
                ? 'Silenciada. Las respuestas siguen en pantalla.'
                : 'Español. Si el teléfono tiene una voz femenina, Aura la usa. Si no, usa la voz española del sistema.',
            onTap: () => onVoiceMuted(!voiceMuted),
          ),
          _SettingTile(
            title: 'Bienvenida',
            detail: 'Volver a ver la introducción.',
            onTap: onShowIntro,
          ),
          _SettingTile(
            title: 'Listas de amenazas',
            detail:
                'Esta sesión: ${state.blockedEvents} bloqueos, '
                '${state.dgaAlertEvents} alertas DGA, '
                '${state.localForestEvaluations} evaluaciones del bosque.',
            onTap: onTelemetry,
          ),
          const _SettingTile(
            title: 'Modo de defensa',
            detail:
                'La defensa es el túnel VPN: activa o inactiva, con el control DEFENSA de Inicio. '
                'No hay modos Normal, Estricto ni Paranoico, ni bloqueo por aplicación. '
                'El túnel solo se excluye a sí mismo para no reentrar en su propia VPN.',
          ),
          _SettingTile(
            title: 'Modelo local de IA',
            detail:
                llm?.statusLabel ?? 'IA local no configurada en esta sesión.',
            onTap: llm == null
                ? null
                : () => showAuraLlmSetupSheet(context, llm),
          ),
          const _SettingTile(
            title: 'Acerca de Aura',
            detail:
                'Aura Mobile Defens. Inteligencia que te defiende, en este teléfono. '
                'Los números de la interfaz salen del túnel, del escáner y del bosque local.',
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.title, required this.detail, this.onTap});

  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      title: Text(title, style: const TextStyle(color: AuraTokens.textPrimary)),
      subtitle: Text(
        detail,
        style: const TextStyle(color: AuraTokens.textMuted, height: 1.35),
      ),
      onTap: onTap,
    );
  }
}

Future<void> _runConfirmed(
  BuildContext context, {
  required Future<void> Function(String command) onCommand,
  required bool commandsEnabled,
  required String command,
  required String title,
  required String explanation,
}) async {
  if (!commandsEnabled) {
    _snack(context, 'Aura todavía no confirmó el acceso local.');
    return;
  }
  final ask = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AuraTokens.surface,
      title: Text(title),
      content: Text(explanation),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Pedir confirmación'),
        ),
      ],
    ),
  );
  if (ask != true || !context.mounted) return;
  final before = AgentController.instance.history.length;
  await onCommand(command);
  if (!context.mounted) return;
  final pending = AgentController.instance.history
      .skip(before)
      .any((event) => event.data?['confirmation_pending'] == true);
  if (!pending) {
    _snack(
      context,
      'La orden no dejó una confirmación pendiente. Revisa el registro de Inicio.',
    );
    return;
  }
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AuraTokens.surface,
      title: const Text('CONFIRMO'),
      content: const Text(
        'Responde CONFIRMO solo si quieres ejecutar exactamente la orden que acabas de pedir. Tienes 60 segundos.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Ahora no'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('CONFIRMO'),
        ),
      ],
    ),
  );
  if (confirm == true && context.mounted) await onCommand('CONFIRMO');
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Map<String, dynamic>? _latestThreat(Iterable<Map<String, dynamic>> events) {
  for (final event in events.toList(growable: false).reversed) {
    final action = event['action'];
    if (action == 'BLOCKED' || action == 'DGA_ALERT') return event;
  }
  return null;
}

AuraVerdictExplanation? _explanationFor(AuraStateProvider state, String host) {
  if (!_isHost(host)) return null;
  for (final explanation in state.explanationHistory.reversed) {
    if (explanation.host == host) return explanation;
  }
  return null;
}

bool _isHost(String value) {
  return RegExp(
    r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$',
  ).hasMatch(value);
}

String _plain(double? value) {
  if (value == null || !value.isFinite) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2);
}

DateTime? _eventTime(Object? raw) {
  if (raw is! int || raw <= 0) return null;
  final millis = raw > 100000000000 ? raw : raw * 1000;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

String _clockLabel(Object? raw) {
  final time = _eventTime(raw);
  if (time == null) return 'Hora no informada';
  return _hhmm(time);
}

String _hhmm(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _actionLabel(Object? action) => switch (action) {
  'ALLOWED' => 'Permitido',
  'BLOCKED' => 'Bloqueado',
  'DGA_ALERT' => 'Alerta DGA',
  'SNI_OBSERVED' => 'SNI observado',
  'SNI_ENCRYPTED' => 'SNI cifrado',
  'DIRECT_IP' => 'Conexión por IP',
  'ENCRYPTED_DNS_BLOCKED' => 'DNS cifrado bloqueado',
  'QUIC_BLOCKED' => 'QUIC bloqueado',
  'VPN_REVOKED' => 'Túnel revocado',
  _ => action is String && action.isNotEmpty ? action : 'Evento',
};

String _kindLabel(AgentEventKind kind) => switch (kind) {
  AgentEventKind.thought => 'Nota',
  AgentEventKind.action => 'Acción',
  AgentEventKind.success => 'Hecho',
  AgentEventKind.warning => 'Aviso',
  AgentEventKind.error => 'Error',
};

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final domain = event['requested_domain'];
    final source = event['source_app'];
    final blocked =
        event['action'] == 'BLOCKED' || event['action'] == 'DGA_ALERT';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AuraTokens.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(AuraTokens.rMd),
          border: Border.all(
            color: blocked ? AuraTokens.alert : AuraTokens.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _actionLabel(event['action']),
                style: TextStyle(
                  color: blocked ? AuraTokens.alert : AuraTokens.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (domain is String && domain.isNotEmpty)
                Text(
                  domain,
                  style: const TextStyle(color: AuraTokens.textPrimary),
                ),
              Text(
                [
                  _clockLabel(event['timestamp']),
                  if (source is String && source.isNotEmpty) source,
                ].join(' · '),
                style: const TextStyle(
                  color: AuraTokens.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<_ListedApp> _appsFromScan(Map<String, dynamic>? scan) {
  if (scan == null || scan['ok'] != true) return const <_ListedApp>[];
  final notes = <String, String>{};
  final names = <String, String>{};
  void take(Object? raw, String note) {
    if (raw is! List) return;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final package = entry['package_name'];
      if (package is! String || package.isEmpty) continue;
      final name = entry['app_name'];
      names.putIfAbsent(
        package,
        () => name is String && name.isNotEmpty ? name : package,
      );
      notes.putIfAbsent(package, () => note);
    }
  }

  take(
    scan['suspicious_apps'],
    'Permisos de alto riesgo en el informe del escáner.',
  );
  take(scan['special_access'], 'Figura en accesos especiales del informe.');
  take(scan['applications'], 'Servicio sensible activo en el informe.');
  take(scan['signature_issues'], 'Incidencia de firma en el informe.');
  take(scan['obfuscated_apps'], 'Indicador de ofuscación en el informe.');
  final packages = names.keys.toList()..sort();
  return [
    for (final package in packages)
      _ListedApp(names[package]!, package, notes[package] ?? 'En el informe.'),
  ];
}
