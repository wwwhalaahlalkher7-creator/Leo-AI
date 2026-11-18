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

app_dir = Path.cwd().resolve()
repo_root = (app_dir / "../..").resolve()
config_path = app_dir / "flutter_rust_bridge.yaml"
values = {}
for line in config_path.read_text(encoding="utf-8").splitlines():
    match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*([^#]+?)\s*$", line)
    if match:
        values[match.group(1)] = match.group(2).strip().strip("\"'")

required = {
    "base_dir": "../..",
    "rust_root": "core/bridge",
    "rust_output": "core/bridge/src/frb_generated.rs",
    "dart_output": "apps/leo_app/lib/src/rust",
    "dart_root": ".",
}
for key, expected in required.items():
    actual = values.get(key)
    if actual != expected:
        raise SystemExit(
            f"ERROR: flutter_rust_bridge.yaml has invalid {key}: "
            f"expected {expected!r}, found {actual!r}."
        )

crate_root = (repo_root / values["rust_root"]).resolve()
rust_output = (repo_root / values["rust_output"]).resolve()
dart_output = (repo_root / values["dart_output"]).resolve()
if not rust_output.is_relative_to(crate_root):
    raise SystemExit("ERROR: FRB Rust output must be inside the canonical Rust crate root.")
if not dart_output.is_relative_to(app_dir / "lib"):
    raise SystemExit("ERROR: FRB Dart output must be inside the Flutter app's lib directory.")
if (app_dir / values["dart_root"]).resolve() != app_dir:
    raise SystemExit("ERROR: FRB dart_root must resolve to apps/leo_app.")
print("FRB path contract passed: Rust/Dart outputs resolve from canonical roots.")
PY_FRB_PATHS

flutter pub get
flutter_rust_bridge_codegen generate
