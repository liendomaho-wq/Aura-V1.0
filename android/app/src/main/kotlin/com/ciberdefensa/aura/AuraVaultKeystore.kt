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
    const val PURGE_PREFS = "aura_vault_purge"
    const val PENDING_KEY_DELETION = "pending_key_deletion"
    private const val CHANNEL = "com.ciberdefensa.aura/vault_keystore"
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"

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

    fun deleteKnownKeys(context: Context): Boolean {
        val dataCleared = clearPluginStores(context)
        val marked = markPendingKeyDeletion(context)
        return dataCleared && marked
    }

    fun markPendingKeyDeletion(context: Context): Boolean {
        return context
            .getSharedPreferences(PURGE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(PENDING_KEY_DELETION, true)
            .commit()
    }

    fun isPendingKeyDeletion(context: Context): Boolean {
        return context
            .getSharedPreferences(PURGE_PREFS, Context.MODE_PRIVATE)
            .getBoolean(PENDING_KEY_DELETION, false)
    }

    /**
     * Next process start, before flutter_secure_storage is opened. Uses
     * [deleteAliases] so a failed delete does not report the key as gone.
     */
    fun consumePendingKeyDeletion(context: Context): Boolean {
        if (!isPendingKeyDeletion(context)) return true
        val aliasesDeleted = deleteKeystoreAliases(context.packageName)
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
        // Values written after the purge used the key this step deletes.
        val dataCleared = clearPluginStores(context)
        val flagCleared = context
            .getSharedPreferences(PURGE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(PENDING_KEY_DELETION)
            .commit()
        return aliasesDeleted &&
            keysCleared &&
            legacyCleared &&
            markersWritten &&
            dataCleared &&
            flagCleared &&
            !isPendingKeyDeletion(context)
    }

    private fun deleteKeystoreAliases(packageName: String): Boolean {
        return try {
            val keyStore = java.security.KeyStore.getInstance(KEYSTORE_PROVIDER)
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
        if (!consumePendingKeyDeletion(context)) {
            android.util.Log.e(
                "AuraVault",
                "No se pudo completar el borrado de la clave pendiente.",
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deleteVaultKeystoreKeys" ->
                        result.success(deleteKnownKeys(context))
                    "consumePendingKeyDeletion" ->
                        result.success(consumePendingKeyDeletion(context))
                    else -> result.notImplemented()
                }
            }
    }
}
