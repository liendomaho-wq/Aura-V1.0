#!/usr/bin/env python3
"""Static regression tests for Aura's Android release-signing policy."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReleaseSigningPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gradle = (ROOT / "android/app/build.gradle").read_text(encoding="utf-8")
        cls.build_script = (ROOT / "tool/compile_aura.sh").read_text(encoding="utf-8")
        cls.release_workflow = (
            ROOT / ".github/workflows/android-release.yml"
        ).read_text(encoding="utf-8")
        cls.integrity_workflow = (
            ROOT / ".github/workflows/release-signing-integrity.yml"
        ).read_text(encoding="utf-8")
        cls.codemagic_workflow = (
            ROOT / "codemagic.yaml"
        ).read_text(encoding="utf-8")

    def test_android_codemagic_workflow_uses_free_plan_macos_runner(self):
        self.assertRegex(
            self.codemagic_workflow,
            re.compile(r"(?m)^\s*instance_type:\s*mac_mini_m2\s*$"),
        )
        self.assertNotIn("linux_x2", self.codemagic_workflow)

    def test_gradle_requires_all_production_signing_values(self):
        for variable in (
            "AURA_KEYSTORE_PATH",
            "AURA_STORE_PASSWORD",
            "AURA_KEY_ALIAS",
            "AURA_KEY_PASSWORD",
        ):
            self.assertIn(f'"{variable}"', self.gradle)

    def test_gradle_debug_fallback_requires_explicit_opt_in(self):
        self.assertIn('System.getenv("AURA_ALLOW_DEBUG_SIGNING") == "true"', self.gradle)
        self.assertRegex(
            self.gradle,
            re.compile(
                r"if\s*\(isDebugFallback\s*&&\s*!debugFallbackExplicitlyAllowed\)"
                r"[\s\S]*?throw new GradleException",
            ),
        )

    def test_build_script_marks_debug_fallback_as_explicit_test_mode(self):
        self.assertIn("export AURA_ALLOW_DEBUG_SIGNING=true", self.build_script)
        self.assertIn('AURA_REQUIRE_RELEASE_SIGNING:-false', self.build_script)
        self.assertIn(
            "⚠️ ADVERTENCIA: Generando APK de pruebas (DEBUG). NO DISTRIBUIR.",
            self.build_script,
        )
        self.assertRegex(
            self.build_script,
            re.compile(
                r'AURA_REQUIRE_RELEASE_SIGNING:-false\}" != "true"[\s\S]*?'
                r'USE_DEBUG_SIGNING=true[\s\S]*?'
                r'unset AURA_KEYSTORE_PATH AURA_KEYSTORE_BASE64'
            ),
        )

    def test_release_workflow_forbids_debug_fallback(self):
        self.assertGreaterEqual(
            self.release_workflow.count("AURA_REQUIRE_RELEASE_SIGNING: 'true'"),
            2,
        )

    def test_codemagic_defaults_to_debug_testing_and_keeps_strict_verification(self):
        build_script = self.codemagic_workflow.split(
            "- name: Build Android Release artifact", 1
        )[1].split("- name: Verify Android Release artifact signer", 1)[0]
        verify_script = self.codemagic_workflow.split(
            "- name: Verify Android Release artifact signer", 1
        )[1]
        self.assertIn("bash tool/compile_aura.sh", build_script)
        self.assertNotIn("export AURA_REQUIRE_RELEASE_SIGNING=false", build_script)
        self.assertIn('AURA_REQUIRE_RELEASE_SIGNING: "false"', self.codemagic_workflow)
        self.assertIn("bash tool/compile_aura.sh --verify-artifact", verify_script)
        self.assertIn('APK signer does not match the configured production certificate.', self.build_script)
        self.assertIn('APK must have exactly one verified signer.', self.build_script)
        self.assertRegex(
            verify_script,
            re.compile(
                r'AURA_REQUIRE_RELEASE_SIGNING:-false\}" == "true"[\s\S]*?'
                r"else[\s\S]*?Production signer verification skipped"
            ),
        )

    def test_artifact_verification_fails_closed_for_debug_or_missing_apksigner(self):
        self.assertRegex(
            self.build_script,
            re.compile(
                r'\[\[ "\$mode" == "verify-artifact" && '
                r'"\$USE_DEBUG_SIGNING" == "true" \]\][\s\S]*?'
                r'fail "Artifact verification requires production signing credentials'
            ),
        )
        self.assertIn(
            'fail "apksigner is required to verify the APK artifact certificate."',
            self.build_script,
        )

    def test_release_signing_report_rejects_missing_credentials(self):
        task = self.gradle.split('tasks.register("printReleaseSigning")', 1)[1]
        self.assertIn("def missingVariables =", task)
        self.assertIn("throw new GradleException", task)

    def test_codemagic_validates_pull_requests(self):
        events = self.codemagic_workflow.split("events:", 1)[1].split(
            "branch_patterns:", 1
        )[0]
        self.assertIn("- pull_request", events)

    def test_codemagic_pr_patterns_select_destination_branches(self):
        for branch in ("main", "principal"):
            self.assertRegex(
                self.codemagic_workflow,
                rf"pattern: '{branch}'\s+include: true\s+source: false",
            )

    def test_codemagic_keeps_full_validation_and_vault_recovery_tests(self):
        self.assertIn("dart format --set-exit-if-changed .", self.codemagic_workflow)
        self.assertIn('"$VENV_DIR/bin/python" -m pytest -q -rs', self.codemagic_workflow)
        self.assertIn("python3 tool/test_verify_aab.py", self.codemagic_workflow)
        self.assertIn("--tests com.ciberdefensa.aura.VpnRecoveryGateTest", self.codemagic_workflow)
        # The migration needs AndroidKeyStore; a desktop --tests invocation
        # cannot provide it. Require the real instrumentation task and class.
        self.assertIn(":app:connectedStorageMigrationAndroidTest", self.codemagic_workflow)
        self.assertIn(
            "-Pandroid.testInstrumentationRunnerArguments.class="
            "com.ciberdefensa.aura.SecureStorageMigrationTest",
            self.codemagic_workflow,
        )
        self.assertIn('AURA_REQUIRE_DEVICE_MIGRATION_TESTS: "false"', self.codemagic_workflow)
        self.assertIn('if ! command -v adb >/dev/null 2>&1 || ! adb get-state >/dev/null 2>&1; then', self.codemagic_workflow)
        self.assertIn('AURA_REQUIRE_DEVICE_MIGRATION_TESTS:-false', self.codemagic_workflow)
        self.assertIn('[AURA-VALIDATION][NOT RUN]', self.codemagic_workflow)
        self.assertIn('exit 1', self.codemagic_workflow)
        self.assertNotIn("--tests com.ciberdefensa.aura.SecureStorageMigrationTest", self.codemagic_workflow)

    def test_integrity_retains_real_positive_and_negative_signing_checks(self):
        self.assertIn("python3 tool/test_release_signing_policy.py", self.integrity_workflow)
        self.assertIn("Expected printReleaseSigning to fail without signing variables.", self.integrity_workflow)
        self.assertIn("grep -Fq 'IS_DEBUG_SIGNING=false'", self.integrity_workflow)
        self.assertIn("STORE_FILE=$AURA_KEYSTORE_PATH", self.integrity_workflow)
        self.assertIn("KEY_ALIAS=$AURA_KEY_ALIAS", self.integrity_workflow)
        self.assertNotIn("continue-on-error", self.integrity_workflow)

    def test_release_and_privacy_guides_preserve_honest_limits(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        privacy = (ROOT / "docs/PRIVACY.md").read_text(encoding="utf-8")
        release = (ROOT / "docs/RELEASE_AND_DEVICE_VALIDATION.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("docs/PRIVACY.md", readme)
        self.assertIn("docs/RELEASE_AND_DEVICE_VALIDATION.md", readme)
        self.assertIn("500 eventos", privacy)
        self.assertIn("HMAC-SHA-256", privacy)
        self.assertIn("no demuestra que el reconocimiento permanezca", privacy)
        self.assertIn("AURA_REQUIRE_RELEASE_SIGNING=true", release)
        self.assertIn("NO PROBADO", release)
        self.assertIn("DEBUG de prueba", release)


if __name__ == "__main__":
    unittest.main(verbosity=2)
