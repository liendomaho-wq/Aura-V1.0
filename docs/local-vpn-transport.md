# Aura local VPN transport

## What changed

Aura no longer expects the fictional host `socks5.tun2socks.local` to exist. The existing
`hev-socks5-tunnel` engine is still used as a TUN-to-SOCKS5 client, but its SOCKS5 endpoint
is now a device-local listener bound only to `127.0.0.1` on an ephemeral local port.

- TCP CONNECT requests are forwarded through outbound sockets protected with
  `VpnService.protect(Socket)` before connecting.
- SOCKS5 UDP ASSOCIATE uses a local relay whose datagram socket is protected with
  `VpnService.protect(DatagramSocket)` before sending outbound packets. The relay only
  forwards replies from endpoints requested by that association and caps tracked endpoints.
- The VPN advertises `1.1.1.1` and `1.0.0.1` as DNS servers. DNS packets are captured by
  the full-tunnel routes and carried through the UDP relay; protected upstream sockets bypass
  the TUN and therefore avoid a forwarding loop.
- DNS hostnames are intentionally not resolved inside the SOCKS relay. It accepts numeric
  destination addresses only, preventing recursive DNS lookups from the forwarding path.
- The threat feed is defense-in-depth: a temporary feed outage no longer prevents the VPN
  interface from starting. The last validated IP list is cached locally and retained if a
  refresh fails.

## Important limitations

This is a local forwarding transport, not a full DNS filtering implementation. Removing
Hev's `mapdns` synthetic-address mode means domain-based DNS classification/blocking must
not be claimed on the basis of this change alone. IP block rules and the existing TCP SNI
inspection remain separate features and require their own end-to-end verification.

DNS is sent to the configured public resolvers through the tunnel; this does not make DNS
queries private from those resolvers. Android Private DNS (DoT), DNS-over-HTTPS, QUIC, ECH,
IPv6 UDP relay behavior, captive portals, network changes, and per-app traffic need device
integration tests. The unit tests exercise local IPv4 TCP and UDP relay behavior only.

The local SOCKS5 listener requires per-run random RFC 1929 credentials and binds only to
loopback. Its generated credentials are written to the app-private tunnel configuration for
Hev to consume. Do not change the bind address to `0.0.0.0` or a LAN interface without a
separate threat model and additional hardening.

## Verification

Run:

```bash
flutter pub get
flutter test
cd android
./gradlew testDebugUnitTest --no-daemon
```

A successful JVM unit test run does not replace testing on a physical Android device. Keep
this branch unmerged until CI is green and VPN activation, DNS, TCP, UDP, pause/resume, and
network handoff are verified on-device.

## Release-gate checklist for a physical Android device

Do not interpret the VPN notification or the “active” indicator as proof that all traffic is inspected. Record the device model, Android version, build SHA, and result for each case before promoting a release.

- [ ] Start and stop the VPN repeatedly; verify Android's system VPN indicator follows the actual service state.
- [ ] Load an HTTPS site and a plain DNS test endpoint; verify normal TCP and DNS connectivity while the tunnel is active.
- [ ] Exercise a UDP application and confirm it remains functional; repeat with IPv4 and IPv6 where the network supports both.
- [ ] Confirm a threat-feed outage does not erase the cached list, and that a successful refresh replaces it with validated entries.
- [ ] Pause/resume forwarding and activate/deactivate panic isolation; verify no stale “protected” state remains in the UI.
- [ ] Switch Wi-Fi to mobile data, reverse the switch, and repeat with airplane mode. Record whether Android recreates the network and whether Aura recovers without a force-stop.
- [ ] Test captive portal sign-in and networks that block public DNS resolvers. Document expected limitations rather than bypassing user or network policy.
- [ ] Verify app-private config and per-session credentials are cleared after stop, failed startup, and service revocation.
- [ ] Check battery use and stability during a sustained session, including several reconnect cycles.

Current implementation boundaries: the local relay rejects SOCKS domain destinations and fragmented UDP; DNS domain classification is not provided by this transport. DoH, DoT/Android Private DNS, QUIC/DoQ, ECH, and direct-IP traffic must not be described as comprehensively filtered without independent detection/blocking and test evidence. A test should be considered a pass only when the observed network behavior and the UI/event log agree.

