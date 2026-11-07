import 'agent_event.dart';

enum AuraIntentKind {
  block,
  isolate,
  panicIsolation,
  resumeNetwork,
  cryptographicPurge,
  updateDefenses,
  scanApps,
  analyzeDomain,
  analyzeThreats,
  auditDevice,
  greet,
  identity,
  capabilities,
  securityCheck,
  insult,
  praise,
  existential,
  fear,
  provocation,
  humor,
  status,
  toggleDefenses,
  help,
  unknown,
}

class AuraIntent {
  const AuraIntent({
    required this.name,
    required this.kind,
    required this.entities,
    required this.confidence,
  });

  final String name;
  final AuraIntentKind kind;
  final Map<String, dynamic> entities;
  final double confidence;

  AgentEvent toEvent() => AgentEvent(
    kind: switch (kind) {
      AuraIntentKind.block ||
      AuraIntentKind.isolate ||
      AuraIntentKind.panicIsolation ||
      AuraIntentKind.resumeNetwork ||
      AuraIntentKind.cryptographicPurge ||
      AuraIntentKind.updateDefenses ||
      AuraIntentKind.scanApps ||
      AuraIntentKind.analyzeDomain ||
      AuraIntentKind.auditDevice ||
      AuraIntentKind.toggleDefenses => AgentEventKind.action,
      AuraIntentKind.greet ||
      AuraIntentKind.identity ||
      AuraIntentKind.capabilities ||
      AuraIntentKind.securityCheck ||
      AuraIntentKind.insult ||
      AuraIntentKind.praise ||
      AuraIntentKind.existential ||
      AuraIntentKind.fear ||
      AuraIntentKind.provocation ||
      AuraIntentKind.humor => AgentEventKind.thought,
      AuraIntentKind.analyzeThreats => AgentEventKind.thought,
      AuraIntentKind.status || AuraIntentKind.help => AgentEventKind.thought,
      AuraIntentKind.unknown => AgentEventKind.warning,
    },
    message: name,
    data: <String, dynamic>{
      'entities': Map<String, dynamic>.from(entities),
      'confidence': confidence,
    },
  );
}

class AuraIntentParser {
  AuraIntentParser._();

  static const int historyCapacity = 5;
  static final List<AuraIntent?> _historyBuffer = List<AuraIntent?>.filled(
    historyCapacity,
    null,
  );
  static int _nextHistoryIndex = 0;
  static int _historySize = 0;

  static final RegExp _explicitConfirmationCommand = RegExp(
    r'^\s*(?:sí[, ]+)?(?:confirmo|confirmar|autorizo|autoriza|apruebo|aprobar)\b',
    caseSensitive: false,
  );
  static final RegExp _negatedConfirmationRemainder = RegExp(
    r'\b(?:no|nunca|jam[aá]s|cancelar|cancelo|rechazo|deniego|anular|anulo)\b',
    caseSensitive: false,
  );

  static bool _hasExplicitConfirmation(String text) {
    final match = _explicitConfirmationCommand.firstMatch(text);
    if (match == null) return false;
    // A negation anywhere in the confirmation clause makes authorization
    // ambiguous, so require the user to restate the affirmative instruction.
    return !_negatedConfirmationRemainder.hasMatch(text.substring(match.end));
  }

  static final RegExp _blockCommand = RegExp(
    r'\b(?:bloquea|bloquear|bloquee|bloqueo|block|blockear|deniega|denegar)\b',
    caseSensitive: false,
  );
  static final RegExp _isolateCommand = RegExp(
    r'\b(?:a[ií]sla|a[ií]slar|aislamiento|isolate|revisar?\s+(?:la\s+)?app(?:licaci[oó]n)?)\b',
    caseSensitive: false,
  );
  static final RegExp _statusCommand = RegExp(
    r'\b(?:estado|status|salud|state|health|cómo está|como esta)\b',
    caseSensitive: false,
  );
  static final RegExp _panicIsolationCommand = RegExp(
    r'\b(?:pánico|panico|panic isolation|aislamiento de emergencia|aislar (?:la )?red|cortar (?:la )?red)\b',
    caseSensitive: false,
  );
  static final RegExp _resumeNetworkCommand = RegExp(
    r'\b(?:reanudar (?:la )?red|restablecer (?:la )?red|reanudar (?:el )?t[uú]nel|resume network|restore network)\b',
    caseSensitive: false,
  );
  static final RegExp _cryptographicPurgeCommand = RegExp(
    r'\b(?:purga criptográfica|purga criptografica|cryptographic purge|purga segura|borrado seguro de credenciales)\b',
    caseSensitive: false,
  );
  static final RegExp _activateDefensesCommand = RegExp(
    r'\b(activar|activa|enciende|encender|habilitar|habilita|conectar|conecta)\s+(las?\s+|el\s+|los?\s+)?(defensas|defensa|escudo|vpn|protecci[oó]n|t[uú]nel)\b',
    caseSensitive: false,
  );
  static final RegExp _deactivateDefensesCommand = RegExp(
    r'\b(desactivar|desactiva|apagar|apaga|desconectar|desconecta)\s+(las?\s+|el\s+|los?\s+)?(defensas|defensa|escudo|vpn|protecci[oó]n|t[uú]nel)\b',
    caseSensitive: false,
  );
  static final RegExp _helpCommand = RegExp(
    r'\b(ayuda|help|comandos|[oó]rdenes|que puedes hacer|qué puedes hacer)\b',
    caseSensitive: false,
  );
  static final RegExp _analyzeDomainCommand = RegExp(
    r'\b(?:analiza|analizar|revisa|revisar|eval[uú]a|evaluar|comprueba|comprobar)\s+(?:el\s+)?(?:dominio|host|sitio|website)\b',
    caseSensitive: false,
  );
  static final RegExp _analyzeThreatsCommand = RegExp(
    r'\b(?:analiza|analizar|revisa|revisar|muestra|ver)\s+(?:(?:las?|los)\s+)?amenazas\b',
    caseSensitive: false,
  );
  static final RegExp _auditDeviceCommand = RegExp(
    r'\b(?:audita|auditar|revisa|revisar|comprueba|comprobar)\s+(?:el\s+)?(?:dispositivo|entorno|seguridad del dispositivo|integridad del dispositivo)\b|\b(?:auditor[ií]a)\s+(?:de\s+)?(?:seguridad|dispositivo|entorno)\b',
    caseSensitive: false,
  );
  static final RegExp _scanAppsCommand = RegExp(
    r'\b(?:analiza|analizar|escanea|escanear|revisa|revisar)\s+(?:(?:las?|los)\s+)?(?:apps|aplicaciones|aplicativos)\b|\b(?:escaneo|an[aá]lisis)\s+de\s+(?:apps|aplicaciones)\b|\b(?:scan|scan apps|scan applications)\b',
    caseSensitive: false,
  );
  static final RegExp _updateDefensesCommand = RegExp(
    r'\b(?:actualizar sistema de defensas|actualizar|update defenses|update)\b',
    caseSensitive: false,
  );
  static const Map<AuraIntentKind, List<String>> _conversationTokens = {
    AuraIntentKind.greet: [
      'hola',
      'buenos dias',
      'buenas tardes',
      'buenas noches',
      'saludos',
      'hey aura',
      'buen dia',
    ],
    AuraIntentKind.identity: [
      'quien eres',
      'quien sos',
      'tu nombre',
      'como te llamas',
      'que eres',
      'identidad',
    ],
    AuraIntentKind.capabilities: [
      'que puedes hacer',
      'capacidades',
      'funciones',
      'que sabes hacer',
      'como me ayudas',
      'herramientas',
    ],
    AuraIntentKind.securityCheck: [
      'estado de seguridad',
      'estoy seguro',
      'estoy protegido',
      'estoy protegida',
      'revisa mi seguridad',
      'como esta el sistema',
      'salud del sistema',
    ],
    AuraIntentKind.insult: [
      'inutil',
      'idiota',
      'estupida',
      'estupido',
      'mala ia',
      'no sirves',
    ],
    AuraIntentKind.praise: [
      'bien hecho',
      'excelente',
      'gran trabajo',
      'eres genial',
      'te felicito',
      'gracias aura',
    ],
    AuraIntentKind.existential: [
      'tienes conciencia',
      'estas viva',
      'sientes',
      'tienes alma',
      'que significa existir',
      'piensas por ti misma',
    ],
    AuraIntentKind.fear: [
      'tengo miedo',
      'estoy asustado',
      'estoy asustada',
      'me preocupa',
      'estoy nervioso',
      'estoy nerviosa',
      'hay peligro',
    ],
    AuraIntentKind.provocation: [
      'te reto',
      'te desafio',
      'no puedes',
      'a que no',
      'demuestra lo que vales',
      'te voy a hackear',
    ],
    AuraIntentKind.humor: [
      'cuentame un chiste',
      'hazme reir',
      'algo gracioso',
      'tienes humor',
      'chiste',
      'broma',
    ],
  };
  static final Map<AuraIntentKind, RegExp> _conversationPatterns = {
    for (final entry in _conversationTokens.entries)
      entry.key: RegExp(
        '\\b(?:${entry.value.map(RegExp.escape).join('|')})\\b',
        caseSensitive: false,
      ),
  };
  static final RegExp _ipv4Pattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
  static final RegExp _hostPattern = RegExp(
    r'\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\b',
    caseSensitive: false,
  );
  static final RegExp _packageLabelPattern = RegExp(
    r'\b(?:paquete|package|aplicación|aplicacion|app)\s*[:=]?\s*([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+)\b',
    caseSensitive: false,
  );
  static final RegExp _androidPackagePattern = RegExp(
    r'\b(?:com|org|net|io|dev|app|co|es|gov|edu)(?:\.[a-z][a-z0-9_]*){1,}\b',
    caseSensitive: false,
  );

  static List<AuraIntent> get history {
    final oldestIndex =
        (_nextHistoryIndex - _historySize + historyCapacity) % historyCapacity;
    return List<AuraIntent>.unmodifiable(
      List<AuraIntent>.generate(
        _historySize,
        (index) => _historyBuffer[(oldestIndex + index) % historyCapacity]!,
      ),
    );
  }

  static void clearHistory() {
    for (var index = 0; index < historyCapacity; index++) {
      _historyBuffer[index] = null;
    }
    _nextHistoryIndex = 0;
    _historySize = 0;
  }

  static Future<AuraIntent> parse(String text) {
    // Treat pasted feeds, quoted reports and multi-command text as data.
    // A single user message may resolve to at most one executable intent.
    final executablePatterns = <RegExp>[
      _panicIsolationCommand,
      _resumeNetworkCommand,
      _cryptographicPurgeCommand,
      _activateDefensesCommand,
      _deactivateDefensesCommand,
      _analyzeDomainCommand,
      _auditDeviceCommand,
      _scanAppsCommand,
      _updateDefensesCommand,
      _blockCommand,
      _isolateCommand,
    ];
    final executableMatches = executablePatterns
        .where(
          (pattern) => identical(pattern, _isolateCommand)
              ? _hasIndependentIsolateCommand(text)
              : pattern.hasMatch(text),
        )
        .length;
    final hasEmbeddedCommandBoundary = RegExp(r'[;:\n]').hasMatch(text);
    if (executableMatches > 1 ||
        (hasEmbeddedCommandBoundary && executableMatches > 0)) {
      final rejected = AuraIntent(
        name: 'unknown',
        kind: AuraIntentKind.unknown,
        entities: const <String, dynamic>{},
        confidence: 0.0,
      );
      _remember(rejected);
      return Future<AuraIntent>.value(rejected);
    }

    final host = _extractHost(text);
    final isBlockCommand = _blockCommand.hasMatch(text);
    final isIsolateCommand = _isolateCommand.hasMatch(text);

    late final AuraIntent intent;
    if (_panicIsolationCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'panic_isolation',
        kind: AuraIntentKind.panicIsolation,
        entities: <String, dynamic>{
          if (_hasExplicitConfirmation(text)) 'confirmed_by_user': true,
        },
        confidence: 0.96,
      );
    } else if (_resumeNetworkCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'resume_network',
        kind: AuraIntentKind.resumeNetwork,
        entities: <String, dynamic>{
          if (_hasExplicitConfirmation(text)) 'confirmed_by_user': true,
        },
        confidence: 0.96,
      );
    } else if (_cryptographicPurgeCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'cryptographic_purge',
        kind: AuraIntentKind.cryptographicPurge,
        entities: <String, dynamic>{
          if (_hasExplicitConfirmation(text)) 'confirmed_by_user': true,
        },
        confidence: 0.96,
      );
    } else if (_activateDefensesCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'toggle_defenses',
        kind: AuraIntentKind.toggleDefenses,
        entities: <String, dynamic>{
          'activate': true,
          if (_hasExplicitConfirmation(text)) 'confirmed_by_user': true,
        },
        confidence: 0.96,
      );
    } else if (_deactivateDefensesCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'toggle_defenses',
        kind: AuraIntentKind.toggleDefenses,
        entities: <String, dynamic>{
          'activate': false,
          if (_hasExplicitConfirmation(text)) 'confirmed_by_user': true,
        },
        confidence: 0.96,
      );
    } else if (_helpCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'help',
        kind: AuraIntentKind.help,
        entities: <String, dynamic>{},
        confidence: 0.9,
      );
    } else if (_analyzeThreatsCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'analyze_threats',
        kind: AuraIntentKind.analyzeThreats,
        entities: <String, dynamic>{},
        confidence: 0.96,
      );
    } else if (_analyzeDomainCommand.hasMatch(text) && host != null) {
      intent = AuraIntent(
        name: 'analyze_domain',
        kind: AuraIntentKind.analyzeDomain,
        entities: <String, dynamic>{'domain': host},
        confidence: 0.96,
      );
    } else if (_auditDeviceCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'audit_device',
        kind: AuraIntentKind.auditDevice,
        entities: <String, dynamic>{},
        confidence: 0.95,
      );
    } else if (_scanAppsCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'scan_apps',
        kind: AuraIntentKind.scanApps,
        entities: <String, dynamic>{},
        confidence: 0.95,
      );
    } else if (_updateDefensesCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'update_defenses',
        kind: AuraIntentKind.updateDefenses,
        entities: <String, dynamic>{},
        confidence: 0.96,
      );
    } else if (isBlockCommand && host != null) {
      intent = AuraIntent(
        name: 'block_domain',
        kind: AuraIntentKind.block,
        entities: <String, dynamic>{
          'domain': host,
          if (_hasExplicitConfirmation(text)) 'confirmed_by_user': true,
        },
        confidence: 0.96,
      );
    } else if (isIsolateCommand) {
      final packageName = _extractPackageName(text);
      intent = AuraIntent(
        name: 'isolate_app',
        kind: AuraIntentKind.isolate,
        entities: <String, dynamic>{
          if (packageName != null) 'package_name': packageName,
          if (_hasExplicitConfirmation(text)) 'confirmed_by_user': true,
        },
        confidence: packageName == null ? 0.62 : 0.96,
      );
    } else if (_statusCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'status',
        kind: AuraIntentKind.status,
        entities: <String, dynamic>{},
        confidence: 0.88,
      );
    } else {
      final conversationKind = _classifyConversation(text);
      intent = conversationKind == null
          ? AuraIntent(
              name: 'unknown',
              kind: AuraIntentKind.unknown,
              entities: <String, dynamic>{},
              confidence: 0.0,
            )
          : AuraIntent(
              name: _intentName(conversationKind),
              kind: conversationKind,
              entities: <String, dynamic>{},
              confidence: 0.9,
            );
    }

    _remember(intent);
    return Future<AuraIntent>.value(intent);
  }

  static bool _hasIndependentIsolateCommand(String text) {
    final panicMatches = _panicIsolationCommand.allMatches(text);
    return _isolateCommand.allMatches(text).any((isolateMatch) {
      return !panicMatches.any(
        (panicMatch) =>
            isolateMatch.start < panicMatch.end &&
            panicMatch.start < isolateMatch.end,
      );
    });
  }

  static AuraIntentKind? _classifyConversation(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u');
    final matches = <AuraIntentKind, int>{};
    for (final entry in _conversationPatterns.entries) {
      final tokenMatches = entry.value.allMatches(normalized).length;
      if (tokenMatches > 0) matches[entry.key] = tokenMatches;
    }
    if (matches.isEmpty) return null;
    return matches.entries
        .reduce(
          (best, candidate) => candidate.value > best.value ? candidate : best,
        )
        .key;
  }

  static String _intentName(AuraIntentKind kind) => switch (kind) {
    AuraIntentKind.greet => 'greet',
    AuraIntentKind.identity => 'identity',
    AuraIntentKind.capabilities => 'capabilities',
    AuraIntentKind.securityCheck => 'security_check',
    AuraIntentKind.analyzeThreats => 'analyze_threats',
    AuraIntentKind.insult => 'insult',
    AuraIntentKind.praise => 'praise',
    AuraIntentKind.existential => 'existential',
    AuraIntentKind.fear => 'fear',
    AuraIntentKind.provocation => 'provocation',
    AuraIntentKind.humor => 'humor',
    AuraIntentKind.help => 'help',
    AuraIntentKind.toggleDefenses => 'toggle_defenses',
    _ => 'unknown',
  };

  static String? _extractHost(String text) {
    final candidates = <String>{};
    for (final match in _ipv4Pattern.allMatches(text)) {
      final value = match.group(0)!;
      final octets = value.split('.');
      if (!octets.every((octet) {
        final number = int.tryParse(octet);
        return number != null && number >= 0 && number <= 255;
      })) {
        // A malformed address alongside a valid host is still ambiguous.
        return null;
      }
      candidates.add(value);
    }
    for (final match in _hostPattern.allMatches(text)) {
      candidates.add(match.group(0)!.toLowerCase());
    }
    // Never silently choose a target when the request contains more than one.
    // Repeated mentions of the same normalized host remain unambiguous.
    return candidates.length == 1 ? candidates.single : null;
  }

  static String? _extractPackageName(String text) {
    final candidates = <String>{};
    for (final match in _packageLabelPattern.allMatches(text)) {
      candidates.add(match.group(1)!);
    }
    for (final match in _androidPackagePattern.allMatches(text)) {
      // Do not extract a suffix such as com.example from foo.com.example.
      if (match.start > 0 && text[match.start - 1] == '.') continue;
      candidates.add(match.group(0)!);
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  static void _remember(AuraIntent intent) {
    _historyBuffer[_nextHistoryIndex] = intent;
    _nextHistoryIndex = (_nextHistoryIndex + 1) % historyCapacity;
    if (_historySize < historyCapacity) _historySize++;
  }
}
