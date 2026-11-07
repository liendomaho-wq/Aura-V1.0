#!/usr/bin/env python3
"""Verify the model asset with the public key that will be embedded in Aura.

Uses only Python's standard library and the system OpenSSL CLI. This validates
packaged bytes, not model quality or runtime operation on Android.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "assets/model/aura_brain_model.json"
DIGEST = ROOT / "assets/model/aura_brain_model.json.sha256"
SIGNATURE = ROOT / "assets/model/aura_brain_model.json.sig"
MAX_MODEL_BYTES = 5 * 1024 * 1024


def _openssl(*arguments: str) -> bytes:
    try:
        result = subprocess.run(
            ["openssl", *arguments],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise ValueError("OpenSSL no está disponible para verificar el modelo.") from error
    if result.returncode != 0:
        raise ValueError("OpenSSL no pudo validar la clave o la firma del modelo.")
    return result.stdout


def verify_packaged_model(
    key_der: Path,
    model: Path = MODEL,
    digest: Path = DIGEST,
    signature: Path = SIGNATURE,
) -> None:
    try:
        if not 0 < model.stat().st_size <= MAX_MODEL_BYTES:
            raise ValueError("El modelo incluido está vacío o supera el límite de tamaño.")
        model_bytes = model.read_bytes()
        digest_text = digest.read_text(encoding="ascii").strip()
        if not re.fullmatch(r"[0-9a-fA-F]{64}", digest_text):
            raise ValueError("El SHA-256 incluido no tiene el formato esperado.")
        if not hmac.compare_digest(hashlib.sha256(model_bytes).hexdigest(), digest_text.lower()):
            raise ValueError("El SHA-256 no coincide con el modelo incluido.")
        if signature.stat().st_size != 256:
            raise ValueError("La firma del modelo debe tener 256 bytes.")
        if not 0 < key_der.stat().st_size <= 4096:
            raise ValueError("La clave pública DER está vacía o supera el límite.")
    except (OSError, UnicodeError) as error:
        raise ValueError("Faltan archivos válidos para verificar el modelo incluido.") from error

    modulus_output = _openssl("rsa", "-pubin", "-inform", "DER", "-in", str(key_der), "-noout", "-modulus")
    match = re.fullmatch(rb"Modulus=([0-9a-fA-F]+)\s*", modulus_output)
    if match is None or int(match.group(1), 16).bit_length() != 2048:
        raise ValueError("La clave del modelo debe ser RSA de exactamente 2048 bits.")

    with tempfile.TemporaryDirectory(prefix="aura-model-verify-") as tmp:
        public_pem = Path(tmp) / "public.pem"
        public_pem.write_bytes(
            _openssl("pkey", "-pubin", "-inform", "DER", "-in", str(key_der), "-pubout")
        )
        _openssl(
            "dgst", "-sha256", "-verify", str(public_pem),
            "-signature", str(signature), str(model),
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-key-der", type=Path, required=True)
    args = parser.parse_args()
    try:
        verify_packaged_model(args.public_key_der)
    except ValueError as error:
        print(f"ERROR: {error}")
        return 1
    print("Modelo incluido: SHA-256 y firma RSA verificados con la clave configurada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
