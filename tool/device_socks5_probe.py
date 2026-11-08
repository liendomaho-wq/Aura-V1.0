#!/usr/bin/env python3
"""Real-device DEBUG probe: HEV RFC 1929 auth + CONNECT + verified TLS payload.

Requires an explicitly selected, authorized physical Android device with Aura's
VPN already active, adb, and an owner-controlled HTTPS payload/digest. Does not
start the VPN, bypass run-as, accept invalid TLS, print credentials or emulate HEV.
A passing proxy probe alone does NOT validate the Android TUN ingress or leaks.
"""
import argparse
import hashlib
import http.client
import re
import socket
import ssl
import struct
import subprocess
import sys
import traceback

PACKAGE = "com.ciberdefensa.aura"
MAX_PAYLOAD = 16 * 1024 * 1024


def adb(serial, *args):
    return subprocess.run(
        ["adb", "-s", serial, *args], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout


def read_exact(stream, length):
    data = bytearray()
    while len(data) < length:
        chunk = stream.recv(length - len(data))
        if not chunk:
            raise OSError("HEV closed the connection before its complete reply")
        data.extend(chunk)
    return bytes(data)


def credentials_from_private_config(serial):
    # Read directly into this process, never into a shell variable or log file.
    config = bytearray(adb(serial, "exec-out", "run-as", PACKAGE,
                           "cat", "files/aura-hev-socks5.yml"))
    try:
        if not config or len(config) > 65536:
            raise ValueError("Invalid private VPN configuration size")
        user = re.findall(rb"^\s*username: '([A-Za-z0-9_-]{1,255})'\s*$", config, re.MULTILINE)
        password = re.findall(rb"^\s*password: '([A-Za-z0-9_-]{1,255})'\s*$", config, re.MULTILINE)
        if len(user) != 1 or len(password) != 1:
            raise ValueError("Private VPN configuration has no unambiguous RFC 1929 credentials")
        return bytearray(user[0]), bytearray(password[0])
    finally:
        config[:] = b"\x00" * len(config)


def authenticated_socket(port, user, password, *, reject_password=False):
    stream = socket.create_connection(("127.0.0.1", port), timeout=10)
    try:
        stream.sendall(b"\x05\x01\x02")
        if read_exact(stream, 2) != b"\x05\x02":
            raise OSError("HEV did not require RFC 1929 authentication")
        secret = bytearray(password)
        if reject_password:
            secret[0] = ord("0") if secret[0] != ord("0") else ord("1")
        packet = bytearray([1, len(user)]) + user + bytearray([len(secret)]) + secret
        try:
            stream.sendall(packet)
            reply = read_exact(stream, 2)
        finally:
            secret[:] = b"\x00" * len(secret)
            packet[:] = b"\x00" * len(packet)
        if reject_password:
            if reply[0] != 1 or reply[1] == 0:
                raise OSError("HEV did not reject an incorrect password")
        elif reply != b"\x01\x00":
            raise OSError("HEV rejected the live service credentials")
        return stream
    except BaseException:
        stream.close()
        raise


def probe(serial, host, port, path, expected_digest):
    user, password = credentials_from_private_config(serial)
    forward = None
    try:
        # tcp:0 asks adb for a free host port without replacing any user forward.
        forward = int(adb(serial, "forward", "tcp:0", "tcp:18763").strip())
        with socket.create_connection(("127.0.0.1", forward), timeout=10) as stream:
            stream.sendall(b"\x05\x01\x00")
            if read_exact(stream, 2) != b"\x05\xff":
                raise OSError("HEV did not reject the unauthenticated SOCKS5 method")
        print("PASS: real HEV listener rejected SOCKS5 NONE")
        with authenticated_socket(forward, user, password, reject_password=True):
            pass
        print("PASS: real HEV listener rejected an incorrect RFC 1929 password")

        with authenticated_socket(forward, user, password) as stream:
            name = host.encode("idna")
            stream.sendall(b"\x05\x01\x00\x03" + bytes([len(name)]) + name + struct.pack("!H", port))
            reply = read_exact(stream, 4)
            if reply[:3] != b"\x05\x00\x00":
                raise OSError("HEV did not confirm a successful SOCKS5 CONNECT")
            if reply[3] == 1:
                read_exact(stream, 4)
            elif reply[3] == 4:
                read_exact(stream, 16)
            elif reply[3] == 3:
                read_exact(stream, read_exact(stream, 1)[0])
            else:
                raise OSError("HEV returned an invalid bound-address type")
            read_exact(stream, 2)

            context = ssl.create_default_context()
            with context.wrap_socket(stream, server_hostname=host) as secured:
                request = (
                    f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\n"
                    "Connection: close\r\nAccept-Encoding: identity\r\n\r\n"
                )
                secured.sendall(request.encode("ascii"))
                response = http.client.HTTPResponse(secured)
                response.begin()
                if response.status != 200:
                    raise OSError(f"Controlled HTTPS endpoint returned HTTP {response.status}")
                digest = hashlib.sha256()
                size = 0
                while chunk := response.read(65536):
                    size += len(chunk)
                    if size > MAX_PAYLOAD:
                        raise ValueError("Controlled payload exceeded the 16 MiB probe limit")
                    digest.update(chunk)
                actual = digest.hexdigest()
                if size == 0 or actual != expected_digest:
                    raise ValueError("HTTPS payload is empty or its SHA-256 does not match the owner-provided digest")
                print(f"PASS: live RFC 1929 + CONNECT + certificate-verified TLS; bytes={size}; SHA256={actual}")
    finally:
        user[:] = b"\x00" * len(user)
        password[:] = b"\x00" * len(password)
        # Cleanup errors also fail the command, rather than claiming full success.
        if forward is not None:
            adb(serial, "forward", "--remove", f"tcp:{forward}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="Authorized physical device serial from adb devices -l")
    parser.add_argument("--host", required=True, help="Owner-controlled DNS name with a valid TLS certificate")
    parser.add_argument("--port", type=int, default=443)
    parser.add_argument("--path", required=True, help="ASCII HTTPS path for the controlled binary payload")
    parser.add_argument("--sha256", required=True, help="SHA-256 independently calculated on that server")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9.-]{1,253}", args.host) or ".." in args.host:
        parser.error("--host must be an ASCII DNS name")
    if not 1 <= args.port <= 65535:
        parser.error("--port must be in 1..65535")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", args.sha256):
        parser.error("--sha256 must be a real 64-digit SHA-256 digest")
    if not args.path.startswith("/") or len(args.path) > 2048 or any(
        ord(char) < 33 or ord(char) > 126 for char in args.path
    ):
        parser.error("--path must be a nonempty ASCII HTTPS path without whitespace/control bytes")
    try:
        probe(args.serial, args.host, args.port, args.path, args.sha256.lower())
    except (OSError, ValueError, http.client.HTTPException, subprocess.CalledProcessError) as error:
        # Neither subprocess stdout nor the private YAML/credentials are logged.
        print("FAIL: real-device SOCKS5 probe did not complete", file=sys.stderr)
        traceback.print_exception(error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
