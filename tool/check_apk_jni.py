"""Exercise APK symbol verification using real host ELF files, not Android execution."""

import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_apk_jni import ABIS, REQUIRED_SYMBOLS, verify_apk


class VerifyApkJniTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def library(self, symbols):
        source = self.root / "library.c"
        shared = self.root / "library.so"
        source.write_text("\n".join(f"void {name}(void) {{}}" for name in symbols), encoding="utf-8")
        subprocess.run(["cc", "-shared", "-fPIC", str(source), "-o", str(shared)], check=True)
        return shared.read_bytes()

    def archive(self, content, abis=ABIS):
        apk = self.root / "test.apk"
        with zipfile.ZipFile(apk, "w") as output:
            for abi in abis:
                output.writestr(f"lib/{abi}/libhev-socks5-tunnel.so", content)
        return apk

    def test_all_required_exports_are_present(self):
        verify_apk(self.archive(self.library(REQUIRED_SYMBOLS)))

    def test_missing_export_fails(self):
        symbols = REQUIRED_SYMBOLS - {"JNI_OnLoad"}
        with self.assertRaisesRegex(ValueError, "JNI_OnLoad"):
            verify_apk(self.archive(self.library(symbols)))

    def test_missing_abi_fails(self):
        with self.assertRaises(KeyError):
            verify_apk(self.archive(self.library(REQUIRED_SYMBOLS), ABIS[:-1]))

    def test_malformed_library_fails(self):
        with self.assertRaises(subprocess.CalledProcessError):
            verify_apk(self.archive(b"not an ELF library"))


if __name__ == "__main__":
    unittest.main()
