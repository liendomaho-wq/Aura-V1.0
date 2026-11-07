#!/usr/bin/env python3
"""Exercise the real HEV DNS handler on host; JNI and logging are test adapters.

The tunnel, Android service, and actual packet delivery still require device tests.
"""
import ctypes
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HEV = ROOT / "android/app/src/main/cpp/hev-socks5-tunnel"


def query(questions):
    packet = struct.pack("!6H", 0x1234, 0x0100, len(questions), 0, 0, 0)
    for domain, qtype in questions:
        for label in domain.split("."):
            encoded = label.encode("ascii")
            packet += bytes([len(encoded)]) + encoded
        packet += b"\0" + struct.pack("!HH", qtype, 1)
    return packet


class MappedDnsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="aura-dns-")
        support = Path(cls.tmp) / "support.c"
        support.write_text(
            """
#include <stdlib.h>
#include <stdint.h>
#include "hev-mapped-dns.h"
void *hev_malloc0(size_t size) { return calloc(1, size); }
void hev_free(void *ptr) { free(ptr); }
void hev_logger_log(int level, const char *fmt, ...) { (void)level; (void)fmt; }
static int events[3];
void reset_events(void) { events[0] = events[1] = events[2] = 0; }
int count_events(int action) { return action >= 0 && action < 3 ? events[action] : -1; }
void hev_jni_report_dns_event(const char *name, int action, uint32_t addr, uint16_t port) {
    (void)name; (void)addr; (void)port;
    if (action >= 0 && action < 3) events[action]++;
}
void release_dns(HevMappedDNS *dns) { hev_object_unref(HEV_OBJECT(dns)); }
""",
            encoding="utf-8",
        )
        output = Path(cls.tmp) / "libmapped_dns.so"
        task = HEV / "third-part/hev-task-system"
        subprocess.run(
            [
                "cc", "-std=gnu11", "-D__ANDROID__", "-shared", "-fPIC", "-pthread",
                "-I", str(HEV / "src"), "-I", str(HEV / "src/misc"),
                "-I", str(HEV / "src/core/include"), "-I", str(task / "include"),
                "-I", str(task / "src"),
                str(HEV / "src/hev-mapped-dns.c"),
                str(HEV / "src/misc/hev-list.c"),
                str(HEV / "src/core/src/hev-rbtree.c"),
                str(task / "src/lib/object/hev-object.c"), str(support),
                "-o", str(output),
            ],
            check=True,
        )
        cls.lib = ctypes.CDLL(str(output))
        cls.lib.hev_mapped_dns_new.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
        cls.lib.hev_mapped_dns_new.restype = ctypes.c_void_p
        cls.lib.hev_mapped_dns_block_domain.argtypes = [ctypes.c_char_p]
        cls.lib.hev_mapped_dns_block_domain.restype = ctypes.c_int
        cls.lib.hev_mapped_dns_handle.argtypes = [
            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p,
            ctypes.c_int, ctypes.c_uint32, ctypes.c_uint16,
        ]
        cls.lib.hev_mapped_dns_handle.restype = ctypes.c_int
        cls.lib.release_dns.argtypes = [ctypes.c_void_p]
        cls.lib.count_events.argtypes = [ctypes.c_int]
        cls.lib.count_events.restype = ctypes.c_int
        if cls.lib.hev_mapped_dns_block_domain(b"blocked.example") != 1:
            raise RuntimeError("could not install test block rule")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def setUp(self):
        self.lib.reset_events()
        self.dns = self.lib.hev_mapped_dns_new(0x64400000, -65536, 256)
        self.assertTrue(self.dns)

    def tearDown(self):
        self.lib.release_dns(self.dns)

    def handle(self, packet):
        response = ctypes.create_string_buffer(2048)
        request = ctypes.create_string_buffer(packet)
        size = self.lib.hev_mapped_dns_handle(
            self.dns, request, len(packet), response, len(response), 0, 0
        )
        return size, response.raw[:max(0, size)]

    def assert_denied_without_answers(self, packet):
        size, response = self.handle(packet)
        self.assertGreaterEqual(size, 12)
        transaction, flags, qd, answers, ns, ar = struct.unpack("!6H", response[:12])
        self.assertEqual(transaction, 0x1234)
        self.assertEqual(flags & 0xF, 3)  # NXDOMAIN, never loopback
        self.assertEqual((answers, ns, ar), (0, 0, 0))
        self.assertEqual(size, len(packet))
        self.assertEqual(qd, struct.unpack("!H", packet[4:6])[0])

    def test_blocked_rule_returns_nxdomain_for_a_aaaa_and_other_types(self):
        for qtype in (1, 28, 15):
            with self.subTest(qtype=qtype):
                self.assert_denied_without_answers(query([("blocked.example", qtype)]))

    def test_heuristic_match_does_not_send_clients_to_loopback(self):
        domain = "abcdefghijklmnopqrstuvwxyz0123456789abcd.example"
        self.assert_denied_without_answers(query([(domain, 1)]))

    def test_mixed_questions_do_not_return_an_answer_with_nxdomain(self):
        for questions in (
            [("allowed.example", 1), ("blocked.example", 1)],
            [("blocked.example", 1), ("allowed.example", 1)],
        ):
            with self.subTest(questions=questions):
                self.lib.reset_events()
                self.assert_denied_without_answers(query(questions))
                self.assertEqual(self.lib.count_events(0), 0)
                self.assertEqual(self.lib.count_events(1), 1)

    def test_allowed_aaaa_remains_a_no_answer_response(self):
        packet = query([("allowed.example", 28)])
        size, response = self.handle(packet)
        self.assertEqual(size, len(packet))
        _, flags, _, answers, _, _ = struct.unpack("!6H", response[:12])
        self.assertEqual(flags & 0xF, 0)
        self.assertEqual(answers, 0)

    def test_allowed_a_is_mapped_for_forwarding(self):
        packet = query([("allowed.example", 1)])
        size, response = self.handle(packet)
        self.assertGreater(size, len(packet))
        _, flags, _, answers, _, _ = struct.unpack("!6H", response[:12])
        self.assertEqual(flags & 0xF, 0)
        self.assertEqual(answers, 1)
        self.assertEqual(response[-4:-2], b"\x64\x40")

    def test_truncated_question_is_rejected(self):
        size, _ = self.handle(query([("allowed.example", 1)])[:-1])
        self.assertEqual(size, -1)


if __name__ == "__main__":
    unittest.main()
