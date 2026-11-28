#!/usr/bin/env python3
"""Validate the checked-in Flutter and Rust lockfiles before qualification."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CARGO_LOCK = ROOT / "Cargo.lock"
PUB_LOCK = ROOT / "apps" / "leo_app" / "pubspec.lock"
REQUIRED_CARGO_PACKAGES = {
    "leo-bridge",
    "leo-capabilities",
    "leo-memory",
    "leo-orchestration",
    "leo-runtime",
    "leo-shared",
}
REQUIRED_PUB_PACKAGES = {
    "audioplayers",
    "flutter_rust_bridge",
    "flutter_rust_bridge_hooks",
    "leo_platform_capabilities",
    "native_toolchain_rust",
    "record",
    "sherpa_onnx",
}


class LockfileValidationError(ValueError):
    """Raised when dependency resolution is not reproducible."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise LockfileValidationError(message)


def _normalize_pub_lock(text: str) -> str:
    """Make pubspec.lock parsing independent of BOM, CRLF and trailing blanks."""
    text = text.lstrip("\ufeff").replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join(line.rstrip() for line in text.split("\n"))


def _top_level_keys(text: str) -> list[str]:
    return re.findall(r"(?m)^[\"']?([A-Za-z0-9_.-]+)[\"']?\s*:", text)


def _describe_pub_lock(path: Path, text: str) -> str:
    """Short, log-friendly description so a failing CI run shows the real content."""
    head = "\n".join(text.split("\n")[:12])
    return (
        f"size={path.stat().st_size} bytes; top-level keys={_top_level_keys(text)!r}; "
        f"first lines:\n{head}"
    )


def _is_git_tracked(path: Path) -> bool | None:
    """Return tracking state, or None when this directory has no Git metadata."""
    try:
        result = subprocess.run(
            ["git", "ls-files", "--error-unmatch", str(path.relative_to(ROOT))],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    if result.returncode == 0:
        return True
    if "not a git repository" in result.stderr.lower():
        return None
    return False


def validate_lockfiles(*, allow_untracked: bool = False) -> list[str]:
    for path in (CARGO_LOCK, PUB_LOCK):
        _require(path.is_file(), f"Required dependency lockfile is missing: {path.relative_to(ROOT)}")
        _require(path.stat().st_size > 0, f"Dependency lockfile is empty: {path.relative_to(ROOT)}")
        tracked = _is_git_tracked(path)
        if tracked is False and not allow_untracked:
            _require(
                False,
                f"Dependency lockfile is not committed to source control: {path.relative_to(ROOT)}. "
                "Integrate the generated bootstrap files before platform qualification.",
            )

    try:
        cargo_data = tomllib.loads(CARGO_LOCK.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise LockfileValidationError(f"Cargo.lock is not valid TOML: {error}") from error

    cargo_names = {
        item.get("name")
        for item in cargo_data.get("package", [])
        if isinstance(item, dict)
    }
    missing_cargo = sorted(REQUIRED_CARGO_PACKAGES - cargo_names)
    _require(
        not missing_cargo,
        "Cargo.lock is missing Leo workspace packages: " + ", ".join(missing_cargo),
    )

    pub_text = _normalize_pub_lock(PUB_LOCK.read_text(encoding="utf-8-sig"))
    section = lambda name: re.search(  # noqa: E731
        rf"(?m)^[\"']?{name}[\"']?\s*:\s*(?:#.*)?$", pub_text
    )
    _require(
        section("packages") is not None and section("sdks") is not None,
        "pubspec.lock does not have the expected packages/sdks sections. "
        + _describe_pub_lock(PUB_LOCK, pub_text),
    )
    pub_names = set(
        re.findall(r"(?m)^  [\"']?([A-Za-z0-9_]+)[\"']?:\s*(?:#.*)?$", pub_text)
    )
    missing_pub = sorted(REQUIRED_PUB_PACKAGES - pub_names)
    _require(
        not missing_pub,
        "pubspec.lock is missing required Flutter packages: " + ", ".join(missing_pub),
    )
    native_toolchain_block = re.search(
        r"(?ms)^  native_toolchain_rust:\n(.*?)(?=^  [A-Za-z0-9_]+:\n|^sdks:\s*$)",
        pub_text,
    )
    _require(native_toolchain_block is not None, "pubspec.lock has no native_toolchain_rust package block.")
    assert native_toolchain_block is not None
    native_toolchain_version = re.search(
        r"(?m)^    version:\s*[\"]?([0-9]+\.[0-9]+\.[0-9]+)[\"]?\s*$",
        native_toolchain_block.group(1),
    )
    _require(native_toolchain_version is not None, "Cannot read native_toolchain_rust version from pubspec.lock.")
    assert native_toolchain_version is not None
    version_tuple = tuple(int(part) for part in native_toolchain_version.group(1).split("."))
    _require(
        version_tuple >= (1, 1, 0),
        "native_toolchain_rust >= 1.1.0 is required for Android 16 KB page-size support; "
        f"lockfile selected {native_toolchain_version.group(1)}.",
    )
    return [
        f"Cargo.lock: {len(cargo_names)} packages; all six Leo workspace crates present",
        f"apps/leo_app/pubspec.lock: {len(pub_names)} packages; native_toolchain_rust {native_toolchain_version.group(1)} and native/runtime packages present",
        "lockfiles are committed" if not allow_untracked else "generated lockfiles validated (bootstrap mode)",
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--allow-untracked",
        action="store_true",
        help="Allow newly generated lockfiles in the one-time bootstrap workflow.",
    )
    args = parser.parse_args()
    try:
        checks = validate_lockfiles(allow_untracked=args.allow_untracked)
    except (OSError, LockfileValidationError) as error:
        print(f"DEPENDENCY LOCKFILE CHECK FAILED: {error}", file=sys.stderr)
        return 1
    print("DEPENDENCY LOCKFILE CHECK PASSED:")
    for item in checks:
        print(f"  - {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
