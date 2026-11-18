# Leo Alpha v0.19.0 — source validation report

## Scope

This milestone introduces proposal-only handoff from three action-capable built-in agents to the existing Flutter tool gateway. Rust validates framing and role/tool shape; Dart reparses the complete request and performs a second role check; Capability Hub remains the sole authority for consent, OS permission/resource selection and action confirmation.

## Commands executed and results

| Command / check | Result |
|---|---|
| `python -m unittest discover -s scripts/tests -v` | **100/100 passed** |
| `python scripts/check_version.py` | Passed: `v0.19.0 / ALPHA`; Flutter, Cargo and changelog synchronized |
| `python scripts/check_version.py --previous v0.18.0 --kind minor --next v0.19.0` | Passed: valid minor version bump |
| `python scripts/verify_sources.py` | Passed: both original source archive hashes match |
| JSON parsing | 10 files passed |
| TOML parsing | 8 files passed |
| YAML parsing | 5 files passed |
| CSV structural validation | 4 files passed; consistent column counts |

Pinned immutable source archives verified:

- J.A.R.V.I.R.zip: `ad07e171884c9d01e256a76944ce337b630b3c30e658e0161f513613c70e6331`
- NEXUS-Beta-1.6.zip: `7dc6ce894fa678060db9166c443b65c53a6f7365995d1d157ae82665ccd50349`

The 100 passing tests are Python source/architecture contracts. They do not compile or execute Rust, Dart, Flutter, Flutter Rust Bridge bindings, native device adapters or local model inference.

## Toolchain availability

The authoring environment does not provide `cargo`, `rustc`, `flutter` or `dart`. Android SDK/NDK and Windows MSVC build tools are also unavailable. Consequently:

- Rust unit tests, `cargo fmt`, `cargo test` and Clippy were not run.
- Dart formatting, Flutter analyze/tests and Flutter Rust Bridge code generation were not run.
- Android APK and Windows application builds were not run.
- Physical-device permission, approval, denial/cancellation and tool-result continuation tests were not run.

## Acceptance tests still required in CI/device testing

1. Confirm the agent stream emits exactly one `agent_tool_proposal` event only after a completed task.
2. Verify `file_operator` can propose only selected-file reading; `device_operator` only URL/app handoff; and `communications` only draft/dialer handoff.
3. Confirm unknown, malformed, oversized, cross-role and multiple proposals are rejected without invoking the gateway.
4. Verify every accepted proposal triggers the expected Leo consent, OS/resource permission and separate action confirmation.
5. Deny/cancel each action and confirm no side effect and no success claim; check that the follow-up model does not retry.
6. Approve each supported operation and confirm the bounded native result returns to the local model as untrusted tool data alongside bounded non-proposal agent notes.
7. Confirm tasks with multiple action-focused specialists fall back to the ordinary sequential tool loop and preserve the per-turn three-call limit.
8. Build Android ARM64 and Windows x64 and repeat the above tests on physical devices.

## Integrity boundary

The Rust proposal parser is a pre-filter, not the final argument security validator. Dart performs the full protocol validation immediately before dispatch. Neither parser proves the model's intent; explicit-action routing and the user's per-action approval remain necessary. A proposal is not evidence that the OS operation happened.

This is a source-implemented Alpha milestone, not a verified installable build.
