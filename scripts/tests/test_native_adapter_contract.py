import shutil
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "scripts/tests/native_adapter_contract_runner.py"


class NativeAdapterContractTests(unittest.TestCase):
    def test_host_fake_llama_contract_and_exported_abi(self):
        if not (shutil.which("c++") or shutil.which("clang++")):
            self.skipTest("A C++17 compiler is not installed")
        result = subprocess.run(
            [sys.executable, str(RUNNER)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=120,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        self.assertIn("Host adapter contract and Windows-branch syntax checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
