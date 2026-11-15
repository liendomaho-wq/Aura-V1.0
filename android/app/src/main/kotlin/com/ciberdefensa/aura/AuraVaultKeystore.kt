package com.ciberdefensa.aura

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Aliases and preference files flutter_secure_storage 10.3.1 leaves behind.
 * [FlutterSecureStorage.deleteAll] only clears the data preferences. The
 * wrapped AES key stays in FlutterSecureKeyStorage, and the next start
 * fails closed because resetOnError is false. This follows the library's
 * deleteAllDataAndKeys: delete the Keystore aliases, clear the wrapped key
 * and the algorithm markers, then write the current algorithm so a new
 * instance can initialize.
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
    private const val PROVIDER = "AndroidKeyStore"

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

    /**
     * Clears the data file, the wrapped AES key and both configuration
     * stores, then records the current cipher so the next plugin instance
     * does not try to unwrap a deleted key.
     */
    fun clearPluginStores(context: Context): Boolean {
        return try {
            val dataCleared = context
                .getSharedPreferences(DATA_PREFS, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .commit()
            val keysCleared = context
                .getSharedPreferences(KEY_PREFS, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .commit()
            val legacyCleared = context
                .getSharedPreferences(LEGACY_CONFIG_PREFS, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .commit()
            val markersWritten = context
                .getSharedPreferences(NAMESPACED_CONFIG_PREFS, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .putString(ALGORITHM_KEY, CURRENT_KEY_ALGORITHM)
                .putString(ALGORITHM_STORAGE, CURRENT_STORAGE_ALGORITHM)
                .commit()
            dataCleared && keysCleared && legacyCleared && markersWritten
        } catch (_: Exception) {
            false
        }
    }

    fun deleteKnownKeys(context: Context): Boolean {
        val storesCleared = clearPluginStores(context)
        val aliasesDeleted = deleteKnownKeys(context.packageName)
        return storesCleared && aliasesDeleted
    }

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
