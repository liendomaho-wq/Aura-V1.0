"""Execute the real native egress logic on Linux, not Android/TUN acceptance.

TCP negative cases use real sockets. UDP bookkeeping cases supply explicit
metadata fixtures: they do NOT demonstrate that a UDP packet was routed.
Full forwarding is tested separately by Android instrumentation.
"""

from __future__ import annotations

import ctypes
from pathlib import Path
import shutil
import socket
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]
CPP = ROOT / "android/app/src/main/cpp"


@pytest.fixture(scope="module")
def native(tmp_path_factory):
    compiler = shutil.which("gcc")
    if not compiler:
        pytest.fail("A real C compiler is required for native forwarding regressions")
    directory = tmp_path_factory.mktemp("aura-egress-native")
    bridge = directory / "test_bridge.c"
    bridge.write_text(r'''
#include <arpa/inet.h>
#include <string.h>
#include "aura_forwarding_health.h"

size_t observation_size(void) { return sizeof(AuraEgressObservation); }

void metadata_fixture(void *state, int event, const char *ip, int port, size_t length) {
    struct sockaddr_in6 peer;
    struct sockaddr_in v4;
    memset(&peer, 0, sizeof(peer));
    memset(&v4, 0, sizeof(v4));
    if (inet_pton(AF_INET, ip, &v4.sin_addr) == 1) {
        v4.sin_family = AF_INET;
        v4.sin_port = htons((uint16_t)port);
        aura_egress_observe_udp(state, event, (struct sockaddr *)&v4, sizeof(v4), length);
    } else if (inet_pton(AF_INET6, ip, &peer.sin6_addr) == 1) {
        peer.sin6_family = AF_INET6;
        peer.sin6_port = htons((uint16_t)port);
        aura_egress_observe_udp(state, event, (struct sockaddr *)&peer, sizeof(peer), length);
    }
}
''', encoding="utf-8")
    library = directory / "libaura-egress-test.so"
    subprocess.run([
        compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
        "-pthread", "-I", str(CPP), str(CPP / "aura_forwarding_health.c"),
        str(bridge), "-o", str(library),
    ], check=True, capture_output=True, text=True)
    result = ctypes.CDLL(str(library))
    result.observation_size.restype = ctypes.c_size_t
    result.aura_egress_recent.restype = ctypes.c_int
    result.aura_egress_observe_tcp.argtypes = [ctypes.c_void_p, ctypes.c_int]
    result.metadata_fixture.argtypes = [
        ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_size_t,
    ]
    return result


@pytest.fixture
def observation(native):
    native.aura_egress_reset()
    return ctypes.create_string_buffer(native.observation_size())


def event(native, observation, kind, ip="198.51.100.42", port=32967, length=32):
    native.metadata_fixture(observation, kind, ip.encode("ascii"), port, length)


def test_reset_and_invalid_fd_cannot_claim_egress(native, observation):
    native.aura_egress_observe_tcp(observation, -1)
    assert native.aura_egress_recent() == 0


def test_real_bidirectional_loopback_tcp_is_not_physical_egress(native, observation):
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        with socket.create_connection(listener.getsockname(), timeout=3) as client:
            connection, _ = listener.accept()
            with connection:
                client.sendall(b"not-egress")
                assert connection.recv(32) == b"not-egress"
                connection.sendall(b"local-reply")
                assert client.recv(32) == b"local-reply"
                native.aura_egress_observe_tcp(observation, client.fileno())
    assert native.aura_egress_recent() == 0


@pytest.mark.parametrize("ip", ["127.0.0.1", "127.9.8.7", "::1", "::ffff:127.0.0.1", "0.0.0.0", "::", "224.0.0.1", "ff02::1"])
def test_local_unspecified_or_multicast_udp_metadata_cannot_claim_egress(native, observation, ip):
    event(native, observation, 1, ip=ip)
    event(native, observation, 2, ip=ip)
    assert native.aura_egress_recent() == 0


def test_udp_unsolicited_metadata_is_not_bidirectional_evidence(native, observation):
    event(native, observation, 2)
    assert native.aura_egress_recent() == 0


def test_udp_write_only_metadata_is_not_a_reply(native, observation):
    event(native, observation, 1)
    assert native.aura_egress_recent() == 0


def test_udp_reply_must_match_both_address_and_port(native, observation):
    event(native, observation, 1)
    event(native, observation, 2, port=32968)
    event(native, observation, 2, ip="198.51.100.43")
    assert native.aura_egress_recent() == 0
    event(native, observation, 2)
    assert native.aura_egress_recent() == 1
    native.aura_egress_reset()
    assert native.aura_egress_recent() == 0


def test_udp_ipv4_and_mapped_ipv6_metadata_match(native, observation):
    event(native, observation, 1)
    event(native, observation, 2, ip="::ffff:198.51.100.42")
    assert native.aura_egress_recent() == 1


def test_zero_length_udp_payload_metadata_is_not_evidence(native, observation):
    event(native, observation, 1, length=0)
    event(native, observation, 2)
    assert native.aura_egress_recent() == 0


def test_udp_observations_are_bounded_without_eviction_of_fresh_peers(native, observation):
    for port in range(32900, 32916):
        event(native, observation, 1, port=port)
    event(native, observation, 1, port=32916)
    event(native, observation, 2, port=32916)
    assert native.aura_egress_recent() == 0
    event(native, observation, 2, port=32900)
    assert native.aura_egress_recent() == 1


def test_jni_allocation_failure_is_checked_before_array_write():
    source = (CPP / "hev-socks5-tunnel/src/hev-jni.c").read_text(encoding="utf-8")
    start = source.index("    res = (*env)->NewLongArray (env, 4);")
    end = source.index("    (*env)->SetLongArrayRegion", start)
    guard = source[start:end]
    assert "if (!res)" in guard
    assert "return NULL" in guard
    assert "ExceptionClear" not in guard


def test_jni_failed_lookup_does_not_continue_with_pending_exception():
    import re
    source = (ROOT / "android/app/src/main/cpp/hev-socks5-tunnel/src/hev-jni.c").read_text()
    on_load = source[source.index("JNI_OnLoad ("):source.index("\nint\nhev_jni_protect_socket")]
    for field in ("tproxy_class", "dns_event_method", "sni_event_method", "encrypted_dns_event_method", "protect_socket_method", "resolve_host_method"):
        assert re.search(r"if \(!" + field + r"\)\s+goto failure;", on_load)
        assert on_load.index("if (!" + field + ")") < on_load.index("RegisterNatives")
    assert "java_vm = vm;" in on_load
    assert on_load.index("java_vm = vm;") > on_load.index("RegisterNatives")
    assert "ExceptionClear" not in on_load
    assert "pthread_mutex_destroy" in on_load
    assert "pthread_key_delete" in on_load
