package com.ciberdefensa.aura;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import com.it_nomads.fluttersecurestorage.FlutterSecureStorage;
import com.it_nomads.fluttersecurestorage.FlutterSecureStorageConfig;
import com.it_nomads.fluttersecurestorage.SecurePreferencesCallback;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.HashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import javax.crypto.AEADBadTagException;

import static org.junit.Assert.*;

/** Actual AES-GCM/provider integrity; separate UID and namespace, no vault reset. */
@RunWith(AndroidJUnit4.class)
public final class SecureStorageIntegrityTest {
    @Test
    public void rejectsTamperedGcmValueWithoutResettingOtherSecrets() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertEquals("com.ciberdefensa.aura.vaultmigrationtest", context.getPackageName());
        assertTrue(android.os.Process.myUid() >= 10000);
        HashMap<String, Object> options = new HashMap<>();
        options.put("storageNamespace", "aura_gcm_integrity_test");
        options.put("resetOnError", "false");
        options.put("migrateOnAlgorithmChange", "true");
        options.put("migrateWithBackup", "true");
        FlutterSecureStorageConfig config = new FlutterSecureStorageConfig(options);
        FlutterSecureStorage storage = new FlutterSecureStorage(context);
        CountDownLatch initialized = new CountDownLatch(1);
        AtomicReference<Exception> failure = new AtomicReference<>();
        storage.initialize(config, new SecurePreferencesCallback<Void>() {
            @Override public void onSuccess(Void unused) { initialized.countDown(); }
            @Override public void onError(Exception error) {
                failure.set(error);
                initialized.countDown();
            }
        });
        assertTrue("Real Keystore initialization timed out", initialized.await(30, TimeUnit.SECONDS));
        if (failure.get() != null) throw failure.get();
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
            // Restore the exact original TEST ciphertext, never rekey/reset.
            if (!raw.edit().putString(first, original).commit()) {
                AssertionError restoration = new AssertionError("Could not restore isolated TEST ciphertext");
                if (primaryFailure != null) primaryFailure.addSuppressed(restoration);
                else throw restoration;
            }
        }
        assertEquals("authenticated-test-secret", storage.read(first));
        assertEquals("independent-test-secret-preserved", storage.read(second));
    }
}
