#!/usr/bin/env python3
"""Run an actual llama-bench on an authorized ARM64 Android device.

This is a performance benchmark, not Aura inference or a quality/security test.
The operator supplies a pre-installed llama-bench and GGUF with a trusted digest.
No model or binary is downloaded, installed, modified, or deleted by this tool.
"""

import argparse
import json
import math
import re
import shlex
import subprocess
import sys
from pathlib import PurePosixPath


def android_path(value: str) -> str:
    if not value.startswith("/") or "\0" in value or "\n" in value or "\r" in value:
        raise ValueError("Android paths must be absolute, single-line paths")
    if ".." in PurePosixPath(value).parts:
        raise ValueError("Android paths cannot contain parent traversal")
    return value


def adb_shell(serial: str, arguments: list[str], timeout: int) -> str:
    # adb shell interprets a command string on Android. Quote each argument;
    # do not interpolate paths or accept free-form commands from a model.
    result = subprocess.run(
        ["adb", "-s", serial, "shell", shlex.join(arguments)],
        check=True, capture_output=True, text=True, timeout=timeout,
    )
    return result.stdout.strip()


def digest_on_device(serial: str, path: str, timeout: int) -> str:
    result = adb_shell(serial, ["sha256sum", path], timeout)
    match = re.fullmatch(r"([0-9a-fA-F]{64})\s+.+", result)
    if not match:
        raise ValueError("Device did not return a valid SHA-256 digest")
    return match.group(1).lower()


def run_benchmark(args: argparse.Namespace) -> dict:
    model = android_path(args.model)
    binary = android_path(args.binary)
    if not re.fullmatch(r"[0-9a-fA-F]{64}", args.sha256):
        raise ValueError("Expected model SHA-256 must be 64 hexadecimal characters")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", args.binary_sha256):
        raise ValueError("Expected binary SHA-256 must be 64 hexadecimal characters")
    if not 1 <= args.threads <= 16 or not 1 <= args.repetitions <= 10:
        raise ValueError("Threads must be 1–16 and repetitions 1–10")
    if not 1 <= args.prompt_tokens <= 4096 or not 1 <= args.generate_tokens <= 1024:
        raise ValueError("Prompt tokens must be 1–4096 and generated tokens 1–1024")
    if not 30 <= args.timeout <= 3600:
        raise ValueError("Timeout must be between 30 and 3600 seconds")

    abi = adb_shell(args.serial, ["getprop", "ro.product.cpu.abi"], args.timeout)
    api = adb_shell(args.serial, ["getprop", "ro.build.version.sdk"], args.timeout)
    if abi != "arm64-v8a" or not api.isdigit():
        raise ValueError("The selected device must expose a valid Android ARM64 ABI and API level")
    actual_digest = digest_on_device(args.serial, model, args.timeout)
    if actual_digest != args.sha256.lower():
        raise ValueError("Model SHA-256 mismatch; benchmark was not started")
    binary_digest = digest_on_device(args.serial, binary, args.timeout)
    if binary_digest != args.binary_sha256.lower():
        raise ValueError("Binary SHA-256 mismatch; benchmark was not started")
    size_text = adb_shell(args.serial, ["stat", "-c", "%s", model], args.timeout)
    if not size_text.isdigit() or int(size_text) <= 0:
        raise ValueError("Could not determine the model file size")

    command = [binary, "-m", model, "-o", "json", "-p", str(args.prompt_tokens),
               "-n", str(args.generate_tokens), "-r", str(args.repetitions),
               "-t", str(args.threads), "-ngl", "0"]
    output = adb_shell(args.serial, command, args.timeout)
    if digest_on_device(args.serial, model, args.timeout) != actual_digest:
        raise ValueError("Model changed during benchmarking; results discarded")
    if digest_on_device(args.serial, binary, args.timeout) != binary_digest:
        raise ValueError("Binary changed during benchmarking; results discarded")
    measurements = json.loads(output)
    if not isinstance(measurements, list) or not measurements:
        raise ValueError("llama-bench did not return a nonempty JSON measurement list")
    for row in measurements:
        rate = row.get("avg_ts") if isinstance(row, dict) else None
        if isinstance(rate, bool) or not isinstance(rate, (int, float)) or not math.isfinite(rate) or rate <= 0:
            raise ValueError("Invalid llama-bench tokens/second measurement")
    return {
        "android_api": int(api), "abi": abi, "model_sha256": actual_digest,
        "model_bytes": int(size_text), "binary_sha256": binary_digest,
        "benchmark": measurements,
        "limitations": [
            "llama-bench does not test Aura integration, conversation quality or tool calls",
            "RAM, energy, temperature and offline operation were not measured",
            "model and binary provenance, native dependencies, expected hashes and model license require independent verification",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="Authorized adb device serial")
    parser.add_argument("--binary", required=True, help="Absolute Android path to llama-bench")
    parser.add_argument("--model", required=True, help="Absolute Android path to GGUF")
    parser.add_argument("--sha256", required=True, help="Independently verified GGUF SHA-256")
    parser.add_argument("--binary-sha256", required=True, help="Independently verified llama-bench SHA-256")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--prompt-tokens", type=int, default=512)
    parser.add_argument("--generate-tokens", type=int, default=128)
    parser.add_argument("--timeout", type=int, default=1200)
    args = parser.parse_args()
    try:
        print(json.dumps(run_benchmark(args), ensure_ascii=False, indent=2, allow_nan=False))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Benchmark failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
