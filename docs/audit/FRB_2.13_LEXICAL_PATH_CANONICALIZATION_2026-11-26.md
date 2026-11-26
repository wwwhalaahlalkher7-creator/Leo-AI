# FRB 2.13.0 lexical path canonicalization — 2026-11-26

## Latest failure evidence

The 2026-11-26 `Prepare Leo Android Bootstrap Files` attempt reached the FRB
code generator after dependency resolution, then failed in
`compute_mod_from_rust_path`:

```text
code_path=".../apps/leo_app/../../core/bridge/src/frb_generated.rs"
base_dir=".../core/bridge/src"
prefix not found
```

The configured relative destination resolves to the correct file on disk, but
FRB 2.13.0 retained the lexical `..` segments in `code_path`. Its module-path
calculation compared that lexical value against the canonical Rust `src`
folder. The earlier Python preflight called `Path.resolve()`, which normalized
the path and therefore failed to model the exact string/path representation
passed to FRB.

## Source correction

The checked-in `apps/leo_app/flutter_rust_bridge.yaml` remains portable and
repository-relative. `scripts/generate_bridge.sh` now:

1. Validates the checked-in relative path contract and all existing Native
   Assets / version / toolchain requirements.
2. Resolves the repository, Rust crate, generated Rust file, Flutter package
   and Dart output directories to canonical absolute paths.
3. Creates a short-lived runtime config which replaces only the five path
   fields (`base_dir`, `rust_root`, `rust_output`, `dart_output`, `dart_root`)
   with those absolute paths. Other FRB options remain unchanged.
4. Verifies that every runtime path is absolute and contains no `..` segment.
5. Checks that the pinned FRB 2.13.0 CLI advertises both `--config-file` and
   `--skip-fvm-install`, then runs:

   ```bash
   flutter_rust_bridge_codegen generate \
     --config-file "$FRB_RUNTIME_CONFIG" \
     --skip-fvm-install
   ```

6. Removes the temporary config on exit and verifies the generated Rust,
   common Dart, IO Dart and Web Dart bindings.

This avoids changing repository structure, hard-coding a runner path, or
relying on FRB to normalize a relative path containing `..`.

## Validation performed

- `python3 -W error::SyntaxWarning -m unittest discover -s scripts/tests -v` —
  **219/219 passed**.
- The hermetic `generate_bridge.sh` integration test inspects the exact
  temporary config argument received by a fake FRB executable, checks all
  path values are canonical absolute paths without `..`, and has the fake
  generator write all four expected outputs.
- `python3 scripts/check_version.py` — **PASS**, source remains
  `v0.27.0 / ALPHA`.
- `python3 scripts/verify_sources.py` — **PASS**, J.A.R.V.I.S and NEXUS source
  archives match their recorded SHA-256 hashes.
- `python3 -m compileall -q scripts` — **PASS**.
- `bash -n scripts/*.sh` — **PASS**.
- PyYAML parsed both GitHub Actions workflow files — **PASS**.

## Verification boundary

Flutter, Dart, Cargo/Rust and `flutter_rust_bridge_codegen` are not installed
in this authoring environment. The new test proves that the shell script
passes canonical absolute paths through the pinned CLI's documented config
file interface, but it does not execute the real FRB compiler. The next
acceptance criterion is a fresh GitHub Actions run that generates and compiles
the bridge. Android native-asset compilation, APK packaging and physical
device qualification remain blocked until that succeeds.

No version, build number, release channel, dependency version or production
signing configuration was changed. The project remains `v0.27.0 / ALPHA`.
