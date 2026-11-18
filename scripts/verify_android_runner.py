#!/usr/bin/env python3
"""Validate the generated Android runner's security and platform contract."""
from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
FORBIDDEN_PERMISSIONS = {
    "android.permission.MANAGE_EXTERNAL_STORAGE",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.QUERY_ALL_PACKAGES",
}


class AndroidRunnerValidationError(ValueError):
    """Raised when the generated Android project violates Leo's contract."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AndroidRunnerValidationError(message)


def _parse_xml(path: Path) -> ET.Element:
    _require(path.is_file(), f"Required Android XML file is missing: {path}")
    try:
        return ET.parse(path).getroot()
    except ET.ParseError as error:
        raise AndroidRunnerValidationError(f"Invalid XML in {path}: {error}") from error


def _has_shared_preferences_exclusion(root: ET.Element) -> bool:
    return any(
        element.attrib.get("domain") == "sharedpref"
        and element.attrib.get("path") == "."
        for element in root.iter()
    )


def validate_android_runner(app_dir: Path) -> list[str]:
    """Validate runner files and return a concise list of verified properties."""
    app_dir = app_dir.resolve()
    android_dir = app_dir / "android"
    gradle_file = android_dir / "app" / "build.gradle.kts"
    manifest_file = android_dir / "app" / "src" / "main" / "AndroidManifest.xml"

    _require(gradle_file.is_file(), "Android app/build.gradle.kts was not generated.")
    gradle = gradle_file.read_text(encoding="utf-8")
    _require(
        re.search(r'(?m)^\s*namespace\s*=\s*"ai\.leo\.leo_app"\s*$', gradle)
        is not None,
        "Android namespace must remain ai.leo.leo_app.",
    )
    _require(
        re.search(r"(?m)^\s*compileSdk\s*=\s*36\s*$", gradle) is not None,
        "Android compileSdk must be pinned to API 36.",
    )
    _require(
        re.search(r"(?m)^\s*minSdk\s*=\s*28\s*$", gradle) is not None,
        "Android minSdk must be pinned to API 28.",
    )
    _require(
        re.search(r'(?m)^\s*applicationId\s*=\s*"ai\.leo\.leo_app"\s*$', gradle)
        is not None,
        "Android applicationId must remain ai.leo.leo_app.",
    )
    _require(
        re.search(r'(?m)^\s*ndkVersion\s*=\s*"30\.0\.16248370"\s*$', gradle)
        is not None,
        "Android Gradle runner must use the same pinned NDK 30.0.16248370 as the native adapter.",
    )

    manifest = _parse_xml(manifest_file)
    application = manifest.find("application")
    _require(application is not None, "Android manifest has no <application> element.")
    assert application is not None
    _require(
        application.attrib.get(f"{ANDROID_NS}allowBackup") == "false",
        "Android backup must remain disabled because secure-storage keys are device-bound.",
    )
    _require(
        application.attrib.get(f"{ANDROID_NS}fullBackupContent") == "@xml/leo_backup_rules",
        "Android fullBackupContent must reference Leo's SharedPreferences exclusions.",
    )
    _require(
        application.attrib.get(f"{ANDROID_NS}dataExtractionRules") == "@xml/leo_data_extraction_rules",
        "Android dataExtractionRules must reference Leo's cloud/device-transfer exclusions.",
    )

    for permission_tag in ("uses-permission", "uses-permission-sdk-23", "uses-permission-sdk-m"):
        for permission in manifest.findall(permission_tag):
            permission_name = permission.attrib.get(f"{ANDROID_NS}name", "")
            _require(
                permission_name not in FORBIDDEN_PERMISSIONS,
                f"Broad Android permission is not allowed: {permission_name}",
            )

    resources = android_dir / "app" / "src" / "main" / "res" / "xml"
    backup_rules = _parse_xml(resources / "leo_backup_rules.xml")
    extraction_rules = _parse_xml(resources / "leo_data_extraction_rules.xml")
    _require(
        backup_rules.tag == "full-backup-content" and _has_shared_preferences_exclusion(backup_rules),
        "Full backup rules must exclude SharedPreferences.",
    )
    for section_name in ("cloud-backup", "device-transfer"):
        section = extraction_rules.find(section_name)
        _require(section is not None, f"Data extraction rules are missing <{section_name}>.")
        assert section is not None
        _require(
            _has_shared_preferences_exclusion(section),
            f"Android {section_name} must exclude SharedPreferences.",
        )

    # The platform plugin deliberately declares only contact access and a
    # narrowly scoped launcher-intent query; it must never broaden package
    # visibility or request broad external-storage access.
    workspace_root = app_dir.parent.parent
    plugin_manifest = workspace_root / "packages" / "leo_platform_capabilities" / "android" / "src" / "main" / "AndroidManifest.xml"
    plugin = _parse_xml(plugin_manifest)
    plugin_gradle_file = workspace_root / "packages" / "leo_platform_capabilities" / "android" / "build.gradle"
    _require(plugin_gradle_file.is_file(), "The Android platform capability plugin Gradle file is missing.")
    plugin_gradle = plugin_gradle_file.read_text(encoding="utf-8")
    _require(
        re.search(r"(?m)^\s*compileSdk\s+36\s*$", plugin_gradle) is not None,
        "The Android platform capability plugin must compile against API 36.",
    )
    _require(
        re.search(r"(?m)^\s*minSdk\s+28\s*$", plugin_gradle) is not None,
        "The Android platform capability plugin must retain minSdk 28.",
    )
    plugin_permissions = {
        item.attrib.get(f"{ANDROID_NS}name", "")
        for permission_tag in ("uses-permission", "uses-permission-sdk-23", "uses-permission-sdk-m")
        for item in plugin.findall(permission_tag)
    }
    _require(
        "android.permission.READ_CONTACTS" in plugin_permissions,
        "The platform plugin must retain its explicit READ_CONTACTS permission declaration.",
    )
    _require(
        not (plugin_permissions & FORBIDDEN_PERMISSIONS),
        "The platform plugin declares a forbidden broad Android permission.",
    )
    queries = plugin.find("queries")
    _require(queries is not None, "The platform plugin must declare its narrow launcher query.")
    assert queries is not None
    intents = queries.findall("intent")
    _require(
        len(queries) == 1 and len(intents) == 1,
        "The platform plugin may expose only the single launcher intent query.",
    )
    intent = intents[0]
    actions = intent.findall("action")
    categories = intent.findall("category")
    _require(
        len(actions) == 1
        and actions[0].attrib.get(f"{ANDROID_NS}name") == "android.intent.action.MAIN"
        and len(categories) == 1
        and categories[0].attrib.get(f"{ANDROID_NS}name") == "android.intent.category.LAUNCHER",
        "The platform plugin query must be restricted to MAIN + LAUNCHER intents.",
    )

    return [
        "compileSdk=36",
        "minSdk=28",
        "namespace/applicationId=ai.leo.leo_app",
        "NDK=30.0.16248370",
        "application backup disabled",
        "SharedPreferences excluded from cloud/device backup",
        "no broad storage/package-visibility permissions",
        "platform plugin contact permission remains explicit",
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "app_dir",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "apps" / "leo_app",
        help="Path to apps/leo_app (defaults to this workspace's app directory)",
    )
    args = parser.parse_args()
    try:
        verified = validate_android_runner(args.app_dir)
    except (OSError, AndroidRunnerValidationError) as error:
        print(f"ANDROID RUNNER CHECK FAILED: {error}", file=sys.stderr)
        return 1
    print("ANDROID RUNNER CHECK PASSED:")
    for item in verified:
        print(f"  - {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
