# Leo Alpha v0.18.0 work log — Reliable multi-agent execution

## Delivered in source

- Added `core/orchestration/src/execution.rs` with a validated, dependency-aware task coordinator and a platform-neutral `AgentExecutor` contract.
- Added stable sequential execution of ready DAG steps, bounded conversation/dependency context, bounded step output, progress events and verifier-first final output selection.
- Added explicit retryable/permanent/cancelled failures, two attempts by default (three maximum), dependent-step skipping, independent-branch continuation and partial completion reporting.
- Added reviewed bilingual-safe system instruction profiles for all 13 built-in agents. Every agent is inference-only and explicitly lacks OS/tool authority.
- Added Flutter Rust Bridge task request/event DTOs, execution stream API and request-matched task cancellation. The active native generation request is tracked so stopping one task cannot cancel an unrelated generation.
- Added automatic multi-agent selection in chat for complex reasoning requests. Communications, device operations, file operations and explicit edit/run/build requests continue using the established chat Capability Hub and approval loop.
- Added safeguards for malformed task identifiers, model generation parameters, stream disconnect cancellation and stale chat-page request completion.
- Added Rust unit tests for retry, dependency failure, skipped verifier, cancellation, independent branches and output bounds; added Python architecture/bridge/chat contract tests.
- Updated version metadata to `v0.18.0` / `ALPHA`; platform build number remains `+4` because no installable binary was produced.

## Execution boundaries

- The coordinator runs one model call at a time. Parallel branches in a DAG are queued in stable plan order to respect the current native runtime's single-generation lock and device resource constraints.
- Agent execution is a reasoning workflow only. It does not execute shell commands, filesystem changes, communications, network operations or installed-app actions.
- Those actions remain in the existing tool execution gateway, which independently checks Leo consent, OS permissions and action approval.
- User goals are capped at 6,000 characters. Step outputs are capped at 16,000 characters by default; dependency snippets at 4,000 characters; conversation context at 12,000 characters.
- No durable task history or prompt/output audit store was introduced.

## Checks performed in this workspace

- Python contract suite: **97/97 tests passed** (`python -m unittest discover -s scripts/tests -q`).
- `python scripts/check_version.py`
- `python scripts/check_version.py --previous v0.17.0 --kind minor --next v0.18.0`
- `python scripts/verify_sources.py`
- JSON, TOML, YAML and CSV parser checks as part of the source validation run.
- Archive integrity verification after packaging.
- Parsed all structured source files: 10 JSON, 8 TOML, 5 YAML and 4 CSV files.

## Not verified here

- Cargo/Rust are unavailable. The new Rust scheduler unit tests, `cargo fmt`, `cargo test --workspace` and `cargo clippy` were not run.
- Flutter/Dart are unavailable. FRB code generation, Dart format, `flutter analyze`, `flutter test` and the generated Dart method/DTO signatures were not run.
- Android SDK/NDK and Windows MSVC toolchain are unavailable. No APK or Windows application build was produced.
- No physical-device multi-agent latency, memory, stop/cancel, thermal or long-running regression test was run.

## Current source version

- `config/VERSION`: `v0.18.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Flutter/Cargo metadata: `0.18.0+4` / `0.18.0`
- No new binary artifact; `BUILD_NUMBER` remains `4`.
