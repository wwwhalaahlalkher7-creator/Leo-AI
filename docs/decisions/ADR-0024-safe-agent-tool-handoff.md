# ADR-0024: Safe agent tool handoff

**Status:** Accepted for Leo Alpha v0.19.0  
**Date:** 2026-11-17

## Context

Alpha v0.18.0 can route a complex request through a bounded local multi-agent DAG. Action-oriented requests previously bypassed this coordinator so that model-proposed operations continued through the existing Flutter tool gateway. This preserved the security boundary, but specialists could not contribute to a complex request and then hand a narrowly scoped action proposal to Leo.

The native Rust coordinator must not execute model-authored device operations. Giving agents direct native APIs, method-channel names, shell access, or authority to mark their own actions approved would bypass Leo's established Capability Hub and user-confirmation model.

## Decision

Add a proposal-only handoff from exactly three reviewed specialist roles:

| Agent | Allowed proposals |
|---|---|
| `file_operator` | `files.read_selected` |
| `device_operator` | `web.open`, `app.launch` |
| `communications` | `email.compose`, `messages.compose`, `phone.dial` |

An action specialist may emit one complete `<leo_tool_call>` envelope as its entire step output. The Rust orchestration layer validates the wrapper, JSON object, version, ID, argument-key shape, string value types, size and role/tool pairing. It scans only successful action-specialist steps and permits one proposal per agent task. Malformed, unsupported, out-of-role, multiple or incomplete-task proposals fail closed.

When a task completes with one valid proposal, Rust emits a terminal `agent_tool_proposal` event using the existing `AgentTaskEventDto` fields. It does not dispatch the tool, open native APIs or grant permissions. Bounded outputs from the other successful agents may be sent in a separate `agent_tool_context` event; those notes exclude the raw proposal and remain explicitly untrusted.

Flutter then:

1. Re-parses the complete tool envelope with `LeoToolCall.parseAssistantResponse`.
2. Re-checks the specialist/tool role mapping with `isAllowedFromAgent`.
3. Passes the call through the existing `ToolExecutionGateway`.
4. Relies on `CapabilityHubService` for Leo's first-use consent, live OS permission/resource checks, scope validation and separate action approval.
5. Adds the bounded tool outcome as an untrusted `tool` message, with an instruction not to retry a denied/cancelled/failed operation, then resumes the ordinary local model turn for the final user-facing response.

The agent DAG does not resume after the handoff. The local chat model consumes the returned result and the bounded notes; it must not treat either as trusted instructions. The existing three-tool-call user-turn limit remains in force.

Multi-agent routing permits at most one action-focused specialist in a handoff task. Requests that route to more than one action-focused specialist fall back to the ordinary sequential tool loop, which already handles one approved call at a time. Unsupported writes, deletes, process execution, shell commands, direct sending/calling and general UI automation remain unavailable.

## Consequences

### Positive

- Specialists can now participate in complex, multi-domain requests that require one supported device/file/communication action.
- There is no new native execution surface and no new permission store.
- The existing role-specific tool allowlists are checked in both Rust and Dart.
- Consent, OS permissions, resource selection and action approval remain owned by the trusted Flutter capability layer.
- Tool results return to the local model as bounded, untrusted context; metadata audit storage continues to exclude arguments and content.
- The FFI DTO schema is unchanged; the implementation uses a new event kind over existing string fields.

### Trade-offs and limitations

- One multi-agent task can hand off only one proposal. More than one action specialist falls back to the ordinary chat tool loop.
- The agent DAG does not resume after the operation. The normal local model turn performs the final synthesis using bounded non-proposal agent notes and the tool result.
- Rust and Dart each validate part of the proposal. The Dart parser remains authoritative for complete URL, email, phone, body, control-character and length validation immediately before gateway dispatch.
- Model adherence, Rust/Dart compilation, FRB binding compatibility and OS approval flows still require CI and physical Android/Windows verification.

## Rejected alternatives

- Direct native execution by the agent coordinator: rejected because it would bypass the Capability Hub.
- Letting an agent grant Leo or OS permissions: rejected; agents cannot authorize themselves.
- Accepting arbitrary tool names or multiple batched operations: rejected; the schema remains a strict allowlist and the user approves one action at a time.
- Treating the agent's proposal or verifier text as evidence that an operation succeeded: rejected; only the gateway result can confirm the OS handoff.
