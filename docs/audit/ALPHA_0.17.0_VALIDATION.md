# Leo Alpha v0.17.0 — source validation report

## Source-level checks

| Check | Result | Scope |
|---|---:|---|
| Python architecture and contract suite | **90/90 passed** | All `scripts/tests` test modules |
| Version synchronization and bump policy | **PASS** | `v0.16.0 → v0.17.0`, minor increment; `config/VERSION`, release channel, Flutter pubspec, Cargo workspace and changelog |
| Source archive verification | **PASS** | Pinned J.A.R.V.I.S and NEXUS ZIP SHA-256 values |
| Host native adapter contract | **PASS** | C++17 fake-llama C ABI contract, memory refusal, thread-limit rejection and 12 exported Leo ABI symbols |
| Windows native branch syntax | **PASS** | Clang syntax-only compile using test Windows API stub headers; not an MSVC/Windows build |
| JSON parsing | **10 files passed** | All JSON source/config files |
| TOML parsing | **8 files passed** | All TOML source/config files |
| YAML parsing | **5 files passed** | All YAML/YML source/config files |
| CSV structural validation | **4 files passed** | Consistent column counts across all CSV files |

Commands run from the project root:

```bash
python3 -m unittest discover -s scripts/tests -q
python3 scripts/check_version.py --previous v0.16.0 --kind minor --next v0.17.0
python3 scripts/verify_sources.py
python3 scripts/tests/native_adapter_contract_runner.py
```

The native runner compiles the adapter against a deliberately small fake llama.cpp API. It exercises the Leo C ABI contract and compiles the Windows-specific branch against stub Windows headers. This does **not** link the pinned upstream llama.cpp source and is not an Android or Windows application build.

Pinned source archive checks:

- `J.A.R.V.I.R.zip`: `ad07e171884c9d01e256a76944ce337b630b3c30e658e0161f513613c70e6331`
- `NEXUS-Beta-1.6.zip`: `7dc6ce894fa678060db9166c443b65c53a6f7365995d1d157ae82665ccd50349`

## Toolchain availability and unrun checks

Python, CMake and Clang++ are available. Flutter, Dart, Cargo, rustc, Android SDK/NDK and Windows MSVC are not installed in this authoring environment.

Therefore, the following have **not** been run:

- `dart format`, Dart analyzer and the new Dart unit tests under `apps/leo_app/test/core/`.
- `flutter analyze`, `flutter test`, APK build or Windows application build.
- `cargo fmt`, `cargo test` or `cargo clippy`.
- Compilation/linking against the pinned real llama.cpp source or Android/Windows native toolchains.
- Physical-device model-load, low-memory, voice-ASR/VAD/TTS, latency, thermal or battery tests.

The 89 passing tests are Python source/architecture contracts; they do not execute Flutter/Dart or sherpa ONNX model inference. The fake-native contract checks only the adapter boundary against test doubles.

## v0.17.0 implementation and validation boundaries

- The model-load dialog displays a conservative admission estimate. It is **not** a live free-memory reading.
- The native adapter remains the authoritative live available-memory gate immediately before model allocation. Its memory and thread rules were exercised using test doubles on the host.
- The UI allows context presets up to 4096 tokens and recommends no more than four CPU threads. The native adapter rejects a request above four threads and now reports that exact limit.
- Voice VAD/ASR/TTS use a dynamic one-to-two-thread CPU budget. A confirmation is shown when the GGUF chat model is resident; Leo does not unload it automatically.
- RSS/peak-RSS reports the complete Leo process, not model-only memory.

No real Android/Windows device was available. No hardware performance, free-memory behavior under load, actual model-load success or voice-quality claim is made. This is a source milestone with host-side contract checks, not a verified installable build.
