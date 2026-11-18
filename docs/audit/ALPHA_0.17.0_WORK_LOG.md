# Leo Alpha v0.17.0 work log — Model resource policy and voice usability

## Delivered in source

- Added `ModelResourcePolicy`, a pure-Dart policy component shared by model inference and offline voice.
- Mirrored the native GGUF loader admission estimate: model file size + one-eighth margin + 384 MiB base reserve + 128 MiB for each rounded-up 2048 context tokens.
- Added supported model context presets (512/1024/2048/4096, filtered against the GGUF-declared maximum), with a default no greater than 2048 tokens.
- Added an explicit context/thread selection dialog before GGUF loading. The recommended model thread budget reserves one logical processor where possible and is capped at four; the user can lower it.
- Kept the native loader's live-memory check authoritative. Android reads `MemAvailable`; Windows reads `GlobalMemoryStatusEx`. A failed or insufficient reading still blocks loading.
- Added process resident/peak memory display to the runtime card, explicitly labeling it as whole-process data.
- Capped VAD/ASR/TTS worker concurrency at one or two CPU threads based on available logical processor count.
- Added a user-confirmed warning before starting voice capture if the local GGUF chat model is already loaded. Leo never unloads that model automatically.
- Added a preflight-in-progress guard to prevent duplicate mic-start dialogs/actions during asynchronous pack, resource and permission checks.
- Updated the reusable offline voice-evaluation template to identify `v0.17.0` as the tested application version.
- Added Dart unit tests for context filtering/defaults, memory arithmetic and CPU budgets; added Python source-contract checks for integration boundaries.

## Version

- `config/VERSION`: `v0.17.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Platform build metadata remains `+4`; no new installable APK/EXE was built here.

## Checks performed here

- Python architecture/contract suite: **90/90 passed**.
- Version bump policy and synchronized Flutter/Cargo metadata: **passed** (`v0.16.0` → `v0.17.0`, minor increment).
- Original J.A.R.V.I.R and NEXUS archive SHA-256 verification: **passed**.
- Host-side fake-llama C ABI contract and Clang Windows-branch syntax check: **passed**; these use test doubles/stub headers, not real native platform builds.
- Structured source validation: **10 JSON, 8 TOML, 5 YAML and 4 CSV files passed**.

## Not verified here

Flutter/Dart/Rust, Android SDK/NDK and Windows MSVC toolchains are not installed in this workspace. The new Dart unit tests, `dart format`, `flutter analyze`, `flutter test`, `cargo fmt`, `cargo test`, native Android/Windows builds and real-device resource/voice tests were not run. The Python contract suite and fake-native C++ tests do not substitute for those checks.

## Resource-policy boundary

The Dart dialog shows a conservative admission estimate; it does not read or promise current free RAM. The native adapter checks live available physical memory immediately before allocation. Process RSS/peak-RSS describes the whole Leo process, not memory attributable to one model. GGUF inference and sherpa voice inference remain CPU-only in this milestone.
