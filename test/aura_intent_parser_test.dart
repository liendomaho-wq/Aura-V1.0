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

  test('la orden literal ESCANEAR APLICACIONES activa scan_apps', () async {
    final intent = await AuraIntentParser.parse('ESCANEAR APLICACIONES');

    expect(intent.name, 'scan_apps');
    expect(intent.kind, AuraIntentKind.scanApps);
    expect(intent.entities, isEmpty);
  });

  test('auditar dispositivo invoca la herramienta nativa de postura Android', () async {
    final intent = await AuraIntentParser.parse('audita el dispositivo');

    expect(intent.name, 'audit_device');
    expect(intent.kind, AuraIntentKind.auditDevice);
    expect(intent.entities, isEmpty);
    expect(intent.toEvent().kind, AgentEventKind.action);
  });

  test('analizar un dominio invoca la herramienta del modelo local', () async {
    final intent = await AuraIntentParser.parse(
      'analiza el dominio example.org',
    );

    expect(intent.name, 'analyze_domain');
    expect(intent.kind, AuraIntentKind.analyzeDomain);
    expect(intent.entities['domain'], 'example.org');
    expect(intent.toEvent().kind, AgentEventKind.action);
  });

  test('un bloqueo requiere confirmación explícita en una segunda orden', () async {
    final request = await AuraIntentParser.parse('bloquea evil.example.com');
    expect(request.entities['confirmed_by_user'], isNull);

    final declined = await AuraIntentParser.parse(
      'no confirmo el bloqueo de evil.example.com',
    );
    expect(declined.entities['confirmed_by_user'], isNull);

    final confirmation = await AuraIntentParser.parse(
      'confirmo el bloqueo de evil.example.com',
    );
    expect(confirmation.name, 'block_domain');
    expect(confirmation.entities['domain'], 'evil.example.com');
    expect(confirmation.entities['confirmed_by_user'], isTrue);
  });

  test('aislamiento de emergencia distingue la confirmación explícita', () async {
    final request = await AuraIntentParser.parse('aislamiento de emergencia');
    expect(request.entities['confirmed_by_user'], isNull);

    final confirmation = await AuraIntentParser.parse(
      'confirmo el aislamiento de emergencia',
    );
    expect(confirmation.name, 'panic_isolation');
    expect(confirmation.entities['confirmed_by_user'], isTrue);
  });

  test('purga criptográfica requiere confirmación explícita', () async {
    final request = await AuraIntentParser.parse('purga criptográfica');
    expect(request.entities['confirmed_by_user'], isNull);

    final confirmation = await AuraIntentParser.parse(
      'confirmo la purga criptográfica',
    );
    expect(confirmation.name, 'cryptographic_purge');
    expect(confirmation.entities['confirmed_by_user'], isTrue);
  });

  test('bloquear un dominio sigue usando block_domain', () async {
    final intent =
        await AuraIntentParser.parse('bloquea evil.example.com');

    expect(intent.name, 'block_domain');
    expect(intent.kind, AuraIntentKind.block);
    expect(intent.entities['domain'], 'evil.example.com');
  });
}
