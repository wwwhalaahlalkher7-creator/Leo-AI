# ADR-0017: Structured Tool Execution Gateway

**Status:** Accepted for Alpha v0.12.0  
**Date:** 2026-11-16

## Context

Leo v0.11.0 had a native capability catalogue, persistent first-use permission broker and Android/Windows adapters, but the local chat model could not request these capabilities. Exposing raw platform channels or arbitrary command strings to the model would bypass the least-privilege design and create an unsafe execution surface.

## Decision

Add a strict, versioned, one-call-per-response tool protocol in Flutter. The model can propose only a reviewed allowlist of actions. Flutter validates the envelope and arguments, then dispatches only to typed `CapabilityHubService` methods. The existing service remains the sole owner of Leo consent, OS/resource checks and per-action confirmation.

The model cannot grant permissions, mark actions approved, choose a native method-channel name, run arbitrary commands, or invoke native APIs directly.

Tool output is returned as an untrusted `tool` message to the local runtime. A user turn is limited to three sequential tool calls. User-denied, cancelled or failed outcomes are reported explicitly and the model is instructed not to retry the rejected action.

## Consequences

### Positive

- Reuses the OS-first capability layer rather than duplicating device functions in the chat app.
- Keeps model-generated data separate from the trusted action policy.
- Enables a local model to perform selected device handoffs while preserving explicit user control.
- Adds a bounded metadata-only audit trail without persisting sensitive tool arguments or results.

### Trade-offs and limitations

- Tool use depends on the model following the prompt protocol; invalid outputs are rejected.
- Only seven narrow tool definitions are exposed in this slice.
- The current execution loop is sequential and limited to three calls per turn.
- The metadata audit is app-private but not separately encrypted.
- Platform build and physical-device testing remain required.

## Rejected alternatives

- Giving the model direct MethodChannel names or raw OS API access: rejected because it bypasses the capability broker.
- Allowing model-provided shell/PowerShell strings: rejected because it creates arbitrary code execution.
- Treating one persistent permission grant as approval for every future external action: rejected; action confirmation remains separate.
- Returning tool output as trusted system instructions: rejected; tool results are untrusted data.
