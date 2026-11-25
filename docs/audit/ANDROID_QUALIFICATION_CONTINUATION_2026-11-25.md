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

- `python -m unittest discover -s scripts/tests -v` — **210/210 passed**.
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
