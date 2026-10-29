# Aura local VPN architecture

## Purpose

Aura is a **local Android traffic-filtering VPN**, not a commercial VPN and not a connection to a remote VPN provider. No remote VPN server is required.

## Data path

1. Android `VpnService` creates the TUN interface and captures IPv4/IPv6 traffic.
2. The Hev tun2socks engine translates captured packets into SOCKS5 TCP/UDP sessions.
3. A Kotlin SOCKS5 proxy listens only on `127.0.0.1:18763` and requires a fresh random RFC 1929 username/password pair for each tunnel start. The credentials are held in memory and written only to Aura's private app configuration file.
4. TCP CONNECT sessions use sockets bound to Android's selected physical `Network`.
5. UDP uses Hev's `FWD_UDP` framing over the SOCKS TCP control/data stream. The proxy unwraps each datagram and uses a protected, physical-network-bound `DatagramSocket`.
6. DNS lookups for outbound destinations use `Network.getAllByName`, not the VPN's default resolver.

All outbound sockets must be protected from the VPN TUN to prevent recursive routing. The native Hev SOCKS listener that previously competed for the same loopback port has been removed; the Kotlin proxy is the sole owner of that port. Authentication is mandatory even on loopback so other applications on the device cannot use Aura as an unauthenticated open proxy.

## Startup policy

- The remote threat feed is not a prerequisite for establishing the local tunnel.
- Optional SNI rules may fail without disabling basic connectivity.
- Aura checks that the native engine remains running and that the local SOCKS proxy can establish a real TCP connection to `example.com:443` before reporting startup success.
- This startup probe is not a substitute for full packet-path validation on a physical device.

## Validation required before release

- TCP HTTP and HTTPS from multiple Android apps.
- UDP DNS, QUIC/HTTP3 and representative UDP applications.
- IPv4 and IPv6 connectivity.
- DNS behavior and leak checks with private DNS enabled/disabled.
- Wi-Fi to mobile-data handover and loss/recovery of connectivity.
- VPN permission revocation, app process death, service restart and device reboot.
- Battery, memory, socket cleanup and long-running stability.

## Security and scope limits

This implementation does not decrypt HTTPS. TLS inspection is limited to metadata that is actually visible (for example, SNI when not hidden by ECH); encrypted payload contents remain encrypted. A local VPN can filter or observe network metadata, but it cannot guarantee detection of every malicious domain, IP, app or payload.

Do not describe the VPN as production-ready until the Android build passes and the physical-device matrix above has been executed.
