# Leo Alpha v0.19.0 work log — Safe agent tool handoff

## Delivered in source

- Added `AgentToolProposal` and `extract_agent_tool_proposal` to the Rust orchestration layer. It scans only successful `file_operator`, `device_operator` and `communications` results.
- Added strict wrapper framing, JSON object shape, protocol version, bounded identifier, 16 KiB envelope limit, exact argument key/type shape and role-to-tool mapping validation.
- Added fail-closed handling for malformed, unsupported, cross-role and multiple proposals. A handoff is emitted only when the full agent task completed successfully.
- Added `agent_tool_handoff_instructions` for action-capable roles. These roles can propose a single tool request but cannot execute native actions, self-authorize or claim success.
- Added a terminal `agent_tool_proposal` event using the existing `AgentTaskEventDto`, plus a bounded `agent_tool_context` event containing successful non-proposal agent notes.
- Added explicit-action routing in chat. Only one action-focused specialist may enter this handoff path; tasks with multiple action specialists fall back to the normal bounded chat tool loop.
- Added a second full-envelope parse and role/tool check in Flutter before `_runToolCall`.
- Reused `ToolExecutionGateway` and `CapabilityHubService`; no new native operation or permission route was added.
- Added bounded agent notes as explicitly untrusted transient system context, then returned the tool result in the existing untrusted tool-result format to the local model for final synthesis.
- Added Rust unit tests for valid role-scoped handoff, cross-role rejection, malformed/multiple proposals and ignoring failed/non-action steps; added Dart role-mapping tests and Python source-contract tests.

## Safety boundaries

- Rust never executes tool proposals. Flutter is the only dispatch point.
- The proposal does not grant Leo consent or operating-system permission and cannot mark an action approved.
- The Capability Hub still performs first-use Leo consent, live OS permission/resource checks, scope validation and separate consequential-action confirmation.
- Only one proposal is accepted per agent task. A task with multiple action-focused specialists uses the ordinary sequential tool loop.
- Only the approved agent/tool mappings are accepted. Full argument safety validation remains in the Dart protocol parser.
- Non-proposal notes and tool results are transient untrusted request context. The existing audit remains metadata-only and does not store arguments, text, file contents or paths.
- A denied, cancelled or failed operation is not reported as success and the resumed model is instructed not to retry it.

## Version

- `config/VERSION`: `v0.19.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Flutter app version: `0.19.0+4`
- Cargo workspace version: `0.19.0`
- `BUILD_NUMBER` remains `4`; no installable binary was created.

## Checks performed in this workspace

- `python -m unittest discover -s scripts/tests -v`: **100/100 tests passed**.
- `python scripts/check_version.py`: passed (`v0.19.0 / ALPHA`; Flutter package, Cargo workspace and changelog synchronized).
- `python scripts/check_version.py --previous v0.18.0 --kind minor --next v0.19.0`: passed.
- `python scripts/verify_sources.py`: passed; immutable J.A.R.V.I.R and NEXUS archive hashes match their pinned baselines.
- Structured data validation: **10 JSON, 8 TOML, 5 YAML and 4 CSV** files parsed; every CSV has consistent row widths.
- Toolchain availability check confirmed `cargo`, `rustc`, `flutter` and `dart` are unavailable in this workspace.

## Not verified here

- Cargo/Rust are unavailable; new Rust tests, `cargo fmt`, `cargo test --workspace` and `cargo clippy` were not run.
- Flutter/Dart are unavailable; Dart format, `flutter analyze`, `flutter test` and Flutter Rust Bridge generation were not run.
- Android SDK/NDK and Windows MSVC toolchains are unavailable; no APK or Windows executable was built.
- No physical-device test of proposal generation, Leo consent, OS permissions, user approval, denial/cancellation or resumed model synthesis was run.

This is a source-implemented Alpha milestone, not a verified installable build.
