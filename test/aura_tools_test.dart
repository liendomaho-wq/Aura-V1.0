import 'package:aura_mobile_defens/agent/aura_tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shieldChannel = MethodChannel('com.ciberdefensa.aura/shield');
  const securityChannel = MethodChannel('com.ciberdefensa.aura/security');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(shieldChannel, null);
    messenger.setMockMethodCallHandler(securityChannel, null);
  });

  test('scan_apps devuelve informe nativo y advierte sobre límites heurísticos', () async {
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      expect(call.method, 'scanActiveSensitiveServices');
      return <String, dynamic>{
        'timestamp': 123,
        'count': 1,
        'applications': <dynamic>[
          <String, dynamic>{'package_name': 'com.example.app'},
        ],
        'suspicious_app_count': 1,
        'suspicious_apps': <dynamic>[],
        'signature_issue_count': 0,
        'signature_issues': <dynamic>[],
        'obfuscated_app_count': 0,
        'obfuscated_apps': <dynamic>[],
      };
    });

    final result = await AuraTools.execute(
      const ToolStep(name: 'scan_apps', arguments: <String, dynamic>{}),
    );

    expect(result.data['ok'], isTrue);
    expect(result.data['scan_type'], 'installed_app_static_review');
    expect(result.data['active_service_app_count'], 1);
    expect(result.data['suspicious_app_count'], 1);
    expect(result.data['limitations'], isA<List<String>>());
    expect(result.summary, contains('no prueba de malware'));
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

  test('toggle_defenses informa errores del motor VPN en español', () async {
    messenger.setMockMethodCallHandler(shieldChannel, (_) async {
      throw PlatformException(code: 'vpn_unavailable');
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': true},
      ),
    );

    expect(
      result.summary,
      'No pude contactar el motor VPN. Revisa que Aura esté activa.',
    );
    expect(result.data['ok'], isFalse);
  });
}
