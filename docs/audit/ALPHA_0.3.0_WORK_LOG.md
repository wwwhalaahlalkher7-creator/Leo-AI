# Leo Alpha v0.3.0 — local model runtime integration work log

**Status:** Implementation slice added; not build-verified in the current execution environment.

## Implemented

- Added `core/bridge` to the Cargo workspace and defined typed Rust-to-Flutter APIs for health, diagnostics, model listing/import/removal/load/unload, KV-cache clearing, streaming generation and request cancellation.
- Added Flutter Rust Bridge 2.13.0 code-generation configuration and a Native Assets build hook.
- Replaced the temporary MethodChannel chat transport with `FlutterRustBridgeAssistantRuntimeClient`, which uses generated Rust APIs and streams native deltas.
- Prevented duplicate terminal error events when the Rust runtime emits `Failed` and also returns an error.
- Added a Flutter local-model page using the OS file picker and the app-private support directory; no model weights are bundled into the application.
- Added SHA-256 integrity checking and persistent model import lifecycle to the Rust runtime, including invalid GGUF rejection, duplicate IDs, path confinement and recoverable catalogue persistence.
- Added Rust workspace version synchronization to `scripts/check_version.py` and `scripts/sync_version.py`.

## Version

- `config/VERSION`: `v0.3.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Flutter package: `0.3.0+1`
- Cargo workspace package version: `0.3.0`
- Build number remains `1`; no installable binary has yet been produced.

## Verified in this environment

- Python architecture/version/source integrity tests: pending final run in this work slice.
- C++ host adapter contract test uses a fake llama.cpp API and does not prove an upstream llama.cpp build.

## Not verified here

- Rust formatting, compilation, unit tests and Clippy: Cargo/Rust are not installed in this environment.
- Flutter Rust Bridge generation, Dart formatting/analyze/widget tests: Flutter/Dart are not installed in this environment.
- Real llama.cpp Android NDK build and APK packaging: Android SDK/NDK are not installed here. The CI job still needs to run.
- Windows native inference: not implemented in this milestone.

## Next steps

1. Run FRB generation and Rust/Flutter test suites in CI; correct any generator/API/compiler findings.
2. Execute the pinned Android NDK build and package the native adapter into an Android app build.
3. Test GGUF import/load/generate/unload on real ARM64 Android hardware and record RAM/latency results.
4. Implement a Windows native adapter and its app packaging before claiming local inference on Windows.
5. Complete license review for adapted NEXUS source before redistribution.
