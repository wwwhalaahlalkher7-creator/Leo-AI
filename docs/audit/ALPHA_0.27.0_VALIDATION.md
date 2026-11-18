# Leo Alpha v0.27.0 — source validation report

**Version:** `v0.27.0`  
**Channel:** `ALPHA`  
**Platform build metadata:** `0.27.0+4`  
**Validation date:** 2026-11-18

## Results completed in this workspace

| Check | Result | Boundary |
|---|---:|---|
| Python architecture and contract suite | **186/186 passed** | `python -m unittest discover -s scripts/tests -q` |
| Host fake-llama native adapter contract | **1/1 passed** | Includes the host harness checks for native session contention, memory preflight and cancellation during preflight; Windows branch syntax is checked by the harness. |
| Version transition policy | Passed | `v0.26.0` → `v0.27.0`, minor feature increment |
| Version synchronization | Passed | `config/VERSION`, channel, Flutter pubspec metadata, Cargo workspace metadata and changelog |
| Immutable source archive verification | Passed | Pinned J.A.R.V.I.S and NEXUS source ZIP SHA-256 values |
| JSON parsing | **10 files** | All source/config JSON files |
| TOML parsing | **8 files** | All TOML files |
| YAML parsing | **5 files** | All YAML/YML files |
| CSV structural validation | **4 files** | Consistent column counts |

Commands run:

```bash
python -m unittest discover -s scripts/tests -q
python -m unittest scripts.tests.test_native_adapter_contract -v
python scripts/check_version.py --previous v0.26.0 --kind minor --next v0.27.0
python scripts/check_version.py
python scripts/verify_sources.py
```

The source archive hashes matched the immutable baselines:

- J.A.R.V.I.S: `ad07e171884c9d01e256a76944ce337b630b3c30e658e0161f513613c70e6331`
- NEXUS: `7dc6ce894fa678060db9166c443b65c53a6f7365995d1d157ae82665ccd50349`

## Toolchain availability and checks not run

Available: `/usr/bin/cmake`, `/usr/local/swift/usr/bin/clang++`.

Unavailable in this authoring environment:

- Flutter and Dart SDKs
- Cargo and rustc
- Android SDK/NDK and Android Gradle build environment
- Windows MSVC build environment

No `pubspec.lock` or workspace `Cargo.lock` was present in the supplied v0.26.0 source archive. Therefore the following were **not run**:

- `dart format`, `flutter analyze`, `flutter test`
- `cargo fmt`, `cargo test`, `cargo clippy`
- Flutter Rust Bridge code generation and generated-code diff verification
- Production Android/NDK/llama.cpp build or APK packaging
- Production Windows/MSVC/CMake/llama.cpp build or EXE packaging
- Physical Android/Windows inference, audio, lifecycle, cancellation and memory-pressure tests

The 186 passing tests are Python source/architecture contract tests. The host fake-llama ABI test verifies a controlled test adapter and is not a substitute for building or exercising the pinned production llama.cpp runtime on Android or Windows. Dart and Rust unit tests have been added but were not executed here.

## v0.27.0 implementation boundary

This source milestone adds whole-turn application-side context planning, native-context-aware input/output budgets across chat and agent continuations, metadata-only opt-in runtime measurements, nonblocking native session operations, a 96 MiB memory preflight reserve, and a Rust-to-C++ pending-cancellation handshake.

The context planner estimates token cost from character count; it is intentionally not an exact tokenizer. llama.cpp remains authoritative and may trim more complete historical turns or reject an oversized current request. The 96 MiB reserve is a guard, not an OOM guarantee. RSS is process-wide, and throughput is successful output characters per second—not tokens per second.

## Release qualification boundary

`v0.27.0` is **source-implemented but not platform-qualified**. The remaining milestones are:

1. `v0.28.0`: Android production build and real-device qualification.
2. `v0.29.0`: Windows production build and host qualification.
3. `v0.30.0`: integrated Alpha acceptance, security/privacy review and feature freeze.
4. `v1.0.0`: first coherent application entering Beta only after both platform gates pass.
