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
        cls.base = APP.resolve()

    def test_paths_are_relative_to_flutter_package_root(self) -> None:
        self.assertNotIn("base_dir", self.values)
        self.assertEqual(self.base, APP.resolve())

    def test_rust_root_and_output_share_canonical_prefix(self) -> None:
        crate_root = (APP / self.values["rust_root"]).resolve()
        rust_output = (APP / self.values["rust_output"]).resolve()
        self.assertEqual(crate_root, (ROOT / "core" / "bridge").resolve())
        self.assertTrue(rust_output.is_relative_to(crate_root))
        self.assertEqual(
            rust_output,
            (ROOT / "core" / "bridge" / "src" / "frb_generated.rs").resolve(),
        )
        self.assertEqual(self.values["rust_output"], "../../core/bridge/src/frb_generated.rs")

    def test_dart_output_and_root_resolve_to_flutter_package(self) -> None:
        dart_output = (APP / self.values["dart_output"]).resolve()
        dart_root = (APP / self.values["dart_root"]).resolve()
        self.assertEqual(dart_root, APP.resolve())
        self.assertTrue(dart_output.is_relative_to(APP / "lib"))
        self.assertEqual(
            dart_output,
            (APP / "lib" / "src" / "rust").resolve(),
        )

    def test_codegen_preflight_and_workflows_use_bash(self) -> None:
        generator = (ROOT / "scripts" / "generate_bridge.sh").read_text(encoding="utf-8")
        android_builder = (ROOT / "scripts" / "build_android_app.sh").read_text(encoding="utf-8")
        ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
        bootstrap = (
            ROOT / ".github" / "workflows" / "prepare_android_bootstrap_files.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("FRB path contract passed", generator)
        self.assertIn('bash "${ROOT_DIR}/scripts/prepare_android_runner.sh"', android_builder)
        self.assertIn("run: bash scripts/generate_bridge.sh", ci)
        self.assertIn("run: bash scripts/build_android_app.sh", ci)
        self.assertIn("run: bash scripts/generate_bridge.sh", bootstrap)
        self.assertIn("run: bash scripts/prepare_android_runner.sh", bootstrap)


if __name__ == "__main__":
    unittest.main()
