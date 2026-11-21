package com.ciberdefensa.aura

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * flutter_secure_storage 10.3.1 keeps the AES key in memory after
 * [FlutterSecureStorage.deleteAll]. Deleting that key from disk makes every
 * later write in the same process unreadable on the next start, and
 * resetOnError=false then fails closed. A purge therefore clears only the
 * data preferences and leaves FlutterSecureKeyStorage and the Keystore
 * aliases in place until the next process start.
 */
internal interface VaultKeystoreEntries {
    fun contains(alias: String): Boolean
    fun delete(alias: String)
}

object AuraVaultKeystore {
    const val MASTER_KEY_ALIAS = "_androidx_security_master_key_"
    const val DATA_PREFS = "FlutterSecureStorage"
    const val KEY_PREFS = "FlutterSecureKeyStorage"
    const val LEGACY_CONFIG_PREFS = "FlutterSecureStorageConfiguration"
    const val NAMESPACED_CONFIG_PREFS =
        "FlutterSecureStorageConfiguration:FlutterSecureStorage"
    const val ALGORITHM_KEY = "FlutterSecureSAlgorithmKey"
    const val ALGORITHM_STORAGE = "FlutterSecureSAlgorithmStorage"
    const val CURRENT_KEY_ALGORITHM = "RSA_ECB_OAEPwithSHA_256andMGF1Padding"
    const val CURRENT_STORAGE_ALGORITHM = "AES_GCM_NoPadding"
    private const val CHANNEL = "com.ciberdefensa.aura/vault_keystore"

    fun aliases(packageName: String): List<String> = listOf(
        "$packageName.FlutterSecureStoragePluginKey",
        "$packageName.FlutterSecureStoragePluginKeyOAEP",
        MASTER_KEY_ALIAS,
    )

    internal fun deleteAliases(store: VaultKeystoreEntries, aliases: List<String>): Boolean {
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

    /**
     * Clears stored secrets. The wrapped AES key and the Keystore aliases
     * stay, so the plugin instance that is already in memory can keep
     * writing values the next process is able to read.
     */
    fun clearPluginStores(context: Context): Boolean {
        return try {
            context
                .getSharedPreferences(DATA_PREFS, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .commit()
        } catch (_: Exception) {
            false
        }
    }

    fun deleteKnownKeys(context: Context): Boolean = clearPluginStores(context)

    fun install(flutterEngine: FlutterEngine, context: Context) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "deleteVaultKeystoreKeys") {
                    result.success(deleteKnownKeys(context))
                } else {
                    result.notImplemented()
                }
            }
    }
}
