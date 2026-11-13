import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/screens/aura_core_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpAuraFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('muestra hallazgos verificables y su evidencia en solo lectura', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    const shieldChannel = MethodChannel('com.ciberdefensa.aura/shield');
    const securityChannel = MethodChannel('com.ciberdefensa.aura/security');
    const biometricChannel = MethodChannel('com.aura.cyberdefense/biometrics');
    const telemetryChannel = MethodChannel('com.ciberdefensa.aura/telemetry');
    const networkEventChannel = EventChannel(
      'com.aura.cyberdefense/network_stream',
    );
    final state = AuraStateProvider();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(shieldChannel, null);
      messenger.setMockMethodCallHandler(securityChannel, null);
      messenger.setMockMethodCallHandler(biometricChannel, null);
      messenger.setMockMethodCallHandler(telemetryChannel, null);
      messenger.setMockStreamHandler(networkEventChannel, null);
      state.dispose();
    });
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      if (call.method == 'checkHostileEnvironment') {
        return <String, Object>{
          'untrustedAccessibilityServicePackages': <String>[],
        };
      }
      return true;
    });
    messenger.setMockMethodCallHandler(biometricChannel, (_) async => true);
    messenger.setMockMethodCallHandler(shieldChannel, (call) async {
      if (call.method == 'getShieldStatus') {
        return <String, dynamic>{
          'service_active': false,
          'vpn_interface_active': false,
          'forwarding_active': false,
          'isolation_active': false,
          'status_verified': true,
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(telemetryChannel, (call) async {
      if (call.method == 'domainTelemetryStatus') {
        return <String, Object>{'optedIn': false, 'endpointConfigured': false};
      }
      return true;
    });
    messenger.setMockStreamHandler(
      networkEventChannel,
      MockStreamHandler.inline(onListen: (_, __) {}),
    );

    state.recordDeviceAuditResult(<String, dynamic>{
      'ok': true,
      'tool': 'audit_device',
      'is_rooted': true,
      'is_emulator': false,
      'is_instrumented': false,
      'is_debugger_connected': false,
      'screen_overlay_detected': false,
      'root_confidence': 90,
      'root_indicators': <String>['su_binary:/system/bin/su'],
      'untrusted_accessibility_packages': <String>[],
      'check_errors': <String>[],
      'timestamp': 1000,
    });
    state.recordAppScanResult(<String, dynamic>{
      'ok': true,
      'scan_type': 'installed_app_static_review',
      'timestamp': 2000,
      'applications': <dynamic>[
        <String, dynamic>{
          'package_name': 'com.example.one',
          'app_name': 'One',
          'active_services': <dynamic>[
            <String, dynamic>{'type': 'ACCESSIBILITY'},
          ],
        },
      ],
      'special_access': <dynamic>[],
      'suspicious_apps': <dynamic>[
        <String, dynamic>{
          'package_name': 'com.example.one',
          'app_name': 'One',
          'high_risk_permissions': <String>[
            'android.permission.SYSTEM_ALERT_WINDOW',
          ],
        },
      ],
      'signature_issues': <dynamic>[],
      'obfuscated_apps': <dynamic>[],
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AuraStateProvider>.value(
        value: state,
        child: const MaterialApp(home: AuraCoreScreen()),
      ),
    );
    await _pumpAuraFrames(tester);

    final eventList = find.byKey(const ValueKey<String>('aura-event-list'));
    expect(eventList, findsOneWidget);
    final findingsCenter = find.byKey(
      const ValueKey<String>('findings-center'),
    );
    await tester.dragUntilVisible(
      findingsCenter,
      eventList,
      const Offset(0, 300),
    );
    await tester.ensureVisible(findingsCenter);
    await tester.pump();

    expect(find.text('CENTRO DE HALLAZGOS'), findsOneWidget);
    expect(find.text('3 HALLAZGOS'), findsOneWidget);
    expect(
      find.text('Postura: completa · Apps: completa · Red: 0 alertas'),
      findsOneWidget,
    );
    expect(find.text('ACTUALIZAR'), findsOneWidget);

    final rootFinding = find.byKey(
      const ValueKey<String>('finding-device-root-indicators'),
    );
    await tester.ensureVisible(rootFinding);
    await tester.pump();
    await tester.tap(rootFinding);
    await _pumpAuraFrames(tester);

    expect(
      find.text('• Indicadores: su_binary:/system/bin/su'),
      findsOneWidget,
    );
    expect(
      find.text(
        '• Root o Shizuku puede ocultarse a las comprobaciones de una app normal.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Solo lectura · no se modificó ninguna app'),
      findsOneWidget,
    );
  });
}
