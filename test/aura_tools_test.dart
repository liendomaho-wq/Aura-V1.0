import 'package:aura_mobile_defens/agent/aura_tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shieldChannel = MethodChannel('com.ciberdefensa.aura/shield');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(shieldChannel, null);
  });

  test('toggle_defenses activa el VPN y devuelve el estado confirmado',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(shieldChannel, (call) async {
      calls.add(call.method);
      return true;
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': true},
      ),
    );

    expect(calls, <String>['startShield']);
    expect(result.summary, 'DEFENSA ACTIVADA — túnel en marcha');
    expect(result.data, <String, dynamic>{
      'ok': true,
      'vpn_active': true,
      'security_level': 'safe',
    });
  });

  test('toggle_defenses detiene el VPN con nivel de advertencia', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(shieldChannel, (call) async {
      calls.add(call.method);
      return true;
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': false},
      ),
    );

    expect(calls, <String>['stopShield']);
    expect(result.summary, 'DEFENSA DESACTIVADA — túnel detenido');
    expect(result.data, <String, dynamic>{
      'ok': true,
      'vpn_active': false,
      'security_level': 'warning',
    });
  });

  test('toggle_defenses informa si falta el plugin del motor VPN', () async {
    messenger.setMockMethodCallHandler(shieldChannel, (_) async {
      throw MissingPluginException();
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': false},
      ),
    );

    expect(
      result.summary,
      'No pude contactar el motor VPN. Revisa que Aura esté activa.',
    );
    expect(result.data['ok'], isFalse);
  });
}
