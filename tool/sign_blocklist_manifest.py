#!/usr/bin/env python3
"""Firma y verifica el manifiesto de blocklists de Aura.

El manifiesto viaja por HTTPS y sus SHA-256 protegen los feeds, pero un
manifiesto alterado podría apuntar a feeds maliciosos. Por eso Aura verifica
una firma RSA SHA-256 (PKCS#1 v1.5) con una o varias claves públicas
compiladas en la app.

Formato de la firma (archivo `<manifiesto>.sig`):

    {"algorithm":"RS256","key_id":"aura-2026-11","signature":"<base64>"}

La clave pública para Android se expresa como `keyId:base64DER`, donde el
base64 es la SubjectPublicKeyInfo en DER. Varias claves se separan con `;` en
AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS para permitir rotación sin romper a los
usuarios que aún no actualizaron la app.
"""

from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
import re
import sys
import tempfile
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

KEY_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
MIN_PASSWORD_LENGTH = 12


def _atomic_write(path: Path, content: bytes, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as temporary_file:
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, path)
        os.chmod(path, mode)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        temporary_path.unlink(missing_ok=True)
        raise


def _password() -> bytes:
    value = os.environ.get("AURA_SIGNING_PASSPHRASE")
    if value is None:
        value = getpass.getpass("Contraseña de la clave privada: ")
    encoded = value.encode("utf-8")
    if len(encoded) < MIN_PASSWORD_LENGTH:
        raise ValueError(
            "La contraseña debe tener al menos "
            f"{MIN_PASSWORD_LENGTH} bytes."
        )
    return encoded


def _public_key_der(key: rsa.RSAPublicKey) -> bytes:
    return key.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def _load_private_key(path: Path, password: bytes) -> rsa.RSAPrivateKey:
    key = serialization.load_pem_private_key(
        path.read_bytes(),
        password=password,
    )
    if not isinstance(key, rsa.RSAPrivateKey):
        raise ValueError("La clave privada debe ser RSA.")
    return key


def generate_key_pair(
    private_key_path: Path,
    public_key_path: Path,
    password: bytes,
) -> rsa.RSAPrivateKey:
    if private_key_path.exists() or public_key_path.exists():
        raise FileExistsError(
            "Ya existe una de las claves. No se sobrescriben: muévalas o "
            "elija otro nombre para rotar."
        )
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=3072,
    )
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.BestAvailableEncryption(password),
    )
    _atomic_write(private_key_path, private_pem, mode=0o600)
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    _atomic_write(public_key_path, public_pem)
    return private_key


def sign_manifest(
    manifest_path: Path,
    private_key_path: Path,
    key_id: str,
    password: bytes,
) -> dict[str, str]:
    if not KEY_ID_PATTERN.fullmatch(key_id):
        raise ValueError("El key id debe cumplir [A-Za-z0-9._-]{1,64}.")
    manifest = manifest_path.read_bytes()
    if not manifest.strip():
        raise ValueError("El manifiesto está vacío.")
    key = _load_private_key(private_key_path, password)
    signature = key.sign(
        manifest,
        padding.PKCS1v15(),
        hashes.SHA256(),
    )
    return {
        "algorithm": "RS256",
        "key_id": key_id,
        "signature": base64.b64encode(signature).decode("ascii"),
    }


def verify_manifest(
    manifest_path: Path,
    signature_path: Path,
    public_keys: dict[str, rsa.RSAPublicKey],
) -> str:
    envelope = json.loads(signature_path.read_text(encoding="utf-8"))
    if envelope.get("algorithm") != "RS256":
        raise ValueError("La firma debe usar RS256.")
    key_id = envelope.get("key_id")
    if not isinstance(key_id, str) or key_id not in public_keys:
        raise ValueError(f"key_id desconocido: {key_id!r}.")
    try:
        signature = base64.b64decode(envelope["signature"], validate=True)
    except (KeyError, ValueError) as error:
        raise ValueError("La firma no es base64 válido.") from error
    try:
        public_keys[key_id].verify(
            signature,
            manifest_path.read_bytes(),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
    except InvalidSignature as error:
        raise ValueError("La firma no coincide con el manifiesto.") from error
    return key_id


def parse_public_keys(raw: str) -> dict[str, rsa.RSAPublicKey]:
    keys: dict[str, rsa.RSAPublicKey] = {}
    for entry in raw.split(";"):
        if not entry.strip():
            continue
        separator = entry.find(":")
        if separator <= 0 or separator == len(entry) - 1:
            raise ValueError("Cada clave debe usar keyId:base64DER.")
        key_id = entry[:separator].strip()
        if not KEY_ID_PATTERN.fullmatch(key_id):
            raise ValueError(f"key id inválido: {key_id!r}.")
        der = base64.b64decode(entry[separator + 1 :].strip(), validate=True)
        key = serialization.load_der_public_key(der)
        if not isinstance(key, rsa.RSAPublicKey):
            raise ValueError(f"La clave {key_id} no es RSA.")
        if key_id in keys:
            raise ValueError(f"key id duplicado: {key_id}.")
        keys[key_id] = key
    if not keys:
        raise ValueError("No hay claves públicas.")
    return keys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser(
        "generate",
        help="Genera una clave privada cifrada y su clave pública.",
    )
    generate.add_argument("--private-key", type=Path, required=True)
    generate.add_argument("--public-key", type=Path, required=True)

    sign = subparsers.add_parser("sign", help="Firma un manifiesto.")
    sign.add_argument("--manifest", type=Path, required=True)
    sign.add_argument("--private-key", type=Path, required=True)
    sign.add_argument("--key-id", required=True)
    sign.add_argument("--output", type=Path)

    verify = subparsers.add_parser("verify", help="Verifica una firma.")
    verify.add_argument("--manifest", type=Path, required=True)
    verify.add_argument("--signature", type=Path, required=True)
    verify.add_argument("--public-keys", required=True)

    args = parser.parse_args(argv)
    try:
        if args.command == "generate":
            key = generate_key_pair(
                args.private_key,
                args.public_key,
                _password(),
            )
            encoded = base64.b64encode(_public_key_der(key.public_key())).decode(
                "ascii"
            )
            print("Clave privada creada con permisos 0600.")
            print("Clave pública (formato de AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS):")
            print(f"aura-2026-11:{encoded}")
            return 0

        if args.command == "sign":
            output = args.output or Path(f"{args.manifest}.sig")
            envelope = sign_manifest(
                args.manifest,
                args.private_key,
                args.key_id,
                _password(),
            )
            _atomic_write(
                output,
                (json.dumps(envelope, separators=(",", ":")) + "\n").encode(
                    "utf-8"
                ),
            )
            print(f"Firma escrita en {output}")
            return 0

        key_id = verify_manifest(
            args.manifest,
            args.signature,
            parse_public_keys(args.public_keys),
        )
        print(f"Firma válida con la clave {key_id}.")
        return 0
    except (OSError, ValueError, FileExistsError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
