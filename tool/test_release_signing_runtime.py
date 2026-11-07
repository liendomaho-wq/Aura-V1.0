#!/usr/bin/env python3
"""Exercise release signer decisions using fake tool outputs, not real APKs.

This tests the shell control flow; real APK signatures still need apksigner in
CI and a production keystore. Temporary files never touch the project build.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SigningRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aura-signing-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tool").mkdir()
        shutil.copy(ROOT / "tool/compile_aura.sh", self.root / "tool/compile_aura.sh")
        shutil.copy(ROOT / "tool/VerifyAab.java", self.root / "tool/VerifyAab.java")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self._tool("keytool", '#!/bin/sh\nprintf "Owner: CN=Aura Release\\nSHA256: %s\\n" "$KEY_DIGEST"\n')
        self._tool("java", '''#!/bin/sh
case "$1" in */tool/VerifyAab.java) ;; *) exit 9;; esac
[ "$3" = "$KEY_DIGEST" ] || exit 8
[ "${AAB_VERIFY_FAIL:-0}" = 0 ] || exit 1
printf "CERT_SHA256=%s\\n" "$KEY_DIGEST"
''')
        self._tool("apksigner", '''#!/bin/sh
if [ "${SIGNER_FAIL:-0}" = 1 ]; then exit 1; fi
printf "Signer #1 certificate DN: CN=Aura Release\\n"
printf "Signer #1 certificate SHA-256 digest: %s\\n" "$APK_DIGEST"
if [ "${MULTIPLE_SIGNERS:-0}" = 1 ]; then
  printf "Signer #2 certificate SHA-256 digest: %s\\n" "$APK_DIGEST"
fi
''')
        self.keystore = self.root / "test.keystore"
        self.keystore.write_bytes(b"test-only-not-a-real-keystore")
        artifact = self.root / "build/app/outputs/flutter-apk/app-release.apk"
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b"test-only-not-a-real-apk")
        self.env = os.environ.copy()
        for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT", "AURA_KEYSTORE_BASE64", "AURA_ALLOW_DEBUG_SIGNING"):
            self.env.pop(name, None)
        self.env.update({
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "AURA_REQUIRE_RELEASE_SIGNING": "true",
            "AURA_KEYSTORE_PATH": str(self.keystore),
            "AURA_STORE_PASSWORD": "test-only",
            "AURA_KEY_ALIAS": "test-only",
            "AURA_KEY_PASSWORD": "test-only",
            "KEY_DIGEST": "A" * 64,
            "APK_DIGEST": "A" * 64,
        })

    def _tool(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def verify(self, **variables):
        env = {**self.env, **variables}
        return subprocess.run(
            ["bash", str(self.root / "tool/compile_aura.sh"), "--verify-artifact"],
            cwd=self.root, env=env, text=True, capture_output=True,
        )

    def test_matching_configured_signer_passes(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CERT_SHA256=" + "A" * 64, result.stdout)

    def test_different_signer_fails(self):
        result = self.verify(APK_DIGEST="B" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)

    def test_multiple_signers_fail(self):
        result = self.verify(MULTIPLE_SIGNERS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exactly one", result.stderr)

    def test_invalid_apk_fails(self):
        result = self.verify(SIGNER_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("apksigner rejected", result.stderr)

    def test_missing_apksigner_fails_closed(self):
        (self.bin / "apksigner").unlink()
        result = self.verify(PATH=f"{self.bin}:/usr/bin:/bin")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("apksigner is required", result.stderr)

    def test_aab_requires_successful_archive_verifier(self):
        artifact = self.root / "build/app/outputs/bundle/release/app-release.aab"
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b"test-only-not-a-real-bundle")
        result = self.verify(AURA_BUILD_FORMAT="aab", AAB_VERIFY_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("AAB signature verification failed", result.stderr)
        result = self.verify(AURA_BUILD_FORMAT="aab")
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
