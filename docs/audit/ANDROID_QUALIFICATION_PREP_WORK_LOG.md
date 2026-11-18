# Android qualification preparation — work log

**Target milestone:** `v0.28.0` (Android ARM64 qualification)  
**Workspace source version:** `v0.27.0` / `ALPHA`  
**Date:** 2026-11-18  
**State:** qualification tooling strengthened; Android qualification itself remains pending.

## Changes delivered in this preparation pass

- Added a generated Android runner validator for the app ID, compile SDK 36, API 28 minimum, device-bound secure-storage backup exclusions, and prohibited broad storage/package-visibility permissions.
- Connected runner validation to `scripts/prepare_android_runner.sh`, so a generated Flutter scaffold that violates the security/platform contract fails before compilation.
- Pinned both the generated Gradle runner and native Android adapter build to NDK `30.0.16248370`, in addition to the existing llama.cpp source revision, ABI `arm64-v8a` and API 28 checks; CI now installs Android SDK platform 36 and Build Tools `36.0.0` explicitly.
- Extended `scripts/build_android_app.sh` to build debug, release, or both modes from one prepared native adapter and verify every produced APK.
- Added APK verification for ZIP integrity, required Leo native adapter and C++ runtime, AArch64 ELF architecture of every packaged native library, unexpected ABI rejection and accidental model/voice-weight bundling; the build writes an APK SHA-256 manifest alongside the native-library checksums.
- Updated the Android CI job to build and publish both ARM64 debug and release-mode test APKs plus native checksums.
- Added the physical-device qualification protocol in `docs/testing/ANDROID_QUALIFICATION_PROTOCOL.md`.
- Added Python tests for successful and failing runner/APK contract cases.

## Validation performed in this workspace

- `python -m unittest scripts.tests.test_android_qualification_contract -v` — **10/10 passed**.
- `python -m unittest discover -s scripts/tests -q` — **196/196 passed**.
- `bash -n scripts/prepare_android_runner.sh scripts/build_android_native.sh scripts/build_android_app.sh` — passed.
- `python scripts/check_version.py` — passed; source remains `v0.27.0 / ALPHA` and all version metadata is synchronized.
- `python scripts/verify_sources.py` — passed; immutable J.A.R.V.I.R and NEXUS source archive hashes match their baselines.

## Not run / not claimed

- Flutter/Dart format, analyze, tests and dependency resolution.
- Cargo/Rust tests, Android-target Rust compilation, Clippy and FRB generation.
- Real NDK/CMake/llama.cpp Android build, Gradle APK build, APK installation or runtime smoke test.
- Physical Android inference, voice, memory/secure-storage, permission, offline, lifecycle, cancellation and low-memory tests.
- CI execution or real-device evidence.
- The supplied workspace has no committed `apps/leo_app/pubspec.lock` or workspace `Cargo.lock`; generate and commit both with the pinned SDKs before treating dependency resolution as reproducible.

The supplied authoring environment has no Flutter, Dart, Cargo/rustc, Android SDK/NDK, adb or Android Gradle toolchain. The APK verifier tests use synthetic ELF headers and therefore verify the packaging validator logic only; they do not establish that a production Android APK has been built.

## Version decision

Do **not** advance `config/VERSION` to `v0.28.0` in this preparation pass. The roadmap defines `v0.28.0` as Android qualification, including actual Android ARM64 production build and documented physical-device validation. Those exit conditions have not run. The project remains `v0.27.0 / ALPHA` until the automated and real-device gates in `docs/testing/ANDROID_QUALIFICATION_PROTOCOL.md` pass.
