"""Source guards only: these do NOT execute Android or prove a migration."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TEST_PATH = (
    ROOT / "android/app/src/androidTest/java/com/ciberdefensa/aura/"
    "SecureStorageMigrationTest.java"
)


class SecureStorageInstrumentationPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = TEST_PATH.read_text(encoding="utf-8")
        cls.gradle = (ROOT / "android/app/build.gradle").read_text(encoding="utf-8")
        cls.workflow = (
            ROOT / ".github/workflows/android-debug-build.yml"
        ).read_text(encoding="utf-8")

    def test_uses_platform_keystore_not_a_replacement_provider(self):
        self.assertIn("@RunWith(AndroidJUnit4.class)", self.source)
        self.assertIn(
            "InstrumentationRegistry.getInstrumentation().getTargetContext()",
            self.source,
        )
        self.assertIn("MasterKey.DEFAULT_MASTER_KEY_ALIAS", self.source)
        self.assertIn("EncryptedSharedPreferences.create(", self.source)
        self.assertNotIn("Robolectric", self.source)
        self.assertNotIn("Security.addProvider", self.source)
        self.assertNotIn("Security.insertProviderAt", self.source)
        self.assertIn(
            'testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"',
            self.gradle,
        )

    def test_preserves_both_migration_tests_and_all_result_assertions(self):
        for name in (
            "migratesRealVersion9EncryptedPreferencesAndPreservesSecret",
            "restartsAnInterruptedBackupAndStillMigratesVersion9Secret",
        ):
            self.assertIn("public void " + name + "() throws Exception", self.source)
        self.assertEqual(
            self.source.count("assertEquals(LEGACY_VALUE, storage.read(prefixedSecretKey));"),
            2,
        )
        self.assertEqual(
            self.source.count("assertFalse(legacyPreferences().contains(prefixedSecretKey));"),
            2,
        )
        self.assertIn("assertNotNull(migratedCiphertext);", self.source)
        self.assertIn("assertNotEquals(LEGACY_VALUE, migratedCiphertext);", self.source)
        self.assertIn(
            'assertFalse(rawDataPreferences().contains(prefixedSecretKey + "_BACKUP"));',
            self.source,
        )
        self.assertIn("initialized.await(30, TimeUnit.SECONDS)", self.source)
        self.assertIn("if (failure.get() != null) throw failure.get();", self.source)
        self.assertNotIn("@Ignore", self.source)
        self.assertNotIn("Assume.", self.source)

    def test_separate_uid_and_namespace_before_any_preference_clear(self):
        self.assertIn('testBuildType "storageMigration"', self.gradle)
        self.assertRegex(
            self.gradle,
            r'storageMigration\s*\{\s*initWith debug\s*'
            r'applicationIdSuffix "\.vaultmigrationtest"',
        )
        self.assertIn('"com.ciberdefensa.aura.vaultmigrationtest"', self.source)
        self.assertIn(
            'options.put("storageNamespace", "aura_v9_v10_migration_test");',
            self.source,
        )
        self.assertLess(
            self.source.index("TEST_APPLICATION_ID, context.getPackageName()"),
            self.source.index(".edit().clear().commit()"),
        )
        self.assertNotIn(
            'getSharedPreferences("FlutterSecureStorageConfiguration",', self.source
        )
        for option in ("resetOnError", "migrateOnAlgorithmChange", "migrateWithBackup"):
            value = "false" if option == "resetOnError" else "true"
            self.assertIn(f'options.put("{option}", "{value}");', self.source)

    def test_isolated_app_and_instrumentation_runner_versions_match(self):
        for artifact in (
            "androidx.test:runner:1.7.0",
            "androidx.test.ext:junit:1.3.0",
        ):
            self.assertIn(f'storageMigrationImplementation "{artifact}"', self.gradle)
            self.assertIn(f'androidTestImplementation "{artifact}"', self.gradle)

    def test_ci_requires_real_android_execution_and_never_ignores_failure(self):
        self.assertIn("reactivecircus/android-emulator-runner@v2", self.workflow)
        self.assertIn("api-level: 36", self.workflow)
        self.assertIn(":app:connectedStorageMigrationAndroidTest", self.workflow)
        self.assertIn(":app:assembleStorageMigrationAndroidTest", self.workflow)
        self.assertIn(
            "-Pandroid.testInstrumentationRunnerArguments.class="
            "com.ciberdefensa.aura.SecureStorageMigrationTest",
            self.workflow,
        )
        self.assertNotIn("continue-on-error", self.workflow)
        # Standard GitHub Linux runners may lack KVM. Software emulation still
        # runs the same real Android Keystore instrumentation test; it is not skipped.
        self.assertIn("disable-linux-hw-accel: true", self.workflow)
        self.assertNotIn("Require unprivileged emulator acceleration", self.workflow)
        self.assertIn("exit 1", self.workflow)


if __ __name__ == "__main__":
    unittest.main(verbosity=2)
