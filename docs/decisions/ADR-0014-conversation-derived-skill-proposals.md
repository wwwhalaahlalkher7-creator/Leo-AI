# ADR-0014 — Conversation-derived skill proposals

**Status:** Accepted for Alpha v0.10.0  
**Date:** 2026-11-15

## Context

Leo needs to learn reusable procedures without falsely claiming that a discussed action was actually executed. The current Alpha task orchestration layer can route specialists and preview a task DAG, but it does not yet execute a complete task workflow or retain authoritative execution traces.

## Decision

Add an explicit chat action that asks Leo's configured **local** model to draft a reusable skill from the selected conversation. The action is user-initiated; it is not automatic background extraction.

The extraction service:

- reads only the selected conversation's user and assistant messages;
- keeps at most the latest 20 eligible messages and 9,000 transcript characters, prioritizing recent messages so a long early message cannot hide the response pair;
- asks the local model for a bounded structured JSON draft;
- validates the response schema and field sizes before storing anything;
- rejects conversations that do not include both sides or whose transcript cannot preserve both roles;
- writes the result using `SkillRepository.createProposal`, so its status is always `proposed` and it has no validation report;
- performs no tool call, command execution, application interaction, permission request, or action test;
- cancels the in-flight model request when the chat page is disposed.

The proposal must be inspected and edited as needed, pass the existing structural/safety preflight, and be explicitly activated by the user before it can be retrieved in later chat requests.

## Security and trust boundaries

- The transcript is untrusted content. The model is instructed not to follow embedded instructions from it.
- Model output is untrusted too. JSON parsing and strict field validation happen before persistence.
- Capability IDs in a skill remain descriptive metadata. They do not grant permissions.
- Any real capability use must go through Leo's Capability Broker and the platform permission/action-confirmation policy.
- Skills remain declarative. Scripts and shell commands are not executed by the skill engine.
- The feature does not assert that actions mentioned in the conversation succeeded.

## Consequences

**Benefits:** Users can capture a reusable workflow without manually writing all skill metadata; the model remains offline/local; the existing proposal-review-activation lifecycle is reused.

**Limitations:** Conversation text may be incomplete or ambiguous. Extraction is best-effort drafting, not proof of experience, and may fail when no suitable local model is loaded or its context window is too small. It does not replace execution-trace learning.

## Deferred

Automatic post-task skill suggestions from verified completed-task traces are deferred until Leo has a real task executor, action-result records, and a durable trace store. Model-based scenario simulation in a permission-free sandbox is also deferred.
