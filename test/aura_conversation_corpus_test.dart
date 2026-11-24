import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aura_mobile_defens/agent/aura_conversation.dart';
import 'package:aura_mobile_defens/agent/aura_intent_parser.dart';

const String _corpusPath = 'test/fixtures/aura_conversation_corpus_es.json';

Map<String, dynamic> _loadCorpus() {
  final decoded = jsonDecode(File(_corpusPath).readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('El corpus no es un objeto JSON.');
  }
  return decoded;
}

AuraIntent _hostIntent(String host) => AuraIntent(
  name: 'analyze_domain',
  kind: AuraIntentKind.analyzeDomain,
  entities: <String, dynamic>{'domain': host},
  confidence: 0.96,
);

AuraIntent _packageIntent(String packageName) => AuraIntent(
  name: 'isolate_app',
  kind: AuraIntentKind.isolate,
  entities: <String, dynamic>{'package_name': packageName},
  confidence: 0.96,
);

void main() {
  final corpus = _loadCorpus();
  final intents = (corpus['intents'] as List).cast<Map<String, dynamic>>();
  final followUps = (corpus['followUps'] as List).cast<Map<String, dynamic>>();
  final confirmations = (corpus['confirmations'] as List)
      .cast<Map<String, dynamic>>();
  final denials = (corpus['denials'] as List).cast<Map<String, dynamic>>();
  final total =
      intents.length + followUps.length + confirmations.length + denials.length;

  test('el corpus contiene al menos 300 frases naturales', () {
    expect(total, greaterThanOrEqualTo(300));
  });

  test('la intención se clasifica sin errores en el corpus', () async {
    final failures = <String>[];
    for (final entry in intents) {
      final text = entry['text'] as String;
      final expected = AuraIntentKind.values.byName(
        entry['expected'] as String,
      );
      AuraIntentParser.clearHistory();
      final intent = await AuraIntentParser.parse(text);
      if (intent.kind != expected) {
        failures.add('$text → ${intent.kind.name} (esperado ${expected.name})');
      }
    }
    // ignore: avoid_print
    print(
      'Intención: ${intents.length - failures.length}/${intents.length} '
      '(${((intents.length - failures.length) / intents.length * 100).toStringAsFixed(1)}%)',
    );
    expect(failures, isEmpty, reason: failures.take(25).join('\n'));
  });

  test('el seguimiento resuelve la referencia correcta', () {
    final memory = AuraConversationMemory.instance;
    final failures = <String>[];
    for (final entry in followUps) {
      memory.reset();
      memory.recordIntent(_hostIntent('tracker.example'));
      memory.recordIntent(_packageIntent('com.example.app'));
      memory.recordAuraMessage('Respuesta previa de la sesión.');
      final text = entry['text'] as String;
      final expected = AuraFollowUpKind.values.byName(
        entry['expected'] as String,
      );
      final followUp = memory.followUpFor(text);
      if (followUp?.kind != expected) {
        failures.add(
          '$text → ${followUp?.kind.name} (esperado ${expected.name})',
        );
      }
    }
    // ignore: avoid_print
    print(
      'Seguimiento: ${followUps.length - failures.length}/${followUps.length} '
      '(${((followUps.length - failures.length) / followUps.length * 100).toStringAsFixed(1)}%)',
    );
    expect(failures, isEmpty, reason: failures.take(25).join('\n'));
  });

  test('la confirmación natural no acepta objetivos nuevos ni negaciones', () {
    final memory = AuraConversationMemory.instance;
    final failures = <String>[];
    for (final entry in confirmations) {
      final text = entry['text'] as String;
      final expected = entry['expected'] as bool;
      if (memory.isConfirmation(text) != expected) {
        failures.add('$text → ${!expected} (esperado $expected)');
      }
    }
    expect(failures, isEmpty, reason: failures.take(25).join('\n'));
  });

  test('la negación natural solo acepta frases completas', () {
    final memory = AuraConversationMemory.instance;
    final failures = <String>[];
    for (final entry in denials) {
      final text = entry['text'] as String;
      final expected = entry['expected'] as bool;
      if (memory.isDenial(text) != expected) {
        failures.add('$text → ${!expected} (esperado $expected)');
      }
    }
    expect(failures, isEmpty, reason: failures.take(25).join('\n'));
  });

  test('ninguna confirmación positiva contiene un dominio', () {
    final seen = <String>{};
    for (final entry in confirmations.where(
      (entry) => entry['expected'] == true,
    )) {
      final text = entry['text'] as String;
      if (RegExp(r'\b[a-z0-9-]+(?:\.[a-z0-9-]+)+\b').hasMatch(text)) {
        seen.add(text);
      }
    }
    expect(seen, isEmpty);
  });
}
