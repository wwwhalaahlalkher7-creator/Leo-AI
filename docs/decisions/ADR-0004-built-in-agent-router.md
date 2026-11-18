# ADR-0004: Built-in agents are selected automatically

- Status: Accepted for Alpha foundation
- Date: 2026-11-15

## Decision

Ship an initial specialist catalog and have Leo route tasks automatically. The user is not required to create or configure agents. Multi-agent orchestration is used only when the task needs it; simple tasks should use one agent or the general runtime.

## Consequences

- The router must inspect task intent, available skills, runtime capabilities, and authorized capabilities.
- The planner validates task dependencies and only passes necessary outputs between agents.
- Agents never receive system permissions directly; they go through the Capability Hub.
