package com.ciberdefensa.aura

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Aliases flutter_secure_storage 10.3.1 may leave in AndroidKeyStore.
 * [FlutterSecureStorage.deleteAll] only clears SharedPreferences. The
 * Keystore entry has to be deleted on its own.
 */
internal interface VaultKeystoreEntries {
    fun contains(alias: String): Boolean
    fun delete(alias: String)
}

internal object AuraVaultKeystore {
    const val MASTER_KEY_ALIAS = "_androidx_security_master_key_"
    private const val CHANNEL = "com.ciberdefensa.aura/vault_keystore"
    private const val PROVIDER = "AndroidKeyStore"

    fun aliases(packageName: String): List<String> = listOf(
        "$packageName.FlutterSecureStoragePluginKey",
        "$packageName.FlutterSecureStoragePluginKeyOAEP",
        MASTER_KEY_ALIAS,
    )

    fun deleteAliases(store: VaultKeystoreEntries, aliases: List<String>): Boolean {
        return try {
            for (alias in aliases) {
                if (!store.contains(alias)) continue
                store.delete(alias)
                if (store.contains(alias)) return false
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun deleteKnownKeys(packageName: String): Boolean {
        return try {
            val keyStore = java.security.KeyStore.getInstance(PROVIDER)
            keyStore.load(null)
            deleteAliases(
                object : VaultKeystoreEntries {
                    override fun contains(alias: String) = keyStore.containsAlias(alias)
                    override fun delete(alias: String) {
                        keyStore.deleteEntry(alias)
                    }
                },
                aliases(packageName),
            )
        } catch (_: Exception) {
            false
        }
    }

    fun install(flutterEngine: FlutterEngine, context: Context) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "deleteVaultKeystoreKeys") {
                    result.success(deleteKnownKeys(context.packageName))
                } else {
                    result.notImplemented()
                }
            }
    }
}
