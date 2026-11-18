# Source baseline — Leo Alpha v0.1.0

Date: 2026-11-15. The two source ZIPs supplied for this work are preserved byte-for-byte in `source_refs/`.

## Immutable archive references

| Source | SHA-256 | Archive file size | Extracted files | Internal app/package version | Source revision |
|---|---|---:|---:|---|---|
| J.A.R.V.I.R | `ad07e171884c9d01e256a76944ce337b630b3c30e658e0161f513613c70e6331` | 7,043,971 bytes | 1,017 | Flutter `0.3.2+5`; Dart `^3.12.2` | Git metadata absent from ZIP |
| NEXUS-Beta-1.6 | `7dc6ce894fa678060db9166c443b65c53a6f7365995d1d157ae82665ccd50349` | 510,731 bytes | 274 | Flutter `2.9.0-beta.7+71`; Rust workspace `2.6.2`; Dart `>=3.13.0`; Flutter `>=3.47.0` | Git metadata absent from ZIP |

The extracted tree totals 1,291 source files (J.A.R.V.I.R 1,017; NEXUS 274). Per-file sizes, SHA-256 values, proposed migration decisions, target destinations, and provisional confidence are in `MIGRATION_REGISTER.csv`.

## Findings verified in source

### J.A.R.V.I.R

- Flutter app and backend/server are both present; `android/` and `windows/` platform trees are included.
- The Android application ID is `com.jarvis.assistant`, and the Android label is `JARVIS`.
- Flutter CI pins 3.47.1 and Java 17. The Android Gradle wrapper points to Gradle 9.1.0.
- The package declares Dart `^3.12.2` and version `0.3.2+5`.
- `lib/core/jarvis/jarvis_runtime.dart` constructs `HermesAdapter` from `ApiClient`; `MemoryService` defaults to `EphemeralMemoryService`.
- `server/` is named and implemented as a Hermes Mobile server, not a standalone Leo local runtime.
- The UI has reusable chat rendering for Markdown, LaTeX, code, tables and Mermaid, plus workspace/file/terminal/Git screens. Those screens still require dependency tracing before direct migration.

### NEXUS Beta 1.6

- The package version is `2.9.0-beta.7+71`; Cargo workspace version is `2.6.2`; Rust toolchain is pinned to `1.100.0`.
- Flutter constraints are Dart `>=3.13.0 <4.0.0` and Flutter `>=3.47.0`.
- The llama.cpp implementation is built from external upstream source pinned in NEXUS documentation to `ggml-org/llama.cpp` commit `cd959bae99ff4bed22bef2604f45241c09bbb8c8` (v0.9.0). The source code is not embedded in this ZIP.
- `core/runtime/src/native/engine.rs` has an Android implementation and explicit non-Android stubs that return unavailable. Thus Windows local inference is not implemented in the supplied NEXUS archive.
- `native/llama/CMakeLists.txt` expects `LLAMA_CPP_SOURCE_DIR`; it builds an Android shared adapter named `nexus_llama_probe`.
- NEXUS's Android bootstrap generates its `android/` scaffold; the ZIP does not include an Android platform project directory.
- NEXUS has model management, GGUF inspection, resource policies, local SQLite, knowledge retrieval, agent catalog and sequential task orchestration. Its own README states one local model session and sequential execution rather than parallel inference.
- NEXUS root `Cargo.toml` declares workspace MIT metadata, but a root `LICENSE` file is not present in the supplied ZIP. The llama.cpp MIT notice is included separately.

## Baseline test execution

| Check | Result | Evidence / limitation |
|---|---|---|
| NEXUS host-side Python/C++ contract scripts | **34 passed, 0 failed** | Ran all 34 `scripts/test_*.py` files directly with Python 3.13.5; these scripts compile/run fake C++ ABI tests where applicable. |
| NEXUS Rust tests / formatting / Clippy | Not run | Rust/Cargo absent from this execution environment. |
| NEXUS Flutter analyze / tests / APK build | Not run | Flutter/Dart/Android SDK/NDK absent. |
| J.A.R.V.I.R Flutter analyze / tests / APK/Windows build | Not run | Flutter/Dart and platform build toolchains absent. |
| J.A.R.V.I.R backend regression subset | **14 passed, 2 skipped** | `tests/test_session_live_state.py`: 5 passed. `tests/test_server.py`: 9 passed, 2 skipped. The complete backend suite was not run to completion and remains unverified. |

No source file in either archive has been modified. The original ZIP hashes above are the integrity references.
