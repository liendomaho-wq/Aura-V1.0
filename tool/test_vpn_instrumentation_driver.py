"""Real host-socket/process regressions, NOT Android instrumentation evidence."""

import json
from pathlib import Path
import socket
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "tool/run_android_vpn_instrumentation.py"


def run_host_command(source):
    return subprocess.run(
        [sys.executable, str(DRIVER), "--", sys.executable, "-c", source],
        cwd=ROOT, capture_output=True, text=True, timeout=25,
    )


def assert_fixture_stopped():
    with pytest.raises(OSError):
        with socket.create_connection(("127.0.0.1", 32967), timeout=0.5):
            pytest.fail("Host traffic peer leaked its listener after driver shutdown")


def test_driver_owns_real_ipv4_ipv6_tcp_udp_peers_and_shuts_them_down():
    result = run_host_command('''
import socket,struct
from tool.vpn_echo_fixture import PREFIX, receive_exact
payload=PREFIX+b"host-process-regression"
for family,host in ((socket.AF_INET,"127.0.0.1"),(socket.AF_INET6,"::1")):
    with socket.socket(family,socket.SOCK_STREAM) as stream:
        stream.settimeout(3)
        stream.connect((host,32967))
        stream.sendall(struct.pack("!H",len(payload))+payload)
        assert receive_exact(stream,2)==struct.pack("!H",len(payload))
        assert receive_exact(stream,len(payload))==payload
    with socket.socket(family,socket.SOCK_DGRAM) as datagram:
        datagram.settimeout(3)
        datagram.sendto(payload,(host,32967))
        assert datagram.recvfrom(1200)[0]==payload
''')
    assert result.returncode == 0, result.stdout + result.stderr
    report = json.loads((ROOT / "build/vpn-instrumentation-fixture.log").read_text().splitlines()[-1])
    assert report["status"] == "stopped"
    assert report["successful_echoes"] == {"tcp_ipv4": 1, "tcp_ipv6": 1, "udp_ipv4": 1, "udp_ipv6": 1}
    assert_fixture_stopped()


def test_driver_preserves_actual_child_nonzero_exit_code():
    # This is the negative process-contract unit test, not a Gradle substitute
    # in CI. The Android workflow still executes Gradle and requires real XML.
    result = run_host_command("raise SystemExit(23)")
    assert result.returncode == 23, result.stdout + result.stderr
    assert_fixture_stopped()
