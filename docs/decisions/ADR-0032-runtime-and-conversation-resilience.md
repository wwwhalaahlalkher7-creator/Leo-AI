# ADR-0032: Runtime and conversation resilience

**Status:** Accepted for Leo Alpha v0.27.0  
**Date:** 2026-11-18

## Context

The v0.26.0 memory/privacy work completed the last major data-layer milestone before platform qualification. The conversation path still needed explicit context budgeting, model-aware output allowance, consistent handling for agent resume paths, and a dependable Stop path around native startup. Runtime performance data also needed an opt-in, content-free local representation.

## Decisions

1. Add a pure-Dart application context planner that works with complete conversation turns. Keep all system messages and the newest complete user/tool cycle, then preserve newest complete historical turns while they fit. Never slice an interaction or silently drop the current request/system policy.
2. Read the active context size from the native runtime diagnostics DTO and share the derived input/output budget across chat, agent starts, tool continuations and durable task restoration.
3. Treat the planner's character-based token estimate as a hint only. llama.cpp's tokenizer and context limit remain the final authority.
4. Keep the Capability Hub policy as the final system instruction. Skill and memory context may be inserted only before that boundary.
5. Make runtime measurements opt-in by default-off preference and metadata-only. Bounded samples may contain timestamp, elapsed milliseconds, output character count, process RSS values, platform and success status; no prompts, answers, model identifiers, file paths or conversation/request identifiers are permitted.
6. Use nonblocking native session locks for model lifecycle operations and retain a 96 MiB free-memory reserve before prompt evaluation. This is a guard, not an OOM guarantee.
7. Remember cancellation in the active Rust request state, not only in the C++ atomic. The native start callback forwards a pending Stop request once C++ generation is active, closing the request-registration/native-entry race without holding a Rust mutex throughout inference.

## Consequences

- Long histories are compacted at interaction boundaries, with a visible notice, and system/tool policies remain pinned.
- A current request that cannot fit produces an actionable error. Native tokenization may still compact more complete old turns or reject the request.
- Agent continuation uses the currently loaded context/output settings rather than a fixed output limit.
- Benchmark records are useful for coarse local device comparison but are not token/s measurements; throughput is output characters per second and process RSS includes the whole Leo process.
- Users can stop before, during or after native startup without a request cancellation being silently lost. A completion-vs-cancel race at the final native return remains governed by whichever terminal event wins.
- Full Dart/Rust/FRB/native and physical platform validation remains a CI/device gate.

## Alternatives considered

- Blindly keeping the last N messages: rejected because it can split a tool cycle and discard the initial goal or mandatory security policy.
- Treating character count as an exact token count: rejected because tokenizer density differs by model and language.
- Holding the Rust active-request mutex for the complete native generation: rejected because it would block the cancellation call for the entire inference.
- Persisting prompts/answers for benchmarking: rejected to preserve the metadata-only privacy boundary.
- Waiting for the native session mutex during model load/unload: rejected because a long generation could freeze model-management operations; native calls fail fast instead.
