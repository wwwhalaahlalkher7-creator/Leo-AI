import importlib.util
import json
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "check_version.py"
SPEC = importlib.util.spec_from_file_location("leo_version_policy", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class VersionPolicyTests(unittest.TestCase):
    def test_current_format_is_valid(self):
        root = Path(__file__).resolve().parents[2]
        current = (root / "config/VERSION").read_text(encoding="utf-8").strip()
        policy = json.loads((root / "config/version_policy.json").read_text(encoding="utf-8"))
        self.assertEqual(len(MODULE.parse_version(current)), 3)
        self.assertEqual(policy["current_version"], current)
        self.assertEqual(policy["current_channel"], (root / "config/RELEASE_CHANNEL").read_text(encoding="utf-8").strip())

    def test_patch_bump(self):
        MODULE.validate_bump("v0.1.0", "v0.1.1", "patch")

    def test_minor_bump_resets_patch(self):
        MODULE.validate_bump("v0.1.8", "v0.2.0", "minor")

    def test_major_bump_resets_minor_and_patch(self):
        MODULE.validate_bump("v0.9.8", "v1.0.0", "major")

    def test_rejects_wrong_patch_bump(self):
        with self.assertRaises(ValueError):
            MODULE.validate_bump("v0.1.0", "v0.2.0", "patch")

    def test_rejects_invalid_version_prefix(self):
        with self.assertRaises(ValueError):
            MODULE.parse_version("0.1.0")

    def test_rejects_leading_zero(self):
        with self.assertRaises(ValueError):
            MODULE.parse_version("v0.01.0")


if __name__ == "__main__":
    unittest.main()
