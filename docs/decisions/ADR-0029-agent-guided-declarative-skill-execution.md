# ADR-0029: Agent-guided declarative skill execution

**Status:** Accepted for Alpha v0.24.0  
**Date:** 2026-11-17

## Context

Leo already had a local declarative skill library with import/export, validation, inactive proposals, explicit activation, and bounded retrieval. Skills could influence a prompt, but there was no user-reviewed execution lifecycle or durable record connecting a selected skill to a multi-agent task. Directly interpreting a `SKILL.md` file as executable code would create a new arbitrary execution surface and bypass the established Capability Hub.

## Decision

Use a bounded, user-approved skill as untrusted procedural context for the existing local multi-agent DAG. Do not introduce a script interpreter, shell runner, plugin runtime, or new native execution path.

Before execution, chat displays a dry-run preview containing the ordered steps, full additional instruction text, selected acceptance examples, and declared capability metadata. The user explicitly approves the skill. Immediately after the dialog, Leo reloads the skill and requires the same ID and version to remain active and structurally validated.

A `SkillRunRepository` stores a minimal encrypted audit record in `flutter_secure_storage`. It records a generated task identity, skill identity/version, ordered step labels, timestamps, status, static lifecycle event text, and a bounded count of successful external approvals. It does not duplicate the user's raw task goal, model transcript, tool arguments, file paths, or file contents. Only terminal records may be evicted to make capacity; active, paused, and review-pending work is not silently discarded.

The execution envelope is capped at 8 KiB and marks all skill content as untrusted data. The existing agent protocol and role allowlist remain authoritative. Any external action continues through the existing Flutter validation and Capability Hub, with its own user approval. No skill can grant a permission or call a native adapter directly.

At the end of the agent task, the user reviews each skill step. The status `verified` means only that the user attested that all listed steps were completed. Acceptance examples are guidance for the agent and visible to the user, but are not run as an automated test suite in this milestone.

## Consequences

### Positive

- Provides a first practical skill execution path while reusing the existing planner, local agents, tool protocol and permission controls.
- Gives each run a bounded, inspectable lifecycle and per-step user review.
- Prevents a stale or changed skill from being silently executed after the preview.
- Avoids storing the raw task goal and external tool payloads again in the skill ledger.
- Refuses to evict non-terminal records when the ledger is full.

### Trade-offs and limitations

- This is agent-guided, model-mediated execution, not deterministic workflow bytecode; the model may interpret procedural guidance imperfectly.
- It is available only when the request qualifies for the existing multi-agent DAG route; ordinary chat continues normally.
- The skill context may be rejected when it exceeds the 8 KiB limit; Leo then continues without the skill and informs the user.
- Acceptance examples are not automatically executed. User review is an attestation, not independent technical verification.
- No generic rollback is provided for completed external actions or successful workspace writes.
- The ledger is encrypted through the platform secure-storage plugin, but integration behavior, key persistence and backup/restore behavior still require Android and Windows device tests.
- Dart/Flutter and native compilation/tests remain pending until the corresponding toolchains and CI runners are available.

## Rejected alternatives

- Execute arbitrary scripts embedded in `SKILL.md`: rejected because it would bypass the Capability Hub and introduce a general code-execution surface.
- Let skills grant their declared capabilities: rejected because a skill's metadata must never become a permission grant.
- Mark a skill as successful based only on the model's final response: rejected because it would conflate model assertion with user review.
- Persist the full task prompt and tool payloads in the run ledger: rejected to avoid duplicating potentially sensitive conversation and action data.
