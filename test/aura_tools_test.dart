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

  test('audit_device consumes the real Android posture report', () async {
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      expect(call.method, 'checkHostileEnvironment');
      return <String, dynamic>{
        'isEmulator': false,
        'isRooted': false,
        'rootConfidence': 0,
        'isInstrumented': false,
        'isScreenOverlayDetected': false,
        'isHostile': false,
        'indicators': <String>[],
        'environmentCheckErrors': <String>['overlay_app_ops_unavailable'],
        'untrustedAccessibilityServicePackages': <String>[],
        'timestamp': 123,
      };
    });

    final result = await AuraTools.execute(
      const ToolStep(name: 'audit_device', arguments: <String, dynamic>{}),
    );

    expect(result.data['ok'], isTrue);
    expect(result.data['audit_status'], 'incomplete');
    expect(result.data['user_action_required'], isTrue);
    expect(result.data['security_level'], 'warning');
    expect(result.data['is_rooted'], isFalse);
    expect(result.data['check_errors'], <String>['overlay_app_ops_unavailable']);
    expect(result.summary, contains('incompleta'));
    expect(result.summary, isNot(contains('dispositivo seguro')));
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
        'special_access_count': 2,
        'active_special_access_count': 1,
        'special_access': <dynamic>[
          <String, dynamic>{
            'package_name': 'com.example.app',
            'access': 'OVERLAY',
            'state': 'ACTIVE',
          },
          <String, dynamic>{
            'package_name': 'com.example.app',
            'access': 'USAGE_STATS',
            'state': 'UNKNOWN',
          },
        ],
        'app_provenance_count': 1,
        'app_provenance': <dynamic>[
          <String, dynamic>{
            'package_name': 'com.example.app',
            'install_source_status': 'AVAILABLE',
          },
        ],
        'suspicious_app_count': 1,
        'suspicious_apps': <dynamic>[
          <String, dynamic>{
            'package_name': 'com.example.app',
            'app_name': 'Example App',
          },
        ],
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
    expect(result.data['active_special_access_count'], 1);
    expect(result.data['special_access'], hasLength(2));
    expect(result.data['app_provenance'], hasLength(1));
    expect(result.data['limitations'], isA<List<String>>());
    expect(result.summary, contains('no prueba de malware'));
  });

  test('scan_apps marks missing or inconsistent native reports incomplete',
      () async {
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      expect(call.method, 'scanActiveSensitiveServices');
      return <String, dynamic>{
        'timestamp': 123,
        'count': 0,
        // Missing required arrays and counters must never become a clean scan.
      };
    });

    final result = await AuraTools.execute(
      const ToolStep(name: 'scan_apps', arguments: <String, dynamic>{}),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'invalid_scan_report');
    expect(result.data['scan_status'], 'incomplete');
    expect(result.data['security_level'], 'warning');
    expect(result.summary, contains('incompleta'));
    expect(result.summary, isNot(contains('0 apps')));
  });

  test('scan_apps rejects counts that do not match returned evidence',
      () async {
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      return <String, dynamic>{
        'timestamp': 123,
        'count': 0,
        'applications': <dynamic>[
          <String, dynamic>{'package_name': 'com.example.app'},
        ],
        'special_access_count': 0,
        'active_special_access_count': 0,
        'special_access': <dynamic>[],
        'app_provenance_count': 0,
        'app_provenance': <dynamic>[],
        'suspicious_app_count': 0,
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

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'invalid_scan_report');
    expect(result.data['scan_status'], 'incomplete');
  });

  test('scan_apps rejects an active-access count without matching evidence',
      () async {
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      return <String, dynamic>{
        'timestamp': 123,
        'count': 0,
        'applications': <dynamic>[],
        'special_access_count': 1,
        'active_special_access_count': 1,
        'special_access': <dynamic>[
          <String, dynamic>{
            'package_name': 'com.example.app',
            'access': 'OVERLAY',
            'state': 'UNKNOWN',
          },
        ],
        'app_provenance_count': 0,
        'app_provenance': <dynamic>[],
        'suspicious_app_count': 0,
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

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'invalid_scan_report');
    expect(result.data['scan_status'], 'incomplete');
  });

  test('toggle_defenses activa el VPN sin certificar la postura del dispositivo',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(shieldChannel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'startShield' => true,
        'getShieldStatus' => <String, dynamic>{
            'service_active': true,
            'vpn_interface_active': true,
            'forwarding_active': true,
            'isolation_active': false,
          },
        _ => null,
      };
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': true, 'confirmed_by_user': true},
      ),
    );

    expect(calls, <String>['startShield']);
    expect(result.summary, 'DEFENSA ACTIVADA — túnel en marcha');
    expect(result.data, <String, dynamic>{
      'ok': true,
      'tool': 'toggle_defenses',
      'vpn_active': true,
    });
    // Starting the VPN is not a device-posture audit and must not clear
    // an existing warning or critical security state.
  });

  test('toggle_defenses detiene el VPN sin alterar la postura auditada', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(shieldChannel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'stopShield' => true,
        'getShieldStatus' => <String, dynamic>{
            'service_active': false,
            'vpn_interface_active': false,
            'forwarding_active': false,
            'isolation_active': false,
          },
        _ => null,
      };
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': false, 'confirmed_by_user': true},
      ),
    );

    expect(calls, <String>['stopShield']);
    expect(result.summary, 'DEFENSA DESACTIVADA — túnel detenido');
    expect(result.data, <String, dynamic>{
      'ok': true,
      'tool': 'toggle_defenses',
      'vpn_active': false,
    });
    // Stopping the tunnel reports its state; posture remains owned by
    // audit_device and existing critical alerts are never downgraded.
  });

  test('toggle_defenses refuses to change VPN state without user confirmation',
      () async {
    var called = false;
    messenger.setMockMethodCallHandler(shieldChannel, (_) async {
      called = true;
      return true;
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': true},
      ),
    );

    expect(called, isFalse);
    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'user_confirmation_required');
  });

  test('block_domain refuses to add a rule without user confirmation',
      () async {
    const engineChannel = MethodChannel('com.aura.cyberdefense/engine');
    messenger.setMockMethodCallHandler(engineChannel, (_) async {
      fail('Native block channel must not be called without consent.');
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'block_domain',
        arguments: <String, dynamic>{'domain': 'example.test'},
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'user_confirmation_required');
    messenger.setMockMethodCallHandler(engineChannel, null);
  });

  test('isolate_app refuses to open settings without confirmation', () async {
    const engineChannel = MethodChannel('com.aura.cyberdefense/engine');
    messenger.setMockMethodCallHandler(engineChannel, (_) async {
      fail('App settings must not open without explicit confirmation.');
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'isolate_app',
        arguments: <String, dynamic>{'package_name': 'com.example.test'},
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'user_confirmation_required');
    messenger.setMockMethodCallHandler(engineChannel, null);
  });

  test('isolate_app validates package and reports Android limitation', () async {
    const engineChannel = MethodChannel('com.aura.cyberdefense/engine');
    var called = false;
    messenger.setMockMethodCallHandler(engineChannel, (call) async {
      expect(call.method, 'openAppDetails');
      called = true;
      return <String, dynamic>{
        'ok': true,
        'message': 'Se abrió la configuración de la aplicación.',
      };
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'isolate_app',
        arguments: <String, dynamic>{
          'package_name': 'com.example.test',
          'confirmed_by_user': true,
        },
      ),
    );

    expect(called, isTrue);
    expect(result.data['isolation_performed'], isFalse);
    expect(result.data['user_action_required'], isTrue);
    expect(result.data['action'], 'open_app_settings');
    expect(result.data['limitations'], isA<List<String>>());
    messenger.setMockMethodCallHandler(engineChannel, null);
  });

  test('isolate_app refuses success when Android omits its postcondition', () async {
    const engineChannel = MethodChannel('com.aura.cyberdefense/engine');
    messenger.setMockMethodCallHandler(engineChannel, (_) async {
      return <String, dynamic>{
        'message': 'Android abrió la ficha de ajustes.',
      };
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'isolate_app',
        arguments: <String, dynamic>{
          'package_name': 'com.example.test',
          'confirmed_by_user': true,
        },
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'invalid_tool_postcondition');
    expect(result.data['tool'], 'isolate_app');
    messenger.setMockMethodCallHandler(engineChannel, null);
  });

  test('isolate_app rejects invalid package identifiers', () async {
    const engineChannel = MethodChannel('com.aura.cyberdefense/engine');
    messenger.setMockMethodCallHandler(engineChannel, (_) async {
      fail('Invalid package identifiers must not reach Android.');
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'isolate_app',
        arguments: <String, dynamic>{
          'package_name': '../../not.a.package',
          'confirmed_by_user': true,
        },
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'invalid_package_name');
    messenger.setMockMethodCallHandler(engineChannel, null);
  });

  test('panic isolation refuses to run without explicit confirmation', () async {
    const panicChannel = MethodChannel('com.aura.cyberdefense/panic');
    messenger.setMockMethodCallHandler(panicChannel, (_) async {
      fail('Panic isolation must not run without user confirmation.');
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'panic_isolation',
        arguments: <String, dynamic>{},
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'user_confirmation_required');
    messenger.setMockMethodCallHandler(panicChannel, null);
  });

  test('resume_network refuses to restore forwarding without confirmation',
      () async {
    const panicChannel = MethodChannel('com.aura.cyberdefense/panic');
    messenger.setMockMethodCallHandler(panicChannel, (_) async {
      fail('VPN forwarding must not resume without explicit confirmation.');
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'resume_network',
        arguments: <String, dynamic>{},
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'user_confirmation_required');
    expect(result.data['tool'], 'resume_network');
    messenger.setMockMethodCallHandler(panicChannel, null);
  });

  test('resume_network restores forwarding only after confirmation', () async {
    const panicChannel = MethodChannel('com.aura.cyberdefense/panic');
    messenger.setMockMethodCallHandler(shieldChannel, (call) async {
      expect(call.method, 'getShieldStatus');
      return <String, dynamic>{
        'service_active': true,
        'vpn_interface_active': true,
        'forwarding_active': true,
        'isolation_active': false,
      };
    });
    var called = false;
    messenger.setMockMethodCallHandler(panicChannel, (call) async {
      expect(call.method, 'resumeTunnel');
      called = true;
      return true;
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'resume_network',
        arguments: <String, dynamic>{'confirmed_by_user': true},
      ),
    );

    expect(called, isTrue);
    expect(result.data['ok'], isTrue);
    expect(result.data['tool'], 'resume_network');
    expect(result.data.containsKey('security_level'), isFalse);
    // Restoring forwarding is not a device-posture audit.
    messenger.setMockMethodCallHandler(panicChannel, null);
  });

  test('cryptographic purge refuses to run without explicit confirmation', () async {
    final result = await AuraTools.execute(
      const ToolStep(
        name: 'cryptographic_purge',
        arguments: <String, dynamic>{},
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'user_confirmation_required');
  });

  test('toggle_defenses informa si falta el plugin del motor VPN', () async {
    messenger.setMockMethodCallHandler(shieldChannel, (_) async {
      throw MissingPluginException();
    });

    final result = await AuraTools.execute(
      const ToolStep(
        name: 'toggle_defenses',
        arguments: <String, dynamic>{'activate': false, 'confirmed_by_user': true},
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
        arguments: <String, dynamic>{'activate': true, 'confirmed_by_user': true},
      ),
    );

    expect(
      result.summary,
      'No pude contactar el motor VPN. Revisa que Aura esté activa.',
    );
    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'operation_failed');
    expect(result.data['tool'], 'toggle_defenses');
    expect(result.data['code'], 'vpn_unavailable');
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
        arguments: <String, dynamic>{'activate': true, 'confirmed_by_user': true},
      ),
    );

    expect(result.data['ok'], isFalse);
    expect(result.data['error'], 'operation_failed');
    expect(result.data['tool'], 'toggle_defenses');
    expect(result.data['security_level'], 'warning');
  });
}
