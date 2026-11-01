package com.ciberdefensa.aura

import android.app.AppOpsManager

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.PackageInfo
import android.content.pm.Signature
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.security.NoSuchAlgorithmException
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

data class SuspiciousApp(
    val packageName: String,
    val appName: String,
    val targetSdkVersion: Int,
    val highRiskPermissions: List<String>,
    val mediumRiskPermissions: List<String>,
)

data class AppSignatureIssue(
    val packageName: String,
    val appName: String,
    val problems: List<String>,
    val signatureCount: Int,
    val signatureSha256: List<String>,
)

data class ObfuscatedApp(
    val packageName: String,
    val appName: String,
    val dexEntropy: Double,
    val obfuscatedIdentifierRatio: Double,
    val analyzedDexFiles: Int,
    val reasons: List<String>,
)

object AuraAppGenomeScanner {
    private const val DEX_ENTROPY_THRESHOLD = 7.5
    private const val OBFUSCATED_IDENTIFIER_RATIO_THRESHOLD = 0.5
    private const val MIN_IDENTIFIERS_FOR_RATIO = 20
    private const val MAX_DEX_TABLE_ITEMS_FOR_PARSING = 250_000
    private const val MAX_DEX_PARSE_SIZE_BYTES = 16 * 1024 * 1024
    private const val MAX_DEX_FILES_PER_APP = 8
    private const val ACCESSIBILITY_PERMISSION =
        "android.permission.BIND_ACCESSIBILITY_SERVICE"
    private const val NOTIFICATION_PERMISSION =
        "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"

    private val highRiskPermissions = setOf(
        "android.permission.SYSTEM_ALERT_WINDOW",
        "android.permission.BIND_ACCESSIBILITY_SERVICE",
        "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE",
        "android.permission.READ_SMS",
        "android.permission.RECEIVE_SMS",
        "android.permission.SEND_SMS",
        "android.permission.RECEIVE_MMS",
        "android.permission.READ_CONTACTS",
        "android.permission.WRITE_CONTACTS",
        "android.permission.READ_CALL_LOG",
        "android.permission.WRITE_CALL_LOG",
        "android.permission.CALL_PHONE",
        "android.permission.READ_PHONE_STATE",
        "android.permission.RECORD_AUDIO",
        "android.permission.CAMERA",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.ACCESS_BACKGROUND_LOCATION",
        "android.permission.REQUEST_INSTALL_PACKAGES",
        "android.permission.PACKAGE_USAGE_STATS",
        "android.permission.WRITE_SETTINGS",
        "android.permission.MANAGE_EXTERNAL_STORAGE",
        "android.permission.READ_EXTERNAL_STORAGE",
        "android.permission.WRITE_EXTERNAL_STORAGE",
    )
    private val mediumRiskPermissions = setOf(
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.ACCESS_WIFI_STATE",
        "android.permission.CHANGE_NETWORK_STATE",
        "android.permission.CHANGE_WIFI_STATE",
        "android.permission.BLUETOOTH",
        "android.permission.BLUETOOTH_ADMIN",
        "android.permission.BLUETOOTH_CONNECT",
        "android.permission.BLUETOOTH_SCAN",
        "android.permission.NFC",
        "android.permission.VIBRATE",
        "android.permission.WAKE_LOCK",
        "android.permission.RECEIVE_BOOT_COMPLETED",
        "android.permission.FOREGROUND_SERVICE",
    )

    fun scan(context: Context): Map<String, Any> {
        val packageManager = context.packageManager
        val enabledAccessibility = if (
            Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0,
            ) == 1
        ) {
            enabledComponents(
                Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                ),
            )
        } else {
            emptySet()
        }
        val enabledNotificationListeners = enabledComponents(
            Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ),
        )

        val installedApps = packageManager
            .getInstalledApplications(PackageManager.GET_META_DATA)
            .associateBy { it.packageName }
        val activeServices = mutableMapOf<String, MutableList<Map<String, String>>>()

        collectActiveServices(
            packageManager = packageManager,
            action = AccessibilityService.SERVICE_INTERFACE,
            requiredPermission = ACCESSIBILITY_PERMISSION,
            enabledComponents = enabledAccessibility,
            serviceType = "ACCESSIBILITY",
            installedApplications = installedApps,
            output = activeServices,
        )
        collectActiveServices(
            packageManager = packageManager,
            action = NotificationListenerService.SERVICE_INTERFACE,
            requiredPermission = NOTIFICATION_PERMISSION,
            enabledComponents = enabledNotificationListeners,
            serviceType = "NOTIFICATION_LISTENER",
            installedApplications = installedApps,
            output = activeServices,
        )

        val applications = activeServices.entries
            .sortedBy { it.key }
            .map { (packageName, services) ->
                val appInfo = installedApps.getValue(packageName)
                mapOf(
                    "package_name" to packageName,
                    "app_name" to packageManager.getApplicationLabel(appInfo).toString(),
                    "active_services" to services,
                )
            }
        val suspiciousApps = analyzeInstalledApps(context)
        val signatureIssues = verifyAppSignatures(context)
        val obfuscatedApps = detectSuspiciousObfuscation(context)
        val thirdPartyApps = installedApps.values
            .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 }
            .sortedBy { it.packageName }
        val appProvenance = thirdPartyApps.map { appInfo ->
            val installSource = readInstallSource(packageManager, appInfo.packageName)
            mapOf(
                "package_name" to appInfo.packageName,
                "app_name" to packageManager.getApplicationLabel(appInfo).toString(),
                "installer_package" to (installSource["installer_package"] ?: ""),
                "initiating_package" to (installSource["initiating_package"] ?: ""),
                "originating_package" to (installSource["originating_package"] ?: ""),
                "install_source_status" to (installSource["status"] ?: "UNKNOWN"),
                "assessment_note" to "La procedencia es una señal contextual; no demuestra que la aplicación sea maliciosa.",
            )
        }
        // AppOps is queried per installed package. DEFAULT and FOREGROUND are
        // deliberately not treated as confirmed active access.
        val specialAccess = thirdPartyApps.flatMap { appInfo ->
            readSpecialAccess(context, appInfo).map { access ->
                mapOf(
                    "package_name" to appInfo.packageName,
                    "app_name" to packageManager.getApplicationLabel(appInfo).toString(),
                    "access" to access.first,
                    "state" to access.second,
                    "mode" to access.third,
                )
            }
        }
        val activeSpecialAccessCount = specialAccess.count { it["state"] == "ACTIVE" }

        return mapOf(
            "timestamp" to System.currentTimeMillis(),
            "count" to applications.size,
            "applications" to applications,
            "app_provenance_count" to appProvenance.size,
            "app_provenance" to appProvenance,
            "special_access_count" to specialAccess.size,
            "active_special_access_count" to activeSpecialAccessCount,
            "special_access" to specialAccess,
            "suspicious_app_count" to suspiciousApps.size,
            "suspicious_apps" to suspiciousApps.map { it.toMap() },
            "signature_issue_count" to signatureIssues.size,
            "signature_issues" to signatureIssues.map { it.toMap() },
            "obfuscated_app_count" to obfuscatedApps.size,
            "obfuscated_apps" to obfuscatedApps.map { it.toMap() },
        )
    }

    /**
     * Reports per-package special AppOps access. A DEFAULT mode is UNKNOWN,
     * not a grant; FOREGROUND is CONDITIONAL and is never counted as ACTIVE.
     */
    @Suppress("DEPRECATION")
    private fun readSpecialAccess(
        context: Context,
        appInfo: ApplicationInfo,
    ): List<Triple<String, String, String>> {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return emptyList()
        val requested = try {
            context.packageManager.getPackageInfo(
                appInfo.packageName,
                PackageManager.GET_PERMISSIONS,
            ).requestedPermissions.orEmpty().toSet()
        } catch (_: Exception) {
            emptySet()
        }
        val operations = buildList {
            add(Triple("OVERLAY", AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                "android.permission.SYSTEM_ALERT_WINDOW"))
            add(Triple("USAGE_STATS", AppOpsManager.OPSTR_GET_USAGE_STATS,
                "android.permission.PACKAGE_USAGE_STATS"))
            add(Triple("MODIFY_SETTINGS", AppOpsManager.OPSTR_WRITE_SETTINGS,
                "android.permission.WRITE_SETTINGS"))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                add(Triple("INSTALL_UNKNOWN_APPS", AppOpsManager.OPSTR_REQUEST_INSTALL_PACKAGES,
                    "android.permission.REQUEST_INSTALL_PACKAGES"))
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                add(Triple("ALL_FILES_ACCESS", AppOpsManager.OPSTR_MANAGE_EXTERNAL_STORAGE,
                    "android.permission.MANAGE_EXTERNAL_STORAGE"))
            }
        }
        return operations.map { (name, operation, permission) ->
            if (permission !in requested) {
                return@map Triple(name, "NOT_DECLARED", "NOT_APPLICABLE")
            }
            try {
                val mode = appOps.checkOpNoThrow(operation, appInfo.uid, appInfo.packageName)
                val state = when (mode) {
                    AppOpsManager.MODE_ALLOWED -> "ACTIVE"
                    AppOpsManager.MODE_FOREGROUND -> "CONDITIONAL"
                    AppOpsManager.MODE_IGNORED, AppOpsManager.MODE_ERRORED -> "INACTIVE"
                    else -> "UNKNOWN"
                }
                Triple(name, state, mode.toString())
            } catch (_: SecurityException) {
                Triple(name, "UNKNOWN", "ACCESS_DENIED")
            } catch (_: IllegalArgumentException) {
                Triple(name, "UNSUPPORTED", "OP_NOT_AVAILABLE")
            } catch (_: RuntimeException) {
                Triple(name, "UNKNOWN", "CHECK_FAILED")
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun readInstallSource(
        packageManager: PackageManager,
        packageName: String,
    ): Map<String, String> {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val source = packageManager.getInstallSourceInfo(packageName)
                mapOf(
                    "installer_package" to (source.installingPackageName ?: ""),
                    "initiating_package" to (source.initiatingPackageName ?: ""),
                    "originating_package" to (source.originatingPackageName ?: ""),
                    "status" to "AVAILABLE",
                )
            } else {
                mapOf(
                    "installer_package" to
                        (packageManager.getInstallerPackageName(packageName) ?: ""),
                    "initiating_package" to "",
                    "originating_package" to "",
                    "status" to "LEGACY_INSTALLER_ONLY",
                )
            }
        } catch (_: PackageManager.NameNotFoundException) {
            mapOf(
                "installer_package" to "",
                "initiating_package" to "",
                "originating_package" to "",
                "status" to "PACKAGE_NO_LONGER_AVAILABLE",
            )
        } catch (_: SecurityException) {
            mapOf(
                "installer_package" to "",
                "initiating_package" to "",
                "originating_package" to "",
                "status" to "ACCESS_DENIED",
            )
        } catch (_: UnsupportedOperationException) {
            mapOf(
                "installer_package" to "",
                "initiating_package" to "",
                "originating_package" to "",
                "status" to "UNSUPPORTED",
            )
        }
    }

    @Suppress("DEPRECATION")
    fun analyzeInstalledApps(context: Context): List<SuspiciousApp> {
        val packageManager = context.packageManager
        val enabledAccessibility = if (
            Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0,
            ) == 1
        ) {
            enabledComponents(
                Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                ),
            )
        } else {
            emptySet()
        }
        val enabledNotificationListeners = enabledComponents(
            Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ),
        )
        val activeServicePermissions = mutableMapOf<String, MutableSet<String>>()
        val serviceTypes = listOf(
            AccessibilityService.SERVICE_INTERFACE to enabledAccessibility,
            NotificationListenerService.SERVICE_INTERFACE to enabledNotificationListeners,
        )
        for ((action, enabled) in serviceTypes) {
            val services = packageManager.queryIntentServices(
                Intent(action),
                PackageManager.MATCH_DISABLED_COMPONENTS,
            )
            for (resolveInfo in services) {
                val serviceInfo = resolveInfo.serviceInfo ?: continue
                val appInfo = packageManager.getApplicationInfo(serviceInfo.packageName, 0)
                val component = ComponentName(serviceInfo.packageName, serviceInfo.name)
                val requiredPermission = if (
                    action == AccessibilityService.SERVICE_INTERFACE
                ) ACCESSIBILITY_PERMISSION else NOTIFICATION_PERMISSION
                if (
                    serviceInfo.permission == requiredPermission &&
                    serviceInfo.enabled &&
                    appInfo.enabled &&
                    component in enabled
                ) {
                    activeServicePermissions
                        .getOrPut(serviceInfo.packageName) { mutableSetOf() }
                        .add(requiredPermission)
                }
            }
        }

        return packageManager.getInstalledPackages(PackageManager.GET_PERMISSIONS)
            .asSequence()
            .filter { packageInfo ->
                val appInfo = packageInfo.applicationInfo
                appInfo != null &&
                    (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) == 0
            }
            .mapNotNull { packageInfo ->
                val appInfo = packageInfo.applicationInfo ?: return@mapNotNull null
                val requestedPermissions = packageInfo.requestedPermissions.orEmpty()
                val requestedHighRisk = requestedPermissions.toSet()
                    .intersect(highRiskPermissions)
                val permissionFlags = packageInfo.requestedPermissionsFlags
                val grantedHighRisk = requestedHighRisk.filter { permission ->
                    val index = requestedPermissions.indexOf(permission)
                    val flags = permissionFlags?.getOrNull(index)
                    index >= 0 && flags != null &&
                        (flags and PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0
                }.toSet()
                val activeServices = activeServicePermissions[packageInfo.packageName]
                    .orEmpty()
                // A declaration is not proof of active access: only confirmed
                // grants and enabled privileged services contribute to this signal.
                val dangerous = grantedHighRisk + activeServices
                if (dangerous.size < 3) return@mapNotNull null

                SuspiciousApp(
                    packageName = packageInfo.packageName,
                    appName = packageManager.getApplicationLabel(appInfo).toString(),
                    targetSdkVersion = appInfo.targetSdkVersion,
                    highRiskPermissions = dangerous.sorted(),
                    mediumRiskPermissions = requestedPermissions
                        .intersect(mediumRiskPermissions)
                        .sorted(),
                )
            }
            .sortedBy(SuspiciousApp::packageName)
            .toList()
    }

    @Suppress("DEPRECATION")
    fun verifyAppSignatures(context: Context): List<AppSignatureIssue> {
        val packageManager = context.packageManager
        val queryFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        return packageManager.getInstalledPackages(queryFlags)
            .mapNotNull { packageInfo ->
                // Multiple current signers are valid Android signing configurations.
                // On Android 9+, use apkContentsSigners (current signers), not the
                // historical certificate rotation list, for the installed APK.
                val signatures: Array<Signature> = if (
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ) {
                    packageInfo.signingInfo?.apkContentsSigners.orEmpty()
                } else {
                    packageInfo.signatures.orEmpty()
                }
                val problems = mutableListOf<String>()
                if (signatures.isEmpty()) {
                    problems.add("SIGNATURE_METADATA_UNAVAILABLE")
                }

                val signatureHashes = mutableListOf<String>()
                signatures.forEach { signature ->
                    try {
                        val digest = MessageDigest.getInstance("SHA-256")
                            .digest(signature.toByteArray())
                        signatureHashes.add(
                            digest.joinToString(separator = "") { value ->
                                "%02X".format(value.toInt() and 0xFF)
                            },
                        )
                    } catch (_: NoSuchAlgorithmException) {
                        problems.add("SIGNATURE_HASH_FAILED")
                    }
                }

                if (problems.isEmpty()) return@mapNotNull null
                AppSignatureIssue(
                    packageName = packageInfo.packageName,
                    appName = packageInfo.applicationInfo?.let {
                        packageManager.getApplicationLabel(it).toString()
                    } ?: packageInfo.packageName,
                    problems = problems.distinct(),
                    signatureCount = signatures.size,
                    signatureSha256 = signatureHashes,
                )
            }
            .sortedBy(AppSignatureIssue::packageName)
    }

    @Suppress("DEPRECATION")
    @Throws(IOException::class)
    fun detectSuspiciousObfuscation(context: Context): List<ObfuscatedApp> {
        val packageManager = context.packageManager
        return packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            .asSequence()
            .filter { appInfo ->
                (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) == 0
            }
            .mapNotNull { appInfo ->
                val apkPaths = (listOfNotNull(appInfo.sourceDir) +
                    appInfo.splitSourceDirs.orEmpty()).distinct()
                var totalIdentifiers = 0
                var obfuscatedIdentifiers = 0
                var maxEntropy = 0.0
                var dexFileCount = 0

                apkPaths.forEach { apkPath ->
                    ZipFile(apkPath).use { apk ->
                        val entries = apk.entries()
                        while (entries.hasMoreElements()) {
                            val entry = entries.nextElement()
                            if (!entry.isDirectory && DEX_ENTRY_PATTERN.matches(entry.name)) {
                                if (dexFileCount >= MAX_DEX_FILES_PER_APP) break
                                val dexData = readDexEntry(apk, entry)
                                dexFileCount++
                                maxEntropy = maxOf(maxEntropy, dexData.entropy)
                                dexData.identifiers?.let { identifiers ->
                                    totalIdentifiers += identifiers.total
                                    obfuscatedIdentifiers += identifiers.obfuscated
                                }
                            }
                        }
                    }
                }

                if (dexFileCount == 0) return@mapNotNull null
                val identifierRatio = if (totalIdentifiers == 0) {
                    0.0
                } else {
                    obfuscatedIdentifiers.toDouble() / totalIdentifiers
                }
                val reasons = buildList {
                    if (maxEntropy > DEX_ENTROPY_THRESHOLD) {
                        add("HIGH_DEX_ENTROPY")
                    }
                    if (totalIdentifiers >= MIN_IDENTIFIERS_FOR_RATIO &&
                        identifierRatio > OBFUSCATED_IDENTIFIER_RATIO_THRESHOLD
                    ) {
                        add("HIGH_OBFUSCATED_IDENTIFIER_RATIO")
                    }
                }
                if (reasons.isEmpty()) return@mapNotNull null

                ObfuscatedApp(
                    packageName = appInfo.packageName,
                    appName = packageManager.getApplicationLabel(appInfo).toString(),
                    dexEntropy = maxEntropy,
                    obfuscatedIdentifierRatio = identifierRatio,
                    analyzedDexFiles = dexFileCount,
                    reasons = reasons,
                )
            }
            .sortedBy(ObfuscatedApp::packageName)
            .toList()
    }

    private fun readDexEntry(zipFile: ZipFile, entry: ZipEntry): DexAnalysis {
        val frequencies = LongArray(256)
        val dexBuffer = ByteArrayOutputStream()
        var totalBytes = 0L
        var canParse = true
        zipFile.getInputStream(entry).buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val bytesRead = input.read(buffer)
                if (bytesRead < 0) break
                totalBytes += bytesRead
                if (totalBytes > MAX_DEX_PARSE_SIZE_BYTES) {
                    canParse = false
                    dexBuffer.reset()
                    break
                }
                for (index in 0 until bytesRead) {
                    frequencies[buffer[index].toInt() and 0xFF]++
                }
                if (canParse) {
                    if (totalBytes <= MAX_DEX_PARSE_SIZE_BYTES) {
                        dexBuffer.write(buffer, 0, bytesRead)
                    } else {
                        canParse = false
                        dexBuffer.reset()
                    }
                }
            }
        }

        if (!canParse) return DexAnalysis(entropy = 0.0, identifiers = null)

        val entropy = if (totalBytes == 0L) {
            0.0
        } else {
            frequencies.asSequence()
                .filter { it > 0L }
                .sumOf { count ->
                    val probability = count.toDouble() / totalBytes
                    -probability * (kotlin.math.ln(probability) / kotlin.math.ln(2.0))
                }
        }
        return DexAnalysis(
            entropy = entropy,
            identifiers = if (canParse) {
                parseDexIdentifiers(dexBuffer.toByteArray())
            } else {
                null
            },
        )
    }

    private fun parseDexIdentifiers(dex: ByteArray): IdentifierCounts? {
        if (dex.size < DEX_HEADER_MIN_SIZE || !dex.copyOfRange(0, 4).contentEquals(
                byteArrayOf('d'.code.toByte(), 'e'.code.toByte(), 'x'.code.toByte(), '\n'.code.toByte()),
            )
        ) {
            return null
        }

        val stringCount = dex.readIntLE(DEX_STRING_IDS_SIZE_OFFSET) ?: return null
        val stringOffset = dex.readIntLE(DEX_STRING_IDS_OFFSET_OFFSET) ?: return null
        val typeCount = dex.readIntLE(DEX_TYPE_IDS_SIZE_OFFSET) ?: return null
        val typeOffset = dex.readIntLE(DEX_TYPE_IDS_OFFSET_OFFSET) ?: return null
        val methodCount = dex.readIntLE(DEX_METHOD_IDS_SIZE_OFFSET) ?: return null
        val methodOffset = dex.readIntLE(DEX_METHOD_IDS_OFFSET_OFFSET) ?: return null
        val classCount = dex.readIntLE(DEX_CLASS_DEFS_SIZE_OFFSET) ?: return null
        val classOffset = dex.readIntLE(DEX_CLASS_DEFS_OFFSET_OFFSET) ?: return null

        if (!dex.isTableInBounds(stringOffset, stringCount, 4) ||
            !dex.isTableInBounds(typeOffset, typeCount, 4) ||
            !dex.isTableInBounds(methodOffset, methodCount, 8) ||
            !dex.isTableInBounds(classOffset, classCount, 32) ||
            stringCount > MAX_DEX_TABLE_ITEMS_FOR_PARSING ||
            typeCount > MAX_DEX_TABLE_ITEMS_FOR_PARSING ||
            methodCount > MAX_DEX_TABLE_ITEMS_FOR_PARSING ||
            classCount > MAX_DEX_TABLE_ITEMS_FOR_PARSING
        ) {
            return null
        }

        val strings = ArrayList<String>(stringCount)
        repeat(stringCount) { index ->
            val dataOffset = dex.readIntLE(stringOffset + index * 4) ?: return null
            strings.add(dex.readDexString(dataOffset) ?: return null)
        }
        val types = IntArray(typeCount)
        repeat(typeCount) { index ->
            types[index] = dex.readIntLE(typeOffset + index * 4) ?: return null
        }
        var total = 0
        var obfuscated = 0

        repeat(classCount) { index ->
            val classIndex = dex.readIntLE(classOffset + index * 32) ?: return null
            val descriptorIndex = types.getOrNull(classIndex) ?: return null
            val descriptor = strings.getOrNull(descriptorIndex) ?: return null
            val simpleName = descriptor.substringAfterLast('/').removeSuffix(";")
            total++
            if (simpleName.isObfuscatedIdentifier()) obfuscated++
        }
        repeat(methodCount) { index ->
            val nameIndex = dex.readIntLE(methodOffset + index * 8 + 4) ?: return null
            val name = strings.getOrNull(nameIndex) ?: return null
            if (name == "<init>" || name == "<clinit>") return@repeat
            total++
            if (name.isObfuscatedIdentifier()) obfuscated++
        }
        return IdentifierCounts(total, obfuscated)
    }

    private fun String.isObfuscatedIdentifier(): Boolean =
        length <= 2 && OBFUSCATED_IDENTIFIER_PATTERN.matches(this)

    private fun ByteArray.readIntLE(offset: Int): Int? {
        if (offset < 0 || offset > size - 4) return null
        return (this[offset].toInt() and 0xFF) or
            ((this[offset + 1].toInt() and 0xFF) shl 8) or
            ((this[offset + 2].toInt() and 0xFF) shl 16) or
            ((this[offset + 3].toInt() and 0xFF) shl 24)
    }

    private fun ByteArray.isTableInBounds(offset: Int, count: Int, itemSize: Int): Boolean {
        if (offset < 0 || count < 0 || itemSize <= 0) return false
        return offset.toLong() + count.toLong() * itemSize <= size.toLong()
    }

    private fun ByteArray.readDexString(offset: Int): String? {
        if (offset !in indices) return null
        var cursor = offset
        var lengthBytes = 0
        while (cursor < size) {
            val value = this[cursor++].toInt() and 0xFF
            lengthBytes++
            if (value and 0x80 == 0) break
            if (lengthBytes == 5) return null
        }
        if (cursor > size) return null
        val stringStart = cursor
        while (cursor < size && this[cursor].toInt() != 0) cursor++
        if (cursor >= size) return null
        return String(this, stringStart, cursor - stringStart, Charsets.UTF_8)
    }

    private fun SuspiciousApp.toMap(): Map<String, Any> = mapOf(
        "package_name" to packageName,
        "app_name" to appName,
        "target_sdk" to targetSdkVersion,
        "high_risk_permissions" to highRiskPermissions,
        "medium_risk_permissions" to mediumRiskPermissions,
    )

    private fun AppSignatureIssue.toMap(): Map<String, Any> = mapOf(
        "package_name" to packageName,
        "app_name" to appName,
        "problems" to problems,
        "signature_count" to signatureCount,
        "signature_sha256" to signatureSha256,
    )

    private fun ObfuscatedApp.toMap(): Map<String, Any> = mapOf(
        "package_name" to packageName,
        "app_name" to appName,
        "dex_entropy" to dexEntropy,
        "obfuscated_identifier_ratio" to obfuscatedIdentifierRatio,
        "analyzed_dex_files" to analyzedDexFiles,
        "reasons" to reasons,
    )

    private fun enabledComponents(value: String?): Set<ComponentName> =
        value.orEmpty()
            .split(':')
            .mapNotNull { component ->
                ComponentName.unflattenFromString(component.trim())
            }
            .toSet()

    @Suppress("DEPRECATION")
    private fun collectActiveServices(
        packageManager: PackageManager,
        action: String,
        requiredPermission: String,
        enabledComponents: Set<ComponentName>,
        serviceType: String,
        installedApplications: Map<String, ApplicationInfo>,
        output: MutableMap<String, MutableList<Map<String, String>>>,
    ) {
        val intent = Intent(action)
        val matches = packageManager.queryIntentServices(
            intent,
            PackageManager.MATCH_DISABLED_COMPONENTS,
        )

        for (match in matches) {
            val serviceInfo = match.serviceInfo ?: continue
            val appInfo = installedApplications[serviceInfo.packageName] ?: continue
            val component = ComponentName(serviceInfo.packageName, serviceInfo.name)
            if (serviceInfo.permission != requiredPermission ||
                !serviceInfo.enabled ||
                !appInfo.enabled ||
                    component !in enabledComponents
            ) {
                continue
            }

            output.getOrPut(serviceInfo.packageName) { mutableListOf() }.add(
                mapOf(
                    "type" to serviceType,
                    "service_name" to serviceInfo.name,
                    "required_permission" to requiredPermission,
                ),
            )
        }
    }

    private data class DexAnalysis(
        val entropy: Double,
        val identifiers: IdentifierCounts?,
    )

    private data class IdentifierCounts(
        val total: Int,
        val obfuscated: Int,
    )

    private val DEX_ENTRY_PATTERN = Regex("""classes(\d*)\.dex""")
    private val OBFUSCATED_IDENTIFIER_PATTERN = Regex("[a-zA-Z_$][a-zA-Z0-9_$]{0,1}")
    private const val DEX_HEADER_MIN_SIZE = 112
    private const val DEX_STRING_IDS_SIZE_OFFSET = 56
    private const val DEX_STRING_IDS_OFFSET_OFFSET = 60
    private const val DEX_TYPE_IDS_SIZE_OFFSET = 64
    private const val DEX_TYPE_IDS_OFFSET_OFFSET = 68
    private const val DEX_METHOD_IDS_SIZE_OFFSET = 88
    private const val DEX_METHOD_IDS_OFFSET_OFFSET = 92
    private const val DEX_CLASS_DEFS_SIZE_OFFSET = 96
    private const val DEX_CLASS_DEFS_OFFSET_OFFSET = 100
}
