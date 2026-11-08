package com.ciberdefensa.aura;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import androidx.security.crypto.EncryptedSharedPreferences;
import androidx.security.crypto.MasterKey;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import com.it_nomads.fluttersecurestorage.FlutterSecureStorage;
import com.it_nomads.fluttersecurestorage.FlutterSecureStorageConfig;
import com.it_nomads.fluttersecurestorage.SecurePreferencesCallback;
import com.it_nomads.fluttersecurestorage.NamespacedConfigSource;
import com.it_nomads.fluttersecurestorage.ciphers.StorageCipherFactory;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import javax.crypto.AEADBadTagException;

import static org.junit.Assert.*;

/** Actual provider/data-integrity regressions; separate UID, never reset/rekey. */
@RunWith(AndroidJUnit4.class)
public final class SecureStorageIntegrityTest {
    private Exception lastInitializationFailure;

    private Context guardedContext() {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertEquals("com.ciberdefensa.aura.vaultmigrationtest", context.getPackageName());
        assertTrue(android.os.Process.myUid() >= 10000);
        return context;
    }

    private FlutterSecureStorageConfig config(String namespace) {
        HashMap<String, Object> options = new HashMap<>();
        options.put("storageNamespace", namespace + "_" + UUID.randomUUID());
        options.put("resetOnError", "false");
        options.put("migrateOnAlgorithmChange", "true");
        options.put("migrateWithBackup", "true");
        return new FlutterSecureStorageConfig(options);
    }

    private FlutterSecureStorage initialize(Context context, FlutterSecureStorageConfig config,
                                            boolean expectFailure) throws Exception {
        FlutterSecureStorage storage = new FlutterSecureStorage(context);
        CountDownLatch initialized = new CountDownLatch(1);
        AtomicReference<Exception> failure = new AtomicReference<>();
        AtomicInteger callbacks = new AtomicInteger();
        storage.initialize(config, new SecurePreferencesCallback<Void>() {
            @Override public void onSuccess(Void unused) {
                callbacks.incrementAndGet();
                initialized.countDown();
            }
            @Override public void onError(Exception error) {
                failure.set(error);
                callbacks.incrementAndGet();
                initialized.countDown();
            }
        });
        assertTrue("Real Keystore initialization timed out", initialized.await(30, TimeUnit.SECONDS));
        assertEquals("Initialization must complete once", 1, callbacks.get());
        lastInitializationFailure = failure.get();
        if (expectFailure) assertNotNull("Corrupt/conflicting data must fail closed", failure.get());
        else if (failure.get() != null) throw failure.get();
        return storage;
    }

    private static Throwable legacyAuthenticationFailure(Throwable failure) {
        assertNotNull("The genuine provider must reject corrupted authenticated ciphertext", failure);
        Throwable root = failure;
        while (root.getCause() != null) root = root.getCause();
        // Tink 1.21 WrappedAead deliberately discards individual primitive
        // exceptions and throws this exact GeneralSecurityException. Do not
        // accept an unrelated error, missing key or arbitrary exception.
        assertTrue("Expected actual AEAD/Tink authentication failure, got " + root,
                root instanceof AEADBadTagException ||
                (root.getClass() == java.security.GeneralSecurityException.class &&
                        "decryption failed".equals(root.getMessage())));
        return root;
    }

    private SharedPreferences legacy(Context context, FlutterSecureStorageConfig config) throws Exception {
        MasterKey master = new MasterKey.Builder(context)
                .setKeyGenParameterSpec(new KeyGenParameterSpec.Builder(MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256).build()).build();
        return EncryptedSharedPreferences.create(context, config.getEffectiveDataPrefsName(), master,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM);
    }

    @Test
    public void rejectsTamperedGcmValueWithoutResettingOtherSecrets() throws Exception {
        Context context = guardedContext();
        FlutterSecureStorageConfig config = config("aura_gcm_integrity_test");
        FlutterSecureStorage storage = initialize(context, config, false);
        String first = config.getSharedPreferencesKeyPrefix() + "_integrity_first";
        String second = config.getSharedPreferencesKeyPrefix() + "_integrity_second";
        storage.write(first, "authenticated-test-secret");
        storage.write(second, "independent-test-secret-preserved");
        assertEquals("authenticated-test-secret", storage.read(first));
        assertEquals("independent-test-secret-preserved", storage.read(second));
        SharedPreferences raw = context.getSharedPreferences(config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE);
        String original = raw.getString(first, null);
        assertNotNull(original);
        byte[] ciphertext = Base64.decode(original, Base64.DEFAULT);
        assertTrue(ciphertext.length > 16);
        ciphertext[ciphertext.length - 1] ^= 1;
        String tampered = Base64.encodeToString(ciphertext, Base64.NO_WRAP);
        assertTrue(raw.edit().putString(first, tampered).commit());
        Throwable primaryFailure = null;
        try {
            try {
                storage.read(first);
                fail("Tampered AES-GCM data must not be accepted or silently reset");
            } catch (Exception error) {
                Throwable cause = error;
                while (cause != null && !(cause instanceof AEADBadTagException)) cause = cause.getCause();
                assertNotNull("Expected a real GCM authentication failure, not an unrelated error", cause);
            }
            assertEquals("Corrupt evidence must remain intact with resetOnError=false", tampered, raw.getString(first, null));
            assertEquals("independent-test-secret-preserved", storage.read(second));
        } catch (Exception | AssertionError error) {
            primaryFailure = error;
            throw error;
        } finally {
            if (!raw.edit().putString(first, original).commit()) {
                AssertionError restoration = new AssertionError("Could not restore isolated TEST ciphertext");
                if (primaryFailure != null) primaryFailure.addSuppressed(restoration);
                else throw restoration;
            }
        }
        assertEquals("authenticated-test-secret", storage.read(first));
        assertEquals("independent-test-secret-preserved", storage.read(second));
    }

    @Test
    public void corruptedLegacyFailsWithoutResetAndCanRetryAfterExactRestoration() throws Exception {
        Context context = guardedContext();
        FlutterSecureStorageConfig config = config("aura_legacy_integrity_test");
        String key = config.getSharedPreferencesKeyPrefix() + "_legacy_integrity";
        SharedPreferences old = legacy(context, config);
        assertTrue(old.edit().putString(key, "legacy-secret-retained").commit());
        assertEquals("legacy-secret-retained", old.getString(key, null));
        SharedPreferences raw = context.getSharedPreferences(config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE);
        String encryptedKey = null;
        for (String candidate : raw.getAll().keySet()) {
            if (!candidate.startsWith("__androidx_security_crypto_")) {
                assertNull("Only the one real legacy record belongs in this fixture", encryptedKey);
                encryptedKey = candidate;
            }
        }
        assertNotNull(encryptedKey);
        String original = raw.getString(encryptedKey, null);
        byte[] corrupted = Base64.decode(original, Base64.DEFAULT);
        corrupted[corrupted.length - 1] ^= 1;
        assertTrue(raw.edit().putString(encryptedKey, Base64.encodeToString(corrupted, Base64.NO_WRAP)).commit());
        Map<String, ?> before = raw.getAll();
        Throwable primaryFailure = null;
        try {
            // Cross-check the damaged record with the ORIGINAL AndroidX
            // provider, independently of Aura's migration implementation.
            Exception referenceFailure = null;
            try {
                old.getString(key, null);
                fail("Original AndroidX provider accepted a corrupted GCM tag");
            } catch (SecurityException error) {
                referenceFailure = error;
            }
            Throwable legacyRoot = legacyAuthenticationFailure(referenceFailure);
            initialize(context, config, true);
            Throwable actualRoot = legacyAuthenticationFailure(lastInitializationFailure);
            assertEquals("Migration must report the same genuine crypto failure class",
                    legacyRoot.getClass(), actualRoot.getClass());
            assertEquals("Migration must report the same genuine crypto failure reason",
                    legacyRoot.getMessage(), actualRoot.getMessage());
            assertEquals("Failure must not remove, overwrite or add data records", before, raw.getAll());
        } catch (Exception | AssertionError error) {
            primaryFailure = error;
            throw error;
        } finally {
            if (!raw.edit().putString(encryptedKey, original).commit()) {
                AssertionError restoration = new AssertionError("Could not restore isolated legacy TEST ciphertext");
                if (primaryFailure != null) primaryFailure.addSuppressed(restoration);
                else throw restoration;
            }
        }
        assertEquals("legacy-secret-retained", legacy(context, config).getString(key, null));
        FlutterSecureStorage retried = initialize(context, config, false);
        assertEquals("legacy-secret-retained", retried.read(key));
        assertFalse(legacy(context, config).contains(key));
    }

    @Test
    public void conflictingLegacyAndCurrentSecretsFailWithoutOverwritingEither() throws Exception {
        Context context = guardedContext();
        FlutterSecureStorageConfig config = config("aura_legacy_conflict_test");
        String key = config.getSharedPreferencesKeyPrefix() + "_conflicting_secret";
        FlutterSecureStorage current = initialize(context, config, false);
        current.write(key, "current-secret-preserved");
        SharedPreferences old = legacy(context, config);
        assertTrue(old.edit().putString(key, "different-legacy-secret-preserved").commit());
        SharedPreferences raw = context.getSharedPreferences(config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE);
        Map<String, ?> before = raw.getAll();
        initialize(context, config, true);
        assertTrue(lastInitializationFailure.getMessage().contains("Conflicting legacy/current secret"));
        assertEquals(before, raw.getAll());
        assertEquals("current-secret-preserved", current.read(key));
        assertEquals("different-legacy-secret-preserved", legacy(context, config).getString(key, null));
    }


    @Test
    public void refusesDestructiveRsaToAesAliasReplacementAndPreservesSecret() throws Exception {
        Context context = guardedContext();
        FlutterSecureStorageConfig config = config("aura_alias_preservation_test");
        String key = config.getSharedPreferencesKeyPrefix() + "_alias_preserved_secret";
        FlutterSecureStorage current = initialize(context, config, false);
        current.write(key, "secret-whose-rsa-key-must-survive");
        assertEquals("secret-whose-rsa-key-must-survive", current.read(key));
        java.security.KeyStore keystore = java.security.KeyStore.getInstance("AndroidKeyStore");
        keystore.load(null);
        String alias = context.getPackageName() + ".FlutterSecureStoragePluginKey" + config.getKeyAliasSuffix();
        assertTrue(keystore.getKey(alias, null) instanceof java.security.PrivateKey);
        byte[] certificate = keystore.getCertificate(alias).getEncoded();
        SharedPreferences raw = context.getSharedPreferences(config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE);
        Map<String, ?> before = raw.getAll();
        try {
            StorageCipherFactory requested = new StorageCipherFactory(
                    new NamespacedConfigSource(context, config.getEffectiveDataPrefsName()),
                    "AES_GCM_NoPadding", "AES_GCM_NoPadding", config);
            requested.getCurrentKeyCipher(context);
            fail("A new AES algorithm must never destroy the existing RSA alias");
        } catch (java.security.InvalidKeyException expected) {
            assertTrue(expected.getMessage().contains("destructive AES replacement refused"));
        }
        assertTrue(keystore.getKey(alias, null) instanceof java.security.PrivateKey);
        assertArrayEquals(certificate, keystore.getCertificate(alias).getEncoded());
        assertEquals(before, raw.getAll());
        // A fresh instance must really unwrap the persisted AES key; a cached
        // plaintext key from the first instance cannot satisfy this assertion.
        assertEquals("secret-whose-rsa-key-must-survive", initialize(context, config, false).read(key));
    }

    @Test
    public void identicalAlreadyMigratedSecretRecoversWithoutRekeying() throws Exception {
        Context context = guardedContext();
        FlutterSecureStorageConfig config = config("aura_legacy_resume_test");
        String key = config.getSharedPreferencesKeyPrefix() + "_same_secret";
        FlutterSecureStorage current = initialize(context, config, false);
        current.write(key, "same-secret-preserved");
        SharedPreferences raw = context.getSharedPreferences(config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE);
        String originalCurrentCiphertext = raw.getString(key, null);
        assertTrue(legacy(context, config).edit().putString(key, "same-secret-preserved").commit());
        FlutterSecureStorage resumed = initialize(context, config, false);
        assertEquals("same-secret-preserved", resumed.read(key));
        assertEquals("Existing current ciphertext must not be rekeyed", originalCurrentCiphertext, raw.getString(key, null));
        assertFalse(legacy(context, config).contains(key));
    }
}
