#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_DIR="${ROOT_DIR}/apps/leo_app"
RUST_ROOT="${ROOT_DIR}/core/bridge"
RUST_OUTPUT="${RUST_ROOT}/src/frb_generated.rs"
DART_OUTPUT="${APP_DIR}/lib/src/rust"
FRB_CODEGEN_VERSION="2.13.0"
CARGO_EXPAND_VERSION="1.0.126"

for tool in flutter dart cargo python3; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "ERROR: ${tool} is required to generate the Rust/Dart bridge." >&2
    exit 2
  }
done
command -v flutter_rust_bridge_codegen >/dev/null 2>&1 || {
  echo "ERROR: Install flutter_rust_bridge_codegen ${FRB_CODEGEN_VERSION} first." >&2
  exit 2
}
CODEGEN_VERSION_OUTPUT="$(flutter_rust_bridge_codegen --version 2>&1 | tail -n 1 | tr -d '\r')"
if [[ "${CODEGEN_VERSION_OUTPUT##* }" != "${FRB_CODEGEN_VERSION}" ]]; then
  echo "ERROR: Expected flutter_rust_bridge_codegen ${FRB_CODEGEN_VERSION}; found '${CODEGEN_VERSION_OUTPUT}'." >&2
  echo "Install with: cargo install flutter_rust_bridge_codegen --version ${FRB_CODEGEN_VERSION} --locked" >&2
  exit 2
fi

# FRB can silently install cargo-expand when it is absent. Pin it ourselves
# and make FRB fail-fast instead, so bootstrap/CI never depends on a floating
# transitive tool version.
EXPAND_VERSION="$(cargo expand --version 2>&1 | tail -n 1 | tr -d '\r')"
if [[ "${EXPAND_VERSION}" != "cargo-expand ${CARGO_EXPAND_VERSION}" ]]; then
  echo "ERROR: Expected cargo-expand ${CARGO_EXPAND_VERSION}; found '${EXPAND_VERSION}'." >&2
  echo "Install with: cargo install cargo-expand --version ${CARGO_EXPAND_VERSION} --locked" >&2
  exit 2
fi

cd "${APP_DIR}"
python3 - <<'PY_FRB_PATHS'
from pathlib import Path
import re
import tomllib

app_dir = Path.cwd().resolve(strict=True)
repo_root = (app_dir / "../..").resolve(strict=True)
config_path = app_dir / "flutter_rust_bridge.yaml"
if not config_path.is_file():
    raise SystemExit(f"ERROR: Flutter Rust Bridge config is missing: {config_path}")

# This project intentionally keeps a flat scalar-only FRB config. Parse it
# without a third-party YAML dependency, rejecting duplicate/unknown syntax.
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

required_values = {
    "base_dir": "../..",
    "rust_input": "crate::api",
    "rust_root": "../../core/bridge",
    # FRB resolves rust_output relative to rust_root, not the Flutter app.
    "rust_output": "src/frb_generated.rs",
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
    raise SystemExit(f"ERROR: FRB base_dir must resolve to repository root: {base_dir}")

dart_root = (app_dir / values["dart_root"]).resolve(strict=True)
if dart_root != app_dir:
    raise SystemExit(f"ERROR: FRB dart_root must resolve to the Flutter app: {dart_root}")

crate_root = (dart_root / values["rust_root"]).resolve(strict=True)
expected_crate_root = (repo_root / "core/bridge").resolve(strict=True)
if crate_root != expected_crate_root:
    raise SystemExit(f"ERROR: FRB rust_root resolves to {crate_root}, expected {expected_crate_root}")

# Critical fix: FRB joins rust_output to rust_root, then derives the module
# path from core/bridge/src. Joining it to APP_DIR created the observed
# apps/leo_app/core/bridge/src/frb_generated.rs and triggered StripPrefix.
rust_output = (crate_root / values["rust_output"]).resolve()
expected_rust_output = (crate_root / "src/frb_generated.rs").resolve(strict=False)
if rust_output != expected_rust_output:
    raise SystemExit(f"ERROR: FRB rust_output resolves to {rust_output}; expected {expected_rust_output}")
if not rust_output.is_relative_to((crate_root / "src").resolve(strict=True)):
    raise SystemExit("ERROR: FRB rust_output must be inside core/bridge/src.")

dash_output = (base_dir / values["dart_output"]).resolve()
if dash_output != (app_dir / "lib/src/rust").resolve(strict=False):
    raise SystemExit(f"ERROR: FRB dart_output resolves to unexpected path: {dash_output}")
if not dash_output.is_relative_to((app_dir / "lib").resolve(strict=True)):
    raise SystemExit("ERROR: FRB Dart output must be inside apps/leo_app/lib.")

for required in (
    crate_root / "Cargo.toml",
    app_dir / "pubspec.yaml",
    app_dir / "hook/build.dart",
    crate_root / "src/lib.rs",
    repo_root / "rust-toolchain.toml",
):
    if not required.is_file():
        raise SystemExit(f"ERROR: Required FRB/Native Assets project file is missing: {required}")

# Keep the Dart package, Rust crate and generator on one exact FRB version.
pubspec = (app_dir / "pubspec.yaml").read_text(encoding="utf-8")
for package in ("flutter_rust_bridge", "flutter_rust_bridge_hooks"):
    match = re.search(rf"(?m)^  {re.escape(package)}:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$", pubspec)
    if not match or match.group(1) != "2.13.0":
        found = match.group(1) if match else "missing or non-exact"
        raise SystemExit(f"ERROR: {package} must be pinned to 2.13.0; found {found}.")
if not re.search(r"(?ms)^dependency_overrides:\s*.*?^  native_toolchain_rust:\s*1\.1\.1\s*$", pubspec):
    raise SystemExit("ERROR: native_toolchain_rust must be pinned to 1.1.1 for 16 KB Android alignment and reliable rebuild tracking.")

bridge_manifest = tomllib.loads((crate_root / "Cargo.toml").read_text(encoding="utf-8"))
bridge_dependency = bridge_manifest.get("dependencies", {}).get("flutter_rust_bridge")
if bridge_dependency != "=2.13.0":
    raise SystemExit(
        "ERROR: core/bridge must depend on flutter_rust_bridge = 2.13.0; "
        f"found {bridge_dependency!r}."
    )
crate_types = set(bridge_manifest.get("lib", {}).get("crate-type", []))
if not {"cdylib", "staticlib"}.issubset(crate_types):
    raise SystemExit(
        "ERROR: Native Assets requires the bridge crate to emit both cdylib and staticlib; "
        f"found {sorted(crate_types)}."
    )

# Flutter Native Assets resolves cratePath from the root of the Dart project.
# Validate it here so the first path failure cannot be deferred to a build hook.
hook_source = (app_dir / "hook/build.dart").read_text(encoding="utf-8")
crate_path_match = re.search(r"cratePath:\s*'([^']+)'", hook_source)
asset_name_match = re.search(r"assetName:\s*'([^']+)'", hook_source)
if not crate_path_match or not asset_name_match:
    raise SystemExit("ERROR: FRB Native Assets hook must declare cratePath and assetName.")
hook_crate_root = (app_dir / crate_path_match.group(1)).resolve(strict=True)
if hook_crate_root != expected_crate_root:
    raise SystemExit(
        "ERROR: Native Assets hook cratePath resolves to "
        f"{hook_crate_root}; expected {expected_crate_root}."
    )
if asset_name_match.group(1) != "src/rust/frb_generated.io.dart":
    raise SystemExit(
        "ERROR: Native Assets assetName must reference the generated IO binding; "
        f"found {asset_name_match.group(1)!r}."
    )

rust_toolchain = tomllib.loads((repo_root / "rust-toolchain.toml").read_text(encoding="utf-8"))
toolchain = rust_toolchain.get("toolchain", {})
if toolchain.get("channel") != "1.100.0":
    raise SystemExit("ERROR: Native Assets must use the pinned Rust toolchain 1.100.0.")
if "aarch64-linux-android" not in toolchain.get("targets", []):
    raise SystemExit("ERROR: rust-toolchain.toml must include aarch64-linux-android.")

print(
    "FRB path contract passed: "
    f"base_dir={base_dir}; rust_root={crate_root}; "
    f"rust_output={rust_output}; dart_output={dash_output}; dart_root={dart_root}; "
    f"native_assets_crate={hook_crate_root}; asset={asset_name_match.group(1)}"
)
PY_FRB_PATHS

# Once both lockfiles are generated, never silently re-resolve the dependency
# graph during qualification. The bootstrap workflow is the only exception.
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

# Prevent FRB from installing a floating cargo-expand version behind our
# back. --skip-tool-install converts a hidden network/tool install into a
# deterministic missing-tool diagnostic.
flutter_rust_bridge_codegen generate --skip-tool-install

# Fail in the codegen step, not much later in the Android hook, if a target
# binding is absent or generated by a different FRB version.
if [[ ! -s "${RUST_OUTPUT}" ]]; then
  echo "ERROR: FRB did not generate ${RUST_OUTPUT}." >&2
  exit 3
fi
if ! grep -Eq '@generated by `flutter_rust_bridge`@ 2\.13\.0|FLUTTER_RUST_BRIDGE_CODEGEN_VERSION: &str = "2\.13\.0"' "${RUST_OUTPUT}"; then
  echo "ERROR: Generated Rust bridge does not identify FRB ${FRB_CODEGEN_VERSION}." >&2
  exit 3
fi
for generated in \
  "${DART_OUTPUT}/frb_generated.dart" \
  "${DART_OUTPUT}/frb_generated.io.dart" \
  "${DART_OUTPUT}/frb_generated.web.dart"; do
  if [[ ! -s "${generated}" ]]; then
    echo "ERROR: FRB did not generate required binding: ${generated}" >&2
    exit 3
  fi
done

echo "FRB ${FRB_CODEGEN_VERSION} generated and verified Rust, common Dart, IO Dart and Web Dart bindings."
