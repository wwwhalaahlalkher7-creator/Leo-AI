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
    "rust_root": "../../core/bridge",
    "rust_output": "../../core/bridge/src/frb_generated.rs",
    "dart_output": "lib/src/rust",
    "dart_root": ".",
}
for key, expected in required.items():
    actual = values.get(key)
    if actual != expected:
        raise SystemExit(
            f"ERROR: flutter_rust_bridge.yaml has invalid {key}: "
            f"expected {expected!r}, found {actual!r}."
        )

# FRB 2.13 resolves rust_root and rust_output from its process working
# directory. The generator is deliberately launched from apps/leo_app.
crate_root = (app_dir / values["rust_root"]).resolve(strict=True)
rust_output = (app_dir / values["rust_output"]).resolve()
dart_output = (app_dir / values["dart_output"]).resolve()
if crate_root != (repo_root / "core/bridge").resolve(strict=True):
    raise SystemExit(f"ERROR: FRB Rust root resolves outside the expected crate: {crate_root}")
if not rust_output.is_relative_to(crate_root):
    raise SystemExit("ERROR: FRB Rust output must be inside the canonical Rust crate root.")
if not dart_output.is_relative_to((app_dir / "lib").resolve()):
    raise SystemExit("ERROR: FRB Dart output must be inside the Flutter app's lib directory.")
if not (crate_root / "Cargo.toml").is_file():
    raise SystemExit(f"ERROR: Rust bridge Cargo.toml is missing: {crate_root / 'Cargo.toml'}")
print(f"FRB path contract passed: rust_root={crate_root}; rust_output={rust_output}; dart_output={dart_output}")
PY_FRB_PATHS

flutter pub get
flutter_rust_bridge_codegen generate
