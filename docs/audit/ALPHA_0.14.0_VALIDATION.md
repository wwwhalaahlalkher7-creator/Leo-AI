# Leo Alpha v0.14.0 — source validation report

## Source-level checks completed

| Check | Result | Scope |
|---|---:|---|
| Python architecture and contract suite | **66/66 passed** | All `scripts/tests` test modules |
| Version synchronization | Passed | `config/VERSION`, channel, Flutter pubspec, Cargo workspace, changelog |
| Immutable source archive verification | Passed | J.A.R.V.I.R and NEXUS source ZIP SHA-256 values |
| JSON parsing | 9 files | All JSON source/config files in the workspace |
| TOML parsing | 8 files | All TOML files in the workspace |
| YAML parsing | 5 files | All YAML/YML files in the workspace |
| CSV structural validation | 4 files | All CSV files have consistent column counts |

Commands run:

```bash
python -m unittest discover -s scripts/tests -v
python scripts/check_version.py
python scripts/verify_sources.py
```

The configuration parse/CSV check was performed with Python's JSON, TOML, PyYAML and CSV parsers. The two original archive hashes matched their source baseline values.

## Toolchain availability

The current authoring environment has `cmake` and `clang++`, but does not have `flutter`, `dart`, `cargo` or `rustc`. Android SDK/NDK and the Windows MSVC build toolchain are not available here either.

Consequently, the following have **not** been run:

- `dart format` and `flutter analyze`
- The new Dart tests under `apps/leo_app/test/core/`
- `cargo fmt`, `cargo test` or `cargo clippy`
- Android APK / Windows application builds
- Real-device microphone, Qwen3-ASR or Supertonic inference tests

The 66 passing tests are Python source/architecture contracts. They do not execute Dart, Rust, ONNX models or native audio plugins.

## v0.14.0 scope and boundaries

The source changes implement streamed local SHA-256 voice-pack baselines and re-verification, manifest validation, legacy-pack adoption, a pure-Dart PCM16 WAV encoder, lazy playback creation and playback-generation isolation. These are source-level changes only until the Flutter/Dart/native toolchain and physical-device checks pass.

A local manifest detects changes relative to the recorded files. It does not authenticate model publishers, verify a signed release or prove the initially imported model files are genuine.
