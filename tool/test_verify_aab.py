#!/usr/bin/env python3
"""Real signed-JAR tests for the production AAB verifier.

Fixtures use ephemeral self-signed certificates and OpenSSL; they are minimal
signed JARs, not Android-built AABs. Android build validation remains required.
"""
import base64
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def digest(data):
    return base64.b64encode(hashlib.sha256(data).digest()).decode("ascii")


@unittest.skipUnless(all(shutil.which(tool) for tool in ("java", "javac", "openssl")), "JDK and OpenSSL are required")
class AabVerifierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="aura-aab-test-")
        cls.root = Path(cls.temp.name)
        run("javac", "-d", str(cls.root), str(ROOT / "tool/VerifyAab.java"))
        for index in (1, 2):
            run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                "-subj", f"/CN=Aura Test {index}", "-keyout", str(cls.root / f"key{index}.pem"),
                "-out", str(cls.root / f"cert{index}.pem"))
        cert = run("openssl", "x509", "-in", str(cls.root / "cert1.pem"), "-outform", "DER").stdout
        cls.fingerprint = hashlib.sha256(cert).hexdigest().upper()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def build_bundle(self, *, tamper=False, unsigned=False, duplicate=False,
                     two_signers=False, unsigned_meta=False, bad_signature=False):
        payloads = {"base/manifest/AndroidManifest.xml": b"test-manifest", "base/dex/classes.dex": b"test-dex"}
        manifest = b"Manifest-Version: 1.0\r\n\r\n"
        sections = {}
        for name, data in payloads.items():
            section = f"Name: {name}\r\nSHA-256-Digest: {digest(data)}\r\n\r\n".encode("ascii")
            sections[name] = section
            manifest += section
        signature_file = f"Signature-Version: 1.0\r\nSHA-256-Digest-Manifest: {digest(manifest)}\r\n\r\n".encode("ascii")
        for name, section in sections.items():
            signature_file += f"Name: {name}\r\nSHA-256-Digest: {digest(section)}\r\n\r\n".encode("ascii")
        sf_path = self.root / "signature.sf"
        sf_path.write_bytes(signature_file)
        signatures = []
        for index in (1, 2) if two_signers else (1,):
            sig = run("openssl", "cms", "-sign", "-binary", "-in", str(sf_path),
                      "-signer", str(self.root / f"cert{index}.pem"), "-inkey", str(self.root / f"key{index}.pem"),
                      "-outform", "DER", "-nosmimecap", "-md", "sha256").stdout
            signatures.append((index, sig))
        path = self.root / "fixture.aab"
        with warnings.catch_warnings(), zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            warnings.simplefilter("ignore", UserWarning)
            archive.writestr("META-INF/MANIFEST.MF", manifest)
            for index, sig in signatures:
                archive.writestr(f"META-INF/TEST{index}.SF", signature_file)
                archive.writestr(f"META-INF/TEST{index}.RSA", b"corrupted" if bad_signature else sig)
            for name, data in payloads.items():
                archive.writestr(name, b"altered" if tamper and name.endswith("classes.dex") else data)
            if unsigned:
                archive.writestr("base/assets/unsigned.bin", b"untrusted")
            if unsigned_meta:
                archive.writestr("META-INF/services/example.Service", b"untrusted")
            if duplicate:
                archive.writestr("base/dex/classes.dex", b"duplicate")
        return path

    def verify(self, path, fingerprint=None):
        return subprocess.run(["java", "-cp", str(self.root), "VerifyAab", str(path), fingerprint or self.fingerprint],
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def test_valid_signed_archive_passes(self):
        result = self.verify(self.build_bundle())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("AAB_SIGNED_ENTRIES=2", result.stdout)

    def test_tampered_entry_is_rejected(self):
        self.assertNotEqual(self.verify(self.build_bundle(tamper=True)).returncode, 0)

    def test_unsigned_entry_is_rejected(self):
        self.assertNotEqual(self.verify(self.build_bundle(unsigned=True)).returncode, 0)

    def test_unsigned_nested_metadata_is_rejected(self):
        self.assertNotEqual(self.verify(self.build_bundle(unsigned_meta=True)).returncode, 0)

    def test_corrupted_signature_is_rejected(self):
        self.assertNotEqual(self.verify(self.build_bundle(bad_signature=True)).returncode, 0)

    def test_duplicate_entry_is_rejected(self):
        self.assertNotEqual(self.verify(self.build_bundle(duplicate=True)).returncode, 0)

    def test_unexpected_signer_is_rejected(self):
        self.assertNotEqual(self.verify(self.build_bundle(), "0" * 64).returncode, 0)

    def test_multiple_signers_are_rejected(self):
        self.assertNotEqual(self.verify(self.build_bundle(two_signers=True)).returncode, 0)


if __name__ == "__main__":
    if not all(shutil.which(tool) for tool in ("java", "javac", "openssl")):
        raise SystemExit("JDK 17 (java and javac) and OpenSSL are required for AAB signature tests")
    unittest.main(verbosity=2)
