# Leo AI — CI failure analysis and source corrections

**Source baseline:** `main` at `810428eb28a51899446d4b65f647137a9f03dddc`  
**Application version:** `v0.27.0` / `ALPHA`  
**Review date:** 2026-11-18

## Latest observed runs

- Bootstrap workflow run `44306519276` failed in job `134809402002` at
  **Generate typed Rust and Dart bridge sources**.
- Leo CI run `44304078264` had `foundation` pass and failed in
  `full-stack` job `134800979966` and Android job `134800980270`. Windows was
  skipped because it depends on `full-stack`.

## Confirmed causes

### 1. Non-executable shell scripts

The bootstrap workflow invoked `scripts/generate_bridge.sh` directly while
repository entries use Git mode `100644`. Linux returned exit code `126` and
`Permission denied`. The Android build helper in the source baseline also
called its child shell scripts as executables.

**Correction:** run the scripts with `bash` at workflow and nested-script
call sites. This does not rely on executable file mode and keeps repository
file permissions unchanged.

### 2. Flutter Rust Bridge path canonicalization

FRB 2.13.0 failed with `prefix not found` in
`compute_mod_from_rust_path`. The configuration resolved `rust_root` to a
canonical absolute path, but `rust_output` still contained `../../` segments.
FRB joins `rust_output` to `base_dir` and then derives a Rust module path by
comparing it with the canonical crate root. The lexical path and canonical
path did not share the required prefix.

**Correction:** set `base_dir: ../..` from the `apps/leo_app` codegen working
directory, then express `rust_root`, `rust_output` and `dart_output` relative
to the repository root without parent traversal. Set `dart_root: .` relative
to the Flutter package working directory. A preflight in
`scripts/generate_bridge.sh` checks these roots before starting FRB.

### 3. Android SDK setup regression from the earlier run

Earlier run `44300239883` failed in `android-actions/setup-android@v3` because
its setup attempted to install the obsolete `tools` SDK package. The current
workflow had already moved to `setup-android@v4` and explicit package
installation; the newer run passed that setup step.

## Changed files in this corrected source archive

- `.github/workflows/ci.yml` — current Linux codegen artifact flow, Android
  SDK v4 setup and explicit Bash script invocation.
- `.github/workflows/prepare_android_bootstrap_files.yml` — invoke both shell
  preparation scripts with Bash.
- `apps/leo_app/flutter_rust_bridge.yaml` — canonical root-relative paths.
- `scripts/generate_bridge.sh` — FRB path preflight and explicit generator run.
- `scripts/build_android_app.sh` — invoke nested shell scripts with Bash.
- `README.txt` — repair notes.

## Validation boundary

The changes are source-level repairs. A fresh GitHub Actions run must still
verify generated lockfiles and bridge outputs, Dart formatting/analyze/tests,
Rust formatting/tests/Clippy, Android ARM64 native compilation, and debug plus
release APK packaging. The failed runs did not reach Android native compilation
or APK packaging. This package does not claim that `v0.28.0` has passed Android
qualification or that any APK has been built.


### 4. Flutter Rust Bridge crate-root anchor mismatch (2026-11-25)

The Android bootstrap run passed the local path preflight but FRB 2.13.0 then
failed while canonicalizing `apps/leo_app/core/bridge`. The log proves that
`rust_root` is resolved from the Flutter package working directory for this
configuration; it is not resolved from `base_dir` as the previous preflight
assumed. This was a real mismatch between the custom preflight and the
generator, not a dependency-resolution failure.

**Correction:** use `rust_root: ../../core/bridge` so the generator resolves
the crate to the repository's `core/bridge` directory. Keep
`rust_output: core/bridge/src/frb_generated.rs` and
`dart_output: apps/leo_app/lib/src/rust` anchored to `base_dir: ../..`. Update
the preflight and regression tests to model these distinct anchors. The
bootstrap workflow should be rerun; actual FRB generation is not claimed until
that run passes.
