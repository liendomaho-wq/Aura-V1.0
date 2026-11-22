import 'package:aura_mobile_defens/voice/aura_briefing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the opening line uses the real network and today count', () {
    expect(
      auraStatusBrief(
        defenseActive: true,
        networkLabel: 'WiFi',
        blocksSeenToday: 2,
      ),
      'Defensa activa en WiFi. Bloqueos que vi hoy: 2.',
    );
    expect(
      auraStatusBrief(
        defenseActive: false,
        networkLabel: 'Sin conexión',
        blocksSeenToday: 0,
      ),
      'Defensa inactiva. Bloqueos que vi hoy: 0.',
    );
  });

  test('only today block and DGA events count', () {
    final now = DateTime(2026, 11, 22, 15, 40);
    final yesterday = DateTime(2026, 11, 21, 23, 0).millisecondsSinceEpoch;
    expect(
      auraBlocksSeenToday(<Map<String, dynamic>>[
        <String, dynamic>{
          'action': 'BLOCKED',
          'timestamp': now.millisecondsSinceEpoch,
        },
        <String, dynamic>{
          'action': 'ALLOWED',
          'timestamp': now.millisecondsSinceEpoch,
        },
        <String, dynamic>{'action': 'DGA_ALERT', 'timestamp': yesterday},
      ], now),
      1,
    );
  });

  test('threat speech is rate limited', () {
    final gate = AuraAlertGate(gap: const Duration(seconds: 20));
    final start = DateTime(2026, 11, 22, 15, 41);
    expect(gate.allow(start), isTrue);
    expect(gate.allow(start.add(const Duration(seconds: 5))), isFalse);
    expect(gate.allow(start.add(const Duration(seconds: 20))), isTrue);
  });
}
