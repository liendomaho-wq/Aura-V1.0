#!/usr/bin/env python3
"""Exercise the real lwIP IP ingress with host pbufs and a fake netif.

The production lwIP core and port configuration are compiled unchanged. A
host-only netif, deterministic random source and UDP callback replace Android,
TUN, HEV sessions and external networking. This is not a device/network test.
"""
import ctypes
import platform
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_tun_packet_filter import HEV, ipv4, ipv6

LWIP = HEV / "third-part/lwip"


class LwipFragmentPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="aura-lwip-fragment-")
        harness = Path(cls.tmp) / "harness.c"
        harness.write_text(
            r'''
#include <stdint.h>
#include "lwip/init.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/udp.h"

static struct netif test_netif;
static struct udp_pcb *listener;
static int delivered;
static err_t init_netif(struct netif *netif) { (void)netif; return ERR_OK; }
static void receive_datagram(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                             const ip_addr_t *address, u16_t port) {
    (void)arg; (void)pcb; (void)address; (void)port;
    delivered++;
    pbuf_free(p);
}
/* A pretend listener is called once to set up each new PCB; lwIP then invokes
 * the installed callback to deliver the same datagram. */
static void accept_datagram(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                            const ip_addr_t *address, u16_t port) {
    (void)arg; (void)p; (void)address; (void)port;
    udp_recv(pcb, receive_datagram, NULL);
}
/* This test does not use real sockets or security-sensitive randomness. */
unsigned int lwip_port_rand(void) { return 4; }

__attribute__((visibility("default"))) int test_init(void) {
    ip4_addr_t address, mask, gateway;
    ip6_addr_t address6;
    lwip_init();
    if (!netif_add_noaddr(&test_netif, NULL, init_netif, ip_input)) return -1;
    ip4_addr_set_loopback(&address);
    ip4_addr_set_any(&mask);
    ip4_addr_set_any(&gateway);
    netif_set_addr(&test_netif, &address, &mask, &gateway);
    ip6_addr_set_loopback(&address6);
    netif_add_ip6_address(&test_netif, &address6, NULL);
    netif_set_up(&test_netif);
    netif_set_link_up(&test_netif);
    netif_set_default(&test_netif);
    netif_set_flags(&test_netif, NETIF_FLAG_PRETEND_UDP);
    listener = udp_new_ip_type(IPADDR_TYPE_ANY);
    if (!listener) return -2;
    udp_bind_netif(listener, &test_netif);
    if (udp_bind(listener, NULL, 0) != ERR_OK) return -3;
    udp_recv(listener, accept_datagram, NULL);
    return 0;
}

__attribute__((visibility("default"))) int test_inject(const uint8_t *data, uint16_t len) {
    const int before = delivered;
    struct pbuf *p = pbuf_alloc(PBUF_RAW, len, PBUF_RAM);
    if (!p) return -1;
    if (pbuf_take(p, data, len) != ERR_OK) { pbuf_free(p); return -2; }
    ip_input(p, &test_netif);
    return delivered - before;
}
''',
            encoding="utf-8",
        )
        output = Path(cls.tmp) / "liblwip_ingress.so"
        linker_gc = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        sources = sorted((LWIP / "src/core").rglob("*.c"))
        command = [
            "cc", "-std=gnu11", "-DFD_SET_DEFINED", "-DSOCKLEN_T_DEFINED",
            "-fPIC", "-fvisibility=hidden", "-ffunction-sections", "-fdata-sections",
            "-shared", linker_gc, "-I", str(LWIP / "src/include"),
            "-I", str(LWIP / "src/ports/include"), str(harness),
            *(str(source) for source in sources), str(LWIP / "src/ports/lib/mem.c"),
            "-o", str(output),
        ]
        subprocess.run(command, check=True)

        # Positive control: compile the same lwIP core with reassembly enabled
        # in a temporary config, proving that the harness can observe delivery
        # of a reassembled datagram rather than merely dropping every packet.
        control_include = Path(cls.tmp) / "reassembly-control"
        control_include.mkdir()
        options = (LWIP / "src/ports/include/lwipopts.h").read_text(encoding="utf-8")
        for name in ("IP_REASSEMBLY", "LWIP_IPV6_REASS"):
            old = next(line for line in options.splitlines() if line.startswith(f"#define {name} "))
            if old.split()[-1] != "0":
                raise RuntimeError(f"unexpected production setting for {name}")
            options = options.replace(old, old.rsplit("0", 1)[0] + "1", 1)
        (control_include / "lwipopts.h").write_text(options, encoding="utf-8")
        control_output = Path(cls.tmp) / "liblwip_control.so"
        control_command = command.copy()
        control_command[control_command.index("-I"):control_command.index("-I")] = [
            "-I", str(control_include)
        ]
        control_command[-1] = str(control_output)
        subprocess.run(control_command, check=True)

        def load(path):
            lib = ctypes.CDLL(str(path))
            lib.test_init.restype = ctypes.c_int
            lib.test_inject.argtypes = [ctypes.c_void_p, ctypes.c_uint16]
            lib.test_inject.restype = ctypes.c_int
            if lib.test_init() != 0:
                raise RuntimeError("could not initialise host lwIP netif")
            return lib

        cls.lib = load(output)
        cls.control = load(control_output)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def inject(self, packet, library=None):
        raw = ctypes.create_string_buffer(packet)
        return (library or self.lib).test_inject(raw, len(packet))

    @staticmethod
    def udp(payload=b"abcdefgh"):
        return struct.pack("!HHHH", 12345, 5353, 8 + len(payload), 0) + payload

    def test_unfragmented_ipv4_and_ipv6_are_delivered(self):
        datagram = self.udp()
        self.assertEqual(self.inject(ipv4(17, datagram)), 1)
        self.assertEqual(self.inject(ipv6(17, datagram)), 1)

    def test_ipv4_fragments_never_reach_udp_in_either_order(self):
        datagram = self.udp()
        first = ipv4(17, datagram[:8], fragment=0x2000)
        last = ipv4(17, datagram[8:], fragment=1)
        for sequence in ((first, last), (last, first)):
            for packet in sequence:
                self.assertEqual(self.inject(packet), 0)

    def test_ipv6_fragments_never_reach_udp_in_either_order(self):
        datagram = self.udp()
        first = ipv6(44, struct.pack("!BBHI", 17, 0, 1, 42) + datagram[:8])
        last = ipv6(44, struct.pack("!BBHI", 17, 0, 8, 42) + datagram[8:])
        for sequence in ((first, last), (last, first)):
            for packet in sequence:
                self.assertEqual(self.inject(packet), 0)

    def test_ipv6_atomic_fragment_is_delivered(self):
        atomic = struct.pack("!BBHI", 17, 0, 0, 42) + self.udp()
        self.assertEqual(self.inject(ipv6(44, atomic)), 1)

    def test_positive_control_reassembles_when_enabled(self):
        datagram = self.udp()
        first4 = ipv4(17, datagram[:8], fragment=0x2000)
        last4 = ipv4(17, datagram[8:], fragment=1)
        self.assertEqual(self.inject(first4, self.control), 0)
        self.assertEqual(self.inject(last4, self.control), 1)
        first6 = ipv6(44, struct.pack("!BBHI", 17, 0, 1, 42) + datagram[:8])
        last6 = ipv6(44, struct.pack("!BBHI", 17, 0, 8, 42) + datagram[8:])
        self.assertEqual(self.inject(first6, self.control), 0)
        self.assertEqual(self.inject(last6, self.control), 1)


if __name__ == "__main__":
    unittest.main()
