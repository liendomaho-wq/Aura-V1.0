"""Real, bounded loopback TCP/UDP peers for Android emulator integration.

The Android guest reaches the runner through its physical virtual network.
This is a traffic peer, NOT a TUN, VPN, SOCKS, DNS or Keystore replacement.
No production endpoint, payload or user data is used.
"""

from __future__ import annotations

import argparse
from contextlib import ExitStack
import json
import selectors
import signal
import socket
import struct
import threading

PREFIX = b"AURA-VPN-TEST:"
MAX_PAYLOAD = 1200
MAX_CONNECTIONS = 8


def receive_exact(connection, length):
    result = bytearray()
    while len(result) < length:
        chunk = connection.recv(length - len(result))
        if not chunk:
            raise EOFError("TCP peer closed an incomplete fixture frame")
        result.extend(chunk)
    return bytes(result)


class VpnEchoFixture:
    def __init__(self, port=32967):
        self.resources = ExitStack()
        self.selector = self.resources.enter_context(selectors.DefaultSelector())
        self.stop_requested = threading.Event()
        self.connection_slots = threading.BoundedSemaphore(MAX_CONNECTIONS)
        self.connections = set()
        self.lock = threading.Lock()
        self.counts = {"tcp_ipv4": 0, "tcp_ipv6": 0, "udp_ipv4": 0, "udp_ipv6": 0}
        self.port = port
        try:
            for family, host, label in (
                (socket.AF_INET, "127.0.0.1", "ipv4"),
                (socket.AF_INET6, "::1", "ipv6"),
            ):
                for kind, transport in ((socket.SOCK_STREAM, "tcp"), (socket.SOCK_DGRAM, "udp")):
                    endpoint = self.resources.enter_context(socket.socket(family, kind))
                    endpoint.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    if family == socket.AF_INET6:
                        endpoint.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
                    endpoint.bind((host, self.port))
                    if not self.port:
                        self.port = endpoint.getsockname()[1]
                    if kind == socket.SOCK_STREAM:
                        endpoint.listen(MAX_CONNECTIONS)
                    endpoint.setblocking(False)
                    self.selector.register(endpoint, selectors.EVENT_READ, f"{transport}_{label}")
        except BaseException:
            self.resources.close()
            raise

    def _tcp(self, connection, label):
        try:
            connection.settimeout(10)
            while not self.stop_requested.is_set():
                length = struct.unpack("!H", receive_exact(connection, 2))[0]
                if not len(PREFIX) <= length <= MAX_PAYLOAD:
                    return
                payload = receive_exact(connection, length)
                if not payload.startswith(PREFIX):
                    return
                connection.sendall(struct.pack("!H", len(payload)) + payload)
                with self.lock:
                    self.counts[label] += 1
        except (OSError, EOFError):
            # A broken peer never creates a successful echo/counter.
            pass
        finally:
            with self.lock:
                self.connections.discard(connection)
            connection.close()
            self.connection_slots.release()

    def serve(self):
        while not self.stop_requested.is_set():
            for key, _ in self.selector.select(timeout=0.2):
                endpoint, label = key.fileobj, key.data
                if label.startswith("udp"):
                    payload, peer = endpoint.recvfrom(MAX_PAYLOAD + 1)
                    if payload.startswith(PREFIX) and len(payload) <= MAX_PAYLOAD:
                        sent = endpoint.sendto(payload, peer)
                        if sent == len(payload):
                            with self.lock:
                                self.counts[label] += 1
                else:
                    connection, _ = endpoint.accept()
                    if not self.connection_slots.acquire(blocking=False):
                        connection.close()
                        continue
                    with self.lock:
                        self.connections.add(connection)
                    threading.Thread(target=self._tcp, args=(connection, label), daemon=True).start()

    def close(self):
        self.stop_requested.set()
        with self.lock:
            connections = list(self.connections)
        for connection in connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.resources.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=32967)
    arguments = parser.parse_args()
    fixture = VpnEchoFixture(arguments.port)
    signal.signal(signal.SIGTERM, lambda *_: fixture.stop_requested.set())
    signal.signal(signal.SIGINT, lambda *_: fixture.stop_requested.set())
    print(json.dumps({"status": "ready", "port": fixture.port, "families": ["ipv4", "ipv6"]}), flush=True)
    try:
        fixture.serve()
    finally:
        fixture.close()
        print(json.dumps({"status": "stopped", "successful_echoes": fixture.counts}), flush=True)


if __name__ == "__main__":
    main()
