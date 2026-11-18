# ADR-0009: Built-in agent routing and validated plan previews

- **Status:** Accepted for Alpha v0.5.0
- **Date:** 2026-11-15

## Context

Leo must ship with useful specialist agents. The user should not need to create or configure agents before asking for work. Leo should choose one specialist for a focused task and coordinate a small team only when the request spans multiple domains or phases.

## Decision

1. Ship the built-in agent catalogue as reviewed project configuration.
2. Normalize Arabic orthographic variants and diacritics before the deterministic first-pass router evaluates request intent.
3. Select only agent IDs that exist in the built-in catalogue.
4. Build a validated task DAG from the selected team:
   - a planner step precedes specialist work when coordination is needed;
   - independent specialist steps depend on the planner and can therefore become parallel-ready;
   - a verifier step depends on all selected specialist steps when verification is warranted.
5. Copy each agent's declared required capabilities into its task step.
6. Expose route selection and plan preview through typed Flutter Rust Bridge DTOs.
7. Treat the result as a plan, not an authorization or execution grant. The future execution coordinator must re-check Capability Broker state and action-approval policy before invoking an adapter.

## Explicit non-goals for v0.5.0

- Running multiple independent LLM agents concurrently.
- Scheduling or resuming agent tasks.
- Aggregating specialist outputs into a final answer.
- Delegating tools directly from an agent without the Capability Broker.
- Claiming semantic understanding from keyword routing. The current router is a deterministic baseline; model-assisted refinement may be added later but must remain allow-listed by the catalogue and policy.

## Consequences

The task graph can be inspected and validated before execution, and focused requests avoid unnecessary planner/verifier agents. The bridge now has a stable preview contract. Full multi-agent execution remains a separate Alpha milestone and is not claimed as implemented.
