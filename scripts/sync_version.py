#!/usr/bin/env python3
"""Synchronize the Flutter package version from config/VERSION."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def main() -> int:
    version = (ROOT / "config/VERSION").read_text(encoding="utf-8").strip()
    match = VERSION_RE.fullmatch(version)
    if not match:
        raise SystemExit("config/VERSION must follow vMAJOR.MINOR.PATCH")
    major, minor, patch = (int(value) for value in match.groups())
    build_number = int((ROOT / "config/BUILD_NUMBER").read_text(encoding="utf-8").strip())
    if build_number < 1:
        raise SystemExit("config/BUILD_NUMBER must be a positive integer")
    flutter_version = f"{major}.{minor}.{patch}+{build_number}"

    pubspec_path = ROOT / "apps/leo_app/pubspec.yaml"
    pubspec = pubspec_path.read_text(encoding="utf-8")
    if not re.search(r"(?m)^version:\s*[^\n]+$", pubspec):
        raise SystemExit("apps/leo_app/pubspec.yaml has no version field")
    pubspec = re.sub(
        r"(?m)^version:\s*[^\n]+$",
        f"version: {flutter_version}",
        pubspec,
        count=1,
    )
    pubspec_path.write_text(pubspec, encoding="utf-8")

    cargo_path = ROOT / "Cargo.toml"
    cargo = cargo_path.read_text(encoding="utf-8")
    cargo, replacements = re.subn(
        r'(?ms)(^\[workspace\.package\].*?^version\s*=\s*)"[^\"]+"',
        rf'\g<1>"{major}.{minor}.{patch}"',
        cargo,
        count=1,
    )
    if replacements != 1:
        raise SystemExit("Cargo.toml has no [workspace.package] version field")
    cargo_path.write_text(cargo, encoding="utf-8")

    policy_path = ROOT / "config/version_policy.json"
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    policy["current_version"] = version
    policy["current_channel"] = (ROOT / "config/RELEASE_CHANNEL").read_text(encoding="utf-8").strip()
    policy_path.write_text(json.dumps(policy, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Synchronized Flutter package and Rust workspace versions to {flutter_version} from {version}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
