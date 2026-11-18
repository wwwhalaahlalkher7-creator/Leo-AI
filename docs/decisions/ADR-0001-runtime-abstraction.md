# ADR-0001: Inference engines are behind a runtime abstraction

- Status: Accepted for Alpha foundation
- Date: 2026-11-15

## Decision

Define `AssistantRuntime` before porting NEXUS inference code. Concrete runtimes must expose a common descriptor, capability set, streaming event lifecycle, and cancellation operation.

## Context

JARVIS connects through `ApiClient`/`HermesAdapter` and therefore carries Hermes-specific transport assumptions. NEXUS has a Rust runtime and Flutter Rust Bridge, but the actual native loader currently has an Android implementation and explicit non-Android unavailable stubs.

## Consequences

- JARVIS UI can be retained while Hermes-specific access is removed behind the runtime boundary.
- NEXUS native code can be adapted without making its Android implementation the shared runtime.
- Windows requires a real llama.cpp adapter; a host stub is not an acceptable implementation.
