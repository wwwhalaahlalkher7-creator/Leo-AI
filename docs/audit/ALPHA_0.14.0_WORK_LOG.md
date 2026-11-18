# Alpha v0.14.0 work log — Voice integrity and runtime resilience

## Delivered in source

- Added direct dependency `crypto 3.0.8` and dev dependency `cross_file ^0.3.5` and streaming SHA-256 hashing for voice-pack import. File bytes are hashed in the same stream that is copied; the full model is not loaded into memory.
- Added versioned `.leo-voice-pack.json` manifests with pack ID, runtime, relative paths, byte counts and per-file digests. Import still uses size caps, staging, replacement and rollback.
- Added duplicate required-filename rejection rather than silently taking whichever duplicate the picker returned last.
- Added manifest structure/path/size/digest validation and explicit user-triggered verification. Same-size model-file changes are detected by the full re-hash.
- Preserved pre-v0.14.0 complete model packs as `legacyUnverified`; users can create a local hash baseline without downloading/importing the 0.94 GB ASR pack again.
- Added clear integrity status in the model library. A failed manifest or digest disables the pack until it is re-imported.
- Added a pure-Dart PCM16 mono WAV encoder with correct RIFF lengths, sample clamping and non-finite sample neutralization; removed the voice service dependency on the native `sherpa.writeWave` file writer.
- Made AudioPlayer lazy and fixed a playback-generation race where a stale TTS request could previously complete a newer request's completer.
- Tightened capture cleanup for stream/plugin errors and reject odd-length PCM16 chunks.
- Added Dart tests for WAV headers/sample encoding and voice-pack import/manifest/re-verification/legacy adoption/duplicate names.

## Version

- `config/VERSION`: `v0.14.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Platform build metadata remains `+4`; no new installable APK/EXE was built in this authoring environment.

## Checks performed here

- Python source/architecture contract suite: **66/66 passed** (`python -m unittest discover -s scripts/tests -v`).
- Version policy check: passed; `v0.14.0`, `ALPHA`, Flutter app metadata and Cargo workspace metadata are synchronized.
- Original source archive verification: J.A.R.V.I.R and NEXUS SHA-256 checksums both match their pinned source baselines.
- Python JSON/TOML/YAML/CSV validations: run as part of the packaging checks; details are recorded in the validation report.
- Version policy and synchronized Flutter/Cargo metadata validation.
- Original J.A.R.V.I.R and NEXUS source archive checksums remain unchanged.
- JSON/TOML/YAML/CSV source validation.
- Source-level checks confirm voice assets are not bundled in Flutter assets and model imports remain streamed and size-bounded.

## Not verified here

Flutter, Dart, Rust, Android SDK/NDK and Windows native toolchains are not installed in this workspace. Therefore the new Dart tests, `flutter analyze`, `flutter test`, `cargo test`, APK build, Windows build and real-device microphone/ASR/TTS smoke tests were not run here. The source package must pass CI and hardware testing before any binary or buildable-release claim. The `cross_file` dependency is used only by the `PlatformFile` unit-test adapter; its BSD-3-Clause notice is retained.

## Integrity boundary

A local SHA-256 manifest detects changes relative to the locally recorded baseline. It does not authenticate the upstream publisher, validate a signed model package, or prove that the initial imported model was trustworthy. The model pack UI instructs users to import only from the upstream project.
