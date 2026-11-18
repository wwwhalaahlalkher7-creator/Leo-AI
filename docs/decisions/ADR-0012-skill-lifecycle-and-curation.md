# ADR-0012: Local Skill Lifecycle and Curation

- **Status:** Accepted for Alpha v0.8.0
- **Date:** 2026-11-15

## Context

Leo needs reusable procedural knowledge without pretending that a prompt, memory record, or untested script is a learned capability. NEXUS provides procedural-memory concepts and JARVIS provides workflow-oriented interaction patterns, but neither currently provides the complete reviewed lifecycle needed here.

## Decision

1. Skills are local, declarative workflow records stored in Leo's app-private support directory.
2. A skill follows `proposed -> testing -> active`, with `disabled` and `rejected` terminal/management states.
3. A new or edited skill is always a proposal. It is never activated automatically.
4. The current preflight validates structure, trigger clarity, procedure completeness, test-example presence, capability identifier syntax and explicit approval language for risky actions.
5. Passing preflight is **not** proof that a model executed the examples successfully. The UI labels the report as a structural preflight and explicitly states that scenarios and scripts were not run.
6. The user must explicitly activate a skill after a passing preflight.
7. Active, validated skills may be selected for transient chat context by trigger relevance. The current limit is two skills and 3,600 characters.
8. Skill context is marked as untrusted guidance. It cannot override system policy, grant permissions or authorize side effects.
9. Skill records do not contain executable scripts in this milestone. The skill engine never launches code contained in skill text.
10. Editing a skill creates a new proposed minor revision and records the previous instruction/version snapshot. The active skill must be disabled before editing.
11. Built-in agent routing includes a Skill Curator specialist; users are not required to create agents.

## Consequences

- Skills can be stored, reviewed, revised, activated, disabled, rejected and removed offline.
- Existing chat can retrieve relevant skills without persisting them in the transcript.
- Fully automatic extraction from completed task execution logs is deferred because the current task system previews plans but does not yet execute and persist end-to-end workflows.
- Model-assisted scenario simulation, portable `SKILL.md` pack import/export, cryptographic signing and skill dependency/conflict management remain future work.
- The local JSON skill library is app-private but is not separately encrypted in this milestone.
