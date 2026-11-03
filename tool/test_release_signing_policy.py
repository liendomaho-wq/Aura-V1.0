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

    def test_release_workflow_forbids_debug_fallback(self):
        self.assertGreaterEqual(
            self.release_workflow.count("AURA_REQUIRE_RELEASE_SIGNING: 'true'"),
            2,
        )

    def test_release_signing_report_rejects_missing_credentials(self):
        task = self.gradle.split('tasks.register("printReleaseSigning")', 1)[1]
        self.assertIn("def missingVariables =", task)
        self.assertIn("throw new GradleException", task)


if __name__ == "__main__":
    unittest.main(verbosity=2)
