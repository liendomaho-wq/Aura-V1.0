package com.ciberdefensa.aura;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import com.it_nomads.fluttersecurestorage.FlutterSecureStorage;
import com.it_nomads.fluttersecurestorage.FlutterSecureStorageConfig;
import com.it_nomads.fluttersecurestorage.SecurePreferencesCallback;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.security.KeyStore;
import java.util.HashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

/**
 * Writes through flutter_secure_storage, purges the Keystore alias and the
 * wrapped-key preferences, then proves a new plugin instance can write again.
 * Runs in the isolated vaultmigrationtest UID, same as the migration tests.
 */
@RunWith(AndroidJUnit4.class)
public class SecureVaultPurgeTest {
    private static final String TEST_APPLICATION_ID = "com.ciberdefensa.aura.vaultmigrationtest";
    private static final String SECRET_KEY = "aura_purge_roundtrip";
    private static final String OLD_VALUE = "valor-antes-de-purgar";
    private static final String NEW_VALUE = "valor-despues-de-purgar";

    private Context context;
    private FlutterSecureStorageConfig config;

    @Before
    public void setUp() {
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertEquals("Run only :app:connectedStorageMigrationAndroidTest",
                TEST_APPLICATION_ID, context.getPackageName());
        HashMap<String, Object> options = new HashMap<>();
        options.put("resetOnError", "false");
        options.put("migrateOnAlgorithmChange", "true");
        options.put("migrateWithBackup", "true");
        config = new FlutterSecureStorageConfig(options);
    }

    @Test
    public void purgeLetsANewInstanceWriteAndRead() throws Exception {
        FlutterSecureStorage first = newStorage();
        String prefixed = config.getSharedPreferencesKeyPrefix() + "_" + SECRET_KEY;
        first.write(prefixed, OLD_VALUE);
        assertEquals(OLD_VALUE, first.read(prefixed));

        first.deleteAll();
        assertTrue(AuraVaultKeystore.INSTANCE.deleteKnownKeys(context));

        SharedPreferences wrapped = context.getSharedPreferences(
                AuraVaultKeystore.KEY_PREFS, Context.MODE_PRIVATE);
        assertFalse("the AES key must survive the purge", wrapped.getAll().isEmpty());
        SharedPreferences markers = context.getSharedPreferences(
                AuraVaultKeystore.NAMESPACED_CONFIG_PREFS, Context.MODE_PRIVATE);
        assertEquals(AuraVaultKeystore.CURRENT_KEY_ALGORITHM,
                markers.getString(AuraVaultKeystore.ALGORITHM_KEY, null));
        assertEquals(AuraVaultKeystore.CURRENT_STORAGE_ALGORITHM,
                markers.getString(AuraVaultKeystore.ALGORITHM_STORAGE, null));

        FlutterSecureStorage second = newStorage();
        assertNull(second.read(prefixed));
        second.write(prefixed, NEW_VALUE);
        assertEquals(NEW_VALUE, second.read(prefixed));
    }

    @Test
    public void writeAfterPurgeIsReadableByANewInstance() throws Exception {
        FlutterSecureStorage first = newStorage();
        String prefixed = config.getSharedPreferencesKeyPrefix() + "_" + SECRET_KEY;
        first.write(prefixed, OLD_VALUE);
        assertEquals(OLD_VALUE, first.read(prefixed));

        first.deleteAll();
        assertTrue(AuraVaultKeystore.INSTANCE.deleteKnownKeys(context));
        first.write(prefixed, NEW_VALUE);

        FlutterSecureStorage second = newStorage();
        assertEquals(NEW_VALUE, second.read(prefixed));
    }

    @Test
    public void nextStartDeletesTheKeyBeforeThePluginOpens() throws Exception {
        FlutterSecureStorage first = newStorage();
        String prefixed = config.getSharedPreferencesKeyPrefix() + "_" + SECRET_KEY;
        first.write(prefixed, OLD_VALUE);
        first.deleteAll();
        assertTrue(AuraVaultKeystore.INSTANCE.deleteKnownKeys(context));
        assertTrue(AuraVaultKeystore.INSTANCE.isPendingKeyDeletion(context));
        first.write(prefixed, NEW_VALUE);

        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        boolean aliasPresent = false;
        for (String alias : AuraVaultKeystore.INSTANCE.aliases(context.getPackageName())) {
            if (keyStore.containsAlias(alias)) aliasPresent = true;
        }
        assertTrue(aliasPresent);
        assertFalse(context.getSharedPreferences(
                AuraVaultKeystore.KEY_PREFS, Context.MODE_PRIVATE).getAll().isEmpty());

        assertTrue(AuraVaultKeystore.INSTANCE.consumePendingKeyDeletion(context));
        assertFalse(AuraVaultKeystore.INSTANCE.isPendingKeyDeletion(context));
        assertTrue(context.getSharedPreferences(
                AuraVaultKeystore.KEY_PREFS, Context.MODE_PRIVATE).getAll().isEmpty());
        SharedPreferences markers = context.getSharedPreferences(
                AuraVaultKeystore.NAMESPACED_CONFIG_PREFS, Context.MODE_PRIVATE);
        assertEquals(AuraVaultKeystore.CURRENT_KEY_ALGORITHM,
                markers.getString(AuraVaultKeystore.ALGORITHM_KEY, null));
        assertEquals(AuraVaultKeystore.CURRENT_STORAGE_ALGORITHM,
                markers.getString(AuraVaultKeystore.ALGORITHM_STORAGE, null));
        keyStore.load(null);
        for (String alias : AuraVaultKeystore.INSTANCE.aliases(context.getPackageName())) {
            assertFalse(keyStore.containsAlias(alias));
        }

        FlutterSecureStorage second = newStorage();
        assertNull(second.read(prefixed));
        second.write(prefixed, NEW_VALUE);
        assertEquals(NEW_VALUE, second.read(prefixed));
    }

    private FlutterSecureStorage newStorage() throws Exception {
        FlutterSecureStorage storage = new FlutterSecureStorage(context);
        CountDownLatch initialized = new CountDownLatch(1);
        AtomicReference<Exception> failure = new AtomicReference<>();
        storage.initialize(config, new SecurePreferencesCallback<Void>() {
            @Override
            public void onSuccess(Void unused) {
                initialized.countDown();
            }

            @Override
            public void onError(Exception error) {
                failure.set(error);
                initialized.countDown();
            }
        });
        assertTrue("Secure storage initialization timed out",
                initialized.await(30, TimeUnit.SECONDS));
        if (failure.get() != null) throw failure.get();
        return storage;
    }
}
