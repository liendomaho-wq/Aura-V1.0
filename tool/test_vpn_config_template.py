#!/usr/bin/env python3
"""Regression checks for the YAML template emitted by AuraVpnService."""
from pathlib import Path
import re
import sys

SOURCE = Path("android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt")
ANTI_TAMPERING_SOURCE = Path("android/app/src/main/kotlin/com/ciberdefensa/aura/MainActivity.kt")
NATIVE_TUNNEL = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/hev-socks5-tunnel.c")
NATIVE_SOCKS = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-misc.c")
text = SOURCE.read_text(encoding="utf-8")
anti_tampering = ANTI_TAMPERING_SOURCE.read_text(encoding="utf-8")
native_tunnel = NATIVE_TUNNEL.read_text(encoding="utf-8")
native_socks = NATIVE_SOCKS.read_text(encoding="utf-8")

# A remote threat-feed outage must not prevent Android from establishing the VPN.
start_match = re.search(
    r"private fun startTunnel\(\) \{(.*?)\n    @Synchronized",
    text,
    re.DOTALL,
)
if not start_match:
    sys.exit("FAIL: could not locate AuraVpnService.startTunnel")
if "downloadThreatFeed()" in start_match.group(1):
    sys.exit("FAIL: VPN startup must not synchronously depend on the remote IP feed")
if "feedRefresh.execute { refreshThreatFeed() }" not in text:
    sys.exit("FAIL: initial threat-feed refresh must run asynchronously")
refresh_match = re.search(
    r"private fun refreshThreatFeed\(\) \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not refresh_match or "TProxyIsRunning()" not in refresh_match.group(1):
    sys.exit("FAIL: refreshed IP rules must only be applied to a running tunnel")
if "cobertura reducida" not in refresh_match.group(1):
    sys.exit("FAIL: feed failures must be reported as reduced protection coverage")

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

print("PASS: Hev YAML, loopback SOCKS5 wiring, socket protection and physical DNS checks passed.")

# Secure-storage upgrade must preserve v9 secrets while migrating to authenticated encryption.
PUBSPEC = Path("pubspec.yaml").read_text(encoding="utf-8")
VAULT = Path("lib/secure_vault.dart").read_text(encoding="utf-8")
if not re.search(r"^\s*flutter_secure_storage:\s*\^10\.3\.4\s*$", PUBSPEC, re.MULTILINE):
    sys.exit("FAIL: secure storage must stay on the v10 migration bridge until legacy data is verified")
options_match = re.search(
    r"static const AndroidOptions _androidOptions = AndroidOptions\((.*?)\);",
    VAULT,
    re.DOTALL,
)
if not options_match:
    sys.exit("FAIL: could not locate SecureVault Android migration options")
options = options_match.group(1)
for required_option in (
    "resetOnError: false",
    "migrateOnAlgorithmChange: true",
    "migrateWithBackup: true",
):
    if required_option not in options:
        sys.exit(f"FAIL: SecureVault migration must include {required_option}")
if "encryptedSharedPreferences:" in options:
    sys.exit("FAIL: do not pin the deprecated EncryptedSharedPreferences backend")

print("PASS: SecureVault uses crash-safe v9-to-v10 AES-GCM migration without silent reset.")

# Integrity failures must never erase encryption keys or force-kill the process.
if "destroyLocalKeystoreKeys" in anti_tampering or "KeyStore.getInstance(\"AndroidKeyStore\")" in anti_tampering:
    sys.exit("FAIL: integrity checks must not destroy SecureVault/Android Keystore keys")
if "System.exit(0)" in anti_tampering:
    sys.exit("FAIL: integrity checks must not abruptly terminate the app process")

print("PASS: anti-tampering checks are non-destructive to stored secrets.")
