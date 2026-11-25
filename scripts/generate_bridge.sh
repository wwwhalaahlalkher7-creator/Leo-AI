#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/apps/leo_app"

command -v flutter >/dev/null 2>&1 || { echo "ERROR: Flutter/Dart SDK is required." >&2; exit 2; }
command -v flutter_rust_bridge_codegen >/dev/null 2>&1 || {
  echo "ERROR: Install flutter_rust_bridge_codegen 2.13.0 first." >&2
  exit 2
}

cd "${APP_DIR}"
python3 - <<'PY_FRB_PATHS'
from pathlib import Path
import re

app_dir = Path.cwd().resolve(strict=True)
repo_root = (app_dir / "../..").resolve(strict=True)
config_path = app_dir / "flutter_rust_bridge.yaml"
if not config_path.is_file():
    raise SystemExit(f"ERROR: Flutter Rust Bridge config is missing: {config_path}")

# This project uses a deliberately simple scalar-only FRB YAML config. Keep
# parsing dependency-free so CI does not need PyYAML just for path checks.
values = {}
for line_number, line in enumerate(config_path.read_text(encoding="utf-8").splitlines(), 1):
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$", line)
    if not match:
        raise SystemExit(f"ERROR: Unsupported FRB config syntax at line {line_number}: {line!r}")
    key, raw_value = match.groups()
    value = raw_value.split("#", 1)[0].strip().strip("\"'")
    if key in values:
        raise SystemExit(f"ERROR: Duplicate FRB config key: {key}")
    values[key] = value

# FRB 2.13 uses base_dir as the anchor for rust_root, rust_output and
# dart_output. In this repository base_dir points from apps/leo_app to root.
required_values = {
    "base_dir": "../..",
    "rust_input": "crate::api",
    "rust_root": "core/bridge",
    "rust_output": "core/bridge/src/frb_generated.rs",
    "dart_output": "apps/leo_app/lib/src/rust",
    "dart_root": ".",
}
for key, expected in required_values.items():
    actual = values.get(key)
    if actual != expected:
        raise SystemExit(
            f"ERROR: flutter_rust_bridge.yaml has invalid {key}: "
            f"expected {expected!r}, found {actual!r}."
        )

base_dir = (app_dir / values["base_dir"]).resolve(strict=True)
if base_dir != repo_root:
    raise SystemExit(
        f"ERROR: FRB base_dir must resolve to the repository root: {base_dir}"
    )

crate_root = (base_dir / values["rust_root"]).resolve(strict=True)
rust_output = (base_dir / values["rust_output"]).resolve()
dart_output = (base_dir / values["dart_output"]).resolve()
dart_root = (app_dir / values["dart_root"]).resolve(strict=True)

if crate_root != (repo_root / "core/bridge").resolve(strict=True):
    raise SystemExit(f"ERROR: FRB Rust root resolves outside the expected crate: {crate_root}")
if not rust_output.is_relative_to(crate_root):
    raise SystemExit("ERROR: FRB Rust output must be inside the canonical Rust crate root.")
if not dart_output.is_relative_to((app_dir / "lib").resolve(strict=True)):
    raise SystemExit("ERROR: FRB Dart output must be inside the Flutter app's lib directory.")
if dart_root != app_dir:
    raise SystemExit(f"ERROR: FRB Dart root must be the Flutter app directory: {dart_root}")
if not (crate_root / "Cargo.toml").is_file():
    raise SystemExit(f"ERROR: Rust bridge Cargo.toml is missing: {crate_root / 'Cargo.toml'}")
if not (app_dir / "pubspec.yaml").is_file():
    raise SystemExit(f"ERROR: Flutter pubspec.yaml is missing: {app_dir / 'pubspec.yaml'}")

print(
    "FRB path contract passed: "
    f"base_dir={base_dir}; rust_root={crate_root}; "
    f"rust_output={rust_output}; dart_output={dart_output}; dart_root={dart_root}"
)
PY_FRB_PATHS

# Once both lockfiles have been generated, never silently re-resolve the
# application graph during bridge generation. Qualification CI requires them
# to be checked into source control; the bootstrap workflow may create them.
if [[ "${LEO_REQUIRE_LOCKFILES:-0}" == "1" ]]; then
  python3 "${ROOT_DIR}/scripts/check_dependency_lockfiles.py"
fi
if [[ -s "${APP_DIR}/pubspec.lock" ]]; then
  flutter pub get --enforce-lockfile
else
  if [[ "${LEO_REQUIRE_LOCKFILES:-0}" == "1" ]]; then
    echo "ERROR: apps/leo_app/pubspec.lock is required for qualification." >&2
    exit 2
  fi
  flutter pub get
fi
if [[ -s "${ROOT_DIR}/Cargo.lock" ]]; then
  cargo metadata --manifest-path "${ROOT_DIR}/Cargo.toml" --format-version 1 --locked >/dev/null
elif [[ "${LEO_REQUIRE_LOCKFILES:-0}" == "1" ]]; then
  echo "ERROR: workspace Cargo.lock is required for qualification." >&2
  exit 2
fi
flutter_rust_bridge_codegen generate
