"""Execute actual host peer sockets; these are not Android/TUN results."""

from pathlib import Path
import socket
import struct
import sys
import threading

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vpn_echo_fixture import MAX_PAYLOAD, PREFIX, VpnEchoFixture, receive_exact  # noqa: E402


@pytest.fixture
def peer():
    fixture = VpnEchoFixture(port=0)
    failure = []

    def run():
        try:
            fixture.serve()
        except BaseException as error:
            failure.append(error)

    thread = threading.Thread(target=run)
    thread.start()
    try:
        yield fixture
    finally:
        fixture.stop_requested.set()
        thread.join(timeout=3)
        fixture.close()
        assert not thread.is_alive(), "Real fixture did not stop"
        if failure:
            raise failure[0]


@pytest.mark.parametrize("family,host", [(socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::1")])
def test_real_tcp_echo_preserves_every_byte(peer, family, host):
    data = PREFIX + bytes(range(256))
    with socket.socket(family, socket.SOCK_STREAM) as connection:
        connection.settimeout(3)
        connection.connect((host, peer.port))
        connection.sendall(struct.pack("!H", len(data)) + data)
        assert struct.unpack("!H", receive_exact(connection, 2))[0] == len(data)
        assert receive_exact(connection, len(data)) == data


@pytest.mark.parametrize("family,host", [(socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::1")])
def test_real_udp_echo_preserves_every_byte(peer, family, host):
    data = PREFIX + bytes(range(256))
    with socket.socket(family, socket.SOCK_DGRAM) as connection:
        connection.settimeout(3)
        connection.sendto(data, (host, peer.port))
        received, source = connection.recvfrom(1200)
        assert received == data
        assert source[1] == peer.port


def test_udp_does_not_reflect_unidentified_or_oversized_payloads(peer):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as connection:
        connection.settimeout(0.1)
        for payload in (b"not-an-aura-test", PREFIX + b"x" * MAX_PAYLOAD):
            connection.sendto(payload, ("127.0.0.1", peer.port))
            with pytest.raises(socket.timeout):
                connection.recvfrom(1500)
