# Leo Alpha v0.15.0 work log — Voice endpointing and diagnostics

**Product:** Leo AI  
**Application:** Leo  
**Version:** `v0.15.0`  
**Channel:** `ALPHA`  
**Build number:** `4` (unchanged; no installable binary was produced)

## Delivered source changes

- Added `VoicePackKind.voiceActivityDetection`, a separately managed `silero-vad` voice pack and one required `silero_vad.onnx` file.
- Integrated `sherpa_onnx` VAD using the 16 kHz sample stream and 512-sample frames. VAD endpointing is opt-in and triggers the existing stop-and-transcribe operation after the VAD model emits a completed segment.
- Kept captured PCM as the source passed to Qwen ASR; VAD is used for endpoint detection, not to rewrite or trim the ASR recording.
- Preserved manual stop and the 30-second hard cap. If pack inspection, native loading or VAD operation fails, the service falls back to manual stop and immediately reports the reason in the chat UI.
- Added app lifecycle cleanup for capture and playback.
- Refreshes the VAD preference after returning from the voice-model library, so a changed setting takes effect immediately without restarting the chat page.
- Made ASR/TTS native model handles non-nullable after successful construction, keeping the post-construction cleanup path explicit.
- Added native runtime preflight and optional default-off diagnostics. The stored metrics include operation, load/inference durations, process RSS high-watermark, engine/runtime versions, UTC timestamp and an error stage only.
- Added tests for PCM framing, VAD pack import/integrity and metadata-only diagnostics.
- Added architecture decision record `ADR-0020` and updated the voice model catalogue and architecture documentation.

## Privacy and safety boundaries

- Metrics are opt-in, stored in app-private preferences and cleared when the user disables collection.
- No audio, transcript, prompt, model path or model bytes are stored in diagnostic records.
- VAD does not enable background microphone access, a wake word, continuous listening or autonomous sending of recognized text.
- Local SHA-256 manifests remain a local change-detection baseline, not a signed upstream provenance claim.

## Versioning

- `config/VERSION`: `v0.15.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- `config/BUILD_NUMBER`: `4` (unchanged because no new APK/EXE was built)
- Flutter and Cargo metadata are synchronized from the three source-of-truth files.

## Validation limits

The Python architecture/source contract suite passed **74/74 tests**. Version synchronization, the v0.14.0 → v0.15.0 minor-bump policy check, J.A.R.V.I.R/NEXUS archive verification, and parsing of 9 JSON, 8 TOML, 5 YAML and 4 CSV files passed.

This source workspace does not contain Flutter, Dart, Rust/Cargo, Android SDK/NDK or Windows native build tools. Therefore Flutter Analyze, Dart tests, Cargo tests, APK/EXE builds and real microphone/audio tests were not run. See `ALPHA_0.15.0_VALIDATION.md` for checks that were actually executed.
