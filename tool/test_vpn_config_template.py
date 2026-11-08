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
NATIVE_CONFIG = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/hev-config.c")
NATIVE_MAIN = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/hev-main.c")
NATIVE_USER = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-user.c")
NATIVE_SERVER = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-server.c")
NATIVE_JNI = Path("android/app/src/main/cpp/hev-socks5-tunnel/src/hev-jni.c")
KOTLIN_SOCKS5_CREDENTIALS = Path(
    "android/app/src/main/kotlin/com/ciberdefensa/aura/AuraSocks5Credentials.kt"
)
KOTLIN_SOCKS5_AUTH = Path(
    "android/app/src/main/kotlin/com/ciberdefensa/aura/Socks5AuthProtocol.kt"
)
KOTLIN_SOCKS5_TEST = Path(
    "android/app/src/test/kotlin/com/ciberdefensa/aura/Socks5AuthProtocolTest.kt"
)
text = SOURCE.read_text(encoding="utf-8")
anti_tampering = ANTI_TAMPERING_SOURCE.read_text(encoding="utf-8")
crypto_source = CRYPTO_SOURCE.read_text(encoding="utf-8")
native_tunnel = NATIVE_TUNNEL.read_text(encoding="utf-8")
native_socks = NATIVE_SOCKS.read_text(encoding="utf-8")
native_config = NATIVE_CONFIG.read_text(encoding="utf-8")
native_main = NATIVE_MAIN.read_text(encoding="utf-8")
native_user = NATIVE_USER.read_text(encoding="utf-8")
native_server = NATIVE_SERVER.read_text(encoding="utf-8")
kotlin_credentials = KOTLIN_SOCKS5_CREDENTIALS.read_text(encoding="utf-8")
kotlin_socks5_auth = KOTLIN_SOCKS5_AUTH.read_text(encoding="utf-8")
kotlin_socks5_test = KOTLIN_SOCKS5_TEST.read_text(encoding="utf-8")
native_jni = NATIVE_JNI.read_text(encoding="utf-8")
manifest = Path("android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
CONSOLE_SOURCE = Path("lib/screens/aura_core_screen.dart").read_text(encoding="utf-8")

# A failed or unavailable native authentication result must never unlock the console.
auth_match = re.search(
    r"Future<void> _authenticateConsole\(\) async \{(.*?)\n  \}",
    CONSOLE_SOURCE,
    re.DOTALL,
)
if not auth_match:
    sys.exit("FAIL: could not locate AuraCoreScreen authentication lifecycle")
auth_body = auth_match.group(1)
if "controller.allowUnsecuredLocalSession()" in auth_body:
    sys.exit("FAIL: console authentication failure must not silently create an unsecured session")
if not re.search(
    r"if \(authenticated\) \{.*?setState\(\(\) => _isAuthenticated = true\);.*?return;.*?setState\(\(\) => _isAuthenticated = false\);",
    auth_body,
    re.DOTALL,
):
    sys.exit("FAIL: console must remain locked unless native authentication returns true")
print("PASS: console remains locked when native authentication is not confirmed.")

# Runtime-responsive text styles cannot be nested in a const Text constructor.
if re.search(
    r"const Text\(\s*'Hola, soy Aura\.'.*?fontSize:\s*compactLayout",
    CONSOLE_SOURCE,
    re.DOTALL,
):
    sys.exit("FAIL: responsive greeting font size cannot use a const Text constructor")
print("PASS: compact console greeting keeps runtime-dependent styling outside const.")

# DNS heuristics are not proof that a TLS connection was blocked. The DNS
# counters must also exclude SNI and transport events sharing the same queue.
network_stream = Path(
    "android/app/src/main/kotlin/com/ciberdefensa/aura/AuraNetworkStream.kt"
).read_text(encoding="utf-8")
notifications = Path(
    "android/app/src/main/kotlin/com/aura/cyberdefense/AuraNotificationService.kt"
).read_text(encoding="utf-8")
dga_match = re.search(
    r"fun triggerDgaAlert\(context: Context, domain: String\) \{(.*?)\n        private fun createNotificationChannels",
    notifications,
    re.DOTALL,
)
if not dga_match:
    sys.exit("FAIL: could not locate DNS heuristic notification")
dga_alert = dga_match.group(1)
if any(claim in dga_alert for claim in (
    "conexión cifrada bloqueada", "Tráfico TLS", "evasión cifrada", "$domain"
)):
    sys.exit("FAIL: DNS heuristic notification must not expose domains or claim TLS blocking")
if "falso positivo" not in dga_alert or "intentará aplicar" not in dga_alert:
    sys.exit("FAIL: DNS heuristic notification must explain uncertainty")
if "isDnsQuery = actionCode in 0..2" not in network_stream or (
    "if (pending.isDnsQuery) AuraVpnService.recordDnsAuditEvent(event)" not in network_stream
):
    sys.exit("FAIL: DNS notification counters must exclude SNI and transport events")
if "lastDnsDomain" in text or "coincidencias de bloqueo" not in text:
    sys.exit("FAIL: VPN notification must not expose domain names or claim delivery")
print("PASS: DNS notifications distinguish heuristic matches from verified TLS blocking.")

# A stale Kotlin flag alone must not certify a live native VPN worker.
shield_status = re.search(
    r"fun shieldStatus\(\): Map<String, Boolean> \{(.*?)\n        \}",
    text,
    re.DOTALL,
)
if not shield_status or any(
    required not in shield_status.group(1)
    for required in (
        "TProxyService.TProxyIsRunning()",
        "fileDescriptor?.valid()",
        '"status_verified" to (nativeRunning != null && !service.serviceShuttingDown)',
        "nativeRunning == true",
        "!service.serviceShuttingDown",
    )
):
    sys.exit("FAIL: VPN status must verify both the interface and native worker")
if any(
    required not in CONSOLE_SOURCE
    for required in (
        "invokeMapMethod<String, dynamic>('getShieldStatus')",
        "status['status_verified'] != true",
        "Timer.periodic(const Duration(seconds: 5)",
        "'DEFENSA: SIN FLUJO'",
        "'DEFENSA: ?'",
    )
):
    sys.exit("FAIL: VPN UI must refresh verified status and distinguish unknown forwarding")
print("PASS: VPN status requires a live native worker and is refreshed in the console.")

# Static integration guards complement the executable Kotlin gate tests; they
# cannot simulate Android broadcast ordering, permissions or service lifecycle.
receiver_match = re.search(
    r"private val vpnStateReceiver = object : BroadcastReceiver\(\) \{(.*?)\n    override fun configureFlutterEngine",
    anti_tampering,
    re.DOTALL,
)
if not receiver_match or any(
    required not in receiver_match.group(1)
    for required in (
        "getStringExtra(AuraVpnService.EXTRA_START_REQUEST_ID)",
        "shieldStartGate.matchesServiceResponse(requestId)",
        'val status = AuraVpnService.shieldStatus()',
        'status["status_verified"] == true',
        'status["forwarding_active"] == true',
        "completePendingShieldStart(confirmed)",
    )
):
    sys.exit("FAIL: VPN start replies must match their request and current forwarding state")
if any(
    required not in anti_tampering
    for required in (
        "UUID.randomUUID().toString()",
        "shieldStartGate.consumeConsentResult()",
        "shieldStartGate.matchesConsent()",
        "shieldStartHandler.postDelayed(consentTimeout, 30_000L)",
        '"VPN_CONSENT_TIMEOUT"',
        "shieldStartGate.beginServiceRequest(requestId)",
        ".putExtra(AuraVpnService.EXTRA_START_REQUEST_ID, requestId)",
        "shieldStartHandler.postDelayed(timeout, 30_000L)",
        '"VPN_START_TIMEOUT"',
    )
):
    sys.exit("FAIL: VPN start request correlation, consent or timeout is missing")
if any(
    required not in text
    for required in (
        "intent?.getStringExtra(EXTRA_START_REQUEST_ID)",
        "worker.execute { startTunnel(requestId) }",
        "requestId = requestId",
        "stateIntent.putExtra(EXTRA_START_REQUEST_ID, requestId)",
    )
):
    sys.exit("FAIL: VPN service must return the matching start request ID")
if any(part not in manifest for part in (
    'android:name="${applicationId}.permission.VPN_STATE"',
    'android:protectionLevel="signature"',
)) or any(part not in anti_tampering for part in (
    'val permission = "$packageName.permission.VPN_STATE"',
    'registerReceiver(vpnStateReceiver, filter, permission, null, Context.RECEIVER_NOT_EXPORTED)',
    'registerReceiver(vpnStateReceiver, filter, permission, null)',
)) or 'sendBroadcast(stateIntent, "$packageName.permission.VPN_STATE")' not in text:
    sys.exit("FAIL: VPN state broadcasts must require the app's signature permission")
print("PASS: VPN start broadcasts are correlated, permission-protected and timeout remains unconfirmed.")

# stopService only acknowledges the request; tool results must not immediately
# assert the native worker and TUN have fully stopped.
agent_tools = Path("lib/agent/aura_tools.dart").read_text(encoding="utf-8")
if any(
    guard not in agent_tools
    for guard in (
        "if (!activate && confirmed)",
        "'request_accepted': true",
        "'error': 'shutdown_unconfirmed'",
    )
):
    sys.exit("FAIL: accepted VPN stop requests must not be reported as confirmed shutdowns")
print("PASS: an accepted VPN stop request is not presented as confirmed teardown.")

# Aura communicates with remote services only over authenticated HTTPS.
application_tag = re.search(r"<application\b([^>]*)>", manifest, re.DOTALL)
if not application_tag or not re.search(
    r'android:usesCleartextTraffic="false"',
    application_tag.group(1),
):
    sys.exit("FAIL: Android must explicitly reject cleartext application traffic")

# A remote threat-feed outage must not prevent Android from establishing the VPN.
start_match = re.search(
    r"private fun startTunnel\(requestId: String\?\) \{(.*?)\n    @Synchronized",
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
    r"val config\s*=\s*\"\"\"(.*?)\"\"\"\.trimIndent\(\)",
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

for required_line in (
    "port: $LOCAL_SOCKS5_PORT",
    "address: $LOCAL_SOCKS5_HOST",
    "username: '${credentials.username}'",
    "password: '${credentials.password}'",
    "udp: 'tcp'",
    "log-level: error",
    "address: 10.0.0.3",
    "cache-size: 8192",
):
    if required_line not in raw:
        sys.exit(f"FAIL: expected configuration entry not found: {required_line}")

if "AURA_LOCAL_SOCKS5_PORT 18763" not in native_tunnel or "INADDR_LOOPBACK" not in native_tunnel:
    sys.exit("FAIL: local SOCKS5 listener must bind only to loopback port 18763")
if "hev_socks5_server_new" not in native_tunnel:
    sys.exit("FAIL: local SOCKS5 server is not wired into the Hev task system")
for required_auth_call in (
    "local_socks5_configure_server_auth",
    "hev_config_get_socks5_server",
    "hev_socks5_authenticator_new",
    "hev_socks5_user_new",
    "hev_socks5_authenticator_add",
    "hev_socks5_server_set_auth",
    "hev_socks5_set_timeout",
    "AURA_LOCAL_SOCKS5_AUTH_TIMEOUT_MS 5000",
    "AURA_LOCAL_SOCKS5_MAX_SESSIONS 64",
    "local_socks5_session_count++",
    "local_socks5_session_count--",
):
    if required_auth_call not in native_tunnel:
        sys.exit(f"FAIL: native local SOCKS5 security control is missing {required_auth_call}")
if "#ifdef __ANDROID__" not in native_tunnel or (
    "!config->user[0] || !config->pass[0])\n        return -1;" not in native_tunnel
):
    sys.exit("FAIL: Android's local SOCKS5 listener must fail closed without credentials")
if not re.search(
    r"if \(self->auth\)\s*method = HEV_SOCKS5_AUTH_METHOD_USER;\s*else\s*method = HEV_SOCKS5_AUTH_METHOD_NONE;",
    native_server,
):
    sys.exit("FAIL: HEV must negotiate only username/password when auth is attached")
if "hev_socks5_authenticator_get (self->auth" not in native_server:
    sys.exit("FAIL: HEV must validate RFC 1929 credentials against its authenticator")
if "Must be set both socks5 username and password!" not in native_config:
    sys.exit("FAIL: HEV config must reject a username or password supplied alone")
if any(
    required not in native_config
    for required in (
        "user_len > 255",
        "pass_len > 255",
        "hev_config_clear_socks5_credentials ();",
    )
):
    sys.exit("FAIL: native SOCKS5 credentials must be bounded and cleared")
if native_main.count("hev_config_clear_socks5_credentials ();\n    return res;") != 2:
    sys.exit("FAIL: native worker must clear SOCKS5 credentials after shutdown")
if "difference |= (unsigned char)self->pass[i] ^ (unsigned char)pass[i]" not in native_user:
    sys.exit("FAIL: SOCKS5 password comparison must not exit early on a partial match")
if "hev_socks5_user_clear_secret (self->pass, self->pass_len + 1)" not in native_user:
    sys.exit("FAIL: native SOCKS5 password buffers must be wiped before release")
if any(
    required not in kotlin_credentials
    for required in ("SecureRandom()", "random.nextBytes(secret)", "secret.fill(0)")
):
    sys.exit("FAIL: local SOCKS5 passwords must be generated ephemerally and clear temporary bytes")
if "Socks5AuthProtocol.authenticate(" not in text:
    sys.exit("FAIL: VPN startup must authenticate its local SOCKS5 readiness probe")
if any(
    required not in kotlin_socks5_auth
    for required in (
        "USER_PASSWORD_METHOD = 2",
        "output.write(username)",
        "output.write(password)",
        "USER_PASSWORD_METHOD.toByte()",
        "result[1].toInt() != 0",
        "password.fill(0.toByte())",
    )
):
    sys.exit("FAIL: local SOCKS5 readiness probe must complete RFC 1929 authentication")
if any(
    required not in kotlin_socks5_test
    for required in (
        "completesRfc1929AuthenticationWithTheSuppliedCredentials",
        "rejectsAServerThatSelectsNoAuthentication",
        "surfacesRfc1929CredentialRejection",
    )
):
    sys.exit("FAIL: SOCKS5 auth regression tests must cover success and rejection cases")
if "hev_jni_protect_socket (fd)" not in native_socks:
    sys.exit("FAIL: native outbound sockets are not protected from VPN recursion")
if "activeService?.protectAndBindSocket(socketFd)" not in text:
    sys.exit("FAIL: native upstream sockets must use Aura's selected physical network")
if "private fun protectAndBindSocket(socketFd: Int): Boolean" not in text:
    sys.exit("FAIL: VPN socket protection/binding routine is missing")
if "if (!protect(socketFd)) return false" not in text:
    sys.exit("FAIL: VPN must protect upstream sockets before binding them")
if "network.bindSocket(socketFd)" not in text:
    sys.exit("FAIL: VPN upstream sockets are not pinned to the selected physical network")
if "hev_jni_resolve_host (name" not in native_socks:
    sys.exit("FAIL: Android destination DNS must resolve on the underlying network")

print("PASS: ephemeral RFC 1929 SOCKS5 auth, native secret cleanup, socket protection and physical DNS checks passed.")

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

# USB debugging is a user-controlled development setting, not proof of
# runtime tampering. Keep it observable but do not make it disable the VPN.
integrity_policy = re.search(
    r"val integrityFailed = (.*?)\n\n        return mapOf",
    anti_tampering,
    re.DOTALL,
)
if (
    not integrity_policy
    or "adbEnabled" in integrity_policy.group(1)
    or "adbBlocked" in anti_tampering
    or '"adbEnabled" to adbEnabled' not in anti_tampering
    or "debuggerBlocked" not in integrity_policy.group(1)
):
    sys.exit("FAIL: ADB must remain diagnostic while signature/debugger tampering checks stay enforced")

print("PASS: USB debugging is reported as an advisory signal without disabling VPN protection.")

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

# Forwarding relies on sockets bound to the selected Network. If Android rejects
# callback registration, Aura cannot safely recover after a handover, so startup,
# panic-isolation resume and network recovery must refuse to report forwarding.
monitor_guard = re.search(
    r"private fun requireUnderlyingNetworkMonitor\(\) \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not monitor_guard:
    sys.exit("FAIL: VPN must fail closed when physical-network monitoring is unavailable")
monitor_guard_body = monitor_guard.group(1)
if "!networkCallbackRegistered" not in monitor_guard_body or "throw IOException(" not in monitor_guard_body:
    sys.exit("FAIL: failed physical-network monitoring must prevent forwarding")
start_tunnel_region = text.split("private fun startTunnel(", 1)[1].split(
    "private fun handleTunnelStartFailure", 1
)[0]
resume_tunnel_region = text.split("private fun resumeTunnelForwarding()", 1)[1].split(
    "private fun handleResumeFailure", 1
)[0]
recovery_region = text.split("private fun recoverTunnelAfterNetworkChange(", 1)[1].split(
    "private fun handleNetworkRecoveryFailure", 1
)[0]
for region_name, region in (
    ("startup", start_tunnel_region),
    ("resume", resume_tunnel_region),
    ("handover recovery", recovery_region),
):
    if "requireUnderlyingNetworkMonitor()" not in region:
        sys.exit(f"FAIL: VPN {region_name} must require a registered physical-network callback")

print("PASS: VPN fails closed when physical-network monitoring cannot be registered.")

# A failed setUnderlyingNetworks call must not commit the candidate Network;
# keeping the previous value makes the next callback retry the same handover.
refresh_network_region = text.split(
    "private fun refreshUnderlyingNetwork(excludedNetwork: Network? = null)", 1
)[1].split("private fun stopTunnelForwardingForNetworkFailure", 1)[0]
metadata_update_position = refresh_network_region.find("setUnderlyingNetworks(")
metadata_failure_position = refresh_network_region.find("if (!underlayUpdated)")
metadata_failure_return_position = refresh_network_region.find("return", metadata_failure_position)
network_commit_position = refresh_network_region.find("underlyingNetwork = selected")
if (
    metadata_update_position < 0
    or metadata_failure_position < metadata_update_position
    or metadata_failure_return_position < metadata_failure_position
    or network_commit_position <= metadata_failure_return_position
):
    sys.exit(
        "FAIL: a failed underlay update must stop before committing its candidate Network, "
        "so a later callback can retry recovery"
    )

print("PASS: failed physical-network metadata updates remain retryable on a later callback.")

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
    r"private fun recoverTunnelAfterNetworkChange\(requestId: String\? = null\) \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not recovery:
    sys.exit("FAIL: VPN network handover recovery routine is missing")
recovery_body = recovery.group(1)
for required_recovery_step in (
    "restartNativeWorker(",
    "verifyLocalSocks5Ready(socks5Credentials)",
    "AuraBlocklistService.knownEncryptedDnsEndpoints()",
    "lifecycleGate.runIfOpen",
    "tunnelStarted = true",
):
    if required_recovery_step not in recovery_body:
        sys.exit("FAIL: VPN handover recovery is missing " + required_recovery_step)
if "requestTunnelRecovery()" not in text:
    sys.exit("FAIL: selected physical-network changes do not schedule tunnel recovery")
failure_handler = re.search(
    r"private fun handleNetworkRecoveryFailure\(error: Throwable, requestId: String\? = null\) \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not failure_handler:
    sys.exit("FAIL: failed network recovery handler is missing")
failure_body = failure_handler.group(1)
if (
    "tunnelStarted = false" not in failure_body
    or not re.search(r"reportState\(\s*false", failure_body)
    or "no pudo recuperarse" not in failure_body.lower()
):
    sys.exit("FAIL: failed network recovery must report the tunnel as inactive")

print("PASS: physical-network handover restarts and verifies tun2socks before reporting protection active.")

# Failed handovers retain the TUN but must remain explicitly recoverable.
# A dedicated single-flight gate prevents duplicate worker restarts; the same
# selected Network and an explicit user start both retry without creating a
# second Android TUN interface.
recovery_request = re.search(
    r"private fun requestTunnelRecovery\(requestId: String\? = null\) \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not recovery_request:
    sys.exit("FAIL: retained TUN recovery request gate is missing")
recovery_request_body = recovery_request.group(1)
for required in (
    "recoveryRequested.compareAndSet(false, true)",
    "worker.execute",
    "recoverTunnelAfterNetworkChange(requestId)",
    "recoveryRequested.set(false)",
):
    if required not in recovery_request_body:
        sys.exit("FAIL: VPN recovery gate is missing " + required)
if "tunnelStarted" in recovery_request_body.split("if (serviceShuttingDown || panicIsolationActive)", 1)[0]:
    sys.exit("FAIL: active handovers must be allowed to restart native sockets on the new underlay")

start_command = re.search(
    r"override fun onStartCommand\([^)]*\): Int \{(.*?)\n    \}\n\n    override fun onDestroy",
    text,
    re.DOTALL,
)
if not start_command or (
    "vpnInterface != null && !startRequested.get()" not in start_command.group(1)
    or "requestTunnelRecovery(requestId)" not in start_command.group(1)
):
    sys.exit("FAIL: explicit VPN activation must recover forwarding on the retained TUN")

same_network_retry = re.search(
    r"private fun refreshUnderlyingNetwork\(excludedNetwork: Network\? = null\) \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not same_network_retry or (
    "selected == previous" not in same_network_retry.group(1)
    or "requestTunnelRecovery()" not in same_network_retry.group(1)
    or "!tunnelStarted" not in same_network_retry.group(1)
):
    sys.exit("FAIL: a later callback on the same physical network must retry failed forwarding")

if "startRequested.set(false)" not in failure_body:
    sys.exit("FAIL: failed network recovery must release the start gate for a later retry")
if "startRequested.set(false)" not in start_tunnel_region:
    sys.exit("FAIL: successful initial startup must release the in-progress gate")

print("PASS: failed VPN handovers can be retried on the retained TUN without duplicate starts.")

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
    r"private fun createNotification\(.*?\n    \}",
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

# Underlay loss and failed metadata synchronization must stop forwarding while
# preserving the full-route TUN; recovery must also restart a previously stopped
# native worker when a physical network becomes available again.
for required_fail_closed_guard in (
    "val underlayUpdated = try",
    "if (!underlayUpdated)",
    "stopTunnelForwardingForNetworkFailure(",
    "else if (vpnInterface != null && !panicIsolationActive)",
    "recoverTunnelAfterNetworkChange(requestId)",
    "TProxyService.TProxyStopService()",
    "tunnelStarted = false",
    "stopConfirmed = stopNativeWorker()",
):
    if required_fail_closed_guard not in text:
        sys.exit("FAIL: VPN underlay fail-closed lifecycle is missing " + required_fail_closed_guard)

fail_closed = re.search(
    r"private fun stopTunnelForwardingForNetworkFailure\(message: String\) \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not fail_closed:
    sys.exit("FAIL: VPN underlay failure must have a dedicated forwarding shutdown path")
if "stopNativeWorker()" not in fail_closed.group(1):
    sys.exit("FAIL: forwarding shutdown must reconcile the native worker")
if "stopConfirmed" not in fail_closed.group(1):
    sys.exit("FAIL: forwarding shutdown must not claim success when JNI stop is unconfirmed")
if "updateForegroundNotification()" not in fail_closed.group(1):
    sys.exit("FAIL: degraded network state must be reflected in the VPN notification")

native_stop = re.search(
    r"private fun stopNativeWorkerUnchecked\(\): Boolean \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not native_stop:
    sys.exit("FAIL: VPN must have a centralized native-worker shutdown guard")
for required_native_stop_guard in (
    "val stopAccepted = TProxyService.TProxyStopService()",
    "val workerStopped = !TProxyService.TProxyIsRunning()",
    "if (!stopAccepted || !workerStopped)",
):
    if required_native_stop_guard not in native_stop.group(1):
        sys.exit("FAIL: native shutdown verification is missing " + required_native_stop_guard)

on_destroy = re.search(
    r"override fun onDestroy\(\) \{(.*?)\n    override fun onRevoke",
    text,
    re.DOTALL,
)
if not on_destroy or any(part not in on_destroy.group(1) for part in (
    "lifecycleGate.beginClosing()", "lifecycleGate.close", "stopNativeWorkerUnchecked()",
)):
    sys.exit("FAIL: VPN destruction must close the lifecycle gate and reconcile native worker state")
if '"status_verified" to lastShutdownConfirmed' not in text:
    sys.exit("FAIL: an unconfirmed native teardown must not be reported as verified")
if 'lifecycleGate.runIfOpen { stopNativeWorkerUnchecked() }' not in text:
    sys.exit("FAIL: stale callbacks must not stop a newer service's native worker")
restart = re.search(
    r"private fun restartNativeWorker\(.*?(?=\n    private fun verifyIntegrityOrStop)",
    text,
    re.DOTALL,
)
if not restart or any(part not in restart.group(0) for part in (
    "lifecycleGate.runIfOpen", "stopNativeWorkerUnchecked()", "TProxyService.TProxyStartService(",
    "TProxyService.TProxySetBlockedIps(blockedIpSnapshot())",
)):
    sys.exit("FAIL: VPN restart must reconcile and start JNI inside the lifecycle gate")
if "if (tunnelStarted)" in on_destroy.group(1):
    sys.exit("FAIL: a stale Kotlin flag must not skip native worker cleanup")

print("PASS: VPN underlay loss stops native forwarding and recovery can restart from a stopped state.")
print("PASS: VPN teardown verifies JNI shutdown independently of the Kotlin forwarding flag.")

native_start = re.search(
    r"\nnative_start_service \(JNIEnv \*env.*?\)\n\{(.*?)\n\}",
    native_jni,
    re.DOTALL,
)
native_stop = re.search(
    r"\nnative_stop_service \(JNIEnv \*env.*?\)\n\{(.*?)\n\}",
    native_jni,
    re.DOTALL,
)
if not native_start or not native_stop:
    sys.exit("FAIL: could not inspect native VPN start/stop lifecycle")
for lifecycle_name, lifecycle_body in (
    ("start", native_start.group(1)),
    ("stop", native_stop.group(1)),
):
    join_guard = re.search(
        r"res = pthread_join \(work_thread, NULL\);\s*"
        r"if \(res != 0\)\s*goto exit;\s*"
        r"(?:/\*.*?\*/\s*)?thread_joinable = 0;",
        lifecycle_body,
        re.DOTALL,
    )
    if not join_guard:
        sys.exit(
            f"FAIL: native {lifecycle_name} must preserve joinable state after pthread_join failure"
        )
print("PASS: native VPN start/stop retains recoverable state when pthread_join fails.")

# Verify that the native TUN packet path invokes encrypted-DNS classification
# and discards matched packets, rather than testing only the standalone port helper.
NATIVE_TUNNEL_SOURCE = Path(
    "android/app/src/main/cpp/hev-socks5-tunnel/src/hev-socks5-tunnel.c"
).read_text(encoding="utf-8")
packet_filter = re.search(
    r"static int\npacket_is_encrypted_dns\s*\(.*?\n}\n",
    NATIVE_TUNNEL_SOURCE,
    re.DOTALL,
)
if not packet_filter:
    sys.exit("FAIL: native tunnel packet-level encrypted-DNS classifier is missing")
for packet_guard in (
    "aura_is_encrypted_dns_transport (protocol, destination_port,",
    "is_ipv4_doh_resolver (destination)",
    "is_ipv6_doh_resolver (destination)",
    "protocol != 6 && protocol != 17",
    "pbuf_copy_partial (packet, transport",
):
    if packet_guard not in packet_filter.group(0):
        sys.exit("FAIL: encrypted-DNS packet parser is missing " + packet_guard)
ingress = re.search(
    r"static void\nlwip_io_task_entry\s*\(.*?\n}\n",
    NATIVE_TUNNEL_SOURCE,
    re.DOTALL,
)
if not ingress:
    sys.exit("FAIL: could not locate native TUN ingress loop")
ingress_body = ingress.group(0)
if "packet_is_encrypted_dns (buf" not in ingress_body:
    sys.exit("FAIL: encrypted-DNS classifier is not called from TUN ingress")
if not re.search(
    r"if \(dns_classification != AURA_DNS_NO_MATCH\) \{.*?pbuf_free \(buf\);\s*continue;",
    ingress_body,
    re.DOTALL,
):
    sys.exit("FAIL: classified or uninspectable packets must be discarded in TUN ingress")
if not re.search(
    r"if \(dns_classification == AURA_DNS_MATCH\)\s*hev_jni_report_encrypted_dns_event",
    ingress_body,
):
    sys.exit("FAIL: uninspectable packets must not be falsely reported as DNS matches")
lwip_options = Path(
    "android/app/src/main/cpp/hev-socks5-tunnel/third-part/lwip/src/ports/include/lwipopts.h"
).read_text(encoding="utf-8")
for option in ("IP_REASSEMBLY", "LWIP_IPV6_REASS"):
    if not re.search(rf"^#define\s+{option}\s+0\s*$", lwip_options, re.MULTILINE):
        sys.exit(f"FAIL: {option} must be disabled until reassembled packets can be inspected")

print("PASS: TUN ingress drops recognized encrypted DNS and uninspectable extension chains.")

if "Iniciando motor de red local; verificando interfaz y forwarding." not in text:
    sys.exit("FAIL: foreground notification must not claim protection before the tunnel is verified")
start_tunnel = re.search(
    r"private fun startTunnel\(requestId: String\?\) \{(.*?)\n    @Synchronized",
    text,
    re.DOTALL,
)
if not start_tunnel:
    sys.exit("FAIL: could not locate VPN startup lifecycle")
if "verifyLocalSocks5Ready(socks5Credentials)" not in start_tunnel.group(1):
    sys.exit("FAIL: VPN cannot report active before SOCKS5 readiness is verified")
if "updateForegroundNotification()" not in start_tunnel.group(1):
    sys.exit("FAIL: foreground notification must refresh after startup verification and failure")

print("PASS: VPN notification distinguishes startup from verified forwarding.")


# Native tunnel state must be reconciled on every teardown/recovery path. A stale
# Kotlin flag must never skip stopping a live native worker or leave the UI active
# after a failed SOCKS5 readiness check.
for required_cleanup_guard in (
    "Reconcile native state and restart as one lifecycle operation.",
    "restartNativeWorker(configFile.absolutePath, tun)",
    "No se pudo reanudar el túnel; el forwarding permanece detenido.",
    "tunnelStarted = false",
):
    if required_cleanup_guard not in text:
        sys.exit(
            "FAIL: VPN native-worker cleanup/recovery is missing "
            + required_cleanup_guard
        )

resume_match = re.search(
    r"private fun resumeTunnelForwarding\(\): Boolean \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not resume_match:
    sys.exit("FAIL: could not locate VPN forwarding recovery")
resume_body = resume_match.group(1)
if "verifyLocalSocks5Ready(socks5Credentials)" not in resume_body:
    sys.exit("FAIL: VPN resume must verify the local SOCKS5 service")
if (
    "handleResumeFailure(exception)" not in resume_body
    or "handleResumeFailure(error)" not in resume_body
):
    sys.exit("FAIL: VPN resume failures must enter the native cleanup handler")

resume_failure = re.search(
    r"private fun handleResumeFailure\(error: Throwable\): Boolean \{(.*?)\n    \}",
    text,
    re.DOTALL,
)
if not resume_failure:
    sys.exit("FAIL: VPN resume failure cleanup handler is missing")
resume_failure_body = resume_failure.group(1)
if (
    "stopNativeWorker()" not in resume_failure_body
    or "tunnelStarted = false" not in resume_failure_body
    or "reportState(" not in resume_failure_body
    or "updateForegroundNotification()" not in resume_failure_body
):
    sys.exit("FAIL: failed VPN resume must stop native forwarding and report inactive state")
if (
    "No se pudo reanudar el túnel; el forwarding permanece detenido."
    not in resume_failure_body
    or "No se pudo reanudar el túnel; el cierre nativo no está confirmado."
    not in resume_failure_body
):
    sys.exit("FAIL: failed VPN resume must distinguish confirmed and unconfirmed native shutdown")

print("PASS: VPN teardown and resume reconcile native worker state after failures.")
