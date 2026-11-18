# Leo Alpha v0.21.0 — source validation report

## Results

| Check | Result | Scope |
|---|---:|---|
| Python architecture and contract suite | **121/121 passed** | All `scripts/tests` modules |
| Version synchronization | Passed | VERSION, channel, pubspec, Cargo workspace and changelog |
| Version bump policy | Passed | `v0.20.0` → `v0.21.0`, minor feature bump |
| Immutable source archive verification | Passed | J.A.R.V.I.R and NEXUS ZIP SHA-256 values |
| JSON parsing | 10 files | All JSON source/config files |
| TOML parsing | 8 files | All TOML source/config files |
| YAML parsing | 5 files | All YAML/YML source/config files |
| CSV structural validation | 4 files | All CSV files have consistent column counts |
| Android runner shell syntax | Passed | `bash -n scripts/prepare_android_runner.sh` |
| Android backup-rule generation simulation | Passed | Mock Flutter runner; manifest and backup XML rules parsed |
| Final ZIP integrity | Passed | Packaged v0.21.0 workspace |
| Final SHA-256 | Passed | Packaged v0.21.0 workspace |

Commands executed:

```bash
python -m unittest discover -s scripts/tests -q
python scripts/sync_version.py
python scripts/check_version.py
python scripts/check_version.py --previous v0.20.0 --kind minor --next v0.21.0
python scripts/verify_sources.py
bash -n scripts/prepare_android_runner.sh
```

Structured source parsing was performed using Python's JSON, TOML, PyYAML and CSV parsers. The Android runner script was also exercised in a temporary fixture with a mock `flutter create`; this validates the script's manifest/rule transformation, not an Android Gradle build.

## Toolchain availability

The authoring environment does not contain `flutter`, `dart`, `cargo` or `rustc`. Android SDK/NDK and the Windows MSVC/ATL build toolchain are unavailable as well.

Not run:

- `dart format`, `flutter analyze`, `flutter test`
- `cargo fmt`, `cargo test`, `cargo clippy`
- `flutter_rust_bridge` code generation
- Android APK or Windows EXE builds
- Android Keystore restart/upgrade/backup restore tests
- Windows secure-storage process restart and user-profile tests
- Physical multi-agent recovery and external-action handoff tests

## Source changes and validation limits

The source adds an encrypted secure-storage ledger, bounded checkpoint schema, restart-recovery UI, Rust plan/checkpoint revalidation, safe manual recovery for ambiguous external actions, and Android backup exclusions. The Python contract suite is green, but it does not compile Dart or Rust and does not execute secure storage, Flutter Rust Bridge or native platform APIs. This remains a source-implemented Alpha milestone, not a verified installable build.

## Required CI/device gates

1. Run Dart formatting, analyzer and all Dart tests, especially `agent_task_checkpoint_store_test.dart` and `agent_task_continuation_test.dart`.
2. Run Rust formatting, test and clippy suites; regenerate FRB bindings and verify no generated API drift.
3. Build Android and Windows from clean runners with the documented SDK/NDK/MSVC/ATL/CMake matrix.
4. Verify checkpoint encryption and persistence after process death, application upgrade, Android backup exclusions and Windows user-profile boundaries.
5. Exercise interruption before first inference, between steps, during an action proposal, after a successful action result is persisted, during multiple handoffs, after expiry and after explicit Stop.
6. Verify that no external action is ever replayed automatically and that stale/malformed/corrupt checkpoints fail closed.
