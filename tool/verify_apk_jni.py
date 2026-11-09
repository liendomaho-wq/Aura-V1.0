#!/usr/bin/env python3
"""Verify JNI entry points in each packaged native library (not runtime JNI testing)."""

import argparse
import subprocess
import tempfile
import zipfile
from pathlib import Path

ABIS = ("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
REQUIRED_SYMBOLS = frozenset({
    "JNI_OnLoad",
    "Java_com_ciberdefensa_aura_MainActivity_addDnsBlockRuleNative",
    "Java_com_aura_cyberdefense_AuraCryptoSecure_decryptModelNative",
})


def verify_apk(apk: Path, readelf: str = "readelf") -> None:
    with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory() as temporary:
        for abi in ABIS:
            member = f"lib/{abi}/libhev-socks5-tunnel.so"
            library = Path(temporary) / f"{abi}.so"
            library.write_bytes(archive.read(member))
            result = subprocess.run(
                [readelf, "--wide", "--dyn-syms", str(library)],
                check=True, capture_output=True, text=True,
            )
            exports = set()
            for line in result.stdout.splitlines():
                fields = line.split()
                if (len(fields) >= 8 and fields[0].endswith(":")
                        and fields[3] == "FUNC" and fields[4] == "GLOBAL"
                        and fields[5] == "DEFAULT" and fields[6] != "UND"):
                    exports.add(fields[7].split("@", 1)[0])
            missing = REQUIRED_SYMBOLS - exports
            if missing:
                raise ValueError(f"{member}: missing public JNI functions: {', '.join(sorted(missing))}")
            print(f"{member}: required JNI functions are exported")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--readelf", default="readelf")
    args = parser.parse_args()
    verify_apk(args.apk, args.readelf)


if __name__ == "__main__":
    main()
