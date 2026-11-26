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

FRB 2.13.0 first failed with `Fail to canonicalize .../apps/leo_app/core/bridge`.
The initial path preflight had modeled `rust_root` against the wrong anchor.

**Correction:** keep `base_dir: ../..`, `rust_root: ../../core/bridge`, and
`dart_root: .`. The preflight resolves `rust_root` from the Flutter app
working directory and validates it against the real `core/bridge` crate.

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


### 4. FRB Rust-output path was still anchored incorrectly (2026-11-25)

The next real bootstrap run got past dependency resolution and the path
preflight, but FRB 2.13.0 still failed in `compute_mod_from_rust_path` with:

- `code_path=.../apps/leo_app/src/frb_generated.rs`
- `base_dir=.../core/bridge/src`
- `prefix not found`

This log is direct evidence that the configured `rust_output` value
`src/frb_generated.rs` was resolved from the Dart project root
(`apps/leo_app`), not from `rust_root`. That produced a generated Rust file
outside the bridge crate, while FRB was deriving the module path relative to
`core/bridge/src`.

**Correction:** set `rust_output` to
`../../core/bridge/src/frb_generated.rs`, which resolves from `dart_root: .`
to the canonical `core/bridge/src/frb_generated.rs`. The preflight now uses
that same anchor and explicitly rejects the former `apps/leo_app/src` path.
A hermetic regression test exercises both the failing value and the corrected
value before allowing the codegen shim to run. Actual FRB generation remains
to be confirmed by the next GitHub Actions run.

### 5. FRB's implicit cargo-expand installation was not reproducible

FRB documentation states that the generator installs `cargo-expand` when it is
missing. That means a clean runner could download a transitive tool at an
unfixed version, or fail while installing it, before actual code generation.

**Correction:** both workflows explicitly install `cargo-expand 1.0.126` with
`--locked`; the generation script verifies that exact version before invoking
FRB. The pinned FRB **2.13.0** CLI does not accept the newer
`--skip-tool-install` spelling; it exposes `--skip-fvm-install`. The script now
checks `generate --help` for that exact flag and invokes the version-compatible
option. This prevents an invalid-argument failure while keeping FVM setup under
CI control; the separately pinned `cargo-expand` is already present before
code generation.

### 6. Generated target-specific Dart bindings were not checked

The Native Assets hook refers to `frb_generated.io.dart`; checking only the
common `frb_generated.dart` could allow a partial FRB output to advance into
Android or Windows packaging.

**Correction:** the generator script and both bootstrap/platform artifact
checks require the common, IO and Web Dart outputs. The Windows job now checks
that all three files arrived in the Linux artifact before it builds.

### 7. The bridge crate was not compiled during the bootstrap gate

The one-time bootstrap previously considered the generated file present to be
enough. A syntactically generated file can still fail to compile against the
bridge API or the pinned `flutter_rust_bridge` runtime.

**Correction:** after FRB output validation, the bootstrap workflow runs
`cargo check --package leo-bridge --locked`. Full-stack CI also requires the
committed Flutter and Cargo lockfiles before code generation. Android native
asset builds now export `ANDROID_NDK`, `ANDROID_NDK_HOME` and `ANDROID_NDK_ROOT`
to cover the environment-variable names consumed by different NDK-aware build
hooks.

## External implementation references

- FRB 2.13 configuration supports a YAML config file and its path-resolution
  options; the project-specific resolution contract is now tested against the
  two path errors actually returned by Actions.
- The published FRB 2.13.0 CLI source exposes `--skip-fvm-install` on
  `generate`; current online tool-installation documentation may describe a
  newer `--skip-tool-install` flag, which is not accepted by this pinned binary.
- FRB's Native Assets guide confirms that `flutter_rust_bridge_hooks` delegates
  Rust compilation to `native_toolchain_rust` and requires a crate with static
  and dynamic library outputs plus pinned Rust targets.

## Validation boundary

The updated source checks script logic and its path contract using unit tests
and fake tool shims. It does **not** run the real FRB compiler locally because
this environment lacks Flutter, Dart and Rust toolchains. A successful fresh
GitHub Actions bootstrap run is still required to confirm real code generation,
`cargo check`, Android scaffold preparation and lockfile generation. No APK,
physical-device qualification or `v0.28.0` completion is claimed.

### 8. Native Assets hand-off and Android 16 KB alignment

A path that passes FRB generation can still fail later when the Dart build hook
tries to compile the Rust crate. The project uses the FRB Native Assets backend;
its hook references a generated IO Dart binding and a crate path relative to
the Dart package root. The bridge also needs both dynamic and static library
outputs and a concrete Rust toolchain containing the Android target.

**Correction:** the FRB preflight now validates the hook's `cratePath` and
`assetName`, exact FRB version parity across pubspec/Cargo, required crate types,
and the pinned Android Rust target before it invokes codegen. This catches
mismatched build-hook paths before Flutter starts a target build.

Android 15+ devices can use 16 KB memory pages. The project now pins
`native_toolchain_rust 1.1.1` (the 1.1.0 line added 16 KB Android support and
1.1.1 fixes native rebuild dependency tracking), keeps NDK `30.0.16248370`, and
exports all NDK environment aliases accepted by Dart hooks. APK verification
checks every packaged ELF `PT_LOAD` segment for at least 16 KB alignment and
runs `zipalign -c -P 16 -v 4` for ZIP alignment.

### 9. CI ordering and lockfile drift

The foundation tests previously ran independently from full-stack checks, so a
foundation failure could still waste a full build. Windows also used a plain
`flutter pub get`, which could resolve packages differently from the committed
lockfile.

**Correction:** full-stack now depends on foundation; Cargo test/type-check/
Clippy commands use `--locked`; Windows validates tracked lockfiles and uses
`flutter pub get --enforce-lockfile`.

## Predictive validation boundary

The Native Assets path and version checks run in a hermetic shell integration
test, and the APK verifier has positive and negative ELF-alignment fixtures.
These checks do not replace real toolchain execution. FRB generation, the
Native Assets Android Cargo build, CMake/NDK compilation, APK creation,
`zipalign`, and real-device launch are still gated on a fresh Actions run.


### 10. Generator binary drift and AGP packaging floor

A pinned install step does not by itself guarantee that the binary resolved
from `PATH` is the pinned one; another preinstalled or cached executable can
win. Also, a runner may compile native ELF files correctly but still package
uncompressed `.so` files incorrectly if the Android Gradle Plugin is below
8.5.1.

**Correction:** `generate_bridge.sh` checks the executable's reported FRB
version before generation. Android runner validation now requires a numeric
AGP version of at least 8.5.1; the built APK is still independently checked
with ELF-header verification and `zipalign -P 16`.

### 11. AGP 9 built-in Kotlin / legacy plugin mismatch

Flutter's Android scaffold is generated with AGP 9.x, while Leo's local
`leo_platform_capabilities` Android module still applies
`org.jetbrains.kotlin.android` and uses the legacy Gradle DSL. AGP 9 enables
built-in Kotlin by default; applying the legacy Kotlin Gradle Plugin without
migrating the app and every plugin can stop Gradle during project
configuration.

**Correction:** `prepare_android_runner.sh` explicitly sets
`android.builtInKotlin=false` and `android.newDsl=false`. The runner verifier
checks both flags, and tests reject an accidentally enabled built-in Kotlin
mode. This is a compatibility bridge, not the final migration; remove these
flags only after every Android module and plugin is migrated and tested.

### 12. AGP and Gradle wrapper version drift

A valid AGP version alone is not enough. The Android Gradle Plugin has a
minimum Gradle wrapper version; for example, AGP 9.1 requires Gradle 9.3.1.
A stale or partially generated wrapper would otherwise fail later at Gradle
startup.

**Correction:** the runner verifier now requires executable `gradlew`, the
wrapper scripts, a valid wrapper JAR containing `GradleWrapperMain`, and a
numeric HTTPS `distributionUrl`. It checks the Gradle version against a small,
explicit AGP compatibility table. An unknown AGP line fails closed and asks
for the compatibility table to be reviewed rather than guessing.

### 13. Misaligned transitive voice-engine native library

Android's 16 KB page-size rule applies to native libraries included by
third-party SDKs as well as libraries built by Leo. The app's
`sherpa_onnx` dependency includes Android native binaries, so validating only
`libleo_llama_backend.so` would leave a predictable gap.

**Correction:** `verify_android_apk.py` checks every `.so` packaged below
`lib/`, including Sherpa/ONNX libraries. Added a regression APK containing an
intentionally 4 KB-aligned `libsherpa-onnx-c-api.so`; validation must reject it.
The production build also retains `zipalign -c -P 16 -v 4` to check APK ZIP
alignment independently of ELF segment alignment.

## Verification boundary

The new regression tests cover the failure conditions above, including a
stale Gradle wrapper, AGP 9 built-in Kotlin accidentally enabled, and a
misaligned third-party `.so`. These are source-level tests with fixtures. They
do not substitute for the real pinned Flutter/Gradle Android build or a
16 KB-device smoke test.
