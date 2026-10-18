import 'package:aura_mobile_defens/inference/aura_evasion_endpoints.dart';
import 'package:aura_mobile_defens/providers/aura_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contiene la lista declarada de resolutores cifrados conocidos', () {
    expect(knownEncryptedDnsEndpoints, <String>[
      'cloudflare-dns.com',
      'mozilla.cloudflare-dns.com',
      'chrome.cloudflare-dns.com',
      'dns.google',
      'dns.quad9.net',
      'dns.adguard.com',
      'doh.opendns.com',
      'doh.cleanbrowsing.org',
      'doh.dns.sb',
      'dns.sse.cisco.com',
    ]);
  });

  test('cuenta eventos de bloqueo de DNS cifrado en la sesión', () {
    final state = AuraStateProvider();
    addTearDown(state.dispose);

    state.addTelemetryEvent(<String, Object>{
      'action': 'ENCRYPTED_DNS_BLOCKED',
      'requested_domain': 'dns.google',
      'destination_port': 443,
      'transport_protocol': 'TCP',
    });

    expect(state.encryptedDnsBlocks, 1);
  });
}
