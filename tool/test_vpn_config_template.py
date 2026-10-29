#!/usr/bin/env python3
"""Regression checks for the YAML template emitted by AuraVpnService."""
from pathlib import Path
import re
import sys

SOURCE = Path("android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt")
NATIVE_TUNNEL = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/hev-socks5-tunnel.c")
NATIVE_SOCKS = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-misc.c")
text = SOURCE.read_text(encoding="utf-8")
native_tunnel = NATIVE_TUNNEL.read_text(encoding="utf-8")
native_socks = NATIVE_SOCKS.read_text(encoding="utf-8")
match = re.search(
    r"configFile\.writeText\(\s*\"\"\"(.*?)\"\"\"\.trimIndent\(\)",
    text,
    re.DOTALL,
)
if not match:
    sys.exit("FAIL: could not locate the Hev configuration template")

raw = match.group(1)
lines = raw.splitlines()
nonblank = [line for line in lines if line.strip()]
if not nonblank:
    sys.exit("FAIL: Hev configuration template is empty")

indent = min(len(line) - len(line.lstrip()) for line in nonblank)
normalized = [line[indent:] if line.strip() else "" for line in lines]
keys = {}
for line in normalized:
    if not line.strip():
        continue
    if line[0].isspace():
        continue
    key_match = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):(?:\s|$)", line)
    if not key_match:
        sys.exit(f"FAIL: unexpected top-level YAML line: {line!r}")
    key = key_match.group(1)
    if key in keys:
        sys.exit(f"FAIL: duplicate top-level YAML key: {key}")
    keys[key] = True

required = {"tunnel", "socks5", "misc", "mapdns"}
missing = required - keys.keys()
if missing:
    sys.exit("FAIL: missing top-level YAML sections: " + ", ".join(sorted(missing)))

for section in required:
    section_index = next(
        i for i, line in enumerate(normalized)
        if re.match(rf"^{re.escape(section)}:", line)
    )
    if section_index + 1 >= len(normalized) or not normalized[section_index + 1].startswith("  "):
        sys.exit(f"FAIL: section {section!r} has no indented child keys")

for required_line in ("port: $LOCAL_SOCKS5_PORT", "address: $LOCAL_SOCKS5_HOST",
                      "udp: 'tcp'", "log-level: error",
                      "address: 10.0.0.3", "cache-size: 8192"):
    if required_line not in raw:
        sys.exit(f"FAIL: expected configuration entry not found: {required_line}")

if "AURA_LOCAL_SOCKS5_PORT 18763" not in native_tunnel or "INADDR_LOOPBACK" not in native_tunnel:
    sys.exit("FAIL: local SOCKS5 listener must bind only to loopback port 18763")
if "hev_socks5_server_new" not in native_tunnel:
    sys.exit("FAIL: local SOCKS5 server is not wired into the Hev task system")
if "hev_jni_protect_socket (fd)" not in native_socks:
    sys.exit("FAIL: native outbound sockets are not protected from VPN recursion")
if "hev_jni_resolve_host (name" not in native_socks:
    sys.exit("FAIL: Android destination DNS must resolve on the underlying network")

if "try {\n                replaceBlockedIps(downloadThreatFeed())" not in text:
    sys.exit("FAIL: the optional threat feed must not be a hard startup dependency")
if "private fun verifyLocalSocks5Ready()" not in text or '"example.com"' not in text:
    sys.exit("FAIL: VPN health check must exercise a real SOCKS5 CONNECT destination")
if "readFully(input, responseHeader)" not in text:
    sys.exit("FAIL: VPN health check must read the complete SOCKS5 CONNECT response header")
if "Túnel VPN iniciado." not in text:
    sys.exit("FAIL: successful start status must only be emitted after the egress health check")

print("PASS: Hev YAML, protected loopback SOCKS5, physical DNS, optional feed and real TCP egress checks passed.")
