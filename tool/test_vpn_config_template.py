#!/usr/bin/env python3
"""Regression checks for the YAML template emitted by AuraVpnService."""
from pathlib import Path
import re
import sys

SOURCE = Path("android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt")
text = SOURCE.read_text(encoding="utf-8")
match = re.search(
    r"configFile\.writeText\(\s*\"\"\"(.*?)\"\"\"\.trimIndent\(\)",
    text,
    re.DOTALL,
)
if not match:
    sys.exit("FAIL: could not locate the Hev configuration template")

raw = match.group(1)
lines = raw.splitlines()
nonblank = [line for line in lines if line.strip()]
if not nonblank:
    sys.exit("FAIL: Hev configuration template is empty")

indent = min(len(line) - len(line.lstrip()) for line in nonblank)
normalized = [line[indent:] if line.strip() else "" for line in lines]
keys = {}
for line in normalized:
    if not line.strip():
        continue
    if line[0].isspace():
        continue
    key_match = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):(?:\s|$)", line)
    if not key_match:
        sys.exit(f"FAIL: unexpected top-level YAML line: {line!r}")
    key = key_match.group(1)
    if key in keys:
        sys.exit(f"FAIL: duplicate top-level YAML key: {key}")
    keys[key] = True

required = {"tunnel", "socks5", "misc", "mapdns"}
missing = required - keys.keys()
if missing:
    sys.exit("FAIL: missing top-level YAML sections: " + ", ".join(sorted(missing)))

for section in required:
    section_index = next(
        i for i, line in enumerate(normalized)
        if re.match(rf"^{re.escape(section)}:", line)
    )
    if section_index + 1 >= len(normalized) or not normalized[section_index + 1].startswith("  "):
        sys.exit(f"FAIL: section {section!r} has no indented child keys")

for required_line in ("port: $LOCAL_SOCKS5_PORT", "address: $LOCAL_SOCKS5_HOST",
                      "udp: 'tcp'", "log-level: error",
                      "address: 10.0.0.3", "cache-size: 8192"):
    if required_line not in raw:
        sys.exit(f"FAIL: expected configuration entry not found: {required_line}")

print("PASS: Hev YAML template has consistent top-level sections and required fields.")
