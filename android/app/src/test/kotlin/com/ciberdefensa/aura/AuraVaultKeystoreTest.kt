package com.ciberdefensa.aura

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AuraVaultKeystoreTest {
    @Test
    fun aliasesIncludeThePluginKeyAndTheAndroidxMasterKey() {
        val names = AuraVaultKeystore.aliases("com.ciberdefensa.aura")
        assertTrue(names.contains("com.ciberdefensa.aura.FlutterSecureStoragePluginKey"))
        assertTrue(names.contains("com.ciberdefensa.aura.FlutterSecureStoragePluginKeyOAEP"))
        assertTrue(names.contains(AuraVaultKeystore.MASTER_KEY_ALIAS))
    }

    @Test
    fun purgeDeletesAPresentKeystoreAlias() {
        val present = mutableSetOf(
            "com.ciberdefensa.aura.FlutterSecureStoragePluginKeyOAEP",
            AuraVaultKeystore.MASTER_KEY_ALIAS,
        )
        val store = object : VaultKeystoreEntries {
            override fun contains(alias: String) = alias in present
            override fun delete(alias: String) {
                present.remove(alias)
            }
        }
        assertTrue(
            AuraVaultKeystore.deleteAliases(
                store,
                AuraVaultKeystore.aliases("com.ciberdefensa.aura"),
            ),
        )
        assertTrue(present.isEmpty())
    }

    @Test
    fun purgeFailsIfTheAliasSurvivesDelete() {
        val store = object : VaultKeystoreEntries {
            override fun contains(alias: String) = alias == AuraVaultKeystore.MASTER_KEY_ALIAS
            override fun delete(alias: String) = Unit
        }
        assertFalse(
            AuraVaultKeystore.deleteAliases(
                store,
                listOf(AuraVaultKeystore.MASTER_KEY_ALIAS),
            ),
        )
    }
}
