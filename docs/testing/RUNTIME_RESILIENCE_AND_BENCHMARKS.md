# Runtime resilience and benchmark test protocol

This document defines the required CI and device tests for v0.27.0. It is a test protocol, not evidence that Android/Windows qualification has already passed.

## Automated checks

1. Dart tests:
   - Complete conversation retained when it fits.
   - All system instructions and the newest complete user/tool turn pinned during compaction.
   - Newest historical turn preferred over older turns.
   - Initial user goal retained only when it fits.
   - Oversized current request or mandatory system instructions rejected with an actionable exception.
   - Runtime benchmark opt-in defaults to off; stored field allowlist is metadata-only; records are bounded and can be cleared.
   - Failed/cancelled output is excluded from output-character throughput but remains in latency/success-rate statistics.
2. Rust tests:
   - Active request ID gates cancellation.
   - Cancellation is remembered before the native start callback and cleared when the matching active request guard drops.
3. Native host contract:
   - Model load/unload/context mutation returns immediately when generation owns the session.
   - Insufficient available memory returns the documented failure code before token streaming.
   - Cancellation injected during memory preflight returns the cancellation result without prompt/output callbacks.
   - Windows native branch syntax is checked with the host compiler harness; this does not replace the MSVC runner.
4. CI quality gates:
   - `dart format`, `flutter analyze`, `flutter test`.
   - `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`.
   - Flutter Rust Bridge regeneration and generated-code diff review.
   - Pinned Android NDK/llama.cpp and Windows MSVC/CMake/llama.cpp builds.

## Physical Android and Windows matrix

For each device/host, record exact OS/build, CPU, RAM, model file checksum, GGUF context, requested context and selected CPU threads.

- Short prompt: confirm output is delivered and the process returns to idle.
- Long conversation: use varied Arabic/English/code/tool cycles; confirm the planner notice is shown when old turns are omitted, the latest turn stays whole and the final native tokenizer does not discard the latest request or system policy.
- Tool continuation: make an agent propose an approved tool call; confirm the proposal/result cycle remains intact after compaction and completed agent steps are not repeated.
- Oversized input: submit a request that alone exceeds the selected context; confirm Leo reports a failure and does not fabricate a response.
- Context switch: while generation is running, attempt model load, unload and KV-context clear from another route; confirm they fail fast and the model remains intact.
- Stop before native start, during memory preflight, during prompt evaluation, during decode and just before completion. Confirm no next request is cancelled by a late Stop and no cancelled request continues streaming after its terminal event.
- Background/route disposal: navigate away or background the app during generation. Confirm cancellation, partial visible text persistence and no silent auto-resume.
- Low memory: reduce free RAM to below the configured reserve; confirm a clear failure before prompt evaluation, no crash and no model/session corruption. Test with Android per-app limits because system-wide `MemAvailable` is not identical to the app's effective memory limit.
- Model lifecycle: repeatedly load/unload/switch models after completed generation and verify memory counters, active context and model catalogue remain consistent.

## Benchmark procedure

1. Keep benchmark collection off for the baseline; confirm no benchmark entries are written.
2. Enable collection explicitly in Model Library.
3. Run at least 10 identical prompts per model/context/device after one warm-up. Do not compare unlike prompts or different quantizations as if they were controlled runs.
4. Record median/P95 latency, successful output characters per second, process current/peak RSS and success rate. Do not call characters/second tokens/second.
5. Repeat at 512, 1024, 2048 and 4096 context where the GGUF header supports each setting; include memory pressure and a long history case.
6. Disable collection; verify new records stop. Clear records and verify the local record list is empty.
7. Inspect serialized preference keys and confirm the record schema contains only timestamp, elapsed time, output characters, RSS values, platform and success state.

## Acceptance boundary

A passing Python source-contract suite is not a substitute for Dart/Rust tests or a real platform build. v0.28.0 Android qualification and v0.29.0 Windows qualification must attach device/runner logs for the checks above before Alpha can be frozen in v0.30.0.
