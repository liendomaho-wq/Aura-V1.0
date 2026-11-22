import 'package:aura_mobile_defens/firewall/aura_firewall_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const self = 'com.ciberdefensa.aura';

  test('normal lets chosen apps around the tunnel and never Aura', () {
    expect(
      const AuraFirewallPolicy(
        bypass: <String>['com.example.browser', self],
      ).extraDisallowed(self),
      <String>['com.example.browser'],
    );
  });

  test('estricto ignores the bypass list', () {
    expect(
      const AuraFirewallPolicy(
        mode: AuraFirewallMode.estricto,
        bypass: <String>['com.example.browser'],
      ).extraDisallowed(self),
      isEmpty,
    );
  });

  test('paranoico is refused because Aura must stay outside the tunnel', () {
    expect(
      () => AuraFirewallPolicy.parse(<String, dynamic>{'mode': 'paranoico'}),
      throwsFormatException,
    );
  });
}
