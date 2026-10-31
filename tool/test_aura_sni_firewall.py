import ctypes
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path



def _extension(extension_type, data):
    return extension_type.to_bytes(2, "big") + len(data).to_bytes(2, "big") + data


def _client_hello(extensions):
    body = (
        b"\x03\x03"
        + bytes(range(32))
        + b"\x00"
        + b"\x00\x02\x13\x01"
        + b"\x01\x00"
        + len(extensions).to_bytes(2, "big")
        + extensions
    )
    handshake = b"\x01" + len(body).to_bytes(3, "big") + body
    return b"\x16\x03\x01" + len(handshake).to_bytes(2, "big") + handshake


def _inspect(library, client_hello):
    packet = (ctypes.c_uint8 * len(client_hello)).from_buffer_copy(client_hello)
    output = ctypes.create_string_buffer(254)
    result = library.aura_inspect_tls_sni(
        packet, len(client_hello), output, len(output)
    )
    return result, output.value.decode("ascii")


def _sni_client_hello(hostname):
    encoded_hostname = hostname.encode("ascii")
    names = b"\\x00" + len(encoded_hostname).to_bytes(2, "big") + encoded_hostname
    server_name = len(names).to_bytes(2, "big") + names
    return _client_hello(_extension(0x0000, server_name))


class AuraSniFirewallTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp(prefix="aura-sni-")
        root = Path(__file__).resolve().parents[1]
        source = root / "android/app/src/main/cpp/aura_sni_firewall.c"
        include = root / "android/app/src/main/cpp"
        output = Path(cls.temp_dir) / "libaura_sni.so"
        subprocess.run(
            [
                "gcc",
                "-std=c11",
                "-shared",
                "-fPIC",
                "-pthread",
                f"-I{include}",
                str(source),
                "-o",
                str(output),
            ],
            check=True,
        )
        cls.library = ctypes.CDLL(str(output))
        cls.library.aura_inspect_tls_sni.argtypes = [
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_uint32,
            ctypes.c_char_p,
            ctypes.c_size_t,
        ]
        cls.library.aura_inspect_tls_sni.restype = ctypes.c_int
        cls.library.aura_add_dynamic_sni_rule.argtypes = [ctypes.c_char_p]
        cls.library.aura_add_dynamic_sni_rule.restype = ctypes.c_int

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.temp_dir)

    def test_client_hello_with_ech_returns_ech_code(self):
        ech_payload = b"\x00\x01\x00\x00\x00\x01\x01\x00\x00\x10ciphertext"
        packet = _client_hello(_extension(0xFE0D, ech_payload))

        result, marker = _inspect(self.library, packet)

        self.assertEqual(result, 4)
        self.assertEqual(marker, "[ECH]")

    def test_client_hello_with_sni_and_without_ech_remains_allowed(self):
        hostname = b"example.com"
        names = b"\x00" + len(hostname).to_bytes(2, "big") + hostname
        server_name = len(names).to_bytes(2, "big") + names
        packet = _client_hello(_extension(0x0000, server_name))

        result, host = _inspect(self.library, packet)

        self.assertEqual(result, 1)
        self.assertEqual(host, "example.com")


if __name__ == "__main__":
    unittest.main()