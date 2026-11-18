# ADR-0002: OS/application-first capability resolution is mandatory

- Status: Accepted for Alpha foundation
- Date: 2026-11-15

## Decision

Before embedding or writing an in-app tool, the Capability Hub must check the native operating system, installed application APIs/CLI/deep links, local connectors, and MCP options. A Leo-specific adapter is added only when no suitable existing capability is available.

## Consequences

- The base application remains smaller.
- Integrations are independent of chat UI and can be added without altering the model runtime.
- Tool availability varies by installed applications and OS version; Leo must explain missing capabilities rather than pretending universal support.
