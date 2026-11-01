#!/usr/bin/env python3
"""Regression checks for the YAML template emitted by AuraVpnService."""
from pathlib import Path
import re
import sys

SOURCE = Path("android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt")
ANTI_TAMPERING_SOURCE = Path("android/app/src/main/kotlin/com/ciberdefensa/aura/MainActivity.kt")
CRYPTO_SOURCE = Path("lib/crypto/aura_crypto_layer.dart")
NATIVE_TUNNEL = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/hev-socks5-tunnel.c")
NATIVE_SOCKS = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-misc.c")
text = SOURCE.read_text(encoding="utf-8")
anti_tampering = ANTI_TAMPERING_SOURCE.read_text(encoding="utf-8")
crypto_source = CRYPTO_SOURCE.read_text(encoding="utf-8")
native_tunnel = NATIVE_TUNNEL.read_text(encoding="utf-8")
native_socks = NATIVE_SOCKS.read_text(encoding="utf-8")
manifest = Path("android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")

# Aura communicates with remote services only over authenticated HTTPS.
application_tag = re.search(r"<application\b([^>]*)>", manifest, re.DOTALL)
if not application_tag or not re.search(
    r'android:usesCleartextTraffic="false"',
    application_tag.group(1),
):
    sys.exit("FAIL: Android must explicitly reject cleartext application traffic")

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
if "connection.instanceFollowRedirects = false" not in text:
    sys.exit("FAIL: threat-feed downloads must not follow redirects")
if "MAX_THREAT_FEED_BYTES = 4 * 1024 * 1024" not in text:
    sys.exit("FAIL: threat-feed downloads must have a strict byte limit")
if "declaredLength > MAX_THREAT_FEED_BYTES" not in text:
    sys.exit("FAIL: declared threat-feed size must be checked before reading")
if "output.size() + count > MAX_THREAT_FEED_BYTES" not in text:
    sys.exit("FAIL: streamed threat-feed bytes must be bounded")
if 'connection.url.protocol.equals("https", ignoreCase = true)' not in text:
    sys.exit("FAIL: threat-feed transport must remain HTTPS")

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

# New model envelopes must authenticate the IV and ciphertext before native decryption.
if "_authenticatedEnvelopePrefix = 'aura2:'" not in crypto_source:
    sys.exit("FAIL: new encrypted model payloads must use the versioned authenticated envelope")
if "crypto.Hmac(crypto.sha256, macKey)" not in crypto_source:
    sys.exit("FAIL: model envelopes must use HMAC-SHA-256")
secure_decrypt = re.search(
    r"static Future<String> decryptModelSecure\(.*?\n  }\n\n  static Uint8List _deriveKey",
    crypto_source,
    re.DOTALL,
)
if not secure_decrypt:
    sys.exit("FAIL: could not locate the native model decryption method")
if secure_decrypt.group(0).find("_verifyEnvelopeTag(") > secure_decrypt.group(0).find("_nativeCryptoChannel.invokeMethod"):
    sys.exit("FAIL: model authentication must complete before native decryption")

print("PASS: model encryption authenticates payloads before native decryption.")

# The VPN must track physical connectivity without selecting another VPN as its underlay.
for required_network_guard in (
    "NetworkRequest.Builder()",
    "NetworkCapabilities.NET_CAPABILITY_NOT_VPN",
    "registerNetworkCallback(request, underlyingNetworkCallback)",
    "unregisterNetworkCallback(underlyingNetworkCallback)",
    "override fun onAvailable(network: Network)",
    "override fun onLost(network: Network)",
    "excludedNetwork = network",
    "if (network == excludedNetwork) return@mapNotNull null",
    "override fun onCapabilitiesChanged(",
    "setUnderlyingNetworks(selected?.let { arrayOf(it) } ?: emptyArray())",
    "serviceShuttingDown = true",
    "if (serviceShuttingDown) return",
):
    if required_network_guard not in text:
        sys.exit(
            "FAIL: VPN physical-network lifecycle is missing "
            + required_network_guard
        )

network_selection = re.search(
    r"private fun findUnderlyingNetwork\([^)]*\): Network\? \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not network_selection:
    sys.exit("FAIL: could not locate physical network selection")
if "NET_CAPABILITY_NOT_VPN" not in network_selection.group(1):
    sys.exit("FAIL: VPN must never select another VPN as its physical underlay")
if "TRANSPORT_VPN" not in network_selection.group(1):
    sys.exit("FAIL: VPN transport must be explicitly excluded from underlay selection")
if "excludedNetwork: Network? = null" not in network_selection.group(0):
    sys.exit("FAIL: physical network selection must support excluding a lost network")
if "network == excludedNetwork" not in network_selection.group(1):
    sys.exit("FAIL: a lost physical network must not be selected again during callback races")

print("PASS: VPN tracks physical network availability and unregisters callbacks safely.")

# The legacy shield query must expose real active feed rules, not a permanent
# empty placeholder or a claim that these rules are observed traffic events.
MAIN_ACTIVITY = Path(
    "android/app/src/main/kotlin/com/ciberdefensa/aura/MainActivity.kt"
).read_text(encoding="utf-8")
if 'fun activeBlockedIpRules(): List<String>' not in text:
    sys.exit("FAIL: VPN must expose its currently loaded IP threat-feed rules")
if "activeService?.blockedIpSnapshot()?.sorted()?.take(512)" not in text:
    sys.exit("FAIL: active IP rule diagnostics must be bounded and sourced from the running service")
if '"getLatestBlockedIps" -> {\n                    val blockedIps = listOf<String>()' in MAIN_ACTIVITY:
    sys.exit("FAIL: getLatestBlockedIps must not return a hardcoded empty placeholder")
if "AuraVpnService.activeBlockedIpRules()" not in MAIN_ACTIVITY:
    sys.exit("FAIL: shield IP-rule query is not connected to the active VPN threat feed")
if "not a history of packets blocked" not in text:
    sys.exit("FAIL: active feed rules must be distinguished from observed block events")

print("PASS: shield diagnostics return bounded active IP threat-feed rules without fabricating traffic events.")

# A physical-network handover must restart the native worker: merely updating
# Android's underlay metadata does not migrate sockets opened on the old network.
recovery = re.search(
    r"private fun recoverTunnelAfterNetworkChange\(\) \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not recovery:
    sys.exit("FAIL: VPN network handover recovery routine is missing")
recovery_body = recovery.group(1)
for required_recovery_step in (
    "TProxyService.TProxyStopService()",
    "TProxyService.TProxyStartService(",
    "verifyLocalSocks5Ready()",
    "TProxyService.TProxySetBlockedIps(blockedIpSnapshot())",
    "AuraBlocklistService.knownEncryptedDnsEndpoints()",
    "tunnelStarted = true",
):
    if required_recovery_step not in recovery_body:
        sys.exit("FAIL: VPN handover recovery is missing " + required_recovery_step)
if "recoverTunnelAfterNetworkChange()" not in text:
    sys.exit("FAIL: selected physical-network changes do not invoke tunnel recovery")
if "tunnelStarted = false" not in recovery_body or "no pudo recuperarse" not in recovery_body:
    sys.exit("FAIL: failed network recovery must report the tunnel as inactive")

print("PASS: physical-network handover restarts and verifies tun2socks before reporting protection active.")

# App-risk findings must be based on confirmed access, not permission declarations.
APP_SCANNER = Path(
    "android/app/src/main/kotlin/com/ciberdefensa/aura/AuraAppGenomeScanner.kt"
).read_text(encoding="utf-8")
if "PackageInfo.REQUESTED_PERMISSION_GRANTED" not in APP_SCANNER:
    sys.exit("FAIL: app scanner must check Android permission grant flags")
if "val dangerous = grantedHighRisk + activeServices" not in APP_SCANNER:
    sys.exit("FAIL: requested-but-ungranted permissions must not count as active risk")
if "component in enabled" not in APP_SCANNER:
    sys.exit("FAIL: privileged services must be enabled by the user to count as active")
if "servicePermissions[packageInfo.packageName]" in APP_SCANNER:
    sys.exit("FAIL: inactive service declarations must not be counted as active risk")

print("PASS: app risk scoring requires confirmed permission grants or enabled privileged services.")

# Android signing analysis must accept legitimate multiple current signers and
# use SigningInfo on Android 9+, while retaining the API 24-27 compatibility path.
if "PackageManager.GET_SIGNING_CERTIFICATES" not in APP_SCANNER:
    sys.exit("FAIL: Android 9+ app signing must use GET_SIGNING_CERTIFICATES")
if "packageInfo.signingInfo?.apkContentsSigners?.toList().orEmpty()" not in APP_SCANNER:
    sys.exit("FAIL: app signing must hash current APK signers, not signing history")
if "signingCertificateHistory" in APP_SCANNER:
    sys.exit("FAIL: app signing must not hash historical certificates as current APK signers")
if "Build.VERSION.SDK_INT >= Build.VERSION_CODES.P" not in APP_SCANNER:
    sys.exit("FAIL: app signing query must preserve the Android 9+ compatibility boundary")
if '"MULTIPLE_SIGNERS"' in APP_SCANNER:
    sys.exit("FAIL: multiple valid APK signers must not be reported as a signature issue")
if '"SIGNATURE_METADATA_UNAVAILABLE"' not in APP_SCANNER:
    sys.exit("FAIL: unavailable signing metadata must be reported without alleging malware")

print("PASS: app signing checks support modern Android signer rotation and avoid multi-signer false positives.")

# DNS resolution is not evidence that the local gateway or Wi-Fi is safe.
NETWORK_AUDITOR = Path("lib/network_auditor.dart").read_text(encoding="utf-8")
if "Future<bool> verifyNetworkConnectivity()" not in NETWORK_AUDITOR:
    sys.exit("FAIL: network auditor must expose a connectivity-only check")
if "does not inspect the local gateway" not in NETWORK_AUDITOR:
    sys.exit("FAIL: connectivity checks must disclose that gateway safety is not verified")
if "@Deprecated(" not in NETWORK_AUDITOR or "verifyNetworkConnectivity()" not in NETWORK_AUDITOR:
    sys.exit("FAIL: legacy gateway-safety API must warn callers and redirect to connectivity semantics")

print("PASS: DNS reachability is not mislabeled as gateway or Wi-Fi security.")

# Installation provenance is contextual evidence, never a malware verdict.
if '"app_provenance"' not in APP_SCANNER or '"app_provenance_count"' not in APP_SCANNER:
    sys.exit("FAIL: app inventory must expose installation provenance")
if "packageManager.getInstallSourceInfo(packageName)" not in APP_SCANNER:
    sys.exit("FAIL: Android 11+ provenance must use InstallSourceInfo")
if "packageManager.getInstallerPackageName(packageName)" not in APP_SCANNER:
    sys.exit("FAIL: pre-Android 11 devices must retain the legacy installer source")
if "LEGACY_INSTALLER_ONLY" not in APP_SCANNER or "ACCESS_DENIED" not in APP_SCANNER:
    sys.exit("FAIL: provenance must distinguish legacy and inaccessible metadata")
if "no demuestra que la aplicación sea maliciosa" not in APP_SCANNER:
    sys.exit("FAIL: installer identity must not be presented as proof of malware")

print("PASS: app inventory reports installation provenance with explicit confidence limits.")

# Special Android access must be checked per package through AppOps. Unknown,
# conditional, or undeclared states must not be presented as active grants.
for special_access_check in (
    "AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW",
    "AppOpsManager.OPSTR_GET_USAGE_STATS",
    "AppOpsManager.OPSTR_WRITE_SETTINGS",
    '"android:request_install_packages",',
    '"android:manage_external_storage",',
    "appOps.checkOpNoThrow(operation, appInfo.uid, appInfo.packageName)",
    'AppOpsManager.MODE_ALLOWED -> "ACTIVE"',
    'AppOpsManager.MODE_FOREGROUND -> "CONDITIONAL"',
    'else -> "UNKNOWN"',
    '"special_access_count" to specialAccess.size',
    '"active_special_access_count" to activeSpecialAccessCount',
):
    if special_access_check not in APP_SCANNER:
        sys.exit("FAIL: special-access audit is missing " + special_access_check)
if 'permission !in requested' not in APP_SCANNER:
    sys.exit("FAIL: special-access audit must distinguish undeclared permissions")
if 'MODE_DEFAULT' in APP_SCANNER and 'MODE_DEFAULT -> "ACTIVE"' in APP_SCANNER:
    sys.exit("FAIL: AppOps DEFAULT mode must never be treated as active access")

print("PASS: special Android access is reported per package with conservative AppOps state handling.")

# Agent actions that change networking or isolate traffic require explicit consent.
AGENT_TOOLS = Path("lib/agent/aura_tools.dart").read_text(encoding="utf-8")
for consent_guard in (
    "step.arguments['confirmed_by_user'] != true",
    "'user_confirmation_required'",
    "case 'block_domain':",
    "case 'panic_isolation':",
    "arguments['confirmed_by_user'] != true",
):
    if consent_guard not in AGENT_TOOLS:
        sys.exit("FAIL: agent security action lacks explicit confirmation guard: " + consent_guard)
if "special_access_count" not in AGENT_TOOLS or "app_provenance_count" not in AGENT_TOOLS:
    sys.exit("FAIL: app scan tool must preserve special access and install provenance evidence")
if "MODE_ALLOWED" not in APP_SCANNER or "MODE_FOREGROUND" not in APP_SCANNER:
    sys.exit("FAIL: AppOps audit must distinguish active from conditional access")
if "mapNotNull { (name, operation, permission)" not in APP_SCANNER:
    sys.exit("FAIL: special access inventory must omit undeclared AppOps rows to bound output")

print("PASS: app scan preserves evidence and agent network/isolation actions require user confirmation.")

# Model heuristics must never mutate device network policy without user approval.
AI_BRAIN = Path("lib/ai_brain.dart").read_text(encoding="utf-8")
ml_branch = re.search(
    r"if \(isThreat\) \{(.*?)\n        \} else \{",
    AI_BRAIN,
    re.DOTALL,
)
if not ml_branch:
    sys.exit("FAIL: could not locate model threat decision branch")
if "addDnsBlockRule(" in ml_branch.group(1):
    sys.exit("FAIL: ML threat classification must not automatically install a DNS block")
for required_ml_guard in (
    "requires_user_confirmation",
    "user_confirmation_required",
    "local_dns_engine_only",
    "No se bloqueó automáticamente",
):
    if required_ml_guard not in ml_branch.group(1):
        sys.exit("FAIL: ML finding must disclose consent-gated mitigation: " + required_ml_guard)

print("PASS: ML findings remain recommendations until the user confirms a local DNS block.")

# File-path fragments are not reliable proof of a virtualized device.
if '"isVirtualEnvironment" to isCloned' in anti_tampering:
    sys.exit("FAIL: app path heuristics must not produce a confirmed virtual-device verdict")
if '"possibleVirtualPathIndicator" to possibleVirtualPathIndicator' not in anti_tampering:
    sys.exit("FAIL: weak virtual-path indicators must remain explicitly contextual")
if '"isSecure" to (!isDebugActive && !isCloned)' in anti_tampering:
    sys.exit("FAIL: weak path indicators must not determine the device integrity verdict")

print("PASS: virtual-device path heuristics are contextual and cannot create false integrity verdicts.")


# VPN notification must display the current protection state, not a fixed success message.
notification_match = re.search(
    r"private fun createNotification\\(.*?\\n    \\}",
    text,
    re.DOTALL,
)
if not notification_match:
    sys.exit("FAIL: could not locate VPN notification builder")
notification_builder = notification_match.group(0)
if ".setContentText(contentText)" not in notification_builder:
    sys.exit("FAIL: VPN notification must render the live state summary")
if ".setContentText(NOTIFICATION_TEXT)" in notification_builder:
    sys.exit("FAIL: VPN notification must not claim a fixed active state")
