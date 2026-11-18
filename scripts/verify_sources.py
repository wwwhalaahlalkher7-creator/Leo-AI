#!/usr/bin/env python3
"""Verify the immutable source ZIPs against the recorded SHA-256 manifest."""
from __future__ import annotations

import hashlib
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "source_refs/SHA256SUMS.txt"


def main() -> int:
    failures: list[str] = []
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        expected, name = line.split(maxsplit=1)
        archive = ROOT / "source_refs" / name
        if not archive.is_file():
            failures.append(f"Missing source archive: {name}")
            continue
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if actual != expected:
            failures.append(f"SHA-256 mismatch for {name}: expected {expected}, got {actual}")
            continue
        with zipfile.ZipFile(archive) as source_zip:
            bad_member = source_zip.testzip()
        if bad_member is not None:
            failures.append(f"Corrupt ZIP member in {name}: {bad_member}")
            continue
        print(f"PASS: {name} ({actual})")
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
