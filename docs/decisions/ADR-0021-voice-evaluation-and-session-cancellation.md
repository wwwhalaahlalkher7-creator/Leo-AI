# ADR-0021: Local voice evaluation and capture-session cancellation

**Status:** Accepted for Alpha v0.16.0  
**Date:** 2026-11-16

## Context

Leo now supports offline ASR/TTS and optional VAD, but the project cannot responsibly claim Arabic, English or Sudanese-dialect recognition quality without repeatable reference data and device measurements. The voice capture path also spans asynchronous microphone setup, ASR worker execution and app lifecycle changes. A stale result must not be delivered after the user cancels or leaves the chat.

## Decisions

1. Add a local Python evaluation tool that consumes human-checked reference/hypothesis transcript pairs and optional timing/memory metadata. It computes corpus WER/CER, per-language groups and p50/p95 timing summaries.
2. Normalize text deterministically. Arabic normalization removes combining marks and tatweel, maps common alef variants to alef and alef maqsura to ya; English is case-folded. The evaluator documents the scope of these rules.
3. Keep recordings and transcript datasets outside the repository. The tool rejects audio, recording paths, prompts and unsupported per-sample fields. Reports omit transcript contents and only allow coarse, bounded metadata values.
4. Do not include fabricated sample outcomes or publish an accuracy baseline until genuine, consented phrases are evaluated on physical Android and Windows devices.
5. Enforce one active ASR capture/transcription operation per `LeoVoiceService`. Each capture receives a generation token; cancellation invalidates the token. The worker may finish because Dart isolates are not forcibly terminated by this service, but its stale output is discarded before returning to the chat UI.
6. Treat app lifecycle cancellation during capture preparation, recording or transcription as expected cancellation, not as a recognition error shown to the user.

## Consequences

### Positive

- Arabic and English recognition accuracy can be compared with repeatable, corpus-weighted WER/CER rather than anecdotal checks.
- Latency percentiles and memory high-watermarks can be reported by language and device class.
- Reference/hypothesis text is not copied into the generated report.
- Cancelled voice sessions cannot insert a stale transcript into the composer.

### Trade-offs and limitations

- The evaluator scores text pairs; it does not run ASR or validate the correctness of the reference transcript.
- Arabic normalization is a scoring convention, not a statement that orthographic variants are linguistically identical.
- The ASR isolate may continue consuming resources after cancellation until inference returns; its output is discarded and the service remains busy meanwhile.
- Python contract tests do not replace Flutter/Dart tests or device-level audio tests.

## Rejected alternatives

- Sending recordings to a hosted evaluation API: rejected because local evaluation is sufficient and preserves the offline/privacy boundary.
- Keeping test recordings and transcripts in Git: rejected because speech can contain personal data and the corpus should remain local/private.
- Reporting an average of utterance WER values as the corpus score: rejected because it overweights short phrases; corpus scores use summed edit counts divided by summed reference token counts.
- Attempting to force-kill an in-flight Dart isolate: not supported by the current service boundary; cancellation instead invalidates and discards its result.
