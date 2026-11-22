import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_event.dart';
import '../ai_brain.dart';
import '../explanation/aura_verdict_explanation.dart';
import '../firewall/aura_firewall_policy.dart';
import '../infrastructure/agent/aura_intent_parser.dart';
import '../models/aura_model_integrity_report.dart';
import '../network/underlying_network_label.dart';
import '../network_auditor.dart';
import '../llm/aura_llm_setup_controller.dart';
import '../secure_vault.dart';
import '../security/aura_finding.dart';
import '../providers/aura_state_provider.dart';
import '../services/aura_local_telemetry.dart';
import '../theme/aura_tokens.dart';
import '../voice_engine.dart';
import '../voice/aura_briefing.dart';
import '../widgets/aura_avatar.dart';
import '../widgets/aura_command_filament.dart';
import '../widgets/aura_llm_setup_scope.dart';
import '../widgets/aura_llm_setup_sheet.dart';
import '../widgets/aura_neural_core.dart';
import '../widgets/aura_neural_field.dart';
import 'aura_intro.dart';
import 'aura_places.dart';
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

enum _AuraPanel { home, chat, console }

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
  static const EventChannel _underlyingNetworkChannel = EventChannel(
    'com.ciberdefensa.aura/underlying_network',
  );

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  AuraNetworkAuditor? _networkAuditor;
  AuraAIBrain? _aiBrain;
  StreamSubscription<NetworkAuditEvent>? _networkEventSubscription;
  StreamSubscription<dynamic>? _underlyingNetworkSub;
  String _underlyingNetworkLabel = 'Sin conexión';
  bool _isListening = false;
  bool _isRunning = false;
  bool _isShieldBusy = false;
  bool _shieldStatusKnown = false;
  bool _shieldServiceActive = false;
  int _shieldStatusGeneration = 0;
  Timer? _shieldStatusTimer;
  Timer? _crashReportTimer;
  Completer<String?>? _crashReportResult;
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
  _AuraPanel _panel = _AuraPanel.home;
  bool _showIntro = false;
  bool _spokeOpening = false;
  final AuraAlertGate _alertGate = AuraAlertGate();
  String? _tunnelBytesLabel;
  String _firewallModeLabel = 'Normal';
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenUnderlyingNetwork();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticateConsole();
      unawaited(_loadHomePreferences());
    });
  }

  void _listenUnderlyingNetwork() {
    _underlyingNetworkSub = _underlyingNetworkChannel
        .receiveBroadcastStream()
        .listen((event) {
          final label = underlyingNetworkLabelFromEvent(event);
          if (!mounted || label == _underlyingNetworkLabel) return;
          setState(() => _underlyingNetworkLabel = label);
        }, onError: (Object _) {});
    unawaited(_queryUnderlyingNetwork());
  }

  Future<void> _loadHomePreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      AuraVoiceEngine.muted.value =
          preferences.getBool('aura_voice_muted_v1') ?? false;
      final seen = preferences.getBool('aura_intro_seen_v1') ?? false;
      if (!seen && mounted) setState(() => _showIntro = true);
    } on Object {
      // A storage failure must not cover the console.
    }
    unawaited(_pushStoredFirewallPolicy());
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_readTunnelBytes());
    });
    unawaited(_readTunnelBytes());
  }

  Future<void> _finishIntro() async {
    if (mounted) setState(() => _showIntro = false);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('aura_intro_seen_v1', true);
    } on Object {
      // The intro can still be opened again from Ajustes.
    }
  }

  Future<void> _setVoiceMuted(bool muted) async {
    AuraVoiceEngine.muted.value = muted;
    if (mounted) setState(() {});
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('aura_voice_muted_v1', muted);
    } on Object {
      // The mute still applies for this process.
    }
  }

  Future<void> _speakOpening() async {
    if (_spokeOpening || AuraVoiceEngine.muted.value) return;
    _spokeOpening = true;
    final state = context.read<AuraStateProvider>();
    await AgentController.instance.speakAloud(
      auraStatusBrief(
        defenseActive: state.isVpnActive,
        networkLabel: _underlyingNetworkLabel,
        blocksSeenToday: auraBlocksSeenToday(
          state.telemetryEvents,
          DateTime.now(),
        ),
      ),
    );
  }

  void _announceThreat(String domain, NetworkAuditAction action) {
    if (AuraVoiceEngine.muted.value || !_alertGate.allow(DateTime.now())) {
      return;
    }
    final host = domain.trim();
    if (host.isEmpty) return;
    final line = action == NetworkAuditAction.dgaAlert
        ? 'Alerta. Dominio sospechoso: $host.'
        : 'Bloqueé $host.';
    unawaited(AgentController.instance.speakAloud(line));
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    unawaited(HapticFeedback.lightImpact());
  }

  Future<void> _readTunnelBytes() async {
    try {
      const channel = MethodChannel('com.aura.cyberdefense/engine');
      final raw = await channel.invokeMethod<Object>('getTunnelStats');
      if (!mounted || raw is! List || raw.length < 4) return;
      final sent = raw[1];
      final received = raw[3];
      if (sent is! int || received is! int || sent < 0 || received < 0) {
        return;
      }
      setState(() => _tunnelBytesLabel = 'Túnel ${sent + received} B');
    } on Object {
      if (!mounted || _tunnelBytesLabel != null) return;
      setState(() => _tunnelBytesLabel = 'Túnel sin lectura');
    }
  }

  Future<void> _pushStoredFirewallPolicy() async {
    try {
      final encoded = await AuraSecureVault().readFirewallPolicy();
      if (encoded == null || encoded.isEmpty) return;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return;
      final policy = AuraFirewallPolicy.parse(
        Map<String, dynamic>.from(decoded),
      );
      policy.extraDisallowed('com.ciberdefensa.aura');
      await _shieldChannel.invokeMethod<Object>(
        'setFirewallPolicy',
        policy.toJson(),
      );
      if (!mounted) return;
      setState(() => _firewallModeLabel = auraFirewallModeTitle(policy.mode));
    } on Object {
      // A missing policy or plugin leaves the tunnel in Normal.
    }
  }

  Future<void> _restartDefense() async {
    await AgentController.instance.run(
      'desactivar defensas',
      confirmedByUser: true,
    );
    await AgentController.instance.run(
      'activar defensas',
      confirmedByUser: true,
    );
    await _refreshShieldStatus();
  }

  void _openChat() {
    setState(() => _panel = _AuraPanel.chat);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _panel != _AuraPanel.chat || _isListening) return;
      unawaited(_captureVoice());
    });
  }

  Future<void> _queryUnderlyingNetwork() async {
    try {
      final status = await _shieldChannel.invokeMapMethod<String, dynamic>(
        'getUnderlyingNetwork',
      );
      final label = underlyingNetworkLabelFromEvent(status);
      if (!mounted || label == _underlyingNetworkLabel) return;
      setState(() => _underlyingNetworkLabel = label);
    } on Object {
      // The event channel remains the live source when this query is unavailable.
    }
  }

  Future<void> _authenticateConsole() async {
    final controller = AgentController.instance;
    controller.bindSecurityState(context.read<AuraStateProvider>());
    final authenticated = await controller.authenticateBiometricDevice();
    if (!mounted) return;
    unawaited(_refreshAccessibilityServices());
    await _initializeTelemetryMode();
    if (!mounted) return;
    unawaited(_showPendingCrashReport());
    if (authenticated) {
      controller.initGreeting();
      _startNetworkAuditor();
      setState(() => _isAuthenticated = true);
      unawaited(_refreshShieldStatus());
      unawaited(_speakOpening());
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

  /// Shows the last crash / VPN failure captured on the device so testers
  /// without adb can copy the exact stack trace and send it.
  ///
  /// A missing plugin, a null report, or a channel that never answers must
  /// not block the console. The wait is cancelled in [dispose] so it cannot
  /// leave a timer running after the screen is gone.
  Future<void> _showPendingCrashReport() async {
    final String? report;
    try {
      report = await _loadLastCrashReport();
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } on TimeoutException {
      return;
    } on Object {
      return;
    }
    final text = report?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF07110E),
        title: const Text(
          'Diagnóstico del último fallo',
          style: TextStyle(color: _terminalGreen, fontFamily: 'monospace'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aura se cerró o no pudo iniciar el Escudo. Pulsa COPIAR y '
                'envía este texto al soporte.',
                style: TextStyle(color: _terminalYellow, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      color: _terminalGreen,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Diagnóstico copiado.')),
              );
            },
            child: const Text('COPIAR'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _shieldChannel.invokeMethod<bool>('clearLastCrashReport');
              } on Object {
                // Keep the dialog dismissible even if the file cannot be removed.
              }
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('BORRAR'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }

  Future<String?> _loadLastCrashReport() {
    final result = Completer<String?>();
    final previous = _crashReportResult;
    if (previous != null && !previous.isCompleted) {
      previous.completeError(StateError('crash report lookup replaced'));
    }
    _crashReportResult = result;
    _crashReportTimer?.cancel();
    _crashReportTimer = Timer(const Duration(seconds: 5), () {
      if (!result.isCompleted) {
        result.completeError(
          TimeoutException('getLastCrashReport', const Duration(seconds: 5)),
        );
      }
    });
    unawaited(() async {
      try {
        final report = await _shieldChannel.invokeMethod<String>(
          'getLastCrashReport',
        );
        _crashReportTimer?.cancel();
        if (!result.isCompleted) result.complete(report);
      } catch (error, stackTrace) {
        _crashReportTimer?.cancel();
        if (!result.isCompleted) {
          result.completeError(error, stackTrace);
        }
      }
    }());
    return result.future;
  }

  void _cancelPendingCrashReport() {
    _crashReportTimer?.cancel();
    _crashReportTimer = null;
    final pending = _crashReportResult;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('crash report lookup cancelled'));
    }
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
          status['service_active'] is! bool ||
          status['vpn_interface_active'] is! bool ||
          status['forwarding_active'] is! bool ||
          status['isolation_active'] is! bool) {
        throw const FormatException('Estado VPN no verificable.');
      }
      final verified = status['status_verified'] == true;
      final serviceActive = status['service_active'] == true;
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
      // An unverifiable running service stays unknown so we do not start a
      // second tunnel. An idle service with status_verified != true still
      // lets the user retry after a failed start or unclean shutdown.
      if (status['status_verified'] != true && serviceActive) {
        context.read<AuraStateProvider>().setVpnActive(false);
        if (_shieldStatusKnown || !_shieldServiceActive) {
          setState(() {
            _shieldStatusKnown = false;
            _shieldServiceActive = true;
          });
        }
        return;
      }
      context.read<AuraStateProvider>().setVpnActive(verified && active);
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
    _statsTimer?.cancel();
    _cancelPendingCrashReport();
    unawaited(_underlyingNetworkSub?.cancel());
    _underlyingNetworkSub = null;
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
        if (event.action == NetworkAuditAction.blocked ||
            event.action == NetworkAuditAction.dgaAlert) {
          _announceThreat(event.requestedDomain, event.action);
        }
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
          'Diagnóstico local completado. Escudo: '
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

  Future<void> _runFindingsScan() async {
    if (!_isAuthenticated || _isRunning) return;
    setState(() => _isRunning = true);
    try {
      final controller = AgentController.instance;
      await AuraIntentParser.executeCommand('audita dispositivo');
      if (!mounted) return;
      await AuraIntentParser.executeCommand('escanea aplicaciones');
      if (!mounted) return;
      _scrollToLatest(controller.history.length, force: true);
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
    final findingsReport = state.findingsReport;
    final compactLayout = MediaQuery.sizeOf(context).height < 720;
    final vpnActive = state.isVpnActive;
    final quickActionsEnabled = !_isRunning && _isAuthenticated;
    final llmSetup = AuraLlmSetupScope.maybeOf(context);

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

    final shieldMetric = !_shieldStatusKnown
        ? 'Escudo local · estado no confirmado'
        : vpnActive
        ? 'Escudo local · activo'
        : _shieldServiceActive
        ? 'Escudo local · sin forwarding'
        : 'Escudo local · inactivo';
    final showLlmBanner =
        llmSetup != null && _showsLlmSetupBanner(llmSetup.status);

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
                  networkLabel: _underlyingNetworkLabel,
                  onToggleShield: _toggleShield,
                ),
                Expanded(
                  key: const ValueKey<String>('aura-overview-scroll'),
                  child: _panel == _AuraPanel.console
                      ? ListView(
                          key: const ValueKey<String>('aura-event-list'),
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            18,
                            compactLayout ? 2 : 10,
                            18,
                            22,
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const ValueKey<String>('aura-close-panel'),
                                onPressed: () =>
                                    setState(() => _panel = _AuraPanel.home),
                                child: const Text('Inicio'),
                              ),
                            ),
                            _FindingsCenter(
                              report: findingsReport,
                              scanning: _isRunning,
                              onScan: quickActionsEnabled
                                  ? _runFindingsScan
                                  : null,
                            ),
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
                                  final events =
                                      AgentController.instance.history;
                                  final explanationCount =
                                      state.explanationHistory.length;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (_showCoverageAudit)
                                        _CoverageAuditCard(
                                          isVpnActive: state.isVpnActive,
                                          sniObserved: state.sniObservedEvents,
                                          encryptedSni:
                                              state.encryptedSniEvents,
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
                                          autotestStatus:
                                              _coverageAutotestStatus,
                                          onRunAutotest: _runCoverageAutotest,
                                        )
                                      else if (explanationCount > 0)
                                        _ExplanationCard(
                                          explanation:
                                              state.explanationHistory.last,
                                          onVerifyIntegrity:
                                              _verifyModelIntegrity,
                                          onReportFalsePositive:
                                              _reportFalsePositive,
                                          onOpenModelCard: _openModelCard,
                                        ),
                                      if (!_telemetryEndpointConfigured)
                                        _LocalTelemetryPanel(
                                          events: _localTelemetryEvents,
                                          enabled: _localTelemetryEnabled,
                                        ),
                                      if (_untrustedAccessibilityPackages
                                          .isNotEmpty)
                                        _AccessibilitySignal(
                                          packages:
                                              _untrustedAccessibilityPackages,
                                          onOpenSettings:
                                              _openAccessibilitySettings,
                                          onRetry:
                                              _refreshAccessibilityServices,
                                        )
                                      else if (_accessibilityCheckFailed)
                                        _AccessibilityRetry(
                                          onRetry:
                                              _refreshAccessibilityServices,
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
                        )
                      : _panel == _AuraPanel.chat
                      ? Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const ValueKey<String>('aura-close-panel'),
                                onPressed: () =>
                                    setState(() => _panel = _AuraPanel.home),
                                child: const Text('Inicio'),
                              ),
                            ),
                            Expanded(
                              child: StreamBuilder<AgentEvent>(
                                stream: AgentController.instance.events,
                                builder: (context, snapshot) {
                                  final events =
                                      AgentController.instance.history;
                                  if (events.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        'Dime qué reviso. Si no hay micrófono, escribe abajo.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AuraTokens.textMuted,
                                        ),
                                      ),
                                    );
                                  }
                                  return ListView(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    children: [
                                      for (
                                        var index = 0;
                                        index < events.length;
                                        index++
                                      )
                                        _RevealLine(
                                          text: events[index].message,
                                          animate:
                                              index == events.length - 1 &&
                                              events[index].kind !=
                                                  AgentEventKind.thought,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.fromLTRB(
                                  18,
                                  compactLayout ? 4 : 12,
                                  18,
                                  24,
                                ),
                                children: [
                                  const Text(
                                    'Hola, soy Aura.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AuraTokens.textPrimary,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                  SizedBox(height: compactLayout ? 4 : 8),
                                  Center(
                                    child: AuraNeuralCore(
                                      state: switch (avatarMode) {
                                        AuraAvatarMode.listening =>
                                          AuraCoreVisualState.speaking,
                                        AuraAvatarMode.analyzing =>
                                          AuraCoreVisualState.scanning,
                                        AuraAvatarMode.warning ||
                                        AuraAvatarMode.alert =>
                                          AuraCoreVisualState.alert,
                                        _ => AuraCoreVisualState.calm,
                                      },
                                      size: compactLayout ? 168 : 230,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    [
                                      _tunnelBytesLabel ?? 'Túnel sin lectura',
                                      'Eventos/min ${auraEventsInLastMinute(state.telemetryEvents, DateTime.now())}',
                                      'Modo $_firewallModeLabel',
                                    ].join('   ·   '),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AuraTokens.gold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _GlassCard(
                                    title: vpnActive
                                        ? 'Defensa activa · $_underlyingNetworkLabel'
                                        : 'Defensa inactiva · $_underlyingNetworkLabel',
                                    detail: shieldMetric,
                                  ),
                                  const SizedBox(height: 8),
                                  _GlassCard(
                                    title:
                                        'Bloqueos que vi hoy: ${auraBlocksSeenToday(state.telemetryEvents, DateTime.now())}',
                                    detail:
                                        'Solo cuenta bloqueos y alertas DGA de esta sesión con fecha de hoy.',
                                  ),
                                  const SizedBox(height: 8),
                                  _GlassCard(
                                    title: state.explanationHistory.isEmpty
                                        ? 'Sin análisis en esta sesión'
                                        : 'Último análisis ${_clock(state.explanationHistory.last.timestamp)}',
                                    detail: state.explanationHistory.isEmpty
                                        ? 'Aparece cuando el bosque local responde.'
                                        : state.explanationHistory.last.host,
                                  ),
                                  const SizedBox(height: 12),
                                  AuraPlaceRail(
                                    onCommand: _dispatch,
                                    commandsEnabled: quickActionsEnabled,
                                    onTelemetry: _showTelemetrySettings,
                                    defenseActive: vpnActive,
                                    onRestartDefense: _restartDefense,
                                    onShowIntro: () =>
                                        setState(() => _showIntro = true),
                                    voiceMuted: AuraVoiceEngine.muted.value,
                                    onVoiceMuted: (value) {
                                      unawaited(_setVoiceMuted(value));
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                              child: Column(
                                children: [
                                  FilledButton(
                                    key: const ValueKey<String>(
                                      'aura-open-chat',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AuraTokens.accent,
                                      foregroundColor: const Color(0xFF041018),
                                      minimumSize: const Size.fromHeight(48),
                                    ),
                                    onPressed: _openChat,
                                    child: const Text('Hablar con Aura'),
                                  ),
                                  TextButton(
                                    key: const ValueKey<String>(
                                      'aura-open-console',
                                    ),
                                    onPressed: () => setState(
                                      () => _panel = _AuraPanel.console,
                                    ),
                                    child: const Text('Registro'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                if (_panel == _AuraPanel.chat)
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
          if (_showIntro)
            Positioned.fill(
              child: AuraIntro(onFinished: () => unawaited(_finishIntro())),
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

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AuraTokens.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuraTokens.accent.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AuraTokens.textPrimary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              style: const TextStyle(
                color: AuraTokens.textMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevealLine extends StatefulWidget {
  const _RevealLine({required this.text, required this.animate});

  final String text;
  final bool animate;

  @override
  State<_RevealLine> createState() => _RevealLineState();
}

class _RevealLineState extends State<_RevealLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (!widget.animate || reduced) {
      _controller.value = 1;
      return;
    }
    if (!_controller.isAnimating && _controller.value < 1) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final count = (_controller.value * widget.text.length).ceil();
        final shown = widget.text.substring(
          0,
          count.clamp(0, widget.text.length),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            shown,
            style: const TextStyle(color: AuraTokens.textPrimary, height: 1.35),
          ),
        );
      },
    );
  }
}

String _clock(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _FindingsCenter extends StatefulWidget {
  const _FindingsCenter({
    required this.report,
    required this.scanning,
    required this.onScan,
  });

  final AuraFindingsReport report;
  final bool scanning;
  final VoidCallback? onScan;

  @override
  State<_FindingsCenter> createState() => _FindingsCenterState();
}

class _FindingsCenterState extends State<_FindingsCenter> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final findings = report.findings;
    final visibleFindings = _showAll ? findings : findings.take(3).toList();
    final hasHigh = findings.any(
      (finding) =>
          finding.severity == AuraFindingSeverity.high ||
          finding.severity == AuraFindingSeverity.critical,
    );
    final hasMedium = findings.any(
      (finding) => finding.severity == AuraFindingSeverity.medium,
    );
    final accent = !report.hasScanned
        ? AuraTokens.textMuted
        : hasHigh
        ? AuraTokens.danger
        : hasMedium
        ? AuraTokens.warning
        : findings.isNotEmpty
        ? AuraTokens.accentViolet
        : AuraTokens.success;
    final badge = !report.hasScanned
        ? 'ANÁLISIS PENDIENTE'
        : findings.isEmpty
        ? 'SIN HALLAZGOS'
        : findings.length == 1
        ? '1 HALLAZGO'
        : '${findings.length} HALLAZGOS';
    final actionLabel = widget.scanning
        ? 'ANALIZANDO…'
        : report.hasScanned
        ? 'ACTUALIZAR'
        : 'ANALIZAR';

    return Container(
      key: const ValueKey<String>('findings-center'),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2, right: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: accent.withValues(alpha: 0.6), width: 1.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CENTRO DE HALLAZGOS',
                        style: TextStyle(
                          color: _terminalCyan,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Solo lectura · evidencia local',
                        style: TextStyle(
                          color: AuraTokens.textMuted,
                          fontFamily: 'monospace',
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey<String>('findings-refresh'),
                onPressed: widget.scanning ? null : widget.onScan,
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            badge,
            style: TextStyle(
              color: accent,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Postura: ${report.deviceCoverage.label} · '
            'Apps: ${report.appCoverage.label} · '
            'Red: ${report.networkAlertCount} '
            '${report.networkAlertCount == 1 ? 'alerta' : 'alertas'}',
            style: const TextStyle(
              color: AuraTokens.textMuted,
              fontFamily: 'monospace',
              fontSize: 10,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          if (!report.hasScanned)
            const Text(
              'Sin análisis en esta sesión. Ejecuta la auditoría local para generar evidencia; Aura no modificará apps ni configuración.',
              style: TextStyle(
                color: AuraTokens.textPrimary,
                fontSize: 11,
                height: 1.4,
              ),
            )
          else if (findings.isEmpty)
            const Text(
              'No se observaron señales en las fuentes revisadas. Esto no certifica que el dispositivo esté libre de amenazas.',
              style: TextStyle(
                color: AuraTokens.textPrimary,
                fontSize: 11,
                height: 1.4,
              ),
            )
          else
            for (final finding in visibleFindings)
              _FindingTile(finding: finding),
          if (findings.length > 3)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey<String>('findings-show-all'),
                onPressed: () => setState(() => _showAll = !_showAll),
                style: TextButton.styleFrom(
                  foregroundColor: AuraTokens.accent,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _showAll ? 'VER MENOS' : 'VER TODOS (${findings.length})',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});

  final AuraFinding finding;

  @override
  Widget build(BuildContext context) {
    final color = switch (finding.severity) {
      AuraFindingSeverity.critical ||
      AuraFindingSeverity.high => AuraTokens.danger,
      AuraFindingSeverity.medium => AuraTokens.warning,
      AuraFindingSeverity.low => AuraTokens.accentViolet,
      AuraFindingSeverity.info => AuraTokens.accent,
    };
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        key: ValueKey<String>('finding-${finding.id}'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(
          left: 2,
          right: 2,
          bottom: AuraTokens.s2,
        ),
        iconColor: color,
        collapsedIconColor: color,
        title: Text(
          finding.title,
          style: const TextStyle(
            color: AuraTokens.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FindingPill(
                label: 'RIESGO ${finding.severity.label.toUpperCase()}',
                color: color,
              ),
              Text(
                'confianza ${finding.confidence.label}',
                style: const TextStyle(
                  color: AuraTokens.textMuted,
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                ),
              ),
              Text(
                finding.subject,
                style: const TextStyle(
                  color: AuraTokens.textMuted,
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              finding.summary,
              style: const TextStyle(
                color: AuraTokens.textPrimary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AuraTokens.s2),
          const _FindingSectionLabel('EVIDENCIA'),
          for (final evidence in finding.evidence)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $evidence',
                style: const TextStyle(
                  color: _terminalGreen,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: AuraTokens.s2),
          const _FindingSectionLabel('LÍMITES'),
          for (final limitation in finding.limitations)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $limitation',
                style: const TextStyle(
                  color: AuraTokens.warning,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: AuraTokens.s2),
          const _FindingSectionLabel('QUÉ PUEDES REVISAR'),
          Text(
            finding.recommendedAction,
            style: const TextStyle(
              color: AuraTokens.textPrimary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AuraTokens.s2),
          const Text(
            'Solo lectura · no se modificó ninguna app',
            style: TextStyle(
              color: AuraTokens.textMuted,
              fontFamily: 'monospace',
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _FindingPill extends StatelessWidget {
  const _FindingPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.6)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontFamily: 'monospace',
        fontSize: 8.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    ),
  );
}

class _FindingSectionLabel extends StatelessWidget {
  const _FindingSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AuraTokens.accent,
      fontFamily: 'monospace',
      fontSize: 9,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.5,
    ),
  );
}

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
