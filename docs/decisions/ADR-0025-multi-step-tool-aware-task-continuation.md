# ADR-0025: Multi-step tool-aware task continuation

**Status:** Accepted for Alpha v0.20.0  
**Date:** 2026-11-17

## Context

Leo v0.19.0 could hand one role-scoped proposal from an action specialist to the Flutter Capability Hub, but the agent DAG ended at the handoff. The user then received a normal model follow-up rather than the same planned task continuing. Multi-action requests therefore did not preserve the plan's successful work or dependencies.

A continuation mechanism must preserve the separation between model reasoning and native side effects. It must not accept caller-invented checkpoints, treat a receipt as permission, or replay an action after a retry or application restart.

## Decision

1. The coordinator exposes `AwaitingToolApproval` and can resume a validated `TaskPlan` from successful `AgentStepResult` checkpoints.
2. The coordinator accepts only known step IDs, matching assigned agent IDs, successful results without errors, bounded attempt/output values, unique step IDs, and a dependency-closed checkpoint set. A downstream step is not a valid checkpoint if any dependency is absent.
3. An action specialist may propose one tool at a time. Rust validates the role/tool pairing and pauses the DAG. Flutter reparses the proposal and dispatches it only through the existing `ToolExecutionGateway` and `CapabilityHubService`.
4. Only a successful gateway outcome is encoded as a version-1 resume receipt. The receipt has exactly six fields: `version`, `task_id`, `tool_call_id`, `tool_name`, `success`, and `result`. Rust matches all task/call/tool identifiers to the pending state before consuming it.
5. The bridge keeps pending state only in process memory, with a ten-minute TTL, at most eight pending tasks, one continuation per task, bounded result/context sizes and a maximum of three successful serial handoffs per user turn.
6. Earlier specialist outputs and tool results are passed back as explicitly untrusted evidence. The original action proposal is excluded from the evidence context.
7. Denial, cancellation, failure, task disposal, invalid receipt or expiry terminates the current continuation. No action is automatically retried or replayed.

## Consequences

### Positive

- The same validated DAG continues after an approved action without rerunning completed agents.
- Explicit multi-action tasks can progress through a serial approval loop while retaining the existing tool budget and role boundaries.
- Receipt validation and checkpoint validation narrow the opportunities for forged state or replay.
- The user remains the authority for each action; a persistent capability grant is not treated as blanket action approval.

### Trade-offs and limitations

- Pending state is volatile and is lost when the Leo process exits or the app restarts. It expires after ten minutes and is limited to eight pending tasks. Durable recovery is deferred to v0.21.0.
- Multiple actions are sequential, not parallel. Every action requires its own Capability Hub path and confirmation when policy requires it.
- The three-handoff cap can leave a task partially complete; Leo must report that state rather than silently exceed the budget.
- Rust/Dart unit tests and native platform behavior still require toolchain-enabled CI and physical-device verification.

## Security notes

- A resume receipt is a protocol envelope, not an authorization credential. It cannot grant Leo consent or OS permissions.
- The bridge accepts only a matching pending task/call/tool tuple and only a successful receipt. The pending entry is removed only after matching validation.
- Tool results and agent outputs remain untrusted content. They cannot change the allowlist or approval state.
- Pending data is process memory only in this milestone; no persistent task ledger or restart recovery is implemented.
