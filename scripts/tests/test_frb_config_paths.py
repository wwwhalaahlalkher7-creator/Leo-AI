"""Regression tests for Flutter Rust Bridge path canonicalization."""
from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps" / "leo_app"
CONFIG = APP / "flutter_rust_bridge.yaml"


def read_simple_yaml(path: Path) -> dict[str, str]:
    """Read this flat scalar config without requiring PyYAML in CI."""
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*([^#]+?)\s*$", line)
        if match:
            values[match.group(1)] = match.group(2).strip().strip("\"'")
    return values


class FlutterRustBridgePathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.values = read_simple_yaml(CONFIG)
        cls.base = (APP / cls.values["base_dir"]).resolve()

    def test_base_dir_resolves_to_repository_root(self) -> None:
        self.assertEqual(self.base, ROOT.resolve())

    def test_rust_output_is_resolved_from_dart_root_into_the_rust_crate(self) -> None:
        # FRB 2.13 resolves rust_output from dart_root. A crate-relative
        # `src/frb_generated.rs` incorrectly became apps/leo_app/src/... in CI.
        crate_root = (APP / self.values["rust_root"]).resolve()
        dart_root = (APP / self.values["dart_root"]).resolve()
        rust_output = (dart_root / self.values["rust_output"]).resolve()
        expected = (ROOT / "core" / "bridge" / "src" / "frb_generated.rs").resolve()
        self.assertEqual(crate_root, (ROOT / "core" / "bridge").resolve())
        self.assertEqual(rust_output, expected)
        self.assertTrue(rust_output.is_relative_to(crate_root / "src"))
        self.assertNotEqual(rust_output, (APP / "src/frb_generated.rs").resolve())
        self.assertEqual(self.values["rust_root"], "../../core/bridge")
        self.assertEqual(self.values["rust_output"], "../../core/bridge/src/frb_generated.rs")

    def test_dart_output_and_root_resolve_to_flutter_package(self) -> None:
        dart_output = (self.base / self.values["dart_output"]).resolve()
        dart_root = (APP / self.values["dart_root"]).resolve()
        self.assertEqual(dart_root, APP.resolve())
        self.assertTrue(dart_output.is_relative_to(APP / "lib"))
        self.assertEqual(
            dart_output,
            (APP / "lib" / "src" / "rust").resolve(),
        )

    def test_native_assets_hook_matches_the_same_rust_crate_and_io_binding(self) -> None:
        hook = (APP / "hook" / "build.dart").read_text(encoding="utf-8")
        manifest = (ROOT / "core" / "bridge" / "Cargo.toml").read_text(encoding="utf-8")
        pubspec = (APP / "pubspec.yaml").read_text(encoding="utf-8")
        toolchain = (ROOT / "rust-toolchain.toml").read_text(encoding="utf-8")
        self.assertIn("cratePath: '../../core/bridge'", hook)
        self.assertIn("assetName: 'src/rust/frb_generated.io.dart'", hook)
        self.assertEqual((APP / "../../core/bridge").resolve(), (ROOT / "core/bridge").resolve())
        self.assertIn('crate-type = ["cdylib", "staticlib", "rlib"]', manifest)
        self.assertIn('flutter_rust_bridge: 2.13.0', pubspec)
        self.assertIn('flutter_rust_bridge_hooks: 2.13.0', pubspec)
        self.assertIn('native_toolchain_rust: 1.1.1', pubspec)
        self.assertIn('flutter_rust_bridge = "=2.13.0"', manifest)
        self.assertIn('channel = "1.100.0"', toolchain)
        self.assertIn('"aarch64-linux-android"', toolchain)

    def test_codegen_preflight_and_workflows_use_bash(self) -> None:
        generator = (ROOT / "scripts" / "generate_bridge.sh").read_text(encoding="utf-8")
        android_builder = (ROOT / "scripts" / "build_android_app.sh").read_text(encoding="utf-8")
        ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        bootstrap = (
            ROOT / ".github" / "workflows" / "prepare_android_bootstrap_files.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("FRB path contract passed", generator)
        self.assertIn("FRB resolves rust_output from dart_root", generator)
        self.assertIn('rust_output = (dart_root / values["rust_output"]).resolve()', generator)
        self.assertIn("canonical absolute paths", generator)
        self.assertIn('"rust_output": str(expected_rust_output)', generator)
        self.assertIn('flutter_rust_bridge_codegen generate --config-file "${FRB_RUNTIME_CONFIG}" --skip-fvm-install', generator)
        self.assertIn("--config-file", generator)
        self.assertIn("--skip-fvm-install", generator)
        self.assertIn("generate --help", generator)
        self.assertIn("CODEGEN_GENERATE_HELP", generator)
        self.assertIn("flutter_rust_bridge_codegen --version", generator)
        self.assertIn("CODEGEN_VERSION_OUTPUT##* ", generator)
        self.assertIn('CARGO_EXPAND_VERSION="1.0.126"', generator)
        self.assertIn("frb_generated.io.dart", generator)
        self.assertIn("frb_generated.web.dart", generator)
        self.assertIn('bash "${ROOT_DIR}/scripts/prepare_android_runner.sh"', android_builder)
        self.assertIn("run: bash scripts/generate_bridge.sh", ci)
        self.assertIn("run: bash scripts/build_android_app.sh", ci)
        self.assertIn("run: bash scripts/generate_bridge.sh", bootstrap)
        self.assertIn("run: bash scripts/prepare_android_runner.sh", bootstrap)
        self.assertIn("cargo install cargo-expand --version 1.0.126 --locked", ci)
        self.assertIn("cargo install cargo-expand --version 1.0.126 --locked", bootstrap)
        self.assertIn("cargo check --package leo-bridge --locked", bootstrap)
        self.assertIn("needs: foundation", ci)
        self.assertIn("cargo test --workspace --locked", ci)
        self.assertIn("cargo clippy --workspace --all-targets --locked", ci)
        self.assertIn("ANDROID_NDK_LATEST_HOME", ci)
        self.assertIn("flutter pub get --enforce-lockfile", ci)


if __name__ == "__main__":
    unittest.main()
