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


def _sni_client_hello(hostname):
    encoded = hostname.encode("ascii")
    names = b"\x00" + len(encoded).to_bytes(2, "big") + encoded
    server_name = len(names).to_bytes(2, "big") + names
    return _client_hello(_extension(0x0000, server_name))


def _inspect(library, packet):
    source = (ctypes.c_uint8 * len(packet)).from_buffer_copy(packet)
    output = ctypes.create_string_buffer(254)
    result = library.aura_inspect_tls_sni(source, len(packet), output, len(output))
    return result, output.value.decode("ascii")


class _AuraTlsSniStream(ctypes.Structure):
    _fields_ = [
        ("data", ctypes.POINTER(ctypes.c_uint8)),
        ("length", ctypes.c_size_t),
        ("capacity", ctypes.c_size_t),
    ]


class AuraSniFirewallTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp(prefix="aura-sni-")
        root = Path(__file__).resolve().parents[1]
        source = root / "android/app/src/main/cpp/aura_sni_firewall.c"
        output = Path(cls.temp_dir) / "libaura_sni.so"
        subprocess.run(
            [
                "gcc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                "-shared", "-fPIC", "-pthread", str(source), "-o", str(output),
            ],
            check=True,
        )
        cls.library = ctypes.CDLL(str(output))
        cls.library.aura_inspect_tls_sni.argtypes = [
            ctypes.POINTER(ctypes.c_uint8), ctypes.c_uint32,
            ctypes.c_char_p, ctypes.c_size_t,
        ]
        cls.library.aura_inspect_tls_sni.restype = ctypes.c_int
        cls.library.aura_tls_sni_stream_init.argtypes = [
            ctypes.POINTER(_AuraTlsSniStream),
        ]
        cls.library.aura_tls_sni_stream_dispose.argtypes = [
            ctypes.POINTER(_AuraTlsSniStream),
        ]
        cls.library.aura_tls_sni_stream_append.argtypes = [
            ctypes.POINTER(_AuraTlsSniStream),
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_size_t,
            ctypes.c_char_p,
            ctypes.c_size_t,
        ]
        cls.library.aura_tls_sni_stream_append.restype = ctypes.c_int
        cls.library.aura_add_dynamic_sni_rule.argtypes = [ctypes.c_char_p]
        cls.library.aura_add_dynamic_sni_rule.restype = ctypes.c_int
        cls.library.aura_set_dynamic_sni_allowlist.argtypes = [
            ctypes.POINTER(ctypes.c_char_p), ctypes.c_size_t,
        ]
        cls.library.aura_set_dynamic_sni_allowlist.restype = ctypes.c_int
        cls.library.aura_is_encrypted_dns_transport.argtypes = [
            ctypes.c_uint8, ctypes.c_uint16, ctypes.c_bool,
        ]
        cls.library.aura_is_encrypted_dns_transport.restype = ctypes.c_bool

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.temp_dir)

    def test_dot_tcp_853_and_doq_udp_853_are_filtered(self):
        policy = self.library.aura_is_encrypted_dns_transport
        self.assertTrue(policy(6, 853, False))
        self.assertTrue(policy(17, 853, False))
        self.assertFalse(policy(6, 443, True))
        self.assertFalse(policy(17, 53, True))

    def test_known_doh_resolvers_are_filtered_only_on_udp_443(self):
        policy = self.library.aura_is_encrypted_dns_transport
        self.assertTrue(policy(17, 443, True))
        self.assertFalse(policy(17, 443, False))
        self.assertFalse(policy(6, 443, True))

    def test_ech_is_reported_without_claiming_it_was_decrypted(self):
        packet = _client_hello(_extension(0xFE0D, b"encrypted-client-hello"))
        result, marker = _inspect(self.library, packet)
        self.assertEqual(result, 4)
        self.assertEqual(marker, "[ECH]")

    def test_normal_sni_is_observed_and_allowed_by_default(self):
        result, host = _inspect(self.library, _sni_client_hello("Example.COM"))
        self.assertEqual(result, 1)
        self.assertEqual(host, "example.com")

    def test_dynamic_rule_blocks_exact_domain_and_subdomains(self):
        self.assertEqual(
            self.library.aura_add_dynamic_sni_rule(b"malicious.example"), 1
        )
        for hostname in ("malicious.example", "login.malicious.example"):
            with self.subTest(hostname=hostname):
                result, host = _inspect(self.library, _sni_client_hello(hostname))
                self.assertEqual(result, 2)
                self.assertEqual(host, hostname)

    def test_fragmented_tcp_client_hello_is_reassembled_and_blocked(self):
        self.assertEqual(
            self.library.aura_add_dynamic_sni_rule(b"fragmented.blocked.example"),
            1,
        )
        hello = _sni_client_hello("fragmented.blocked.example")
        split_at = len(hello) // 2
        stream = _AuraTlsSniStream()
        self.library.aura_tls_sni_stream_init(ctypes.byref(stream))
        try:
            first = (ctypes.c_uint8 * split_at).from_buffer_copy(hello[:split_at])
            second_payload = hello[split_at:]
            second = (ctypes.c_uint8 * len(second_payload)).from_buffer_copy(
                second_payload
            )
            hostname = ctypes.create_string_buffer(254)

            first_result = self.library.aura_tls_sni_stream_append(
                ctypes.byref(stream), first, len(first), hostname, len(hostname)
            )
            self.assertEqual(first_result, 0)
            self.assertEqual(stream.length, split_at)

            second_result = self.library.aura_tls_sni_stream_append(
                ctypes.byref(stream), second, len(second), hostname, len(hostname)
            )
            self.assertEqual(second_result, 2)
            self.assertEqual(hostname.value.decode("ascii"), "fragmented.blocked.example")
        finally:
            self.library.aura_tls_sni_stream_dispose(ctypes.byref(stream))

    def test_complete_blocked_client_hello_returns_block_decision(self):
        self.assertEqual(
            self.library.aura_add_dynamic_sni_rule(b"single.blocked.example"),
            1,
        )
        hello = _sni_client_hello("single.blocked.example")
        payload = (ctypes.c_uint8 * len(hello)).from_buffer_copy(hello)
        stream = _AuraTlsSniStream()
        self.library.aura_tls_sni_stream_init(ctypes.byref(stream))
        try:
            hostname = ctypes.create_string_buffer(254)
            result = self.library.aura_tls_sni_stream_append(
                ctypes.byref(stream), payload, len(payload), hostname,
                len(hostname),
            )
            self.assertEqual(result, 2)
            self.assertEqual(hostname.value.decode("ascii"), "single.blocked.example")
        finally:
            self.library.aura_tls_sni_stream_dispose(ctypes.byref(stream))

    def test_blocked_stream_is_wired_to_tcp_abort_and_block_event(self):
        root = Path(__file__).resolve().parents[1]
        source = (
            root
            / "android/app/src/main/cpp/hev-socks5-tunnel/src/hev-socks5-session-tcp.c"
        ).read_text(encoding="utf-8")
        receive_handler = source.split("tcp_recv_handler (", 1)[1].split(
            "tcp_sent_handler (", 1
        )[0]
        inspect_handler = source.split("tls_inspection_append (", 1)[1].split(
            "abort_tcp_session (", 1
        )[0]
        abort_handler = source.split("abort_tcp_session (", 1)[1].split(
            "#endif", 1
        )[0]

        self.assertIn("tls_inspection_append (self, p) < 0", receive_handler)
        self.assertIn("report_blocked_sni (self, sni)", inspect_handler)
        self.assertIn(
            "result == AURA_TLS_SNI_BLOCKED ||\n        result == AURA_TLS_SNI_MALFORMED",
            inspect_handler,
        )
        self.assertIn("aura_tls_sni_stream_append (&self->tls_inspection", inspect_handler)
        self.assertIn("abort_tcp_session (self);", receive_handler)
        self.assertIn(
            "hev_socks5_session_terminate (HEV_SOCKS5_SESSION (self));",
            receive_handler,
        )
        self.assertIn("return ERR_ABRT;", receive_handler)
        self.assertIn("tcp_abort (pcb);", abort_handler)
        self.assertIn("hev_jni_report_dns_event (sni, 3", source)

    def test_dynamic_rule_does_not_block_lookalike_suffix(self):
        self.assertEqual(
            self.library.aura_add_dynamic_sni_rule(b"trusted.example"), 1
        )
        result, host = _inspect(
            self.library, _sni_client_hello("nottrusted.example")
        )
        self.assertEqual(result, 1)
        self.assertEqual(host, "nottrusted.example")

    def test_allowlist_takes_precedence_over_block_rule(self):
        self.assertEqual(
            self.library.aura_add_dynamic_sni_rule(b"allow.example"), 1
        )
        values = (ctypes.c_char_p * 1)(b"allow.example")
        self.assertEqual(
            self.library.aura_set_dynamic_sni_allowlist(values, 1), 1
        )
        result, host = _inspect(
            self.library, _sni_client_hello("login.allow.example")
        )
        self.assertEqual(result, 1)
        self.assertEqual(host, "login.allow.example")

    def test_invalid_dynamic_rule_is_rejected(self):
        self.assertEqual(
            self.library.aura_add_dynamic_sni_rule(b"-invalid.example"), -1
        )
        self.assertEqual(
            self.library.aura_add_dynamic_sni_rule(b"bad..example"), -1
        )

    def test_truncated_client_hello_is_incomplete_not_allowed(self):
        packet = _sni_client_hello("example.com")[:-3]
        result, _ = _inspect(self.library, packet)
        self.assertEqual(result, 0)

    def test_malformed_sni_extension_is_rejected(self):
        malformed = b"\x00\x08\x00\x00\x00\x04\x00\x00\x00\x00"
        result, _ = _inspect(
            self.library, _client_hello(_extension(0x0000, malformed))
        )
        self.assertEqual(result, 3)


if __name__ == "__main__":
    unittest.main()
