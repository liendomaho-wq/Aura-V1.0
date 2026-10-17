import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../explanation/aura_verdict_explanation.dart';

enum AuraSecurityLevel { safe, warning, critical }

typedef AuraCriticalAlert = Future<void> Function(String message);

class AuraStateProvider extends ChangeNotifier {
  static const int maxTelemetryEvents = 500;
  static const int maxExplanationHistory = 50;
  static const String _criticalAlertMessage =
      'Alerta crítica. Aura está mitigando una amenaza de seguridad.';

  final List<Map<String, dynamic>> _telemetryEvents = [];
  final List<AuraVerdictExplanation> _explanationHistory = [];
  final AuraCriticalAlert? _onCriticalAlert;
  String _liveConsoleLogs = 'SISTEMA AURA: Núcleo defensivo activo e íntegro.';
  bool _isVpnActive = false;
  bool _isScanning = false;
  bool _isAiProcessing = false;
  bool _isVoiceListening = false;
  AuraSecurityLevel _securityLevel = AuraSecurityLevel.safe;
  int _tunnelBytesProcessed = 0;
  int _localForestEvaluations = 0;
  int _encryptedDnsBlocks = 0;
  int _sniObservedEvents = 0;
  int _blockedEvents = 0;
  int _dgaAlertEvents = 0;
  String? _lastNetworkAction;

  AuraStateProvider({AuraCriticalAlert? onCriticalAlert})
      : _onCriticalAlert = onCriticalAlert;

  bool get isVpnActive => _isVpnActive;
  bool get isScanning => _isScanning;
  bool get isAiProcessing => _isAiProcessing;
  bool get isVoiceListening => _isVoiceListening;
  String get liveConsoleLogs => _liveConsoleLogs;
  AuraSecurityLevel get securityLevel => _securityLevel;
  int get tunnelBytesProcessed => _tunnelBytesProcessed;
  int get localForestEvaluations => _localForestEvaluations;
  int get encryptedDnsBlocks => _encryptedDnsBlocks;
  int get sniObservedEvents => _sniObservedEvents;
  int get blockedEvents => _blockedEvents;
  int get dgaAlertEvents => _dgaAlertEvents;
  String? get lastNetworkAction => _lastNetworkAction;
  String get avatarAnimation => switch (_securityLevel) {
        AuraSecurityLevel.safe => 'idle_friendly',
        AuraSecurityLevel.warning => 'scanning_active',
        AuraSecurityLevel.critical => 'threat_mitigation_mode',
      };
  UnmodifiableListView<Map<String, dynamic>> get telemetryEvents =>
      UnmodifiableListView(_telemetryEvents);
  UnmodifiableListView<AuraVerdictExplanation> get explanationHistory =>
      UnmodifiableListView(_explanationHistory);
  UnmodifiableListView<String> get observedPublicDnsResolvers =>
      UnmodifiableListView(
        _telemetryEvents
            .where((event) =>
                event['public_dns_resolver'] == true &&
                event['destination_address'] is String)
            .map((event) => event['destination_address'] as String)
            .toSet()
            .toList(growable: false),
      );

  void setVpnActive(bool active) {
    if (_isVpnActive == active) return;
    _isVpnActive = active;
    notifyListeners();
  }

  void setScanning(bool scanning) {
    if (_isScanning == scanning) return;
    _isScanning = scanning;
    notifyListeners();
  }

  void updatePresentation({
    String? liveConsoleLogs,
    bool? isAiProcessing,
    bool? isVoiceListening,
  }) {
    var changed = false;
    if (liveConsoleLogs != null && liveConsoleLogs != _liveConsoleLogs) {
      _liveConsoleLogs = liveConsoleLogs;
      changed = true;
    }
    if (isAiProcessing != null && isAiProcessing != _isAiProcessing) {
      _isAiProcessing = isAiProcessing;
      changed = true;
    }
    if (isVoiceListening != null && isVoiceListening != _isVoiceListening) {
      _isVoiceListening = isVoiceListening;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void setSecurityLevel(AuraSecurityLevel level) {
    if (_securityLevel == level) return;
    _securityLevel = level;
    notifyListeners();
    if (level == AuraSecurityLevel.critical) {
      unawaited(_onCriticalAlert?.call(_criticalAlertMessage));
    }
  }

  void addTelemetryEvent(Map<String, dynamic> event) {
    _telemetryEvents.add(Map<String, dynamic>.unmodifiable(event));
    _lastNetworkAction = event['action'] as String?;
    if (event['action'] == 'ENCRYPTED_DNS_BLOCKED') {
      _encryptedDnsBlocks++;
    }
    if (event['action'] == 'SNI_OBSERVED') _sniObservedEvents++;
    if (event['action'] == 'BLOCKED') _blockedEvents++;
    if (event['action'] == 'DGA_ALERT') _dgaAlertEvents++;
    if (_telemetryEvents.length > maxTelemetryEvents) {
      _telemetryEvents.removeRange(
        0,
        _telemetryEvents.length - maxTelemetryEvents,
      );
    }
    final action = event['action'];
    if (action == 'DGA_ALERT' || action == 'BLOCKED') {
      if (_securityLevel == AuraSecurityLevel.safe) {
        _securityLevel = AuraSecurityLevel.warning;
      }
    }
    notifyListeners();
  }

  void addExplanation(AuraVerdictExplanation explanation) {
    _explanationHistory.add(explanation);
    if (_explanationHistory.length > maxExplanationHistory) {
      _explanationHistory.removeRange(
        0,
        _explanationHistory.length - maxExplanationHistory,
      );
    }
    notifyListeners();
  }

  void markExplanationAsFalsePositive(String explanationId) {
    final index = _explanationHistory.indexWhere(
      (explanation) => explanation.id == explanationId,
    );
    if (index < 0 || _explanationHistory[index].reportedFalsePositive) {
      return;
    }
    _explanationHistory[index] =
        _explanationHistory[index].copyWith(reportedFalsePositive: true);
    notifyListeners();
  }

  void updateTunnelBytesProcessed(int bytes) {
    if (bytes < 0 || bytes == _tunnelBytesProcessed) return;
    _tunnelBytesProcessed = bytes;
    notifyListeners();
  }

  void recordLocalForestEvaluation() {
    _localForestEvaluations++;
    notifyListeners();
  }

  void clearTelemetryHistory() {
    _telemetryEvents.clear();
    _explanationHistory.clear();
    _lastNetworkAction = null;
    _localForestEvaluations = 0;
    _encryptedDnsBlocks = 0;
    _sniObservedEvents = 0;
    _blockedEvents = 0;
    _dgaAlertEvents = 0;
    _tunnelBytesProcessed = 0;
    _liveConsoleLogs = '';
    notifyListeners();
  }
}
