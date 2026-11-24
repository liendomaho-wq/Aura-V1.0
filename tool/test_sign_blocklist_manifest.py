import base64
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from cryptography.hazmat.primitives import serialization

from tool.sign_blocklist_manifest import (
    generate_key_pair,
    parse_public_keys,
    sign_manifest,
    verify_manifest,
)

PASSWORD = b"correct-horse-battery"


class SignBlocklistManifestTest(unittest.TestCase):
    def setUp(self):
        self._temporary = TemporaryDirectory()
        self.root = Path(self._temporary.name)
        self.private_key = self.root / "private.pem"
        self.public_key = self.root / "public.pem"
        self.manifest = self.root / "manifest.json"
        self.signature = self.root / "manifest.json.sig"
        self.manifest.write_text(
            json.dumps({"feeds": {"urlhaus": {"sha256": "a" * 64}}}),
            encoding="utf-8",
        )
        generate_key_pair(self.private_key, self.public_key, PASSWORD)
        loaded = serialization.load_pem_public_key(self.public_key.read_bytes())
        der = loaded.public_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        self.configured = "aura-test:" + base64.b64encode(der).decode("ascii")
        self.signature.write_text(
            json.dumps(
                sign_manifest(
                    self.manifest,
                    self.private_key,
                    "aura-test",
                    PASSWORD,
                )
            ),
            encoding="utf-8",
        )

    def tearDown(self):
        self._temporary.cleanup()

    def test_verifies_the_exact_manifest_bytes(self):
        self.assertEqual(
            verify_manifest(
                self.manifest,
                self.signature,
                parse_public_keys(self.configured),
            ),
            "aura-test",
        )

    def test_rejects_a_modified_manifest(self):
        self.manifest.write_text('{"feeds":{}}', encoding="utf-8")
        with self.assertRaises(ValueError):
            verify_manifest(
                self.manifest,
                self.signature,
                parse_public_keys(self.configured),
            )

    def test_rejects_an_unknown_key_id(self):
        other = self.root / "other.pem"
        other_public = self.root / "other-public.pem"
        generate_key_pair(other, other_public, PASSWORD)
        loaded = serialization.load_pem_public_key(other_public.read_bytes())
        der = loaded.public_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        with self.assertRaises(ValueError):
            verify_manifest(
                self.manifest,
                self.signature,
                parse_public_keys(
                    "otra:" + base64.b64encode(der).decode("ascii")
                ),
            )

    def test_accepts_two_keys_for_rotation(self):
        second_private = self.root / "second.pem"
        second_public = self.root / "second-public.pem"
        generate_key_pair(second_private, second_public, PASSWORD)
        loaded = serialization.load_pem_public_key(second_public.read_bytes())
        der = loaded.public_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        combined = self.configured + ";nueva:" + base64.b64encode(der).decode(
            "ascii"
        )
        self.assertEqual(
            verify_manifest(
                self.manifest,
                self.signature,
                parse_public_keys(combined),
            ),
            "aura-test",
        )

    def test_rejects_duplicate_key_ids(self):
        with self.assertRaises(ValueError):
            parse_public_keys(f"{self.configured};{self.configured}")


if __name__ == "__main__":
    unittest.main()
