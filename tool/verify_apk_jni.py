#!/usr/bin/env python3
"""Verify JNI entry points in each packaged native library (not runtime JNI testing)."""

import argparse
import subprocess
import tempfile
import zipfile
from pathlib import Path

ABIS = ("armeabi-v7a", "arm64-v8a", "x86_64")

# libhev-socks5-tunnel.so keeps the tunnel, DNS rule and model-decrypt entry
# points. libaura_llm.so is the pinned llama.cpp bridge; every AuraLlmBridge
# external function must be exported for the Dart runtime to reach native.
LIBRARY_REQUIREMENTS = {
    "libhev-socks5-tunnel.so": frozenset({
        "JNI_OnLoad",
        "Java_com_ciberdefensa_aura_MainActivity_addDnsBlockRuleNative",
        "Java_com_aura_cyberdefense_AuraCryptoSecure_decryptModelNative",
    }),
    "libaura_llm.so": frozenset({
        "JNI_OnLoad",
        "Java_com_ciberdefensa_aura_AuraLlmBridge_nativeStartup",
        "Java_com_ciberdefensa_aura_AuraLlmBridge_nativeIsModelLoaded",
        "Java_com_ciberdefensa_aura_AuraLlmBridge_nativeMaxContextTokens",
        "Java_com_ciberdefensa_aura_AuraLlmBridge_nativeLoadModel",
        "Java_com_ciberdefensa_aura_AuraLlmBridge_nativeGetLastError",
        "Java_com_ciberdefensa_aura_AuraLlmBridge_nativeStartGeneration",
        "Java_com_ciberdefensa_aura_AuraLlmBridge_nativeCancelGeneration",
        "Java_com_ciberdefensa_aura_AuraLlmBridge_nativeUnloadModel",
    }),
}

REQUIRED_SYMBOLS = frozenset().union(*LIBRARY_REQUIREMENTS.values())


def verify_apk(apk: Path, readelf: str = "readelf") -> None:
    with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory() as temporary:
        for abi in ABIS:
            for library_name, required in LIBRARY_REQUIREMENTS.items():
                member = f"lib/{abi}/{library_name}"
                library = Path(temporary) / f"{abi}-{library_name}"
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
                missing = required - exports
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
