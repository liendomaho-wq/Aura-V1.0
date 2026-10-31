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

  test('unexpected native scan errors return a failed result without leaking details', () async {
    messenger.setMockMethodCallHandler(securityChannel, (_) async {
      throw StateError('private filesystem path /data/user/0/aura');
    });

    final result = await AuraTools.execute(
      const ToolStep(name: 'scan_apps', arguments: <String, dynamic>{}),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'operation_failed');
    expect(result.data['tool'], 'scan_apps');
    expect(result.data['security_level'], 'warning');
    expect(result.summary, contains('No se confirmó ningún cambio'));
    expect(result.summary, isNot(contains('/data/user/0/aura')));
    expect(result.data.toString(), isNot(contains('/data/user/0/aura')));
  });

  test('unexpected VPN tool errors do not escape the agent tool boundary',
      () async {
    messenger.setMockMethodCallHandler(shieldChannel, (_) async {
      throw StateError('native service crashed');
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': true},
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'operation_failed');
    expect(result.data['tool'], 'toggle_defenses');
    expect(result.data['security_level'], 'warning');
  });
}
