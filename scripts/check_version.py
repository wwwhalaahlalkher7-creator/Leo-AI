#!/usr/bin/env python3
"""Validate Leo's custom vMAJOR.MINOR.PATCH policy and Flutter/Rust version sync."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
CHANNELS = {"ALPHA", "BETA", "RELEASE"}


def parse_version(value: str) -> tuple[int, int, int]:
    match = VERSION_RE.fullmatch(value.strip())
    if not match:
        raise ValueError(f"Invalid version '{value}'. Expected vMAJOR.MINOR.PATCH.")
    return tuple(int(part) for part in match.groups())


def validate_bump(previous: str, next_version: str, kind: str) -> None:
    old = parse_version(previous)
    new = parse_version(next_version)
    expected = {
        "patch": (old[0], old[1], old[2] + 1),
        "minor": (old[0], old[1] + 1, 0),
        "major": (old[0] + 1, 0, 0),
    }[kind]
    if new != expected:
        expected_text = f"v{expected[0]}.{expected[1]}.{expected[2]}"
        raise ValueError(
            f"{kind} bump from {previous} must produce {expected_text}, not {next_version}."
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous", help="Previous version for a bump check")
    parser.add_argument("--kind", choices=("patch", "minor", "major"))
    parser.add_argument("--next", dest="next_version", help="Next version for a bump check")
    args = parser.parse_args()

    try:
        version = (ROOT / "config/VERSION").read_text(encoding="utf-8").strip()
        channel = (ROOT / "config/RELEASE_CHANNEL").read_text(encoding="utf-8").strip()
        policy = json.loads((ROOT / "config/version_policy.json").read_text(encoding="utf-8"))
        major, minor, patch = parse_version(version)
        if channel not in CHANNELS:
            raise ValueError(f"Unknown release channel '{channel}'.")
        if policy.get("current_version") != version:
            raise ValueError("config/version_policy.json current_version is out of sync with config/VERSION.")
        if policy.get("current_channel") != channel:
            raise ValueError("config/version_policy.json current_channel is out of sync with config/RELEASE_CHANNEL.")

        build_number = int((ROOT / "config/BUILD_NUMBER").read_text(encoding="utf-8").strip())
        if build_number < 1:
            raise ValueError("config/BUILD_NUMBER must be a positive integer.")
        pubspec = (ROOT / "apps/leo_app/pubspec.yaml").read_text(encoding="utf-8")
        match = re.search(r"(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$", pubspec)
        if not match:
            raise ValueError("Flutter pubspec must contain version: MAJOR.MINOR.PATCH+BUILD.")
        expected_pub_version = f"{major}.{minor}.{patch}+{build_number}"
        if match.group(1) != expected_pub_version:
            raise ValueError(
                f"pubspec version {match.group(1)} is out of sync; expected {expected_pub_version}."
            )

        cargo_workspace = (ROOT / "Cargo.toml").read_text(encoding="utf-8")
        cargo_match = re.search(r"(?ms)^\[workspace\.package\].*?^version\s*=\s*\"([^\"]+)\"", cargo_workspace)
        if not cargo_match or cargo_match.group(1) != f"{major}.{minor}.{patch}":
            actual = cargo_match.group(1) if cargo_match else "missing"
            raise ValueError(
                f"Cargo workspace version {actual} is out of sync; expected {major}.{minor}.{patch}."
            )

        changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        if f"## {version} — {channel}" not in changelog:
            raise ValueError(f"CHANGELOG.md is missing the heading '## {version} — {channel}'.")

        if any((args.previous, args.kind, args.next_version)):
            if not all((args.previous, args.kind, args.next_version)):
                raise ValueError("A bump check requires --previous, --kind, and --next together.")
            validate_bump(args.previous, args.next_version, args.kind)

        print(f"PASS: {version} / {channel}; pubspec, Cargo workspace and changelog are synchronized.")
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
