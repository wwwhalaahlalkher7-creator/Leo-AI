# Leo Alpha v0.15.0 — source validation report

## Scope

This report covers static source and repository-contract checks for optional VAD endpointing, lifecycle cleanup, runtime preflight and local diagnostics. It is not a native build report.

## Checks executed

- `python scripts/sync_version.py`
- `python scripts/check_version.py`
- `python scripts/check_version.py --previous v0.14.0 --kind minor --next v0.15.0`
- `python scripts/verify_sources.py`
- `python -m unittest discover -s scripts/tests -q`
- JSON, YAML, TOML and CSV syntax parsing
- ZIP archive integrity (`unzip -t`) and SHA-256 checksum comparison

The exact test totals and command results are recorded in the final delivery response after execution.

## Not executed

- `dart format`, `flutter analyze`, `flutter test`
- `cargo fmt`, `cargo test`, `cargo clippy`
- Android Gradle/NDK build, Windows MSVC build
- Android or Windows microphone, VAD, ASR, TTS, pause/resume and interruption testing

The reason is that Flutter, Dart, Rust/Cargo, Android SDK/NDK and Windows build toolchains are not installed in the authoring environment. No successful APK/EXE build or physical-device behavior is claimed.

## API and model references

The implementation uses the `VoiceActivityDetector` constructor and its `acceptWaveform`, `isEmpty`, `pop` and `free` methods documented by sherpa_onnx 2.0.1. The official sherpa-onnx Silero VAD inventory lists `silero_vad.onnx` at approximately 629 KB and supports 16 kHz input. The `ProcessInfo.maxRss` value is Dart's process RSS high-watermark, not a per-inference delta.

## Packaging result

- `Leo_AI_Alpha_v0.15.0_Workspace.zip` was created from the validated source tree.
- `unzip -t` completed with no archive errors.
- The archive SHA-256 matched the accompanying `.sha256` sidecar (`sha256sum -c` passed).
- The original J.A.R.V.I.R and NEXUS archives remain byte-for-byte unchanged within `source_refs/`.
