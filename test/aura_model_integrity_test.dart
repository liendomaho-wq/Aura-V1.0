import 'dart:io';

import 'package:aura_mobile_defens/ai_brain.dart';
import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:aura_mobile_defens/secure_vault.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSecureVault extends AuraSecureVault {
  @override
  Future<String> getOrCreateModelMasterKey() async => 'unused-by-base-asset';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compara versiones semver por tripletas numéricas', () {
    expect(compareSemverTriplets('3.0.10', '3.0.2'), greaterThan(0));
    expect(compareSemverTriplets('3.0.0', '3.0.0'), 0);
    expect(compareSemverTriplets('2.99.99', '3.0.0'), lessThan(0));
    expect(modelVersionRollbackMessage('3.0.0'), isNull);
    expect(
      modelVersionRollbackMessage('2.9.9'),
      '[CRIT] Downgrade de modelo rechazado '
      '(2.9.9 < 3.0.0): firma válida pero versión inferior a la mínima soportada.',
    );
    expect(
      () => compareSemverTriplets('3.0', '3.0.0'),
      throwsFormatException,
    );
  });

  test('verifies the published model asset against its SHA-256 sidecar',
      () async {
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final supportDirectory =
        await Directory.systemTemp.createTemp('aura-model-integrity-');
    messenger.setMockMethodCallHandler(
      pathProviderChannel,
      (_) async => supportDirectory.path,
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      await supportDirectory.delete(recursive: true);
    });

    final state = AuraStateProvider();
    addTearDown(state.dispose);
    final brain = AuraAIBrain(
      stateProvider: state,
      secureVault: _TestSecureVault(),
    );
    expect(await brain.preloadModel(), isTrue);
    await brain.analyzeThreatPayload('goggle.com');

    expect(state.explanationHistory, hasLength(1));
    final explanation = state.explanationHistory.single;
    expect(explanation.isThreat, isFalse);
    expect(
      explanation.signals.single.label,
      'Posible typosquatting (señal auxiliar)',
    );

    final report = await brain.verifyModelIntegrity();
    expect(report.verified, isTrue);
    expect(report.signatureVerified, isTrue);
    expect(
      report.sha256,
      'd190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2',
    );
    expect(report.message, contains('firma RSA verificados'));
  });
}
