"""Exercise APK symbol verification using real host ELF files, not Android execution."""

import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_apk_jni import ABIS, LIBRARY_REQUIREMENTS, verify_apk


class VerifyApkJniTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def library(self, symbols, suffix="library"):
        source = self.root / f"{suffix}.c"
        shared = self.root / f"{suffix}.so"
        source.write_text("\n".join(f"void {name}(void) {{}}" for name in symbols), encoding="utf-8")
        subprocess.run(["cc", "-shared", "-fPIC", str(source), "-o", str(shared)], check=True)
        return shared.read_bytes()

    def archive(self, libraries, abis=ABIS):
        apk = self.root / "test.apk"
        with zipfile.ZipFile(apk, "w") as output:
            for abi in abis:
                for name, content in libraries.items():
                    output.writestr(f"lib/{abi}/{name}", content)
        return apk

    def complete_libraries(self):
        return {
            name: self.library(symbols, suffix=name.replace(".so", ""))
            for name, symbols in LIBRARY_REQUIREMENTS.items()
        }

    def test_all_required_exports_are_present(self):
        verify_apk(self.archive(self.complete_libraries()))

    def test_missing_export_fails(self):
        libraries = self.complete_libraries()
        llm_name = "libaura_llm.so"
        libraries[llm_name] = self.library(
            LIBRARY_REQUIREMENTS[llm_name] - {"JNI_OnLoad"},
            suffix="llm-missing-onload",
        )
        with self.assertRaisesRegex(ValueError, "JNI_OnLoad"):
            verify_apk(self.archive(libraries))

    def test_missing_llm_bridge_symbol_fails(self):
        libraries = self.complete_libraries()
        llm_name = "libaura_llm.so"
        libraries[llm_name] = self.library(
            LIBRARY_REQUIREMENTS[llm_name] - {"Java_com_ciberdefensa_aura_AuraLlmBridge_nativeStartGeneration"},
            suffix="llm-missing-generation",
        )
        with self.assertRaisesRegex(ValueError, "nativeStartGeneration"):
            verify_apk(self.archive(libraries))

    def test_missing_abi_fails(self):
        with self.assertRaises(KeyError):
            verify_apk(self.archive(self.complete_libraries(), ABIS[:-1]))

    def test_malformed_library_fails(self):
        libraries = self.complete_libraries()
        libraries["libaura_llm.so"] = b"not an ELF library"
        with self.assertRaises(subprocess.CalledProcessError):
            verify_apk(self.archive(libraries))


if __name__ == "__main__":
    unittest.main()
