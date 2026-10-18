import 'package:aura_mobile_defens/agent/aura_intent_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AuraIntentParser.clearHistory);

  test('activar defensas activa el escudo VPN', () async {
    final intent = await AuraIntentParser.parse('activar defensas');

    expect(intent.name, 'toggle_defenses');
    expect(intent.kind, AuraIntentKind.toggleDefenses);
    expect(intent.entities['activate'], isTrue);

    final joinedIntent = await AuraIntentParser.parse('activardefensas');
    expect(joinedIntent.name, 'toggle_defenses');
    expect(joinedIntent.entities['activate'], isTrue);
  });

  test('desactiva el VPN detiene el escudo VPN', () async {
    final intent = await AuraIntentParser.parse('desactiva el vpn');

    expect(intent.name, 'toggle_defenses');
    expect(intent.kind, AuraIntentKind.toggleDefenses);
    expect(intent.entities['activate'], isFalse);
  });

  test('ayuda reconoce la orden de ayuda', () async {
    final intent = await AuraIntentParser.parse('ayuda');

    expect(intent.name, 'help');
    expect(intent.kind, AuraIntentKind.help);
    expect(intent.entities, isEmpty);
  });

  test('bloquear un dominio sigue usando block_domain', () async {
    final intent =
        await AuraIntentParser.parse('bloquea evil.example.com');

    expect(intent.name, 'block_domain');
    expect(intent.kind, AuraIntentKind.block);
    expect(intent.entities['domain'], 'evil.example.com');
  });
}
