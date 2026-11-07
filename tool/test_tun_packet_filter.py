#!/usr/bin/env python3
"""Host tests for HEV's actual TUN packet classifier and lwIP pbuf copying.

The test compiles the production C file into a small adapter and exercises its
static parser with real lwIP pbuf_copy_partial, including chained pbufs. It
does not run Android, the TUN reader, or lwIP's full IP reassembly pipeline.
"""
import ctypes
import ipaddress
import platform
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CPP = ROOT / "android/app/src/main/cpp"
HEV = CPP / "hev-socks5-tunnel"


def transport(port):
    return struct.pack("!HHI", 12345, port, 0)


def ipv4(protocol, payload, destination="1.1.1.1", fragment=0, options=b""):
    if len(options) % 4 or len(options) > 40:
        raise ValueError("invalid IPv4 options")
    length = 20 + len(options) + len(payload)
    header = bytearray(20)
    header[0] = 0x40 | ((20 + len(options)) // 4)
    header[2:4] = struct.pack("!H", length)
    header[6:8] = struct.pack("!H", fragment)
    header[8] = 64
    header[9] = protocol
    header[12:16] = ipaddress.IPv4Address("192.0.2.1").packed
    header[16:20] = ipaddress.IPv4Address(destination).packed
    return bytes(header) + options + payload


def ipv6(next_header, payload, destination="2606:4700:4700::1111"):
    header = bytearray(40)
    header[0] = 0x60
    header[4:6] = struct.pack("!H", len(payload))
    header[6] = next_header
    header[7] = 64
    header[8:24] = ipaddress.IPv6Address("2001:db8::1").packed
    header[24:40] = ipaddress.IPv6Address(destination).packed
    return bytes(header) + payload


def extension_chain(count, end_protocol=6):
    return b"".join(
        bytes([end_protocol if i == count - 1 else 60, 0]) + bytes(6)
        for i in range(count)
    )


class TunPacketFilterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="aura-tun-parser-")
        harness = Path(cls.tmp) / "harness.c"
        harness.write_text(
            r'''
/* The host build lacks __ANDROID__; import the production policy declaration
 * explicitly. The classifier and lwIP implementation below are unchanged. */
#include "aura_sni_firewall.h"
#include "hev-socks5-tunnel.c"

__attribute__((visibility("default")))
int test_packet(const uint8_t *data, uint16_t length, uint16_t split,
                char *address, uint16_t *port, int *protocol) {
    struct pbuf first = {0}, second = {0};
    const char *transport = NULL;
    int result;
    if (split > length) return -1;
    first.payload = (void *)data;
    first.len = split;
    first.tot_len = length;
    if (split < length) {
        second.payload = (void *)(data + split);
        second.len = second.tot_len = length - split;
        first.next = &second;
    }
    *port = 0;
    *protocol = 0;
    result = packet_is_encrypted_dns(&first, address, INET6_ADDRSTRLEN,
                                     port, &transport);
    if (transport) *protocol = strcmp(transport, "TCP") == 0 ? 6 : 17;
    return result;
}
__attribute__((visibility("default"))) int ipv4_reassembly(void) { return IP_REASSEMBLY; }
__attribute__((visibility("default"))) int ipv6_reassembly(void) { return LWIP_IPV6_REASS; }
''',
            encoding="utf-8",
        )
        output = Path(cls.tmp) / "libtun_filter.so"
        includes = [
            HEV / "src", CPP, HEV / "src/misc", HEV / "src/core/include",
            HEV / "third-part/yaml/include", HEV / "third-part/lwip/src/include",
            HEV / "third-part/lwip/src/ports/include", HEV / "third-part/hev-task-system/include",
        ]
        linker_gc = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        command = [
            "cc", "-std=gnu11", "-DFD_SET_DEFINED",
            "-DSOCKLEN_T_DEFINED", "-DENABLE_LIBRARY", "-fPIC", "-fvisibility=hidden",
            "-ffunction-sections", "-fdata-sections", "-shared", linker_gc, "-pthread",
        ]
        for include in includes:
            command += ["-I", str(include)]
        command += [
            str(harness), str(CPP / "aura_sni_firewall.c"),
            str(HEV / "third-part/lwip/src/core/pbuf.c"), "-o", str(output),
        ]
        subprocess.run(command, check=True)
        cls.lib = ctypes.CDLL(str(output))
        cls.lib.test_packet.argtypes = [
            ctypes.c_void_p, ctypes.c_uint16, ctypes.c_uint16, ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_uint16), ctypes.POINTER(ctypes.c_int),
        ]
        cls.lib.test_packet.restype = ctypes.c_int
        cls.lib.ipv4_reassembly.restype = ctypes.c_int
        cls.lib.ipv6_reassembly.restype = ctypes.c_int

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def classify(self, packet, split=None):
        split = len(packet) if split is None else split
        raw = ctypes.create_string_buffer(packet)
        address = ctypes.create_string_buffer(46)
        port = ctypes.c_uint16()
        protocol = ctypes.c_int()
        result = self.lib.test_packet(raw, len(packet), split, address, ctypes.byref(port), ctypes.byref(protocol))
        return result, address.value.decode("ascii"), port.value, protocol.value

    def test_known_encrypted_dns_ports_and_addresses(self):
        cases = [
            (ipv4(6, transport(853), "192.0.2.20"), "192.0.2.20", 853, 6),
            (ipv4(17, transport(853), "192.0.2.20"), "192.0.2.20", 853, 17),
            (ipv4(17, transport(443)), "1.1.1.1", 443, 17),
            (ipv6(17, transport(443)), "2606:4700:4700::1111", 443, 17),
            (ipv6(6, transport(853), "2001:db8::2"), "2001:db8::2", 853, 6),
        ]
        for packet, address, port, protocol in cases:
            with self.subTest(address=address, port=port, protocol=protocol):
                self.assertEqual(self.classify(packet), (1, address, port, protocol))

    def test_other_traffic_is_not_classified_as_encrypted_dns(self):
        cases = [ipv4(6, transport(443)), ipv4(17, transport(443), "192.0.2.20"),
                 ipv4(17, transport(53)), ipv6(17, transport(443), "2001:db8::2")]
        for packet in cases:
            with self.subTest(packet=packet.hex()):
                self.assertEqual(self.classify(packet)[0], 0)

    def test_parser_handles_chained_pbufs_and_ipv4_options(self):
        packet = ipv4(6, transport(853), options=bytes(12))
        for split in (1, 7, 19, 20, 29, 32, 33, 35, len(packet)):
            with self.subTest(split=split):
                self.assertEqual(self.classify(packet, split), (1, "1.1.1.1", 853, 6))
        packet6 = ipv6(60, extension_chain(2) + transport(853))
        for split in (1, 24, 39, 40, 47, 55, 57, len(packet6)):
            with self.subTest(split=split):
                self.assertEqual(self.classify(packet6, split)[0], 1)

    def test_declared_packet_lengths_never_expose_trailing_bytes(self):
        original = ipv4(6, transport(853))
        for packet in (original[:22], original[:2] + b"\x00\x16" + original[4:],
                       original[:2] + b"\x01\x00" + original[4:]):
            with self.subTest(packet=packet.hex()):
                self.assertEqual(self.classify(packet)[0], 0)
        original6 = ipv6(6, transport(853))
        for payload_len in (0, 2, 255):
            packet = original6[:4] + struct.pack("!H", payload_len) + original6[6:]
            with self.subTest(payload_len=payload_len):
                self.assertEqual(self.classify(packet)[0], 0)

    def test_fragment_headers_are_not_misread_as_ports(self):
        self.assertEqual(self.classify(ipv4(6, transport(853), fragment=0x2000))[0], 1)
        self.assertEqual(self.classify(ipv4(6, transport(853), fragment=1))[0], 0)
        first = bytes([6, 0, 0, 1, 0, 0, 0, 1]) + transport(853)
        later = bytes([6, 0, 0, 8, 0, 0, 0, 1]) + transport(853)
        atomic = bytes([6, 0, 0, 0, 0, 0, 0, 1]) + transport(853)
        self.assertEqual(self.classify(ipv6(44, first))[0], 1)
        self.assertEqual(self.classify(ipv6(44, later))[0], 0)
        self.assertEqual(self.classify(ipv6(44, atomic))[0], 1)

    def test_excessive_extension_chains_fail_closed(self):
        self.assertEqual(self.classify(ipv6(60, extension_chain(8) + transport(853)))[0], 1)
        self.assertEqual(self.classify(ipv6(60, extension_chain(9) + transport(853)))[0], 2)
        huge = bytes([6, 32]) + bytes(262) + transport(853)
        self.assertEqual(self.classify(ipv6(60, huge))[0], 2)

    def test_ipv4_and_ipv6_fragment_reassembly_disabled(self):
        # Configuration only: device tests are still required to prove the
        # compiled Android stack and end-to-end delivery behave as expected.
        self.assertEqual(self.lib.ipv4_reassembly(), 0)
        self.assertEqual(self.lib.ipv6_reassembly(), 0)


if __name__ == "__main__":
    unittest.main()
