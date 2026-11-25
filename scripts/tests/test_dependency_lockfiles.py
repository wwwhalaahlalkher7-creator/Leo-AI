from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "check_dependency_lockfiles.py"
SPEC = importlib.util.spec_from_file_location("check_dependency_lockfiles", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
lockcheck = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lockcheck)

CARGO_LOCK_TEXT = '''version = 4

[[package]]
name = "leo-bridge"
version = "0.27.0"

[[package]]
name = "leo-capabilities"
version = "0.27.0"

[[package]]
name = "leo-memory"
version = "0.27.0"

[[package]]
name = "leo-orchestration"
version = "0.27.0"

[[package]]
name = "leo-runtime"
version = "0.27.0"

[[package]]
name = "leo-shared"
version = "0.27.0"
'''

PUB_LOCK_TEXT = '''packages:
  audioplayers:
    dependency: "direct main"
    version: "6.8.1"
  flutter_rust_bridge:
    dependency: "direct main"
    version: "2.13.0"
  flutter_rust_bridge_hooks:
    dependency: "direct main"
    version: "2.13.0"
  leo_platform_capabilities:
    dependency: "direct main"
    source: path
    version: "0.12.0"
  native_toolchain_rust:
    dependency: transitive
    description:
      name: native_toolchain_rust
      sha256: fake
      url: "https://pub.dev"
    source: hosted
    version: "1.1.1"
  record:
    dependency: "direct main"
    version: "7.2.0"
  sherpa_onnx:
    dependency: "direct main"
    version: "2.0.1"
sdks:
  dart: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.1"
'''


class DependencyLockfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.cargo = self.root / "Cargo.lock"
        self.pub = self.root / "apps" / "leo_app" / "pubspec.lock"
        self.pub.parent.mkdir(parents=True)
        self.cargo.write_text(CARGO_LOCK_TEXT, encoding="utf-8")
        self.pub.write_text(PUB_LOCK_TEXT, encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def validate_fixture(self):
        with (
            mock.patch.object(lockcheck, "ROOT", self.root),
            mock.patch.object(lockcheck, "CARGO_LOCK", self.cargo),
            mock.patch.object(lockcheck, "PUB_LOCK", self.pub),
            mock.patch.object(lockcheck, "_is_git_tracked", return_value=None),
        ):
            return lockcheck.validate_lockfiles()

    def test_accepts_complete_lockfiles(self):
        checks = self.validate_fixture()
        self.assertEqual(len(checks), 3)

    def test_rejects_missing_cargo_lock(self):
        self.cargo.unlink()
        with self.assertRaisesRegex(lockcheck.LockfileValidationError, "Cargo.lock"):
            self.validate_fixture()

    def test_rejects_invalid_cargo_toml(self):
        self.cargo.write_text("[[package]\nname = ", encoding="utf-8")
        with self.assertRaisesRegex(lockcheck.LockfileValidationError, "valid TOML"):
            self.validate_fixture()

    def test_rejects_missing_workspace_crate(self):
        self.cargo.write_text(CARGO_LOCK_TEXT.replace('name = "leo-memory"\nversion = "0.27.0"\n\n', ""), encoding="utf-8")
        with self.assertRaisesRegex(lockcheck.LockfileValidationError, "leo-memory"):
            self.validate_fixture()

    def test_rejects_missing_direct_flutter_package(self):
        self.pub.write_text(PUB_LOCK_TEXT.replace("  sherpa_onnx:\n    dependency: \"direct main\"\n    version: \"2.0.1\"\n", ""), encoding="utf-8")
        with self.assertRaisesRegex(lockcheck.LockfileValidationError, "sherpa_onnx"):
            self.validate_fixture()

    def test_rejects_native_toolchain_without_16kb_page_alignment_support(self):
        self.pub.write_text(PUB_LOCK_TEXT.replace('version: "1.1.1"', 'version: "1.0.6"'), encoding="utf-8")
        with self.assertRaisesRegex(lockcheck.LockfileValidationError, "16 KB page-size support"):
            self.validate_fixture()

    def test_rejects_untracked_lockfile_outside_bootstrap_mode(self):
        with (
            mock.patch.object(lockcheck, "ROOT", self.root),
            mock.patch.object(lockcheck, "CARGO_LOCK", self.cargo),
            mock.patch.object(lockcheck, "PUB_LOCK", self.pub),
            mock.patch.object(lockcheck, "_is_git_tracked", return_value=False),
        ):
            with self.assertRaisesRegex(lockcheck.LockfileValidationError, "not committed"):
                lockcheck.validate_lockfiles()

    def test_allows_untracked_lockfiles_during_bootstrap_only(self):
        with (
            mock.patch.object(lockcheck, "ROOT", self.root),
            mock.patch.object(lockcheck, "CARGO_LOCK", self.cargo),
            mock.patch.object(lockcheck, "PUB_LOCK", self.pub),
            mock.patch.object(lockcheck, "_is_git_tracked", return_value=False),
        ):
            checks = lockcheck.validate_lockfiles(allow_untracked=True)
        self.assertIn("generated lockfiles validated (bootstrap mode)", checks)


if __name__ == "__main__":
    unittest.main()
