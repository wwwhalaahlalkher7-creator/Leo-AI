Leo-AI FRB base_dir hotfix

Purpose
Fixes the false path validation failure in scripts/generate_bridge.sh.

Replace
Copy scripts/generate_bridge.sh from this ZIP into the repository at:
  scripts/generate_bridge.sh

Then commit and push that file to main. No flutter_rust_bridge.yaml change is needed.

Root cause
The current flutter_rust_bridge.yaml sets base_dir: ../.. and declares rust_root,
rust_output and dart_output relative to that base directory. The previous validator
incorrectly required paths relative to apps/leo_app and rejected the valid config.
The replacement validator resolves all paths using base_dir and validates the
resolved targets instead of imposing the wrong relative strings.

Local validation performed
- bash -n scripts/generate_bridge.sh: passed
- FRB path contract with stub Flutter/codegen executables: passed
- python3 -m unittest discover -s scripts/tests -q: 201 tests passed

Not claimed
The real flutter_rust_bridge_codegen generate command and Android APK build were
not executed in this environment. After pushing this replacement, rerun GitHub Actions
and inspect the next failure, if any.
