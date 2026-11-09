package com.ciberdefensa.aura;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import androidx.security.crypto.EncryptedSharedPreferences;
import androidx.security.crypto.MasterKey;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import com.it_nomads.fluttersecurestorage.FlutterSecureStorage;
import com.it_nomads.fluttersecurestorage.FlutterSecureStorageConfig;
import com.it_nomads.fluttersecurestorage.SecurePreferencesCallback;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.HashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public class SecureStorageMigrationTest {
    private static final String TEST_APPLICATION_ID = "com.ciberdefensa.aura.vaultmigrationtest";
    private static final String LEGACY_VALUE = "v9-real-keystore-secret-preserved";
    private static final String KEY_PREFIX = "aura_migration_test_secret";
    private static final String BACKUP_STATUS_KEY = "FlutterSecureStorageBackupStatus";

    private Context context;
    private FlutterSecureStorageConfig config;
    private String prefixedSecretKey;

    @Before
    public void setUp() throws Exception {
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        // Refuse all writes/clears unless the separate test application owns the UID.
        assertEquals("Run only :app:connectedStorageMigrationAndroidTest",
                TEST_APPLICATION_ID, context.getPackageName());
        HashMap<String, Object> options = new HashMap<>();
        options.put("storageNamespace", "aura_v9_v10_migration_test");
        options.put("resetOnError", "false");
        options.put("migrateOnAlgorithmChange", "true");
        options.put("migrateWithBackup", "true");
        config = new FlutterSecureStorageConfig(options);
        prefixedSecretKey = config.getSharedPreferencesKeyPrefix() + "_" + KEY_PREFIX;

        assertTrue(context.getSharedPreferences(config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE)
                .edit().clear().commit());
        assertTrue(context.getSharedPreferences(config.getEffectiveKeyStoragePrefsName(), Context.MODE_PRIVATE)
                .edit().clear().commit());
        assertTrue(context.getSharedPreferences(
                "FlutterSecureStorageConfiguration:" + config.getEffectiveDataPrefsName(),
                Context.MODE_PRIVATE)
                .edit().clear().commit());
        // v10 still uses the default ESP master-key alias. The separate application
        // ID/UID isolates that Keystore alias too; namespace alone would not.
        seedVersion9EncryptedSharedPreferences();
        // Verify the legacy fixture before v10 initialization touches storage.
        // ESP encrypts preference keys as well as values, so the raw preferences
        // must not contain the plaintext prefixed key.
        assertEquals("Legacy ESP fixture must be readable before migration",
                LEGACY_VALUE, legacyPreferences().getString(prefixedSecretKey, null));
        assertFalse("Legacy ESP key must not be present in plaintext",
                rawDataPreferences().contains(prefixedSecretKey));
    }

    @Test
    public void migratesRealVersion9EncryptedPreferencesAndPreservesSecret() throws Exception {
        FlutterSecureStorage storage = initializeVersion10Storage();

        assertEquals(LEGACY_VALUE, storage.read(prefixedSecretKey));
        assertFalse(legacyPreferences().contains(prefixedSecretKey));
        String migratedCiphertext = rawDataPreferences().getString(prefixedSecretKey, null);
        assertNotNull(migratedCiphertext);
        assertNotEquals(LEGACY_VALUE, migratedCiphertext);
    }

    @Test
    public void diagnosticLegacyMigrationWithoutBackupPreservesSecret() throws Exception {
        // Diagnostic only, in the isolated test application. Disabling backup in
        // production is NOT approved by this test; interrupted migration and
        // recovery would still need a separately reviewed design and testing.
        HashMap<String, Object> options = new HashMap<>();
        options.put("storageNamespace", "aura_v9_v10_migration_test");
        options.put("resetOnError", "false");
        options.put("migrateOnAlgorithmChange", "true");
        options.put("migrateWithBackup", "false");
        FlutterSecureStorage storage = initializeVersion10Storage(
                new FlutterSecureStorageConfig(options));
        assertEquals("Diagnostic must preserve the v9 value", LEGACY_VALUE,
                storage.read(prefixedSecretKey));
    }

    @Test
    public void keepsLegacySecretRecoverableIfMigrationDoesNotReturnIt() throws Exception {
        FlutterSecureStorage storage = initializeVersion10Storage();
        String migratedValue = storage.read(prefixedSecretKey);
        if (LEGACY_VALUE.equals(migratedValue)) return;

        // This is an additional data-preservation check, not an alternative
        // success criterion for the strict migration test above.
        assertEquals("An unavailable migrated value must remain recoverable in legacy ESP",
                LEGACY_VALUE, legacyPreferences().getString(prefixedSecretKey, null));
    }

    @Test
    public void restartsAnInterruptedBackupAndStillMigratesVersion9Secret() throws Exception {
        SharedPreferences rawData = rawDataPreferences();
        rawData.edit().putString(prefixedSecretKey + "_BACKUP", "stale-partial-backup").commit();
        context.getSharedPreferences(
                "FlutterSecureStorageConfiguration:" + config.getEffectiveDataPrefsName(),
                Context.MODE_PRIVATE)
                .edit().putString(BACKUP_STATUS_KEY, "started").commit();

        FlutterSecureStorage storage = initializeVersion10Storage();

        assertEquals(LEGACY_VALUE, storage.read(prefixedSecretKey));
        assertFalse(rawDataPreferences().contains(prefixedSecretKey + "_BACKUP"));
        assertFalse(legacyPreferences().contains(prefixedSecretKey));
    }

    private void seedVersion9EncryptedSharedPreferences() throws Exception {
        MasterKey masterKey = new MasterKey.Builder(context)
                .setKeyGenParameterSpec(new KeyGenParameterSpec.Builder(
                        MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .build())
                .build();
        SharedPreferences legacy = EncryptedSharedPreferences.create(
                context,
                config.getEffectiveDataPrefsName(),
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM);
        assertTrue(legacy.edit().putString(prefixedSecretKey, LEGACY_VALUE).commit());
    }

    private FlutterSecureStorage initializeVersion10Storage() throws Exception {
        return initializeVersion10Storage(config);
    }

    private FlutterSecureStorage initializeVersion10Storage(
            FlutterSecureStorageConfig storageConfig) throws Exception {
        FlutterSecureStorage storage = new FlutterSecureStorage(context);
        CountDownLatch initialized = new CountDownLatch(1);
        AtomicReference<Exception> failure = new AtomicReference<>();
        storage.initialize(storageConfig, new SecurePreferencesCallback<Void>() {
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
        assertTrue("v10 secure storage initialization timed out", initialized.await(30, TimeUnit.SECONDS));
        if (failure.get() != null) throw failure.get();
        return storage;
    }

    private SharedPreferences legacyPreferences() throws Exception {
        MasterKey masterKey = new MasterKey.Builder(context)
                .setKeyGenParameterSpec(new KeyGenParameterSpec.Builder(
                        MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .build())
                .build();
        return EncryptedSharedPreferences.create(
                context,
                config.getEffectiveDataPrefsName(),
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM);
    }

    private SharedPreferences rawDataPreferences() {
        return context.getSharedPreferences(config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE);
    }
}
