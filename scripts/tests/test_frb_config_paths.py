"""Regression tests for Flutter Rust Bridge 2.13 path resolution."""
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
        # FRB 2.13 Config::from_config_file sets base_dir to the config's parent.
        cls.base = CONFIG.parent.resolve()

    def test_config_parent_is_the_generator_base_directory(self) -> None:
        self.assertEqual(self.base, APP.resolve())
        self.assertNotIn("base_dir", self.values)

    def test_rust_output_uses_canonical_crate_fallback(self) -> None:
        crate_root = (self.base / self.values["rust_root"]).resolve()
        expected_crate = (ROOT / "core" / "bridge").resolve()
        # FRB 2.13 fallback_rust_output_path joins the already canonical
        # rust_crate_dir with src/frb_generated.rs. No config rust_output is set.
        rust_output = crate_root / "src" / "frb_generated.rs"
        expected_output = expected_crate / "src" / "frb_generated.rs"
        self.assertEqual(crate_root, expected_crate)
        self.assertEqual(rust_output, expected_output)
        self.assertNotIn("rust_output", self.values)
        self.assertNotIn("..", rust_output.parts)
        self.assertTrue(rust_output.is_relative_to(crate_root / "src"))

    def test_dart_output_and_root_resolve_to_flutter_package(self) -> None:
        dart_output = (self.base / self.values["dart_output"]).resolve()
        dart_root = (APP / self.values["dart_root"]).resolve()
        self.assertEqual(dart_root, APP.resolve())
        self.assertEqual(self.values["dart_output"], "lib/src/rust")
        self.assertEqual(dart_output, (APP / "lib" / "src" / "rust").resolve())

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
        self.assertIn("Config::from_config_file overwrites the YAML base_dir", generator)
        self.assertIn('if "rust_output" in values:', generator)
        self.assertIn("canonicalized rust_root fallback", generator)
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
