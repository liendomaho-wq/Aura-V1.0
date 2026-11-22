import 'package:aura_mobile_defens/firewall/aura_firewall_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const self = 'com.ciberdefensa.aura';

  test('normal excludes Aura and the chosen apps', () {
    final decision = const AuraFirewallPolicy(
      bypass: <String>['com.example.browser'],
    ).decide(self);
    expect(decision.disallowed, <String>[self, 'com.example.browser']);
    expect(decision.allowed, isEmpty);
  });

  test('estricto ignores the bypass list', () {
    final decision = const AuraFirewallPolicy(
      mode: AuraFirewallMode.estricto,
      bypass: <String>['com.example.browser'],
    ).decide(self);
    expect(decision.disallowed, <String>[self]);
    expect(decision.allowed, isEmpty);
  });

  test('paranoico never puts Aura in the tunnel list', () {
    final decision = const AuraFirewallPolicy(
      mode: AuraFirewallMode.paranoico,
      tunnelOnly: <String>['com.example.mail', self],
    ).decide(self);
    expect(decision.disallowed, isEmpty);
    expect(decision.allowed, <String>['com.example.mail']);
  });

  test('paranoico without apps is refused', () {
    expect(
      () => const AuraFirewallPolicy(
        mode: AuraFirewallMode.paranoico,
      ).decide(self),
      throwsFormatException,
    );
  });
}
