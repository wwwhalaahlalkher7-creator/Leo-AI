# ADR-0006: Chat UI uses a platform-neutral runtime channel

- Status: Accepted for Alpha v0.2.0
- Date: 2026-11-15

## Decision

The Flutter conversation UI communicates with native inference through the
`leo.ai/runtime` method channel and `leo.ai/runtime/events` event channel. The
channel contract carries request IDs, conversation IDs, role/content messages,
generation options, deltas, completion, cancellation and errors.

The channel is an integration seam, not an implemented inference engine. Until
Android and Windows register native handlers, the app reports the missing local
runtime honestly and does not synthesize placeholder assistant answers.

## Consequences

- The UI is independent of llama.cpp and the native bridge implementation.
- Runtime implementations can be tested and replaced separately.
- Android and Windows still require native registration and end-to-end tests.
- Streaming event ordering and request cancellation are explicit contracts.
