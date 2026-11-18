# Leo Alpha v0.27.0 work log — Runtime and conversation resilience

## Delivered in source

- Added `ConversationContextPlanner`, a pure Dart whole-turn context planner. It retains all system instructions and the latest complete user/tool turn, then adds the newest complete historical turns that fit the application-side budget. It never partially retains an older interaction.
- Reads the loaded `context_tokens` value from native runtime diagnostics. The Flutter chat path reserves output tokens and a framing margin before planning the input window. The active input/output allowances are refreshed and reused by normal chat, agent DAG starts, post-tool continuation and restored task recovery.
- Adds a compaction notice when old complete turns are excluded. If mandatory system instructions or the current user/tool turn exceed the estimated input budget, the planner stops with an actionable error. The estimate is intentionally best-effort; llama.cpp tokenization remains authoritative and can trim more complete older turns or reject an oversized current turn.
- Preserves the strict Capability Hub policy as the final system instruction. Memory guidance and approved skill instructions are inserted before that policy and are not allowed to supersede it.
- Added opt-in local runtime benchmarks. Collection defaults to off. Each bounded record contains only UTC timestamp, elapsed milliseconds, output character count, current/peak process RSS, platform and success state. It excludes prompts, answer text, model names, file paths, conversation IDs and request IDs. Retention is limited to 80 records and 48 KiB.
- Throughput uses successful output characters per second only. Failed/cancelled attempts remain in latency and success-rate aggregates but do not inflate throughput. RSS describes the whole Leo process, not only model weights.
- Added a refreshable performance card. Its refresh and clear flows check widget lifecycle state; the model-library refresh path now avoids `setState` after route disposal.
- Model load/unload/context-clear operations are disabled in the UI while generation is active. The native C++ adapter independently protects session mutation with nonblocking `try_to_lock`, avoiding a stale-Diagnostics race from waiting indefinitely.
- Added a fixed 96 MiB available-memory reserve before prompt evaluation and marks native generation active before the preflight so Stop remains responsive during that phase.
- Hardened the Rust/native cancellation handshake. A cancellation is now remembered in the active Rust request state even if C++ has not reached its first callback; the first callback forwards the pending cancellation after `GenerationLifecycle` is active. Request-identity checks prevent a late cancellation from targeting a different request, and the state is cleared when the active request guard drops.
- Added Dart tests for context planning and performance-store behavior, Rust unit coverage for pending cancellation state, Python source-contract coverage, and host fake-llama C ABI tests for model-session contention, low-memory rejection and cancellation during memory preflight.

## Review corrections before packaging

- Recorded a generation as unsuccessful when the chat route is disposed while a request is still active, rather than losing that opted-in benchmark sample.
- Ensured skill context is inserted before the final Capability Hub policy in both regular and multi-agent routes.
- Applied the actual context size/output budget to both action continuation and restored task execution; removed the former fixed 1024-token continuation setting.
- Added an explicit early-return to model-library refresh after disposal and a manual refresh control to the performance card.
- Added a Rust-side pending cancellation flag to close the race where Stop could arrive after request registration but before the native callback. The host C++ test separately exercises cancellation during memory preflight.

## Version

- `config/VERSION`: `v0.27.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Platform build metadata: `0.27.0+4`; build number remains 4 because no new APK/EXE was produced here.

## Validation boundary

Python source-contract tests and the host fake-llama ABI harness are available in this workspace. The Dart planner/store tests and Rust pending-cancellation unit test have been added but are not run here because Flutter/Dart/Cargo/rustc are not installed. The native fake-llama tests are not a substitute for the real pinned llama.cpp Android/Windows builds. FRB code generation and physical device tests remain mandatory before v0.27.0 can be called platform-qualified.
