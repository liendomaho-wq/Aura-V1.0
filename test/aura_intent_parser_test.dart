import 'package:aura_mobile_defens/agent/aura_intent_parser.dart';
import 'package:aura_mobile_defens/agent/agent_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AuraIntentParser.clearHistory);

  test('activar defensas activa el escudo VPN', () async {
    final intent = await AuraIntentParser.parse('ACTIVAR LAS DEFENSAS');

    expect(intent.name, 'toggle_defenses');
    expect(intent.kind, AuraIntentKind.toggleDefenses);
    expect(intent.entities['activate'], isTrue);
    expect(intent.toEvent().kind, AgentEventKind.action);
  });

  test('desactiva el VPN detiene el escudo VPN', () async {
    final intent = await AuraIntentParser.parse('desactiva el vpn');

    expect(intent.name, 'toggle_defenses');
    expect(intent.kind, AuraIntentKind.toggleDefenses);
    expect(intent.entities['activate'], isFalse);
    expect(intent.toEvent().kind, AgentEventKind.action);
  });

  test('ayuda reconoce la orden de ayuda', () async {
    final intent = await AuraIntentParser.parse('Qué puedes hacer?');

    expect(intent.name, 'help');
    expect(intent.kind, AuraIntentKind.help);
    expect(intent.entities, isEmpty);
    expect(intent.toEvent().kind, AgentEventKind.thought);
  });

  test('escanear aplicaciones activa la herramienta de auditoría', () async {
    final intent = await AuraIntentParser.parse('analiza las aplicaciones instaladas');

    expect(intent.name, 'scan_apps');
    expect(intent.kind, AuraIntentKind.scanApps);
    expect(intent.entities, isEmpty);
    expect(intent.toEvent().kind, AgentEventKind.action);
  });

  test('bloquear un dominio sigue usando block_domain', () async {
    final intent =
        await AuraIntentParser.parse('bloquea evil.example.com');

    expect(intent.name, 'block_domain');
    expect(intent.kind, AuraIntentKind.block);
    expect(intent.entities['domain'], 'evil.example.com');
  });
}
