# Leo Alpha v0.20.0 work log — Multi-step tool-aware task continuation

## Delivered in source

- Added explicit `AwaitingToolApproval` state to the agent coordinator. The coordinator stops the DAG as soon as a valid action specialist emits one proposal.
- Added resumable DAG execution from initial successful results. Completed steps remain as checkpoints and are not executed again.
- Hardened restored checkpoints: step ID and agent must match the plan; status must be successful; errors are forbidden; attempts/output remain bounded; duplicates are rejected; every dependency of a restored step must also be present as a successful checkpoint.
- Added serial tool handoffs for multi-agent tasks. The existing three-tool-call user-turn budget is retained; no tool batch is accepted.
- Added exact six-field success receipts tied to the task, call ID and tool name. Receipts are versioned and bounded.
- Added process-local continuation state with a 10-minute TTL, eight-pending-task cap, one continuation per task and safe matching-before-consumption behavior.
- Fixed the continuation context so successful prior agent outputs and successful tool results are included as bounded untrusted reference data for remaining agents.
- Added Flutter continuation receipt encoding and resumed execution only after a successful `ToolExecutionOutcome` from the existing Capability Hub path. Denial, cancellation and failure stop the chain.
- Added Rust coordinator/bridge unit tests, Dart receipt tests and Python source-contract tests.

## Safety and state boundary

- No Rust coordinator path directly executes OS tools. The proposal is revalidated in Flutter and dispatched through `ToolExecutionGateway` / `CapabilityHubService`.
- Per-action approval is preserved; a permission grant is not treated as approval for a particular consequential action.
- The handoff limit is three successful actions per user turn, one at a time.
- Continuations are held in process memory only, expire after ten minutes, and are limited to eight pending tasks. They are lost after the application process exits or restarts; automatic recovery/replay is deliberately not implemented.
- Invalid, expired, mismatched or replayed receipts fail closed and do not consume a valid pending continuation.
- A restored checkpoint is rejected if a dependency is omitted, preventing a fabricated downstream result from skipping prerequisite work.

## Version

- `config/VERSION`: `v0.20.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- `config/BUILD_NUMBER`: remains `4`; no APK/EXE was created in this authoring environment.

## Validation performed in this workspace

- `python -m unittest discover -s scripts/tests -q`: **110 tests passed**.
- `python scripts/sync_version.py`: passed; Cargo workspace and Flutter metadata synchronized to `0.20.0+4`.
- `python scripts/check_version.py --previous v0.19.0 --kind minor --next v0.20.0`: passed.
- `python scripts/verify_sources.py`: passed; original J.A.R.V.I.R and NEXUS archive SHA-256 values match the recorded baselines.
- JSON/TOML/YAML/CSV parsing: **10 JSON, 8 TOML, 5 YAML and 4 CSV files** parsed with no structural errors.
- Final ZIP passed `unzip -t`; the final SHA-256 was computed into the companion `.sha256` sidecar.

## Not run / not verified

- `cargo fmt`, `cargo test`, `cargo clippy` and Rust compiler checks: Cargo/Rust are not installed.
- Dart formatting, `flutter analyze`, `flutter test`: Flutter/Dart are not installed.
- FRB code generation and generated-binding compile validation.
- Android ARM64 APK build/device tests and Windows x64 build/device tests.
- Real-device multi-action scenarios, permission dialogs, app restart behavior, latency and memory measurements.

The Rust and Dart unit tests are source additions, not test passes. The milestone is source-implemented Alpha, not a verified installable build.
