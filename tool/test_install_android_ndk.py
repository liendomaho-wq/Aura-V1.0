"""Check the CodeMagic NDK preflight without downloading an Android SDK."""

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tool/install_android_ndk.sh"


class InstallAndroidNdkTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.sdk = Path(self.temp.name) / "sdk"
        self.sdk.mkdir()
        self.env = dict(os.environ, ANDROID_SDK_ROOT=str(self.sdk), ANDROID_HOME=str(self.sdk))
        gradle = (ROOT / "android/app/build.gradle").read_text(encoding="utf-8")
        versions = re.findall(r'^\s*ndkVersion\s+"([^"]+)"', gradle, re.MULTILINE)
        self.assertEqual(len(versions), 1)
        self.version = versions[0]

    def run_script(self):
        return subprocess.run(["bash", str(SCRIPT)], env=self.env, text=True, capture_output=True)

    def test_installs_declared_version_and_checks_executable(self):
        manager = self.sdk / "cmdline-tools/latest/bin/sdkmanager"
        manager.parent.mkdir(parents=True)
        manager.write_text(
            '#!/usr/bin/env bash\nset -eu\n'
            'printf "%s\\n" "$@" > "$ANDROID_SDK_ROOT/arguments"\n'
            f'mkdir -p "$ANDROID_SDK_ROOT/ndk/{self.version}"\n'
            f'touch "$ANDROID_SDK_ROOT/ndk/{self.version}/ndk-build"\n'
            f'chmod +x "$ANDROID_SDK_ROOT/ndk/{self.version}/ndk-build"\n'
            f'echo "Pkg.Revision = {self.version}" > "$ANDROID_SDK_ROOT/ndk/{self.version}/source.properties"\n',
            encoding="utf-8",
        )
        manager.chmod(0o755)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.sdk / "arguments").read_text().splitlines(),
                         [f"--sdk_root={self.sdk}", f"ndk;{self.version}"])

    def test_existing_ndk_does_not_require_sdkmanager(self):
        executable = self.sdk / "ndk" / self.version / "ndk-build"
        executable.parent.mkdir(parents=True)
        executable.touch(mode=0o755)
        (executable.parent / "source.properties").write_text(
            f"Pkg.Revision = {self.version}\n", encoding="utf-8"
        )
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_missing_or_wrong_revision(self):
        executable = self.sdk / "ndk" / self.version / "ndk-build"
        executable.parent.mkdir(parents=True)
        executable.touch(mode=0o755)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("metadata is missing", result.stderr)
        (executable.parent / "source.properties").write_text(
            "Pkg.Revision = 0.0.0\n", encoding="utf-8"
        )
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)

    def test_sdkmanager_success_without_ndk_is_rejected(self):
        manager = self.sdk / "cmdline-tools/latest/bin/sdkmanager"
        manager.parent.mkdir(parents=True)
        manager.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        manager.chmod(0o755)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not provide an executable", result.stderr)

    def test_sdkmanager_failure_is_not_hidden(self):
        manager = self.sdk / "cmdline-tools/latest/bin/sdkmanager"
        manager.parent.mkdir(parents=True)
        manager.write_text("#!/usr/bin/env bash\nexit 42\n", encoding="utf-8")
        manager.chmod(0o755)
        self.assertEqual(self.run_script().returncode, 42)

    def test_rejects_conflicting_sdk_roots(self):
        other = Path(self.temp.name) / "other"
        other.mkdir()
        self.env["ANDROID_HOME"] = str(other)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("disagree", result.stderr)


if __name__ == "__main__":
    unittest.main()
