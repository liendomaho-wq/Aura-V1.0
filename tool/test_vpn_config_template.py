#!/usr/bin/env python3
"""Static regression checks for Aura's rebuilt Android local VPN path."""
from pathlib import Path
import sys

SERVICE = Path("android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt")
PROXY = Path("android/app/src/main/kotlin/com/ciberdefensa/aura/AuraLocalSocks5Proxy.kt")
NATIVE = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/hev-socks5-tunnel.c")
JNI = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/hev-jni.c")

for path in (SERVICE, PROXY, NATIVE, JNI):
    if not path.is_file():
        sys.exit(f"FAIL: required VPN source is missing: {path}")

service = SERVICE.read_text(encoding="utf-8")
proxy = PROXY.read_text(encoding="utf-8")
native = NATIVE.read_text(encoding="utf-8")
jni = JNI.read_text(encoding="utf-8")

checks = {
    "Android VpnService establishes a TUN interface": "createBuilder(network).establish()" in service,
    "both IPv4 and IPv6 default routes are captured": (
        '.addRoute("0.0.0.0", 0)' in service and '.addRoute("::", 0)' in service
    ),
    "native packet engine uses the Kotlin loopback SOCKS endpoint": (
        "port: $PROXY_PORT" in service and "address: $PROXY_HOST" in service
    ),
    "UDP transport uses Hev UDP-over-TCP mode": "udp: 'tcp'" in service,
    "native engine no longer binds a competing SOCKS listener": (
        "local_socks5_init" not in native and "AURA_LOCAL_SOCKS5_PORT" not in native
    ),
    "outbound TCP is protected and bound to the physical network": (
        "protectTcp(outbound)" in proxy and "network.bindSocket(outbound)" in proxy
    ),
    "outbound UDP is protected and bound to the physical network": (
        "protectUdp(datagram)" in proxy and "network.bindSocket(datagram)" in proxy
    ),
    "UDP forwarding parses and emits Hev FWD_UDP frames": (
        "private fun relayUdp" in proxy and "readUnsignedShort()" in proxy
        and "output.writeShort(packet.length)" in proxy
    ),
    "domain lookups use Android's physical Network resolver": (
        "network.getAllByName(host)" in proxy
        and "physicalNetwork?.getAllByName(normalized)" in service
    ),
    "service verifies a real SOCKS5 CONNECT to TCP/443": (
        '"example.com"' in service and "input.readFully(response)" in service
    ),
    "JNI protects native sockets from VPN recursion": (
        "hev_jni_protect_socket (int socket_fd)" in jni
    ),
    "the old remote threat feed is not a startup dependency": (
        "THREAT_FEED_URL" not in service and "downloadThreatFeed" not in service
    ),
}

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    sys.exit("VPN regression checks failed: " + "; ".join(failed))

print("PASS: rebuilt local VPN static regression checks passed.")
