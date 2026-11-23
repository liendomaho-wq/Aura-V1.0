// voice_engine.dart - Motor de Voz Nativo de Aura
import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// Texto listo para leer en voz alta.
///
/// La consola usa prefijos como `[OK]` o `[WARN]`, Markdown y URLs largas. Leer
/// esos símbolos en voz alta suena artificial y puede confundir; aquí se
/// convierten en una frase natural sin cambiar el contenido técnico.
abstract final class AuraSpeechText {
  static const int maxLength = 600;

  static String forSpeech(String text) {
    var value = text
        .replaceAll(RegExp(r'\[[A-ZÁÉÍÓÚÑ ]+\]'), ' ')
        .replaceAllMapped(
          RegExp(r'https?://([^/\s]+)\S*'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'[*_`#>|]+'), ' ')
        .replaceAll('·', ',')
        .replaceAllMapped(
          RegExp(r'\s+([.,;:!?])'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.length <= maxLength) return value;
    final cut = value.substring(0, maxLength);
    final lastStop = cut.lastIndexOf(RegExp(r'[.!?]'));
    if (lastStop >= 120) return cut.substring(0, lastStop + 1).trim();
    value = cut.trimRight();
    return '$value…';
  }
}

enum AuraSpeechState { idle, speaking }

class AuraVoiceEngine {
  final FlutterTts _flutterTts = FlutterTts();
  final StreamController<AuraSpeechState> _stateController =
      StreamController<AuraSpeechState>.broadcast();
  late final Future<void> _initialization;
  bool _available = true;
  bool _speaking = false;
  Completer<void>? _completion;

  AuraVoiceEngine() {
    _initialization = _initializeVoice();
  }

  bool get isSpeaking => _speaking;

  Stream<AuraSpeechState> get states => _stateController.stream;

  Future<void> _initializeVoice() async {
    try {
      _flutterTts.setStartHandler(_handleStart);
      _flutterTts.setCompletionHandler(_handleDone);
      _flutterTts.setCancelHandler(_handleDone);
      _flutterTts.setErrorHandler((_) => _handleDone());
      await _selectSpanishVoice();
      await _flutterTts.setSpeechRate(0.55);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.05);
    } on Object {
      // Tests, desktop targets and devices without a TTS plugin remain usable.
      _available = false;
      _handleDone();
    }
  }

  void _handleStart() {
    if (_speaking) return;
    _speaking = true;
    _stateController.add(AuraSpeechState.speaking);
  }

  void _handleDone() {
    final wasSpeaking = _speaking;
    _speaking = false;
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) completion.complete();
    if (wasSpeaking) _stateController.add(AuraSpeechState.idle);
  }

  /// Prefiere español latinoamericano y cae a es-US o es-ES solo si el motor
  /// del dispositivo no ofrece la variante regional.
  Future<void> _selectSpanishVoice() async {
    for (final locale in const <String>['es-419', 'es-US', 'es-ES']) {
      try {
        final available = await _flutterTts.isLanguageAvailable(locale);
        if (available == true || available == 1) {
          await _flutterTts.setLanguage(locale);
          return;
        }
      } on Object {
        // El motor puede no exponer esa variante; se prueba la siguiente.
      }
    }
    await _flutterTts.setLanguage('es-ES');
  }

  Future<void> speak(String text) async {
    final spoken = AuraSpeechText.forSpeech(text);
    if (spoken.isEmpty) return;
    await _initialization;
    if (!_available) return;
    try {
      final previous = _completion;
      _completion = null;
      if (previous != null && !previous.isCompleted) previous.complete();
      await _flutterTts.stop();
      _completion = Completer<void>();
      await _flutterTts.speak(spoken);
    } on Object {
      // Voice is optional; never interrupt the text-based agent response.
      _available = false;
      _handleDone();
    }
  }

  /// Completa cuando el motor informa el final, la cancelación o un error.
  /// Un motor que no emite eventos no bloquea el turno: hay un límite de 30 s.
  Future<void> waitForSpeech() async {
    final completion = _completion;
    if (completion == null) return;
    try {
      await completion.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      // El turno sigue; el siguiente comando puede detener la voz igualmente.
    }
  }

  Future<void> announceToolExecution(
    String toolName,
    Map<String, Object?> arguments,
  ) {
    switch (toolName) {
      case 'mitigate_network_threat':
        final domain = arguments['domain'] as String? ?? 'dominio detectado';
        final appPackage =
            arguments['app_package'] as String? ?? 'aplicación observada';
        return speak(
          'Solicitud en curso para $domain, observada en $appPackage. '
          'La regla DNS solo se confirma cuando el motor local la aplica.',
        );
      case 'isolate_malicious_app':
        final packageName =
            arguments['package_name'] as String? ?? 'aplicación identificada';
        return speak(
          'Alerta crítica. Abriendo los ajustes de $packageName para que '
          'revises la aplicación y decidas las acciones necesarias.',
        );
      default:
        return speak('Aura está ejecutando una acción de ciberdefensa.');
    }
  }

  Future<void> announceToolResult(
    String toolName,
    Map<String, Object?> result,
  ) {
    if (result['ok'] == true && toolName == 'mitigate_network_threat') {
      return speak('La regla DNS global fue aplicada correctamente.');
    }
    if (result['ok'] == true && toolName == 'isolate_malicious_app') {
      return speak('Ajustes abiertos. La decisión final queda en tus manos.');
    }
    final error = result['error'] as String? ?? 'acción no confirmada';
    return speak('No se confirmó la contramedida: $error');
  }

  Future<void> stop() async {
    await _initialization;
    if (!_available) {
      _handleDone();
      return;
    }
    try {
      await _flutterTts.stop();
    } on Object {
      _available = false;
    }
    _handleDone();
  }
}
