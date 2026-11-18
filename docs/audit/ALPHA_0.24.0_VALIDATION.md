# Leo Alpha v0.24.0 — source validation report

## Checks run in this authoring workspace

| Check | Result | Scope |
|---|---:|---|
| Python architecture and contract suite | **154/154 passed** | `python -m unittest discover -s scripts/tests -q` |
| Focused skill-execution contracts | **9/9 passed** | `python -m unittest scripts.tests.test_executable_skills_contract -q` |
| Version synchronization | Passed | `config/VERSION`, channel, Flutter `pubspec.yaml`, Cargo workspace and changelog |
| Version bump policy | Passed | Previous `v0.23.0`, minor bump, next `v0.24.0` |
| Immutable source archive verification | Passed | J.A.R.V.I.S and NEXUS pinned SHA-256 baselines |
| JSON parsing | **10 files** | All project JSON files |
| TOML parsing | **8 files** | All project TOML files |
| YAML parsing | **5 files** | All project YAML/YML files |
| CSV structural validation | **4 files** | Every row has the same field count as its header |

Commands executed:

```bash
python -m unittest scripts.tests.test_executable_skills_contract -q
python scripts/sync_version.py
python scripts/check_version.py --previous v0.23.0 --kind minor --next v0.24.0
python scripts/verify_sources.py
python -m unittest discover -s scripts/tests -q
```

The Python suite includes an isolated fixture test of the voice-evaluation scoring/report utility. Its sample output is not an ASR inference benchmark and does not establish Arabic/English or Sudanese-dialect recognition accuracy.

## Toolchain availability and tests not run

Only the Python test/runtime environment, CMake and Clang++ were available. The following tools were not installed: Flutter, Dart, Cargo and Rust. Android SDK/NDK/Gradle and Windows MSVC build toolchains were not available either.

Consequently, the following checks were **not** run:

- Dart formatting, Flutter Analyze and the Dart unit tests (including `skill_execution_service_test.dart`).
- Rust formatting, Cargo tests, Clippy and Flutter Rust Bridge regeneration.
- Android Kotlin/Gradle compilation or APK build.
- Windows MSVC/CMake compilation or EXE build.
- Real-device secure-storage, process-restart, multi-agent or external-action tests.

The 154 successful tests are Python source/architecture contracts; they do not execute Dart, Rust, Flutter, native plugins, local GGUF inference or device actions. The source package is not yet a verified installable build.

## v0.24.0 implementation boundary

The source adds an explicit preview and user approval for active validated skills on eligible multi-agent tasks, a bounded 8 KiB untrusted skill context, an encrypted skill-run ledger, lifecycle transitions and per-step user review. The ledger avoids duplicating the raw user goal, transcript, tool arguments, file paths and file contents. At capacity, only terminal records can be evicted; active and review-pending runs are retained. Skill acceptance examples are not automatically executed; `verified` is a user attestation, not independent technical proof.

The run ledger uses `flutter_secure_storage`, but its actual Android/Windows encryption provider, backup exclusions, persistence over upgrades/restarts and failure behavior still require tests on the target platforms. No Android or Windows secure-storage claim is treated as physically verified here.
