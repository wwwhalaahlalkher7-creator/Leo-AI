# Alpha v0.13.0 work log — Offline voice foundation

## Delivered

- Pinned the offline voice runtime packages: `sherpa_onnx 2.0.1`, `record 7.2.0`, `audioplayers 6.8.1`.
- Kept model weights optional and outside the app asset bundle. Added a registry for Qwen3-ASR 0.6B INT8 and Supertonic 3 INT8.
- Added bounded streaming import with required-file validation, staged replacement and rollback.
- Implemented local PCM16 capture, post-capture Arabic/English transcription in an isolate, transcript insertion into the composer, offline TTS generation in an isolate and local WAV playback.
- Activated microphone just-in-time permission handling with separate Leo consent and OS gating. Android requests `RECORD_AUDIO`; Windows opens the microphone privacy settings on first use. Prior Leo denial can be explicitly revisited by the user.
- Added links to model downloads and documentation through the existing external URL approval path.
- Added Windows runner preparation for audioplayers 6.8.1 CMake requirements.

## Verification performed in this workspace

- Full Python contract suite: 62/62 tests passed, including the native adapter fake-llama host ABI test.
- Version synchronization and policy validation passed (`v0.13.0`, `ALPHA`, Flutter/Cargo versions synchronized).
- Original J.A.R.V.I.R and NEXUS source archive SHA-256 checks passed.
- JSON/TOML/YAML/CSV and source manifest validation passed.
- Source manifest/version validation and focused voice contract tests are in `scripts/tests/test_offline_voice_contract.py`.
- Source-level inspection confirmed no bundled ONNX/GGUF voice model weights in the base app assets.
- The sherpa-onnx Dart API contracts were checked against upstream source, including Qwen3-ASR feature dimension 128 and Supertonic-3 configuration. The ASR catalog language list was aligned to the upstream documentation (30 languages), and TTS speaker ID 0 follows the upstream sample invocation. A playback-generation token now prevents stale speech synthesis from starting after Stop or a newer request. The 30-second recording notice is aligned to the runtime limit, and a UI timer now stops capture at the same limit instead of continuing to hold the microphone open while discarding later samples. Qwen model import now uses two native picker rounds so the root ONNX files and nested tokenizer files can be selected from separate directories.

## Not verified here

Flutter/Dart/Rust SDKs and Android/Windows build toolchains are not installed in this workspace. No `flutter analyze`, `flutter test`, `cargo test`, APK build, Windows EXE build, microphone permission prompt, model inference or physical-device audio test was run here. CI and physical-device validation are required before this feature is called stable.
