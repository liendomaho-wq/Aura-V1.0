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
import '../llm/aura_llm_setup_controller.dart';
import '../providers/aura_state_provider.dart';
import '../services/aura_local_telemetry.dart';
import '../theme/aura_tokens.dart';
import '../widgets/aura_avatar.dart';
import '../widgets/aura_capability_ring.dart';
import '../widgets/aura_command_filament.dart';
import '../widgets/aura_intent_constellation.dart';
import '../widgets/aura_llm_setup_scope.dart';
import '../widgets/aura_llm_setup_sheet.dart';
import '../widgets/aura_neural_field.dart';
import '../widgets/aura_presence.dart';
import '../widgets/aura_signal_header.dart';

const Color _terminalGreen = Color(0xFF00FF00);
const Color _terminalYellow = Color(0xFFFFFF00);
const Color _terminalCyan = Color(0xFF00FFFF);
const int maxInstructionLength = 240;

String _localTelemetryDomainLabel(Map<String, dynamic> event) {
  final hash = event['domain_hash'];
  if (hash is! String || hash.length < 12) return 'dominio protegido';
  return 'dominio protegido ${hash.substring(0, 12)}';
}

class AuraCoreScreen extends StatefulWidget {
  const AuraCoreScreen({super.key});

  @override
  State<AuraCoreScreen> createState() => _AuraCoreScreenState();
}

class _AuraCoreScreenState extends State<AuraCoreScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _shieldChannel = MethodChannel(
    'com.ciberdefensa.aura/shield',
  );
  static const MethodChannel _voiceChannel = MethodChannel(
    'com.ciberdefensa.aura/voice',
  );
  static const MethodChannel _telemetryChannel = MethodChannel(
    'com.ciberdefensa.aura/telemetry',
  );
  static const MethodChannel _securityChannel = MethodChannel(
    'com.ciberdefensa.aura/security',
  );

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  AuraNetworkAuditor? _networkAuditor;
  AuraAIBrain? _aiBrain;
  StreamSubscription<NetworkAuditEvent>? _networkEventSubscription;
  bool _isListening = false;
  bool _isRunning = false;
  bool _isShieldBusy = false;
  bool _shieldStatusKnown = false;
  bool _shieldServiceActive = false;
  int _shieldStatusGeneration = 0;
  Timer? _shieldStatusTimer;
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
    WidgetsBinding.instance.addObserver(this);
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
      unawaited(_refreshShieldStatus());
      _shieldStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_refreshShieldStatus());
      });
      return;
    }

    controller.reportError(
      'Acceso a la consola denegado: Android no confirmó la autenticación local. '
      'Las acciones defensivas permanecen bloqueadas; vuelva a la pantalla inicial e inténtelo de nuevo.',
    );
    if (!mounted) return;
    setState(() => _isAuthenticated = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isAuthenticated) {
      unawaited(_refreshShieldStatus());
    }
  }

  Future<void> _refreshShieldStatus() async {
    if (!mounted || !_isAuthenticated || _isShieldBusy) return;
    final generation = ++_shieldStatusGeneration;
    try {
      final status = await _shieldChannel
          .invokeMapMethod<String, dynamic>('getShieldStatus')
          .timeout(const Duration(seconds: 3));
      if (status == null ||
          status['status_verified'] != true ||
          status['service_active'] is! bool ||
          status['vpn_interface_active'] is! bool ||
          status['forwarding_active'] is! bool ||
          status['isolation_active'] is! bool) {
        throw const FormatException('Estado VPN no verificable.');
      }
      final active = status['forwarding_active'] == true;
      if (active &&
          (status['service_active'] != true ||
              status['vpn_interface_active'] != true ||
              status['isolation_active'] == true)) {
        throw const FormatException('Estado VPN contradictorio.');
      }
      if (!mounted || generation != _shieldStatusGeneration || _isShieldBusy) {
        return;
      }
      final serviceActive = status['service_active'] == true;
      context.read<AuraStateProvider>().setVpnActive(active);
      if (!_shieldStatusKnown || _shieldServiceActive != serviceActive) {
        setState(() {
          _shieldStatusKnown = true;
          _shieldServiceActive = serviceActive;
        });
      }
    } on Object {
      if (!mounted || generation != _shieldStatusGeneration || _isShieldBusy) {
        return;
      }
      context.read<AuraStateProvider>().setVpnActive(false);
      if (_shieldStatusKnown || _shieldServiceActive) {
        setState(() {
          _shieldStatusKnown = false;
          _shieldServiceActive = false;
        });
      }
    }
  }

  Future<void> _refreshAccessibilityServices() async {
    try {
      final report = await _securityChannel.invokeMapMethod<Object?, Object?>(
        'checkHostileEnvironment',
      );
      final rawPackages = report?['untrustedAccessibilityServicePackages'];
      if (rawPackages is! List ||
          rawPackages.any((value) => value is! String)) {
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
      final opened = await _securityChannel.invokeMethod<bool>(
        'openAccessibilitySettings',
      );
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
    _shieldStatusGeneration++;
    _shieldStatusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
          _shieldStatusGeneration++;
          state.setVpnActive(false);
          // Revocation is not proof that the service and JNI worker finished
          // shutting down. Require a fresh, verified status before toggling.
          if (mounted && (_shieldStatusKnown || _shieldServiceActive)) {
            setState(() {
              _shieldStatusKnown = false;
              _shieldServiceActive = false;
            });
          }
          unawaited(_refreshShieldStatus());
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
      final stored = await AuraLocalTelemetry.recordNetworkEvent(
        event.toJson(),
      );
      if (stored && mounted) {
        await _refreshLocalTelemetryEvents();
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
          ? state.activeDecisionThreshold?.toStringAsFixed(2) ??
                'sin inferencia'
          : latestExplanation.decisionThreshold.toStringAsFixed(2);
      _coverageAutotestStatus =
          'Diagnóstico local completado. Túnel VPN: '
          '${!_shieldStatusKnown
              ? 'estado no confirmado'
              : state.isVpnActive
              ? 'activo'
              : _shieldServiceActive
              ? 'sin forwarding'
              : 'inactivo'}. '
          'Eventos de sesión: ${state.blockedEvents} señales de bloqueo, '
          '${state.dgaAlertEvents} alertas DGA, '
          '${state.encryptedDnsBlocks} bloqueos de DNS cifrado y '
          '${state.quicBlocked} paquetes QUIC descartados. '
          'TLS/SNI: integrado en sesiones TCP del túnel; cobertura limitada y '
          'no validada por este diagnóstico. '
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
    context.read<AuraStateProvider>().markExplanationAsFalsePositive(
      explanationId,
    );
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

      // Execute immediately. Progress must come from the real agent/tool
      // callbacks; artificial delays and fabricated "thinking" events make
      // the interface imply work that has not happened.
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
    if (_isShieldBusy || !_isAuthenticated || !_shieldStatusKnown) return;
    final serviceWasActive = _shieldServiceActive;
    _shieldStatusGeneration++;
    setState(() => _isShieldBusy = true);
    try {
      await AgentController.instance.run(
        serviceWasActive ? 'desactivar defensas' : 'activar defensas',
        // This callback is reached only after the user taps the visible toggle.
        confirmedByUser: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isShieldBusy = false);
        unawaited(_refreshShieldStatus());
      }
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
      var localEvents = endpointConfigured
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
                          final persisted = await AuraLocalTelemetry.setEnabled(
                            value,
                          );
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            localEnabled = persisted;
                            if (!persisted) localEvents = const [];
                          });
                          if (mounted) {
                            setState(() {
                              _localTelemetryEnabled = persisted;
                              if (!persisted) {
                                _localTelemetryEvents = const [];
                              }
                            });
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
    final hash = event['domain_hash'];
    final domain = hash is String && hash.length >= 12
        ? 'dominio protegido ${hash.substring(0, 12)}'
        : 'dominio protegido';
    final action = event['action'] ?? event['outcome'] ?? '';
    return '$time · $type · $domain · $action';
  }

  void _scrollToLatest(int eventCount, {bool force = false}) {
    if (!force && eventCount == _lastRenderedEventCount) return;
    final keepInitialOverview = _lastRenderedEventCount < 0 && !force;
    _lastRenderedEventCount = eventCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || keepInitialOverview) return;
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuraStateProvider>();
    final compactLayout = MediaQuery.sizeOf(context).height < 720;
    final vpnActive = state.isVpnActive;
    final quickActionsEnabled = !_isRunning && _isAuthenticated;
    final llmSetup = AuraLlmSetupScope.maybeOf(context);
    final AuraCapabilityState modelCapability;
    switch (llmSetup?.status) {
      case AuraLlmSetupStatus.ready:
        modelCapability = AuraCapabilityState.ready;
      case AuraLlmSetupStatus.downloading:
      case AuraLlmSetupStatus.verifying:
      case AuraLlmSetupStatus.loading:
        modelCapability = AuraCapabilityState.preparing;
      default:
        modelCapability = AuraCapabilityState.unavailable;
    }

    final avatarMode = _isListening
        ? AuraAvatarMode.listening
        : _isRunning
        ? AuraAvatarMode.analyzing
        : switch (state.securityLevel) {
            AuraSecurityLevel.critical => AuraAvatarMode.alert,
            AuraSecurityLevel.warning => AuraAvatarMode.warning,
            AuraSecurityLevel.safe =>
              vpnActive ? AuraAvatarMode.protecting : AuraAvatarMode.available,
          };

    final neuralMode = !_isAuthenticated
        ? AuraNeuralMode.idle
        : _isListening
        ? AuraNeuralMode.listening
        : _isRunning
        ? AuraNeuralMode.thinking
        : switch (state.securityLevel) {
            AuraSecurityLevel.critical => AuraNeuralMode.alert,
            AuraSecurityLevel.warning => AuraNeuralMode.warning,
            AuraSecurityLevel.safe =>
              vpnActive ? AuraNeuralMode.guarding : AuraNeuralMode.idle,
          };

    final statusLine = _isRunning
        ? 'Estoy procesando tu solicitud…'
        : _isListening
        ? 'Te escucho. Hablá con naturalidad.'
        : state.securityLevel == AuraSecurityLevel.critical
        ? 'Detecté una amenaza crítica. Necesito tu atención.'
        : state.securityLevel == AuraSecurityLevel.warning
        ? 'Hay señales que no cierran. Puedo explicártelas.'
        : modelCapability == AuraCapabilityState.ready
        ? 'IA local activa. Puedo pensar, explicar y actuar contigo.'
        : 'Presencia activa. Prepará la IA para razonar en tu dispositivo.';

    final shieldMetric = !_shieldStatusKnown
        ? 'VPN local opcional · estado no confirmado'
        : vpnActive
        ? 'VPN local opcional · activa'
        : _shieldServiceActive
        ? 'VPN local opcional · sin forwarding'
        : 'VPN local opcional · inactiva';
    final presenceMetrics = <String>[
      '${state.blockedEvents} señales de bloqueo',
      shieldMetric,
    ];
    final showLlmBanner =
        llmSetup != null && _showsLlmSetupBanner(llmSetup.status);

    final intents = <AuraIntentSpec>[
      AuraIntentSpec(
        label: 'Analizar',
        icon: Icons.manage_search_rounded,
        color: AuraTokens.accent,
        onTap: quickActionsEnabled
            ? () => _dispatch('audita dispositivo')
            : null,
      ),
      AuraIntentSpec(
        label: 'Escudo',
        icon: Icons.wifi_rounded,
        color: vpnActive ? AuraTokens.success : AuraTokens.accentViolet,
        onTap: quickActionsEnabled && !_isShieldBusy && _shieldStatusKnown
            ? _toggleShield
            : null,
      ),
      AuraIntentSpec(
        label: 'Privacidad',
        icon: Icons.lock_outline_rounded,
        color: AuraTokens.accentViolet,
        onTap: _showTelemetrySettings,
      ),
      AuraIntentSpec(
        label: 'IA local',
        icon: Icons.auto_awesome_rounded,
        color: modelCapability == AuraCapabilityState.ready
            ? AuraTokens.success
            : AuraTokens.accentViolet,
        onTap: llmSetup == null
            ? (quickActionsEnabled ? () => _dispatch('ayuda') : null)
            : () => showAuraLlmSetupSheet(context, llmSetup),
      ),
      AuraIntentSpec(
        label: 'Informes',
        icon: Icons.query_stats_rounded,
        color: AuraTokens.accent,
        onTap: quickActionsEnabled ? () => _dispatch('estado') : null,
      ),
      AuraIntentSpec(
        label: 'Auditoría',
        icon: Icons.fact_check_outlined,
        color: AuraTokens.success,
        onTap: () {
          setState(() => _showCoverageAudit = true);
          _runCoverageAutotest();
        },
      ),
      AuraIntentSpec(
        label: 'Ayuda',
        icon: Icons.help_outline_rounded,
        color: AuraTokens.textMuted,
        onTap: quickActionsEnabled ? () => _dispatch('ayuda') : null,
      ),
    ];

    return Scaffold(
      backgroundColor: AuraTokens.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AuraNeuralField(mode: neuralMode),
          SafeArea(
            child: Column(
              children: [
                AuraSignalHeader(
                  compact: compactLayout,
                  showCoverageAudit: _showCoverageAudit,
                  onTelemetry: _showTelemetrySettings,
                  onCoverageAudit: () =>
                      setState(() => _showCoverageAudit = !_showCoverageAudit),
                  isAuthenticated: _isAuthenticated,
                  isShieldBusy: _isShieldBusy,
                  shieldStatusKnown: _shieldStatusKnown,
                  shieldServiceActive: _shieldServiceActive,
                  vpnActive: vpnActive,
                  onToggleShield: _toggleShield,
                ),
                Expanded(
                  key: const ValueKey<String>('aura-overview-scroll'),
                  child: ListView(
                    key: const ValueKey<String>('aura-event-list'),
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      18,
                      compactLayout ? 2 : 10,
                      18,
                      22,
                    ),
                    children: [
                      AuraPresence(
                        compact: compactLayout,
                        avatarMode: avatarMode,
                        model: modelCapability,
                        classifier: AuraCapabilityState.ready,
                        defense: vpnActive
                            ? AuraCapabilityState.ready
                            : AuraCapabilityState.unavailable,
                        statusLine: statusLine,
                        aiStatusLabel:
                            llmSetup?.statusLabel ??
                            'Aura Básica · IA local no configurada',
                        aiStatusReady:
                            modelCapability == AuraCapabilityState.ready,
                        onAiStatusTap: llmSetup == null
                            ? null
                            : () => showAuraLlmSetupSheet(context, llmSetup),
                        metrics: presenceMetrics,
                      ),
                      SizedBox(height: compactLayout ? 12 : 18),
                      AuraIntentConstellation(intents: intents),
                      SizedBox(height: compactLayout ? 10 : 18),
                      if (showLlmBanner)
                        _AuraLlmSetupBanner(
                          controller: llmSetup,
                          onPrepare: () =>
                              showAuraLlmSetupSheet(context, llmSetup),
                        ),
                      if (_isAuthenticated)
                        StreamBuilder<AgentEvent>(
                          stream: AgentController.instance.events,
                          builder: (context, snapshot) {
                            final events = AgentController.instance.history;
                            final explanationCount =
                                state.explanationHistory.length;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_showCoverageAudit)
                                  _CoverageAuditCard(
                                    isVpnActive: state.isVpnActive,
                                    sniObserved: state.sniObservedEvents,
                                    encryptedSni: state.encryptedSniEvents,
                                    directIp: state.directIpEvents,
                                    blocked: state.blockedEvents,
                                    dgaAlerts: state.dgaAlertEvents,
                                    encryptedDnsBlocked:
                                        state.encryptedDnsBlocks,
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
                                if (_untrustedAccessibilityPackages.isNotEmpty)
                                  _AccessibilitySignal(
                                    packages: _untrustedAccessibilityPackages,
                                    onOpenSettings: _openAccessibilitySettings,
                                    onRetry: _refreshAccessibilityServices,
                                  )
                                else if (_accessibilityCheckFailed)
                                  _AccessibilityRetry(
                                    onRetry: _refreshAccessibilityServices,
                                  ),
                                if (events.isEmpty) const _SilentStream(),
                                for (final event in events)
                                  _SyslogLine(event: event),
                              ],
                            );
                          },
                        )
                      else
                        const _SilentStream(),
                    ],
                  ),
                ),
                _SignalReadout(
                  blocked: state.blockedEvents,
                  aiReady: modelCapability == AuraCapabilityState.ready,
                  vpnActive: vpnActive,
                ),
                AuraCommandFilament(
                  controller: _inputController,
                  isListening: _isListening,
                  isProcessing: _isRunning || !_isAuthenticated,
                  onSubmitted: _dispatch,
                  onVoice: _captureVoice,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _showsLlmSetupBanner(AuraLlmSetupStatus status) =>
    status == AuraLlmSetupStatus.notInstalled ||
    status == AuraLlmSetupStatus.paused ||
    status == AuraLlmSetupStatus.failed;

class _AuraLlmSetupBanner extends StatelessWidget {
  const _AuraLlmSetupBanner({
    required this.controller,
    required this.onPrepare,
  });

  final AuraLlmSetupController controller;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    final paused = controller.status == AuraLlmSetupStatus.paused;
    final failed = controller.status == AuraLlmSetupStatus.failed;
    return Container(
      key: const ValueKey<String>('aura-llm-setup-banner'),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2, right: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: (failed ? AuraTokens.danger : AuraTokens.accentViolet)
                .withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.auto_awesome_rounded,
                color: failed ? AuraTokens.danger : AuraTokens.accentViolet,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failed
                      ? 'La preparación de Aura IA requiere atención'
                      : 'Aura Básica activa · prepará la IA local',
                  style: const TextStyle(
                    color: AuraTokens.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            failed
                ? controller.errorMessage ??
                      'Revisá el estado del modelo local.'
                : paused
                ? 'La descarga quedó en pausa y se puede reanudar sin perder '
                      'el progreso verificado.'
                : '${controller.source.identityLabel} · '
                      '${controller.source.sizeLabel}. La inferencia local es '
                      'opcional y el archivo se verifica antes de cargarse.',
            style: const TextStyle(
              color: AuraTokens.textMuted,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey<String>('aura-llm-banner-action'),
              onPressed: onPrepare,
              icon: Icon(
                paused ? Icons.play_arrow_rounded : Icons.download_rounded,
                size: 16,
              ),
              label: Text(
                paused
                    ? 'REANUDAR'
                    : failed
                    ? 'REVISAR'
                    : 'PREPARAR IA',
              ),
              style: TextButton.styleFrom(
                foregroundColor: AuraTokens.accent,
                textStyle: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalTelemetryPanel extends StatelessWidget {
  const _LocalTelemetryPanel({required this.events, required this.enabled});

  final List<Map<String, dynamic>> events;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey<String>('local-telemetry-panel'),
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2, right: 4),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: _terminalGreen.withValues(alpha: 0.42),
          width: 1.4,
        ),
      ),
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
            style: TextStyle(color: AuraTokens.textMuted, fontSize: 10),
          )
        else
          for (final event in events.reversed.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${_formatLocalTimestamp(event['timestamp'])} · '
                '${event['type'] ?? 'evento'} · '
                '${_localTelemetryDomainLabel(event)}',
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

  static String _formatLocalTimestamp(Object? timestamp) => timestamp is int
      ? DateTime.fromMillisecondsSinceEpoch(
          timestamp,
        ).toIso8601String().replaceFirst('T', ' ')
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

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AuraTokens.accent.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey<String>('verdict-explanation-card-${explanation.id}'),
          tilePadding: const EdgeInsets.only(left: 12, right: 4),
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          iconColor: AuraTokens.accent,
          collapsedIconColor: AuraTokens.accent,
          title: Text(
            key: ValueKey<String>(
              'verdict-explanation-title-${explanation.id}',
            ),
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
                key: ValueKey<String>(
                  'verdict-explanation-sha256-${explanation.id}',
                ),
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
                    key: ValueKey<String>(
                      'report-false-positive-${explanation.id}',
                    ),
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
                  style: TextStyle(color: AuraTokens.textMuted, fontSize: 11),
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
                  style: TextStyle(color: AuraTokens.textMuted, fontSize: 11),
                ),
              ),
          ],
        ),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2, right: 4),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: AuraTokens.accent.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(left: 4),
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
          const Text(
            'TLS/SNI: el parser está integrado en sesiones TCP del túnel y '
            'puede aplicar reglas a nombres visibles. No inspecciona QUIC ni '
            'descifra ECH; su cobertura requiere validación en el dispositivo.',
            style: TextStyle(
              color: AuraTokens.warning,
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
            style: TextStyle(color: AuraTokens.warning, fontSize: 12),
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
    final timestamp =
        '${event.ts.hour.toString().padLeft(2, '0')}:'
        '${event.ts.minute.toString().padLeft(2, '0')}:'
        '${event.ts.second.toString().padLeft(2, '0')}';
    final accent = event.kind == AgentEventKind.error
        ? AuraTokens.danger
        : event.kind == AgentEventKind.warning
        ? AuraTokens.warning
        : isUser
        ? AuraTokens.accentViolet
        : isAura
        ? AuraTokens.accent
        : AuraTokens.textMuted;
    final textColor = event.kind == AgentEventKind.error
        ? AuraTokens.danger
        : event.kind == AgentEventKind.warning
        ? AuraTokens.warning
        : isUser
        ? const Color(0xFFD9E8FF)
        : AuraTokens.textPrimary;
    final speaker = isUser
        ? 'TÚ'
        : isAura
        ? 'AURA'
        : 'SISTEMA';

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 54,
            top: 7,
            bottom: -18,
            child: Container(width: 1, color: accent.withValues(alpha: 0.16)),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timestamp,
                      style: const TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 8.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      speaker,
                      style: TextStyle(
                        color: accent,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.95),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isThinking)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          'PROCESANDO',
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.85),
                            fontSize: 7.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    SelectableText(
                      event.message,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignalReadout extends StatelessWidget {
  const _SignalReadout({
    required this.blocked,
    required this.aiReady,
    required this.vpnActive,
  });

  final int blocked;
  final bool aiReady;
  final bool vpnActive;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AuraTokens.textMuted.withValues(alpha: 0.9),
      fontSize: 7.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.85,
      fontFamily: 'monospace',
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 5),
      child: Row(
        children: [
          _ReadoutDot(
            color: blocked > 0 ? AuraTokens.warning : AuraTokens.success,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '$blocked BLOQUEOS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Expanded(
            child: Text(
              aiReady ? 'IA LOCAL' : 'IA BÁSICA',
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Expanded(
            child: Text(
              vpnActive ? 'ESCUDO ACTIVO' : 'ESCUDO INACTIVO',
              maxLines: 1,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadoutDot extends StatelessWidget {
  const _ReadoutDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6),
        ],
      ),
    );
  }
}

class _SilentStream extends StatelessWidget {
  const _SilentStream();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Text(
        'El hilo está en silencio. Pedile a Aura una comprobación.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AuraTokens.textMuted,
          fontSize: 10.5,
          height: 1.5,
        ),
      ),
    );
  }
}

class _AccessibilitySignal extends StatelessWidget {
  const _AccessibilitySignal({
    required this.packages,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final List<String> packages;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2, right: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AuraTokens.warning.withValues(alpha: 0.7),
            width: 1.4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SERVICIOS DE ACCESIBILIDAD ACTIVOS PODRÍAN MANIPULAR LA APP',
            style: TextStyle(
              color: _terminalYellow,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Paquetes: ${packages.join(', ')}',
            style: const TextStyle(
              color: AuraTokens.warning,
              fontFamily: 'monospace',
              fontSize: 10,
              height: 1.4,
            ),
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('ABRIR AJUSTES'),
              ),
              TextButton(
                onPressed: onRetry,
                child: const Text('VERIFICAR DE NUEVO'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccessibilityRetry extends StatelessWidget {
  const _AccessibilityRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onRetry,
        style: TextButton.styleFrom(foregroundColor: AuraTokens.warning),
        child: const Text(
          '[WARN] No se pudo verificar accesibilidad · REINTENTAR',
          style: TextStyle(fontFamily: 'monospace', fontSize: 10.5),
        ),
      ),
    );
  }
}
