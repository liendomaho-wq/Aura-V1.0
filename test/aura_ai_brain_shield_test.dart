import 'package:aura_mobile_defens/ai_brain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stop request acknowledgement is not a confirmed shutdown', () async {
    const channel = MethodChannel('com.ciberdefensa.aura/shield');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final brain = AuraAIBrain();
    expect(await brain.setShieldActive(true), isTrue);
    expect(await brain.setShieldActive(false), isFalse);
  });
}
