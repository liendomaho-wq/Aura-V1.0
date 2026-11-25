import 'aura_intent_parser.dart';

/// Acción que Aura puede resolver a partir de una referencia conversacional.
enum AuraFollowUpKind {
  analyzeLastHost,
  blockLastHost,
  isolateLastApp,
  explain,
  summarize,
  repeat,
}

class AuraFollowUp {
  const AuraFollowUp(this.kind, {this.instruction});

  final AuraFollowUpKind kind;

  /// Instrucción canónica que debe pasar por el mismo motor, la misma
  /// allowlist y la misma confirmación que una orden escrita completa.
  final String? instruction;
}

class AuraConversationTurn {
  const AuraConversationTurn({
    required this.role,
    required this.text,
    required this.timestamp,
    this.source,
  });

  final String role;
  final String text;
  final DateTime timestamp;

  /// Motor que produjo el texto cuando es una respuesta de Aura:
  /// `local_llm` cuando lo generó el modelo, `system` cuando salió de la capa
  /// determinista. Nulo en los turnos del usuario.
  final String? source;
}

/// Memoria conversacional acotada y determinista.
///
/// No inventa contexto ni llama a ningún modelo: guarda únicamente el último
/// dominio o paquete que apareció en una intención real, la última respuesta y
/// un número limitado de turnos. Vive en memoria del proceso y se borra con la
/// purga criptográfica.
class AuraConversationMemory {
  AuraConversationMemory._();

  static final AuraConversationMemory instance = AuraConversationMemory._();

  static const int maxTurns = 40;
  static const int maxStoredTextLength = 400;
  static const int maxFollowUpLength = 200;
  static const int maxConfirmationLength = 60;

  final List<AuraConversationTurn> _turns = <AuraConversationTurn>[];
  String? _lastHost;
  String? _lastPackage;
  String? _lastIntentName;
  String? _lastAuraMessage;

  String? get lastHost => _lastHost;
  String? get lastPackage => _lastPackage;
  String? get lastIntentName => _lastIntentName;
  String? get lastAuraMessage => _lastAuraMessage;

  List<AuraConversationTurn> get turns =>
      List<AuraConversationTurn>.unmodifiable(_turns);

  /// Registra la intención ya validada. Solo actualiza el objetivo cuando la
  /// intención trae un dominio o un paquete; una consulta de estado no borra
  /// el último objetivo.
  void recordIntent(AuraIntent intent) {
    _lastIntentName = intent.name;
    final domain = intent.entities['domain'];
    if (domain is String) {
      final normalized = domain.trim().toLowerCase();
      if (normalized.isNotEmpty) _lastHost = normalized;
    }
    final packageName = intent.entities['package_name'];
    if (packageName is String) {
      final normalized = packageName.trim().toLowerCase();
      if (normalized.isNotEmpty) _lastPackage = normalized;
    }
  }

  void recordUserMessage(String text) => _append('user', text);

  void recordAuraMessage(String text, {String? source}) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    _lastAuraMessage = normalized;
    _append('aura', normalized, source: source);
  }

  /// Contexto estructurado para el planificador local. Solo incluye valores
  /// que el parser ya validó; nunca la respuesta anterior del modelo, para no
  /// realimentar una posible inyección de prompt.
  String? promptContext({String? securityLevel}) {
    final parts = <String>[
      if (_lastHost != null) 'ultimo_dominio=$_lastHost',
      if (_lastPackage != null) 'ultima_app=$_lastPackage',
      if (_lastIntentName != null) 'ultima_intencion=$_lastIntentName',
      if (securityLevel != null) 'nivel_seguridad=$securityLevel',
    ];
    return parts.isEmpty ? null : parts.join(' | ');
  }

  void reset() {
    _turns.clear();
    _lastHost = null;
    _lastPackage = null;
    _lastIntentName = null;
    _lastAuraMessage = null;
  }

  /// Confirma una acción pendiente con lenguaje natural.
  ///
  /// Solo acepta frases completas y cortas. "sí, bloquea evil.com" no es una
  /// confirmación: contiene un objetivo nuevo y el llamador debe tratarlo como
  /// una instrucción distinta.
  bool isConfirmation(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty || normalized.length > maxConfirmationLength) {
      return false;
    }
    return _confirmationPattern.hasMatch(normalized);
  }

  bool isDenial(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty || normalized.length > maxConfirmationLength) {
      return false;
    }
    return _denialPattern.hasMatch(normalized);
  }

  /// Resuelve "bloquéalo", "analízalo", "¿por qué?" o "¿qué has hecho?" contra
  /// el último objetivo real. Devuelve `null` cuando el texto trae un objetivo
  /// explícito o no hay contexto suficiente.
  AuraFollowUp? followUpFor(String text) {
    final raw = text.trim();
    if (raw.isEmpty || raw.length > maxFollowUpLength) return null;
    // El host se detecta antes de quitar la puntuación: si el usuario escribió
    // un objetivo nuevo, esta capa no debe reemplazarlo por el anterior.
    final folded = _fold(raw);
    if (_hostPattern.hasMatch(folded)) return null;
    final normalized = _stripPunctuation(folded);
    if (normalized.isEmpty) return null;

    if (_summaryPattern.hasMatch(normalized)) {
      return const AuraFollowUp(AuraFollowUpKind.summarize);
    }
    if (_repeatPattern.hasMatch(normalized)) {
      return _lastAuraMessage == null
          ? null
          : const AuraFollowUp(AuraFollowUpKind.repeat);
    }
    if (_explainPattern.hasMatch(normalized)) {
      return _lastHost == null && _lastAuraMessage == null
          ? null
          : const AuraFollowUp(AuraFollowUpKind.explain);
    }

    final host = _lastHost;
    if (host != null && _blockPattern.hasMatch(normalized)) {
      return AuraFollowUp(
        AuraFollowUpKind.blockLastHost,
        instruction: 'bloquear $host',
      );
    }
    // El aislamiento se evalúa antes que el análisis: "revisa la app" no debe
    // convertirse en "revisa el dominio".
    final packageName = _lastPackage;
    if (packageName != null && _isolatePattern.hasMatch(normalized)) {
      return AuraFollowUp(
        AuraFollowUpKind.isolateLastApp,
        instruction: 'aislar app $packageName',
      );
    }
    if (host != null && _analyzePattern.hasMatch(normalized)) {
      return AuraFollowUp(
        AuraFollowUpKind.analyzeLastHost,
        instruction: 'analizar dominio $host',
      );
    }
    return null;
  }

  void _append(String role, String text, {String? source}) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    final bounded = normalized.length <= maxStoredTextLength
        ? normalized
        : '${normalized.substring(0, maxStoredTextLength - 1)}…';
    _turns.add(
      AuraConversationTurn(
        role: role,
        text: bounded,
        timestamp: DateTime.now(),
        source: source,
      ),
    );
    if (_turns.length > maxTurns) {
      _turns.removeRange(0, _turns.length - maxTurns);
    }
  }

  static String _fold(String text) {
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      buffer.write(_diacriticFold[rune] ?? String.fromCharCode(rune));
    }
    return buffer.toString();
  }

  static String _normalize(String text) => _stripPunctuation(_fold(text));

  static String _stripPunctuation(String text) => text
      .replaceAll(RegExp(r'[¿?¡!.,;:"()\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const Map<int, String> _diacriticFold = <int, String>{
    0x00E1: 'a',
    0x00E0: 'a',
    0x00E2: 'a',
    0x00E4: 'a',
    0x00E3: 'a',
    0x00E9: 'e',
    0x00E8: 'e',
    0x00EA: 'e',
    0x00EB: 'e',
    0x00ED: 'i',
    0x00EC: 'i',
    0x00EE: 'i',
    0x00EF: 'i',
    0x00F3: 'o',
    0x00F2: 'o',
    0x00F4: 'o',
    0x00F6: 'o',
    0x00F5: 'o',
    0x00FA: 'u',
    0x00F9: 'u',
    0x00FB: 'u',
    0x00FC: 'u',
    0x00F1: 'n',
    0x00E7: 'c',
  };

  static final RegExp _confirmationPattern = RegExp(
    r'^(?:si,? )?(?:si|confirmo|confirmar|autorizo|autoriza|apruebo|aprueba|dale|hazlo|hacelo|adelante|procede|proceda|ok|okay|vale|de acuerdo|ejecutalo|ejecutala|aplicalo|aplicala)(?: (?:por favor|ahora|ya|eso|la operacion|la accion|nomas))?$',
  );
  static final RegExp _denialPattern = RegExp(
    r'^(?:no|no,? gracias|cancela|cancelalo|cancelala|cancelar|mejor no|detente|para|aborta|rechazo|rechazar|no lo hagas|olvidalo|olvidalo ya)(?: (?:por favor|ahora|eso))?$',
  );
  static final RegExp _hostPattern = RegExp(r'\b[a-z0-9-]+(?:\.[a-z0-9-]+)+\b');
  static final RegExp _blockPattern = RegExp(
    r'^(?:si,? )?(?:bloquea|bloquealo|bloqueala|bloqueame|ponle un bloqueo|ponle bloqueo)\b',
  );
  static final RegExp _analyzePattern = RegExp(
    r'^(?:y )?(?:analiza|analizalo|analizala|revisalo|revisala|chequealo|chequeala|examina|examinalo)\b|^revisa (?:el |ese |este |mi |la )?(?:dominio|host|sitio|website|url|enlace)\b|^y ese (?:dominio|host|sitio)\b|^que es ese (?:dominio|host|sitio)\b',
  );
  static final RegExp _isolatePattern = RegExp(
    r'^(?:aisla|aislalo|aislala|revisa esa app|revisa la app|revisa esa aplicacion|revisa la aplicacion)\b',
  );
  static final RegExp _explainPattern = RegExp(
    r'^(?:y )?(?:por que|porque|para que|que significa|explicame|explica|explicamelo|en simple|no entendi|no lo entiendo|por que lo dices|como asi)\b',
  );
  static final RegExp _summaryPattern = RegExp(
    r'^(?:dame un |hazme un )?(?:resumen|que paso|que ha pasado|que has hecho|que encontraste|que viste|cuentame que paso)\b',
  );
  static final RegExp _repeatPattern = RegExp(
    r'^(?:repite|repitelo|repetilo|repetirlo|repetir|otra vez|no escuche|no te escuche|como dijiste)\b',
  );
}
