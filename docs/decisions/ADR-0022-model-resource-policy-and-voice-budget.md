# ADR-0022: Model resource policy and voice CPU budget

**Status:** Accepted for Alpha v0.17.0  
**Date:** 2026-11-16

## Context

Leo already rejected GGUF loads when live available physical memory was below a conservative native threshold. However, the model screen selected the maximum 4096-token context and up to eight CPU threads without first explaining the resource cost to the user. Voice VAD/ASR/TTS also used fixed thread counts, and it was possible to start Qwen3-ASR while a GGUF chat model remained loaded.

## Decision

1. Add a pure-Dart resource policy that mirrors the native loader's memory admission formula and is unit-tested independently.
2. Ask the user to select a context preset and thread count before loading a GGUF. Default to at most 2048 context tokens and recommend no more than four model threads, reserving a logical processor where possible. The native adapter enforces the same four-thread upper bound.
3. Keep the native adapter as the authoritative admission gate. It must read current available physical memory immediately before allocation and refuse the load if the reading is unavailable or below the threshold.
4. Use one or two CPU threads for VAD/ASR/TTS, based on logical processor count, and never silently assume a GPU provider is available.
5. Warn before voice capture when a local GGUF chat model is loaded. Let the user decide whether to continue; do not unload or mutate their chat model automatically.
6. Label RSS and peak-RSS as whole-process metrics, not per-model allocations or free-memory readings.

## Consequences

### Positive

- Users see the approximate resource threshold before a potentially expensive load.
- Context and CPU concurrency are explicit and user-controlled rather than hidden maximum defaults.
- The same conservative memory formula is testable in Dart while native enforcement remains independent.
- Speech workloads are less likely to monopolize CPU resources on low-core devices.
- Concurrent model memory pressure is surfaced before microphone use without silently destroying the active chat session.

### Trade-offs and limitations

- The UI estimate is not current free RAM and cannot guarantee that a model will load; the native check is authoritative.
- The formula uses GGUF file size as a conservative proxy and does not predict exact allocator, OS cache, mmap or KV-cache RSS behavior.
- CPU thread recommendations are conservative defaults, not hardware benchmarks. Users may need to lower the count for thermal or responsiveness reasons.
- The app still does not choose or validate a GPU execution provider.
- Physical-device tests are required to validate memory pressure and latency across low/mid/high Android hardware and Windows.

## Rejected alternatives

- Automatically lowering the context or thread count after a failed load: rejected because it would silently change user-selected model quality/performance behavior.
- Automatically unloading the chat model before ASR: rejected because it discards a user-visible runtime state without explicit approval.
- Claiming that process RSS is model-only memory or a reading of free RAM: rejected because the native snapshot covers the complete Leo process.
