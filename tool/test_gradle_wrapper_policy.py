"""Regression checks for the Android Gradle wrapper download configuration."""

import unittest
from pathlib import Path


class GradleWrapperPolicyTest(unittest.TestCase):
    def test_download_timeout_is_explicit_and_sufficient(self):
        path = Path(__file__).resolve().parents[1] / "android/gradle/wrapper/gradle-wrapper.properties"
        entries = [
            line.strip().split("=", 1)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith(("#", "!")) and "=" in line
        ]
        timeouts = [value.strip() for key, value in entries if key.strip() == "networkTimeout"]
        self.assertEqual(len(timeouts), 1, "Set exactly one wrapper networkTimeout")
        self.assertGreaterEqual(int(timeouts[0]), 120000)


if __name__ == "__main__":
    unittest.main()
