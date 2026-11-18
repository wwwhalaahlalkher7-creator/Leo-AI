# Alpha v0.16.0 work log — Voice quality evaluation and session safety

## Delivered in source

- Added `scripts/voice_eval.py`, a dependency-free local evaluator for human-checked reference/hypothesis pairs.
- Added corpus-level WER and CER, deterministic Arabic/English normalization, language-specific results, per-sample error counts, inference/model-load median and p95, and maximum process RSS metadata.
- Added strict JSON schema checks, opaque sample-ID validation, transcript-size limits, allow-listed coarse device metadata and rejection of audio bytes, audio paths, recording paths, prompts and unsupported fields.
- Generated reports exclude transcript/reference text and audio. Test datasets are not included in the repository; the JSON template contains placeholders only.
- Added a 9-test suite for normalization, WER/CER weighting, language grouping, percentile summaries, empty hypotheses, privacy rejection, metadata sanitization, malformed input and CLI output.
- Hardened `LeoVoiceService` against overlapping recording/transcription operations, added a capture-generation token, and discard results after cancellation or lifecycle changes.
- Lifecycle changes now cancel both active recording and a pending capture/transcription preparation. Expected cancellation is not shown as an ordinary error notification.
- Added ADR-0021, voice quality evaluation instructions, and updated the offline voice architecture and Alpha roadmap.

## Version

- `config/VERSION`: `v0.16.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Flutter app package: `0.16.0+4`
- Cargo workspace: `0.16.0`
- Build metadata remains `+4`; no new installable Android/Windows artifact was built here.

## Checks performed here

- Python architecture and contract suite: **85 tests passed**.
- Version synchronization and policy validation: passed (`v0.16.0 / ALPHA`).
- Original J.A.R.V.I.R archive SHA-256: passed.
- Original NEXUS archive SHA-256: passed.
- JSON/TOML/YAML/CSV validation: 10 JSON, 8 TOML, 5 YAML and 4 CSV files parsed successfully.
- Voice-evaluator CLI smoke test: passed on temporary synthetic test input; generated report did not contain transcript contents.
- ZIP integrity and final SHA-256 checked after packaging.

## Not verified here

Flutter, Dart, Rust, Android SDK/NDK and Windows native build tools are not installed in this workspace. `dart format`, `flutter analyze`, Flutter unit/widget tests, `cargo fmt`, `cargo test`, Android APK build, Windows build and physical-device voice tests were not run. The voice evaluator itself was tested; actual model WER/CER, latency and memory results remain unmeasured.

## Important validation boundary

The 85 passing tests are Python architecture/contract/evaluator tests. They do not execute Flutter, Dart, Sherpa/ONNX, Qwen3-ASR, Supertonic, the microphone plugin or Android/Windows native audio code. No recognition-quality or performance claim is made by this milestone.
