#!/usr/bin/env python3
"""Tests of the actual packaged model, digest and RSA verification gate."""
import base64
import hashlib
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))
from verify_packaged_model import DIGEST, MODEL, SIGNATURE, verify_packaged_model


class PackagedModelVerificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="aura-model-tests-")
        cls.tmp = Path(cls.temp.name)
        source = (ROOT / "lib/crypto/aura_crypto_layer.dart").read_text(encoding="utf-8")
        match = re.search(r"defaultValue:\s*'([A-Za-z0-9+/=]+)'", source)
        if not match:
            raise RuntimeError("No se encontró la clave pública predeterminada.")
        cls.key_base64 = match.group(1)
        cls.key = cls.tmp / "public.der"
        cls.key.write_bytes(base64.b64decode(cls.key_base64, validate=True))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_packaged_model_matches_default_public_key_and_digest(self):
        verify_packaged_model(self.key)
        result = subprocess.run(
            [sys.executable, str(ROOT / "tool/verify_packaged_model.py"),
             "--public-key-der", str(self.key)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_build_fallback_key_matches_runtime_default(self):
        script = (ROOT / "tool/compile_aura.sh").read_text(encoding="utf-8")
        match = re.search(r"AURA_PUBLIC_KEY_ENV='([A-Za-z0-9+/=]+)'", script)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), self.key_base64)
        self.assertIn('verify_packaged_model.py" --public-key-der "$key_file"', script)

    def test_modified_model_is_rejected_even_if_its_digest_is_replaced(self):
        model = self.tmp / "changed-model.json"
        model.write_bytes(MODEL.read_bytes() + b" ")
        digest = self.tmp / "changed.sha256"
        digest.write_text(hashlib.sha256(model.read_bytes()).hexdigest(), encoding="ascii")
        with self.assertRaises(ValueError):
            verify_packaged_model(self.key, model, digest, SIGNATURE)

    def test_modified_signature_is_rejected(self):
        signature = self.tmp / "changed.sig"
        data = bytearray(SIGNATURE.read_bytes())
        data[0] ^= 1
        signature.write_bytes(data)
        with self.assertRaises(ValueError):
            verify_packaged_model(self.key, MODEL, DIGEST, signature)

    def test_mismatched_rsa_key_is_rejected(self):
        private_key = self.tmp / "other-private.pem"
        public_key = self.tmp / "other-public.der"
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
             "-out", str(private_key)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", str(private_key), "-pubout", "-outform", "DER",
             "-out", str(public_key)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        with self.assertRaises(ValueError):
            verify_packaged_model(public_key)

    def test_malformed_digest_or_short_signature_is_rejected(self):
        digest = self.tmp / "invalid.sha256"
        digest.write_text("not-a-sha256", encoding="ascii")
        signature = self.tmp / "short.sig"
        signature.write_bytes(b"short")
        with self.assertRaises(ValueError):
            verify_packaged_model(self.key, MODEL, digest, SIGNATURE)
        with self.assertRaises(ValueError):
            verify_packaged_model(self.key, MODEL, DIGEST, signature)


if __name__ == "__main__":
    unittest.main()
