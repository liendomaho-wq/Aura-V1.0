import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_event.dart';
import '../ai_brain.dart';
import '../explanation/aura_verdict_explanation.dart';
import '../infrastructure/agent/aura_intent_parser.dart';
import '../models/aura_model_integrity_report.dart';
import '../network_auditor.dart';
import '../providers/aura_state_provider.dart';
import '../services/aura_local_telemetry.dart';
import '../theme/aura_tokens.dart';
import '../widgets/aura_avatar.dart';

const Color _terminalGreen = Color(0xFF00FF00);
const Color _terminalYellow = Color(0xFFFFFF00);
const Color _terminalCyan = Color(0xFF00FFFF);
const int _maxLocalTelemetryEvents = 500;
const int maxInstructionLength = 240;

class AuraCoreScreen extends StatefulWidget {
  const AuraCoreScreen({super.key});

  @override
  State<AuraCoreScreen> createState() => _AuraCoreScreenState();
}

class _AuraCoreScreenState extends State<AuraCoreScreen> {
  static const MethodChannel _voiceChannel =
      MethodChannel('com.ciberdefensa.aura/voice');
  static const MethodChannel _telemetryChannel =
      MethodChannel('com.ciberdefensa.aura/telemetry');
  static const MethodChannel _securityChannel =
      MethodChannel('com.ciberdefensa.aura/security');

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  AuraNetworkAuditor? _networkAuditor;
  AuraAIBrain? _aiBrain;
  StreamSubscription<NetworkAuditEvent>? _networkEventSubscription;
  bool _isListening = false;
  bool _isRunning = false;
  bool _isShieldBusy = false;
  bool _isAuthenticated = false;
  bool _showCoverageAudit = false;
  bool _telemetryEndpointConfigured = false;
  bool _localTelemetryEnabled = false;
  bool _accessibilityCheckFailed = false;
  List<String> _untrustedAccessibilityPackages = const <String>[];
  List<Map<String, dynamic>> _localTelemetryEvents =
      const <Map<String, dynamic>>[];
  String? _coverageAutotestStatus;
  int _lastRenderedEventCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticateConsole();
    });
  }

  Future<void> _authenticateConsole() async {
    final controller = AgentController.instance;
    controller.bindSecurityState(context.read<AuraStateProvider>());
    final authenticated = await controller.authenticateBiometricDevice();
    if (!mounted) return;
    unawaited(_refreshAccessibilityServices());
    await _initializeTelemetryMode();
    if (!mounted) return;
    if (authenticated) {
      controller.initGreeting();
      _startNetworkAuditor();
      setState(() => _isAuthenticated = true);
      return;
    }

    controller.reportWarning(
      'Consola iniciada sin verificación local confirmada; el modo degradado registra este evento.',
    );
    controller.allowUnsecuredLocalSession();
    // El cierre automático está prohibido desde la versión 3.8.
    controller.initGreeting();
    _startNetworkAuditor();
    setState(() => _isAuthenticated = true);
  }

  Future<void> _refreshAccessibilityServices() async {
    try {
      final report = await _securityChannel
          .invokeMapMethod<Object?, Object?>('checkHostileEnvironment');
      final rawPackages = report?['untrustedAccessibilityServicePackages'];
      if (rawPackages is! List || rawPackages.any((value) => value is! String)) {
        throw const FormatException(
          'Android devolvió una lista de accesibilidad inválida.',
        );
      }
      if (!mounted) return;
      setState(() {
        _untrustedAccessibilityPackages = rawPackages.cast<String>();
        _accessibilityCheckFailed = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _accessibilityCheckFailed = true);
      AgentController.instance.reportWarning(
        'No se pudieron verificar los servicios de accesibilidad: $error. '
        'Remedio: revise manualmente Ajustes > Accesibilidad.',
      );
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      final opened =
          await _securityChannel.invokeMethod<bool>('openAccessibilitySettings');
      if (opened != true) {
        AgentController.instance.reportError(
          'Android no confirmó la apertura de accesibilidad. '
          'Remedio: ábrala manualmente desde Ajustes.',
        );
      }
    } on PlatformException catch (error) {
      AgentController.instance.reportError(
        'No se pudieron abrir los ajustes de accesibilidad: '
        '${error.message}. Remedio: ábralos manualmente desde Ajustes.',
      );
    } on MissingPluginException {
      AgentController.instance.reportError(
        'El canal de ajustes de accesibilidad no está disponible. '
        'Remedio: ábralos manualmente desde Ajustes.',
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    unawaited(_disposeNetworkAuditor());
    super.dispose();
  }

  void _startNetworkAuditor() {
    if (_networkAuditor != null) return;
    final state = context.read<AuraStateProvider>();
    final aiBrain = AuraAIBrain(stateProvider: state);
    final auditor = AuraNetworkAuditor(aiBrain: aiBrain);
    _aiBrain = aiBrain;
    _networkAuditor = auditor;
    _networkEventSubscription = auditor.eventStream.listen(
      (event) {
        state.addTelemetryEvent(event.toJson());
        if (event.action == NetworkAuditAction.vpnRevoked) {
          state.setVpnActive(false);
          state.setSecurityLevel(AuraSecurityLevel.critical);
          AgentController.instance.reportError(event.requestedDomain);
        }
        unawaited(_recordLocalNetworkEvent(event));
      },
      onError: (Object error, StackTrace stackTrace) {
        AgentController.instance.reportWarning(
          'No se pudo leer la telemetría DNS local: $error',
        );
      },
    );
  }

  Future<void> _initializeTelemetryMode() async {
    try {
      final rawStatus = await _telemetryChannel.invokeMethod<Object?>(
        'domainTelemetryStatus',
      );
      if (rawStatus is! Map || rawStatus['endpointConfigured'] is! bool) {
        throw const FormatException(
          'Android devolvió un estado de telemetría inválido.',
        );
      }
      final endpointConfigured = rawStatus['endpointConfigured'] as bool;
      AuraLocalTelemetry.configure(endpointConfigured: endpointConfigured);
      final enabled = await AuraLocalTelemetry.isEnabled();
      final events = endpointConfigured
          ? const <Map<String, dynamic>>[]
          : await AuraLocalTelemetry.loadEvents();
      if (!mounted) return;
      setState(() {
        _telemetryEndpointConfigured = endpointConfigured;
        _localTelemetryEnabled = enabled;
        _localTelemetryEvents = events;
      });
    } on Object catch (error) {
      AuraLocalTelemetry.configure(endpointConfigured: false);
      // Fail closed if the persisted preference cannot be read.
      var enabled = false;
      var events = const <Map<String, dynamic>>[];
      try {
        enabled = await AuraLocalTelemetry.isEnabled();
        events = await AuraLocalTelemetry.loadEvents();
      } on Object catch (storageError) {
        AgentController.instance.reportWarning(
          'No se pudo leer la telemetría local guardada: $storageError',
        );
      }
      if (!mounted) return;
      setState(() {
        _telemetryEndpointConfigured = false;
        _localTelemetryEnabled = enabled;
        _localTelemetryEvents = events;
      });
      AgentController.instance.reportWarning(
        'No se pudo verificar el endpoint de telemetría; se conserva el modo local: $error',
      );
    }
  }

  Future<void> _refreshLocalTelemetryEvents() async {
    try {
      final events = await AuraLocalTelemetry.loadEvents();
      if (mounted) setState(() => _localTelemetryEvents = events);
    } on Object catch (error) {
      AgentController.instance.reportWarning(
        'No se pudo actualizar el panel de telemetría local: $error',
      );
    }
  }

  Future<void> _recordLocalNetworkEvent(NetworkAuditEvent event) async {
    try {
      final stored = await AuraLocalTelemetry.recordNetworkEvent(event.toJson());
      if (stored && mounted) {
        final action = event.toJson()['action']!;
        final events = <Map<String, dynamic>>[
          ..._localTelemetryEvents,
          <String, dynamic>{
            'timestamp': event.timestamp,
            'requested_domain': event.requestedDomain,
            'action': action,
            'type': event.action == NetworkAuditAction.blocked
                ? 'dominio_bloqueado'
                : 'escaneo',
          },
        ];
        if (events.length > _maxLocalTelemetryEvents) {
          events.removeRange(0, events.length - _maxLocalTelemetryEvents);
        }
        setState(() {
          _localTelemetryEvents =
              List<Map<String, dynamic>>.unmodifiable(events);
        });
      }
    } on Object catch (error) {
      AgentController.instance.reportWarning(
        'No se pudo guardar la auditoría local de red: $error',
      );
    }
  }

  Future<void> _disposeNetworkAuditor() async {
    await _networkEventSubscription?.cancel();
    await _networkAuditor?.dispose();
    _networkEventSubscription = null;
    _networkAuditor = null;
    _aiBrain = null;
  }

  void _runCoverageAutotest() {
    final state = context.read<AuraStateProvider>();
    setState(() {
      final latestExplanation = state.explanationHistory.isEmpty
          ? null
          : state.explanationHistory.last;
      final threshold = latestExplanation == null
          ? state.activeDecisionThreshold?.toStringAsFixed(2) ?? 'sin inferencia'
          : latestExplanation.decisionThreshold.toStringAsFixed(2);
      _coverageAutotestStatus = 'Diagnóstico local completado. Túnel VPN: '
          '${state.isVpnActive ? 'activo' : 'inactivo'}. '
          'Eventos de sesión: ${state.sniObservedEvents} SNI, '
          '${state.blockedEvents} bloqueos, ${state.dgaAlertEvents} alertas DGA '
          'y ${state.encryptedDnsBlocks} bloqueos de DNS cifrado; '
          '${state.quicBlocked} paquetes QUIC descartados. '
          'UMBRAL DE DECISIÓN: $threshold. No se generó tráfico de prueba.';
    });
  }

  Future<void> _openModelCard() async {
    final uri = Uri.parse(
      'https://yojamm16-boop.github.io/Aura-V1.0/model-card.md',
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la Model Card.')),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la Model Card: $error')),
      );
    }
  }

  Future<AuraModelIntegrityReport> _verifyModelIntegrity() async {
    final aiBrain = _aiBrain;
    if (aiBrain == null) {
      return const AuraModelIntegrityReport(
        verified: false,
        signatureVerified: false,
        modelVersion: 'desconocida',
        sha256: '',
        message: 'El motor de inferencia aún no está disponible.',
      );
    }
    return aiBrain.verifyModelIntegrity();
  }

  void _reportFalsePositive(String explanationId) {
    context
        .read<AuraStateProvider>()
        .markExplanationAsFalsePositive(explanationId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Falso positivo marcado localmente para revisión; no se enviará telemetría.',
        ),
      ),
    );
  }

  Future<void> _dispatch(String text) async {
    var instruction = text.trim();
    if (instruction.isEmpty || _isRunning) return;
    final instructionRunes = instruction.runes.toList(growable: false);
    if (instructionRunes.length > maxInstructionLength) {
      instruction = String.fromCharCodes(
        instructionRunes.take(maxInstructionLength),
      );
      AgentController.instance.reportWarning(
        'Orden truncada a $maxInstructionLength caracteres. '
        'Remedio: divida la orden en consultas más breves.',
      );
    }
    _inputController.clear();
    setState(() => _isRunning = true);
    try {
      final controller = AgentController.instance;
      controller.reportTerminalInput(instruction);
      _scrollToLatest(controller.history.length, force: true);

      for (var second = 0; second < 3; second++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        controller.reportTerminalThinking();
        _scrollToLatest(controller.history.length, force: true);
      }

      final result = await AuraIntentParser.executeCommand(instruction);
      if (!_telemetryEndpointConfigured) {
        await _refreshLocalTelemetryEvents();
      }
      final response = result['response'];
      if (response is String) {
        final notificationSent = await controller.dispatchRealtimeNotification(
          'Aura Mobile Defens',
          response,
        );
        if (!notificationSent && mounted) {
          controller.reportWarning(
            'Alerta no publicada: Android denegó el permiso o el servicio foreground.',
          );
        }
      }
      if (mounted) {
        _scrollToLatest(controller.history.length, force: true);
      }
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<void> _captureVoice() async {
    if (_isListening || _isRunning) return;
    setState(() => _isListening = true);
    try {
      final transcript = await _voiceChannel.invokeMethod<String>(
        'startListening',
      );
      if (!mounted || transcript == null || transcript.trim().isEmpty) return;
      _inputController.text = transcript.trim();
      await _dispatch(transcript);
    } on PlatformException catch (error) {
      if (mounted) {
        context.read<AuraStateProvider>().setSecurityLevel(
              AuraSecurityLevel.warning,
            );
        AgentController.instance.reportError(
          error.message ?? 'No se pudo capturar el comando de voz.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        context.read<AuraStateProvider>().setSecurityLevel(
              AuraSecurityLevel.warning,
            );
        AgentController.instance.reportError(
          'El reconocimiento de voz no está disponible.',
        );
      }
    } finally {
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _toggleShield() async {
    if (_isShieldBusy || !_isAuthenticated) return;
    final state = context.read<AuraStateProvider>();
    final wasActive = state.isVpnActive;
    setState(() => _isShieldBusy = true);
    try {
      await AgentController.instance.run(
        wasActive ? 'desactivar defensas' : 'activar defensas',
      );
    } finally {
      if (mounted) setState(() => _isShieldBusy = false);
    }
  }

  Future<void> _showTelemetrySettings() async {
    try {
      final rawStatus = await _telemetryChannel.invokeMethod<Object?>(
        'domainTelemetryStatus',
      );
      if (rawStatus is! Map ||
          rawStatus['optedIn'] is! bool ||
          rawStatus['endpointConfigured'] is! bool) {
        throw const FormatException(
          'Android devolvió un estado de telemetría inválido.',
        );
      }
      if (!mounted) return;
      var optedIn = rawStatus['optedIn'] as bool;
      final endpointConfigured = rawStatus['endpointConfigured'] as bool;
      AuraLocalTelemetry.configure(endpointConfigured: endpointConfigured);
      var localEnabled = await AuraLocalTelemetry.isEnabled();
      final localEvents = endpointConfigured
          ? const <Map<String, dynamic>>[]
          : await AuraLocalTelemetry.loadEvents();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF07110E),
            title: const Text(
              'Telemetría de detecciones',
              style: TextStyle(color: _terminalGreen, fontFamily: 'monospace'),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      endpointConfigured
                          ? 'TELEMETRÍA: REMOTA'
                          : 'TELEMETRÍA: LOCAL',
                      style: const TextStyle(color: _terminalGreen),
                    ),
                    subtitle: Text(
                      endpointConfigured
                          ? 'Modo remoto disponible. Solo se envían eventos '
                              'con consentimiento y por HTTPS.'
                          : 'Modo local: escaneos, dominios bloqueados y marcas '
                              'de tiempo permanecen en este dispositivo.',
                      style: const TextStyle(
                        color: _terminalYellow,
                        fontSize: 11,
                      ),
                    ),
                    value: endpointConfigured ? optedIn : localEnabled,
                    onChanged: (value) async {
                      if (endpointConfigured) {
                        try {
                          final persisted =
                              await _telemetryChannel.invokeMethod<bool>(
                                    'setDomainTelemetryOptIn',
                                    value,
                                  ) ??
                                  false;
                          if (!dialogContext.mounted) return;
                          setDialogState(() => optedIn = persisted);
                        } on Object catch (error) {
                          if (!dialogContext.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'No se pudo guardar el consentimiento: $error',
                              ),
                            ),
                          );
                        }
                      } else {
                        try {
                          final persisted =
                              await AuraLocalTelemetry.setEnabled(value);
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            localEnabled = persisted;
                          });
                          if (mounted) {
                            setState(
                              () => _localTelemetryEnabled = persisted,
                            );
                          }
                        } on Object catch (error) {
                          if (!dialogContext.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'No se pudo guardar el ajuste local: $error',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  if (!endpointConfigured) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'TELEMETRÍA LOCAL',
                          style: TextStyle(
                            color: _terminalCyan,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final event in localEvents.reversed.take(20))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(
                                _localTelemetryLine(event),
                                style: const TextStyle(
                                  color: _terminalGreen,
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          if (localEvents.isEmpty)
                            const Text(
                              'Sin eventos locales registrados.',
                              style: TextStyle(
                                color: _terminalYellow,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    endpointConfigured
                        ? 'Se envían hashes SHA-256 y clasificación, nunca el '
                            'dominio en claro. Puedes retirar el consentimiento; '
                            'al desactivarlo se elimina la cola pendiente.'
                        : 'Los eventos permanecen en el almacenamiento privado '
                            'de este dispositivo. No se envían a ningún servidor.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Cerrar',
                  style: TextStyle(color: _terminalGreen),
                ),
              ),
            ],
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el ajuste: $error')),
      );
    }

  }

  String _localTelemetryLine(Map<String, dynamic> event) {
    final timestamp = event['timestamp'];
    final time = timestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String()
        : 'hora desconocida';
    final type = event['type'] is String ? event['type'] as String : 'evento';
    final domain =
        event['requested_domain'] ?? event['domain'] ?? 'sin dominio';
    final action = event['action'] ?? event['outcome'] ?? '';
    return '$time · $type · $domain · $action';
  }

  void _scrollToLatest(int eventCount, {bool force = false}) {
    if (!force && eventCount == _lastRenderedEventCount) return;
    _lastRenderedEventCount = eventCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final vpnActive = state.isVpnActive;
    final quickActionsEnabled = !_isRunning && _isAuthenticated;

    OutlinedButton quickAction(String label, VoidCallback? onPressed) =>
        OutlinedButton(
          onPressed: quickActionsEnabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: _terminalGreen,
            side: const BorderSide(color: Color(0xFF1B3A2A)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(
              color: _terminalGreen,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
          child: Text(label),
        );

    return Scaffold(
      backgroundColor: AuraTokens.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Privacidad y telemetría opcional',
                  onPressed: _showTelemetrySettings,
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  icon: const Icon(
                    Icons.tune,
                    color: _terminalYellow,
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('coverage-audit-toggle'),
                  tooltip: _showCoverageAudit
                      ? 'Volver a la consola'
                      : 'Auditoría de cobertura',
                  onPressed: () => setState(
                    () => _showCoverageAudit = !_showCoverageAudit,
                  ),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  icon: Icon(
                    Icons.fact_check_outlined,
                    color:
                        _showCoverageAudit ? _terminalGreen : _terminalYellow,
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Aura Mobile Defens',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF00FFFF),
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey<String>('vpn-toggle'),
                  onPressed:
                      _isAuthenticated && !_isShieldBusy ? _toggleShield : null,
                  style: TextButton.styleFrom(
                    side: BorderSide(
                      color: _isShieldBusy
                          ? Colors.grey
                          : vpnActive
                              ? _terminalGreen
                              : _terminalYellow,
                    ),
                    backgroundColor: vpnActive
                        ? const Color(0xFF001A00)
                        : const Color(0xFF1A1A00),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: const StadiumBorder(),
                  ),
                  child: _isShieldBusy
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          vpnActive ? 'DEFENSA: ON' : 'DEFENSA: OFF',
                          style: TextStyle(
                            color:
                                vpnActive ? _terminalGreen : _terminalYellow,
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  AuraAvatar(size: 88, isThinking: _isRunning || _isListening),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hola, soy Aura.',
                          style: TextStyle(color: AuraTokens.textPrimary,
                            fontSize: 22, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_isRunning ? 'Estoy trabajando en tu solicitud…'
                          : _isListening ? 'Te estoy escuchando…'
                          : 'Tu inteligencia de ciberdefensa está en línea.',
                          style: const TextStyle(color: AuraTokens.accent, fontSize: 12)),
                        const SizedBox(height: 8),
                        Text('${state.blockedEvents} amenazas bloqueadas · '
                          '${state.sniObservedEvents} eventos de red observados',
                          style: const TextStyle(color: AuraTokens.textMuted, fontSize: 10)),
                        const SizedBox(height: 3),
                        Text(
                          'VPN local opcional · ${state.isVpnActive ? 'activa' : 'inactiva'}',
                          style: const TextStyle(color: AuraTokens.textMuted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_untrustedAccessibilityPackages.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A00),
                  border: Border.all(color: _terminalYellow),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SERVICIOS DE ACCESIBILIDAD ACTIVOS PODRÍAN MANIPULAR LA APP',
                      style: TextStyle(
                        color: _terminalYellow,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Paquetes: ${_untrustedAccessibilityPackages.join(', ')}',
                      style: const TextStyle(
                        color: _terminalYellow,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: _openAccessibilitySettings,
                          child: const Text('ABRIR AJUSTES'),
                        ),
                        TextButton(
                          onPressed: _refreshAccessibilityServices,
                          child: const Text('VERIFICAR DE NUEVO'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (_accessibilityCheckFailed)
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextButton(
                  onPressed: _refreshAccessibilityServices,
                  child: const Text(
                    '[WARN] No se pudo verificar accesibilidad · REINTENTAR',
                    style: TextStyle(
                      color: _terminalYellow,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: _isAuthenticated
                  ? StreamBuilder<AgentEvent>(
                      stream: AgentController.instance.events,
                      builder: (context, snapshot) {
                        final events = AgentController.instance.history;
                        final explanationCount =
                            state.explanationHistory.length;
                        final leadingCardCount =
                            (_showCoverageAudit || explanationCount > 0 ? 1 : 0) +
                                (!_telemetryEndpointConfigured ? 1 : 0);
                        _scrollToLatest(events.length + leadingCardCount);
                        return ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                          children: [
                            if (_showCoverageAudit)
                              _CoverageAuditCard(
                                isVpnActive: state.isVpnActive,
                                sniObserved: state.sniObservedEvents,
                                encryptedSni: state.encryptedSniEvents,
                                directIp: state.directIpEvents,
                                blocked: state.blockedEvents,
                                dgaAlerts: state.dgaAlertEvents,
                                encryptedDnsBlocked: state.encryptedDnsBlocks,
                                quicBlocked: state.quicBlocked,
                                decisionThreshold:
                                    state.activeDecisionThreshold,
                                observedResolvers:
                                    state.observedPublicDnsResolvers,
                                autotestStatus: _coverageAutotestStatus,
                                onRunAutotest: _runCoverageAutotest,
                              )
                            else if (explanationCount > 0)
                              _ExplanationCard(
                                explanation: state.explanationHistory.last,
                                onVerifyIntegrity: _verifyModelIntegrity,
                                onReportFalsePositive: _reportFalsePositive,
                                onOpenModelCard: _openModelCard,
                              ),
                            if (!_telemetryEndpointConfigured)
                              _LocalTelemetryPanel(
                                events: _localTelemetryEvents,
                                enabled: _localTelemetryEnabled,
                              ),
                            for (final event in events)
                              _SyslogLine(event: event),
                          ],
                        );
                      },
                    )
                  : const SizedBox.expand(),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  quickAction('AYUDA', () => _dispatch('ayuda')),
                  const SizedBox(width: 8),
                  quickAction('ESTADO', () => _dispatch('estado')),
                  const SizedBox(width: 8),
                  quickAction(
                    vpnActive ? 'DETENER VPN' : 'ACTIVAR VPN',
                    _isShieldBusy ? null : _toggleShield,
                  ),
                  const SizedBox(width: 8),
                  quickAction(
                    'AUDITORÍA',
                    () => setState(
                      () => _showCoverageAudit = !_showCoverageAudit,
                    ),
                  ),
                ],
              ),
            ),
            _TerminalInput(
              controller: _inputController,
              isListening: _isListening,
              isRunning: _isRunning || !_isAuthenticated,
              onSubmitted: _dispatch,
              onVoice: _captureVoice,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalTelemetryPanel extends StatelessWidget {
  const _LocalTelemetryPanel({
    required this.events,
    required this.enabled,
  });

  final List<Map<String, dynamic>> events;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('local-telemetry-panel'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF07110E),
          border: Border.all(color: _terminalGreen.withAlpha(115)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TELEMETRÍA LOCAL',
              style: TextStyle(
                color: _terminalCyan,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              enabled ? 'REGISTRO LOCAL ACTIVO' : 'REGISTRO LOCAL PAUSADO',
              style: const TextStyle(
                color: _terminalYellow,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 6),
            if (events.isEmpty)
              const Text(
                'Sin escaneos ni bloqueos registrados.',
                style: TextStyle(
                  color: AuraTokens.textMuted,
                  fontSize: 10,
                ),
              )
            else
              for (final event in events.reversed.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${_formatLocalTimestamp(event['timestamp'])} · '
                    '${event['type'] ?? 'evento'} · '
                    '${event['requested_domain'] ?? event['domain'] ?? 'sin dominio'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _terminalGreen,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ),
          ],
        ),
      );

  static String _formatLocalTimestamp(Object? timestamp) =>
      timestamp is int
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
              .toIso8601String()
              .replaceFirst('T', ' ')
          : 'hora desconocida';
}

class _ExplanationCard extends StatefulWidget {
  const _ExplanationCard({
    required this.explanation,
    required this.onVerifyIntegrity,
    required this.onReportFalsePositive,
    required this.onOpenModelCard,
  });

  final AuraVerdictExplanation explanation;
  final Future<AuraModelIntegrityReport> Function() onVerifyIntegrity;
  final ValueChanged<String> onReportFalsePositive;
  final VoidCallback onOpenModelCard;

  @override
  State<_ExplanationCard> createState() => _ExplanationCardState();
}

class _ExplanationCardState extends State<_ExplanationCard> {
  AuraModelIntegrityReport? _integrityReport;
  bool _isVerifying = false;
  bool _verificationStarted = false;

  Future<void> _verifyIntegrity() async {
    if (_verificationStarted) return;
    _verificationStarted = true;
    setState(() => _isVerifying = true);
    try {
      final report = await widget.onVerifyIntegrity();
      if (mounted) setState(() => _integrityReport = report);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _integrityReport = AuraModelIntegrityReport(
            verified: false,
            signatureVerified: false,
            modelVersion: widget.explanation.modelVersion,
            sha256: widget.explanation.modelSha256,
            message: 'No se pudo verificar la integridad: $error',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _showFullDigest() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AuraTokens.surface,
        title: const Text(
          'SHA-256 del modelo',
          style: TextStyle(color: AuraTokens.accent),
        ),
        content: SelectableText(
          widget.explanation.modelSha256,
          style: const TextStyle(
            color: AuraTokens.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: AuraTokens.accent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final explanation = widget.explanation;
    final signatureStatus = _integrityReport == null
        ? explanation.signatureVerified
            ? '[OK] Firma RSA verificada al cargar'
            : '[WARN] Firma RSA sin verificación (asset base)'
        : _integrityReport!.signatureVerified
            ? '[OK] Firma RSA verificada'
            : _integrityReport!.verified
                ? '[WARN] Sin firma RSA; SHA-256 verificado'
                : '[WARN] Sin verificación de integridad';
    final digestPrefix = explanation.modelSha256.length >= 8
        ? explanation.modelSha256.substring(0, 8)
        : explanation.modelSha256;

    return Card(
      color: AuraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AuraTokens.rMd),
        side: const BorderSide(color: AuraTokens.accent),
      ),
      child: ExpansionTile(
        key: ValueKey<String>('verdict-explanation-card-${explanation.id}'),
        iconColor: AuraTokens.accent,
        collapsedIconColor: AuraTokens.accent,
        title: Text(
          explanation.isThreat
              ? '¿Por qué se bloqueó?'
              : '¿Por qué se consideró seguro?',
          style: TextStyle(
            color: AuraTokens.accent,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${explanation.host} · '
          '${explanation.isThreat ? 'amenaza' : 'seguro'} · '
          '${explanation.source}',
          style: const TextStyle(
            color: AuraTokens.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
        onExpansionChanged: (expanded) {
          if (expanded) _verifyIntegrity();
        },
        childrenPadding: const EdgeInsets.fromLTRB(
          AuraTokens.s3,
          0,
          AuraTokens.s3,
          AuraTokens.s3,
        ),
        children: [
          if (explanation.signals.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sin señales de riesgo relevantes observadas.',
                style: TextStyle(color: AuraTokens.textPrimary),
              ),
            ),
          for (final signal in explanation.signals)
            Padding(
              padding: const EdgeInsets.only(bottom: AuraTokens.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${signal.label} · ${signal.value.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AuraTokens.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    signal.description,
                    style: const TextStyle(
                      color: AuraTokens.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AuraTokens.s1),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'UMBRAL DE DECISIÓN: '
              '${explanation.decisionThreshold.toStringAsFixed(2)}',
              style: const TextStyle(
                color: _terminalCyan,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Modelo v${explanation.modelVersion}',
              style: const TextStyle(
                color: AuraTokens.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _showFullDigest,
              style: TextButton.styleFrom(
                foregroundColor: AuraTokens.accent,
                padding: EdgeInsets.zero,
              ),
              child: Text(
                'SHA-256: $digestPrefix…',
                textAlign: TextAlign.left,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _isVerifying
                  ? 'Verificando el modelo…'
                  : '$signatureStatus${_integrityReport == null ? '' : '\n${_integrityReport!.message}'}',
              style: TextStyle(
                color: _integrityReport?.verified == false
                    ? AuraTokens.warning
                    : AuraTokens.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Wrap(
            spacing: AuraTokens.s2,
            children: [
              TextButton.icon(
                onPressed: widget.onOpenModelCard,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Model Card'),
                style: TextButton.styleFrom(
                  foregroundColor: AuraTokens.accent,
                ),
              ),
              if (explanation.isThreat)
                TextButton.icon(
                  onPressed: explanation.reportedFalsePositive
                      ? null
                      : () => widget.onReportFalsePositive(explanation.id),
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: Text(
                    explanation.reportedFalsePositive
                        ? 'Reportado localmente'
                        : 'Reportar falso positivo',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AuraTokens.warning,
                  ),
                ),
            ],
          ),
          if (explanation.isThreat)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Se registrará localmente para revisión; no se enviará telemetría.',
                style: TextStyle(
                  color: AuraTokens.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(height: AuraTokens.s2),
          const Text(
            'Las señales son observaciones del vector de características; '
            'el bosque de decisión no produce probabilidades calibradas.',
            style: TextStyle(
              color: AuraTokens.textMuted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          if (explanation.signals.any(
            (signal) => signal.label.contains('(señal auxiliar)'),
          ))
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'La distancia de edición es auxiliar y no forma parte del '
                'vector del modelo publicado.',
                style: TextStyle(
                  color: AuraTokens.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverageAuditCard extends StatelessWidget {
  const _CoverageAuditCard({
    required this.isVpnActive,
    required this.sniObserved,
    required this.encryptedSni,
    required this.directIp,
    required this.blocked,
    required this.dgaAlerts,
    required this.encryptedDnsBlocked,
    required this.quicBlocked,
    required this.decisionThreshold,
    required this.observedResolvers,
    required this.autotestStatus,
    required this.onRunAutotest,
  });

  final bool isVpnActive;
  final int sniObserved;
  final int encryptedSni;
  final int directIp;
  final int blocked;
  final int dgaAlerts;
  final int encryptedDnsBlocked;
  final int quicBlocked;
  final double? decisionThreshold;
  final List<String> observedResolvers;
  final String? autotestStatus;
  final VoidCallback onRunAutotest;

  @override
  Widget build(BuildContext context) => Card(
        color: AuraTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AuraTokens.rMd),
          side: const BorderSide(color: AuraTokens.accent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AuraTokens.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Auditoría de cobertura',
                style: TextStyle(
                  color: AuraTokens.accent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AuraTokens.s2),
              Text(
                'Eventos de la sesión: $sniObserved SNI observados, '
                '$blocked ${blocked == 1 ? 'bloqueo' : 'bloqueos'}, '
                '$dgaAlerts ${dgaAlerts == 1 ? 'alerta' : 'alertas'} DGA y '
                '$encryptedDnsBlocked '
                '${encryptedDnsBlocked == 1 ? 'bloqueo' : 'bloqueos'} '
                'de DNS cifrado y $quicBlocked paquetes QUIC descartados. '
                'UMBRAL DE DECISIÓN: '
                '${decisionThreshold?.toStringAsFixed(2) ?? 'sin inferencia'}.',
                style: const TextStyle(color: AuraTokens.textPrimary),
              ),
              const SizedBox(height: AuraTokens.s2),
              Text(
                'SNI cifrado (contenido no analizable): $encryptedSni · '
                'Conexión IP directa (sin dominio que evaluar): $directIp',
                style: const TextStyle(
                  color: AuraTokens.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: AuraTokens.s2),
              const Text(
                'Resolutores públicos observados:',
                style: TextStyle(
                  color: AuraTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                observedResolvers.isEmpty
                    ? 'Sin resolutores públicos observados en los eventos de esta sesión.'
                    : observedResolvers.join(', '),
                style: const TextStyle(
                  color: AuraTokens.textMuted,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AuraTokens.s2),
              const Text(
                'Límites conocidos: QUIC/DoQ sin SNI; ECH puede reducir '
                'la detección; inspección userspace, sin iptables.',
                style: TextStyle(
                  color: AuraTokens.warning,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AuraTokens.s2),
              FilledButton.icon(
                onPressed: onRunAutotest,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Ejecutar autotest'),
              ),
              if (autotestStatus != null) ...[
                const SizedBox(height: AuraTokens.s2),
                Text(
                  autotestStatus!,
                  style: const TextStyle(
                    color: AuraTokens.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _SyslogLine extends StatelessWidget {
  const _SyslogLine({required this.event});

  final AgentEvent event;

  @override
  Widget build(BuildContext context) {
    final terminalPrefix = event.data?['terminal_prefix'] as String?;
    final isThinking = event.data?['terminal_thinking'] == true;
    final isUser = terminalPrefix == '[USER]';
    final isAura = terminalPrefix == '[AURA]';
    final timestamp = '${event.ts.hour.toString().padLeft(2, '0')}:'
        '${event.ts.minute.toString().padLeft(2, '0')}:'
        '${event.ts.second.toString().padLeft(2, '0')}';
    final textColor = event.kind == AgentEventKind.error
        ? AuraTokens.danger
        : event.kind == AgentEventKind.warning
            ? AuraTokens.warning
            : AuraTokens.textPrimary;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF173A70) : AuraTokens.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isAura ? AuraTokens.accent.withAlpha(65) : Colors.white.withAlpha(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  isThinking ? 'AURA · ANALIZANDO' : 'AURA · $timestamp',
                  style: const TextStyle(
                    color: AuraTokens.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            SelectableText(
              event.message,
              style: TextStyle(color: textColor, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalInput extends StatelessWidget {
  const _TerminalInput({
    required this.controller,
    required this.isListening,
    required this.isRunning,
    required this.onSubmitted,
    required this.onVoice,
  });

  final TextEditingController controller;
  final bool isListening;
  final bool isRunning;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 8),
      decoration: BoxDecoration(
        color: AuraTokens.surface,
        border: Border(top: BorderSide(color: AuraTokens.accent.withAlpha(55))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isRunning,
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: onSubmitted,
              cursorColor: AuraTokens.accent,
              style: const TextStyle(
                color: AuraTokens.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: 'Dile a Aura qué necesitas proteger…',
                hintStyle: TextStyle(
                  color: _terminalGreen,
                  fontFamily: 'monospace',
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
          IconButton(
            tooltip: isListening ? 'Escuchando' : 'Dictar consulta',
            onPressed: isRunning || isListening ? null : onVoice,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            icon: Icon(
              isListening ? Icons.hearing : Icons.mic_none,
              color: AuraTokens.accent,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
