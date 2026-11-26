# Android qualification continuation — 2026-11-25

**Target milestone:** `v0.28.0` Android ARM64 qualification  
**Source version:** `v0.27.0 / ALPHA`  
**Result:** reproducibility gate implemented; Android qualification remains blocked.

## Scope completed in this pass

- Added `scripts/check_dependency_lockfiles.py` to validate that the Flutter and Rust lockfiles exist, are valid, contain the required Leo workspace/runtime packages, and are committed before qualification. The one-time bootstrap workflow can explicitly validate generated-but-not-yet-committed lockfiles.
- Added unit tests for missing, malformed, incomplete and untracked lockfiles, plus the bootstrap exception.
- Updated `scripts/generate_bridge.sh` to use `flutter pub get --enforce-lockfile` whenever a Flutter lockfile exists, validate Cargo dependency metadata with `--locked`, and fail early when qualification explicitly requires missing lockfiles.
- Updated Android CI so its qualification build depends on `full-stack` and sets `LEO_REQUIRE_LOCKFILES=1`; it can no longer publish Android qualification APKs from an unpinned dependency resolution.
- Updated the bootstrap workflow to validate both lockfiles before assembling its generated-files bundle.
- Updated the engineering acceptance checklist and remaining-releases roadmap.

## Local validation

- `python -m unittest discover -s scripts/tests -v` — **214/214 passed before the final version/AGP preflight additions**; the updated total is recorded after the final validation run below.
- `python scripts/check_version.py` — **PASS**, source remains `v0.27.0 / ALPHA`.
- `python scripts/verify_sources.py` — **PASS**, immutable source archive hashes unchanged.
- `bash -n scripts/*.sh` — **PASS**.
- YAML parsing of `.github/workflows/*.yml` — **PASS**.

## Explicit blockers

The source archive supplied for this pass does not contain `apps/leo_app/pubspec.lock` or workspace `Cargo.lock`. The bootstrap workflow can generate them only on the pinned Flutter/Rust toolchains; those SDKs are not installed in this authoring environment. The Android qualification job is therefore intentionally blocked until the resulting files are integrated and committed.

This environment also lacks Flutter, Dart, Cargo/rustc, Android SDK/NDK, Gradle Android build tooling and connected Android devices. No FRB generation, Android native build, APK packaging/install, local inference, voice, storage, permission, offline, cancellation, lifecycle, backup/restore or two-device matrix result is claimed.

## Version decision

Do not change `config/VERSION`, `config/BUILD_NUMBER`, `config/RELEASE_CHANNEL`, `pubspec.yaml`, Cargo workspace version or `CHANGELOG.md` for this pass. The v0.28.0 exit criteria require the pinned Android pipeline and two-device acceptance evidence. The project remains `v0.27.0 / ALPHA`.


## Bootstrap workflow failure and correction

The first `Prepare Leo Android Bootstrap Files` run successfully resolved
Flutter and Cargo dependencies but failed in FRB 2.13.0 with:
`Fail to canonicalize .../apps/leo_app/core/bridge`. The script's earlier
preflight had validated `rust_root` against `base_dir`, while the generator
resolved it from the Flutter package working directory.

Corrected `flutter_rust_bridge.yaml` to use
`rust_root: ../../core/bridge`, updated the generator preflight to use the
same anchor as FRB, and added regression assertions. The remaining output
paths stay rooted at `base_dir`. This is a source correction only; FRB codegen
and Android qualification still require a fresh pinned CI run.


## Additional FRB resilience fixes — 2026-11-25

A later bootstrap attempt reached code generation but failed with
`compute_mod_from_rust_path(...): prefix not found`. The first occurrence
showed an output path under `apps/leo_app/core/bridge`; a subsequent run after
changing `rust_root` exposed the remaining anchoring mistake more clearly:
`code_path=apps/leo_app/src/frb_generated.rs` while FRB's Rust module base was
`core/bridge/src`. The latter proves `rust_output: src/frb_generated.rs` was
resolved from the Dart project root, not the Rust crate root.

The corrected configuration now sets
`rust_output: ../../core/bridge/src/frb_generated.rs`, and the preflight
resolves it from `dart_root: .` to the canonical
`core/bridge/src/frb_generated.rs`. A regression test deliberately restores
`src/frb_generated.rs` and confirms the preflight rejects the exact bad path
before FRB runs. The real generator result remains pending the next Actions
run; no Android qualification is claimed yet.

Additional predictable failures addressed in the same pass:

- Pin `cargo-expand 1.0.126` explicitly. For the pinned FRB 2.13.0 CLI,
  verify and pass `--skip-fvm-install` (not the newer `--skip-tool-install`),
  preventing CLI argument mismatch while keeping the Flutter SDK managed by CI.
- Verify all three generated Dart bindings (common, IO, Web), including the
  IO binding consumed by the Native Assets hook.
- Compile `leo-bridge` immediately after generation in the bootstrap workflow,
  so an invalid Rust binding fails before packaging the preparation artifact.
- Require committed dependency lockfiles in full-stack CI.
- Export all common Android NDK environment variable aliases for the native
  asset build hooks.

Local unit tests use mocked Flutter/Cargo/FRB executables to check shell
argument flow and generated-output checks. They do not substitute for real
FRB generation or `cargo check`; those remain pending a fresh Actions run.

## Predictive failure review — FRB, Native Assets and Android packaging

The next review expanded beyond the two observed FRB path failures and checked
all hand-off points from FRB generation through native-asset compilation and APK
validation.

- `generate_bridge.sh` now verifies that `flutter_rust_bridge`,
  `flutter_rust_bridge_hooks` and the Rust bridge crate all use FRB `2.13.0`;
  that the Native Assets hook resolves `cratePath` to the same `core/bridge`
  crate; that `assetName` names the generated IO binding; and that the crate
  has both `cdylib` and `staticlib` outputs plus the pinned Android Rust target.
- The Dart Native Assets dependency is pinned to
  `native_toolchain_rust 1.1.1`. Version `1.1.0` introduced Android 16 KB page
  size support; `1.1.1` also fixes rebuild tracking for Cargo manifests,
  lockfiles, build scripts and toolchain changes. The lockfile checker now
  rejects an older resolved version.
- Full-stack CI now waits for `foundation`; Cargo tests, cross-target checks and
  Clippy use `--locked`. Windows now also verifies the committed lockfiles and
  resolves Flutter packages with `--enforce-lockfile`.
- Android setup exports all four NDK environment names accepted by Dart build
  hooks, including `ANDROID_NDK_LATEST_HOME`.
- APK validation now inspects every packaged AArch64 ELF library's `PT_LOAD`
  segments and rejects 4 KB-only alignment. The APK build additionally runs
  `zipalign -c -P 16 -v 4`, so both ELF segment alignment and APK ZIP alignment
  are checked before checksums are published.

These guards were added because Android's 16 KB page-size requirement applies
to native libraries pulled in directly or transitively, not only to Leo's own
llama.cpp adapter. The Android developer guidance requires checking shared
library ELF segment alignment as well as APK packaging alignment.

## Validation boundary

The ELF validator is covered by synthetic APK tests, including a deliberate
4 KB-aligned failure. FRB generation, the Dart Native Assets hook's real Cargo
build, `zipalign` against a produced APK, and device testing still require the
pinned GitHub Actions environment. No APK has been generated in this workspace.


## Final predictive guards added in this pass

- `generate_bridge.sh` now checks the installed `flutter_rust_bridge_codegen`
  executable's own reported version before invoking it. Installing a pinned
  version in CI is not enough if a developer or cached runner has another
  binary earlier on `PATH`.
- Android runner validation now requires an explicit Android Gradle Plugin
  version of at least `8.5.1`, the minimum documented for reliable 16 KB
  alignment of uncompressed shared libraries. This is checked before APK
  compilation, in addition to checking the actual APK with `zipalign`.
- Added regression tests for a mismatched generator and an AGP version below
  the 16 KB packaging floor.

## Second predictive Android Gradle and transitive-native review — 2026-11-25

A further pass checked the generated Android project hand-off, not just the
FRB paths and native library alignment:

- The generated runner is now checked for executable `gradlew`, wrapper
  scripts, a valid wrapper JAR containing `GradleWrapperMain`, and a pinned
  HTTPS `distributionUrl`. Its Gradle version is compared with the
  minimum supported by the detected AGP version; the pinned Flutter 3.47.1
  template is expected to pair AGP 9.1.x with Gradle 9.3.1 or newer.
- Leo's Android capability plugin still applies
  `org.jetbrains.kotlin.android` and uses the legacy Android Gradle DSL.
  Because AGP 9 enables built-in Kotlin by default, runner generation now
  explicitly writes `android.builtInKotlin=false` and `android.newDsl=false`
  until the app and every plugin complete their migration. Runner validation
  fails if either compatibility setting is missing or overridden to `true`.
- Added a negative APK fixture with a misaligned third-party
  `libsherpa-onnx-c-api.so`. This proves the APK verifier rejects misalignment
  in transitive voice-engine libraries, not only Leo's own llama.cpp library.
  The verifier already enumerates every `.so` under the APK's `lib/` tree.

This review did not upgrade `sherpa_onnx` speculatively. Its upstream 16 KB
alignment issue was fixed in 2025, and the actual APK gate now remains the
source of truth for the exact locked native binaries that get packaged.

## Final validation for this pass

- `python -W error::SyntaxWarning -m unittest discover -s scripts/tests -v` —
  **219/219 passed**.
- `python scripts/check_version.py` — **PASS**, still `v0.27.0 / ALPHA`.
- `python scripts/verify_sources.py` — **PASS**, both immutable source hashes
  remain unchanged.
- `python -m compileall -q scripts` — **PASS**.
- `bash -n scripts/*.sh` — **PASS**.
- PyYAML parsing of both GitHub Actions workflow files — **PASS**.

The environment still does not contain Flutter, Dart, Rust/Cargo, Gradle,
Android SDK/NDK or `zipalign`. Accordingly, these additional checks prove the
source-level guard behavior only; they do not claim that the Flutter template,
Gradle build, Native Assets compilation, APK packaging or a device run has
succeeded. The source baseline remains `v0.27.0 / ALPHA`.


## FRB 2.13.0 CLI flag compatibility correction — 2026-11-25

The latest GitHub Actions attempt successfully passed FRB path validation and
dependency resolution, but stopped immediately because `generate
--skip-tool-install` is not a recognized argument in the pinned 2.13.0
generator. Its CLI usage explicitly advertises `--skip-fvm-install`.

The generation script now checks the installed generator version, inspects
`flutter_rust_bridge_codegen generate --help`, requires the 2.13.0-supported
`--skip-fvm-install` flag, and invokes it. The pinned `cargo-expand 1.0.126`
remains separately installed and version-checked before code generation. A
regression test models the exact 2.13.0 CLI surface and rejects reintroduction
of the unsupported flag.

The local tests validate argument selection with a fake generator; a fresh
GitHub Actions run is still required to confirm actual FRB generation.


## FRB 2.13.0 final path-resolution diagnosis — 2026-11-26

The latest bootstrap run `45759264852` failed before Rust compilation, in
`compute_mod_from_rust_path`. This supersedes the earlier assumption that
`rust_output` should be a relative path anchored from `dart_root`. Inspection
of the pinned FRB 2.13.0 source shows that config loading overrides the YAML
`base_dir` with the config file's parent, canonicalizes `rust_root`, but leaves
an explicitly configured `rust_output` lexical. The project now omits
`base_dir` and `rust_output`, allowing FRB's default output path to be derived
from the canonical Rust crate directory; `dart_output` is relative to the
config parent (`lib/src/rust`). A regression test models this fallback.

Only source-level and hermetic tests have been run locally. The next GitHub
Actions run must verify real FRB generation before `cargo check` and Android
qualification can be considered unblocked.
