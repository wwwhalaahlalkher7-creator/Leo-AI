# Leo Alpha v0.20.0 — source validation report

## Scope

This report distinguishes checks actually executed in this authoring environment from Rust/Dart/native checks that require unavailable toolchains.

## Executed checks

| Check | Result | Scope |
|---|---:|---|
| Python architecture/contract suite | See final run below | `scripts/tests/` |
| Version synchronization | Pending final run | `config/VERSION`, Flutter `pubspec.yaml`, Cargo workspace, policy and changelog |
| Original source archive hashes | Pending final run | Immutable J.A.R.V.I.S and NEXUS ZIPs |
| JSON/TOML/YAML/CSV parsing | Pending final run | Source and configuration files |
| ZIP integrity | Pending final run | Final v0.20.0 source archive |
| SHA-256 | Pending final run | Final v0.20.0 source archive |

## Toolchain availability

The authoring environment has Python 3.13.5 and ZIP utilities. It does not have `cargo`, `rustc`, `rustfmt`, `flutter`, `dart`, Android SDK/NDK or the Windows MSVC build toolchain.

Therefore these checks have **not** been run here:

- `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`;
- `dart format`, `flutter analyze`, `flutter test`;
- Flutter Rust Bridge code generation and generated bridge compilation;
- Android APK or Windows application build;
- physical-device permission, serial-action, denial, cancellation, process-restart, voice or local-inference tests.

## v0.20.0 source changes

The source adds a resumable agent DAG with successful-step checkpoints, dependency-closure validation, a bounded exact success receipt, process-local pending state, serial Capability Hub approvals and untrusted result reinjection. The pending state expires after ten minutes, is capped at eight entries and is not persisted. No automatic post-restart execution recovery is included.

The Rust and Dart test files are present but are not represented as passing because their test runners are unavailable in this workspace.

## Required CI and physical qualification before calling the milestone buildable

1. Run Rust formatting, unit tests and Clippy with the pinned toolchain.
2. Regenerate/verify Flutter Rust Bridge bindings if required and run Dart formatting, analysis and tests.
3. Build the Android ARM64 app and Windows x64 app using the documented pinned native dependencies.
4. Verify one, two and three successful serial actions, plus denied/cancelled/failed actions; malformed, mismatched, replayed and expired receipts; task cancellation; and completed-step non-reexecution.
5. Verify that app/process restart loses the volatile continuation without replaying an operation, and that a later user-visible recovery flow is not falsely implied.

## Final package integrity

The final source ZIP passed `unzip -t` with no compressed-data errors. Its SHA-256 was recomputed after packaging and written to the companion `.sha256` sidecar. The sidecar is the exact integrity reference delivered with the ZIP.
