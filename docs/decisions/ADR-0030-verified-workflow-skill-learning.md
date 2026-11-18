# ADR-0030: Verified workflow-derived skill learning

**Status:** Accepted for Leo Alpha v0.25.0  
**Date:** 2026-11-17

## Context

Leo v0.24.0 can guide an active declarative skill through the multi-agent task planner. Each run is stored in an encrypted, bounded ledger, and the user reviews every step. The existing conversation-based extractor is intentionally user-triggered, but it can derive a proposal from a discussion even when there is no completed execution record.

The next learning path should use stronger workflow evidence without uploading raw conversations, file contents, tool arguments or tool results. It must not mistake user attestation for objective technical verification.

## Decision

Add a second, explicitly user-triggered learning path that derives an inactive proposal only from a `LeoSkillRunRecord` in `verified` state whose every step is marked `confirmed`.

The curation service reads the run through the narrow `SkillRunEvidenceReader` interface. It requires an exact source skill ID/version match, a passing source validation report, a non-rejected active/disabled source skill, and the exact ordered step list used by the run.

The local model receives only:

- Redacted source skill name and description.
- Redacted, user-confirmed step instructions.
- The source skill version.
- Aggregate count of user-approved actions.
- The source skill's existing declared capability IDs.

The curation input excludes chat transcripts, user goals, free-form review notes, tool arguments/results, file names, file paths and file contents. Pattern-based redaction covers common e-mail addresses, URLs, Windows/Unix paths, common file extensions, phone-like strings, long numeric identifiers, IPv4/MAC addresses and common bearer/API/provider token forms. Angle brackets are neutralized before wrapping the JSON evidence envelope.

The generated `required_capabilities` must be a subset of the source skill's IDs. The repository stores the result as a proposal with provenance `verified-run:<task-id>`. Both service and serialized repository reject a second proposal from the same run. The user must still edit/review, run structural preflight and explicitly activate the proposal.

## Safety boundaries

- `verified` records a user's confirmation of every step; it does not prove technical correctness.
- Pattern-based redaction is best-effort and cannot identify every name, address, secret format or confidential phrase. The UI discloses this limitation before any local-model call.
- The model is local-only through the existing `AssistantRuntimeClient`; no cloud route is introduced.
- Learning never runs a tool, grants a capability or changes a permission.
- A derived skill cannot increase the source skill's capability declarations.
- Existing conversation-based learning remains a separate opt-in feature.

## Consequences

### Positive

- Reuses the existing encrypted user-reviewed skill-run ledger rather than adding a second execution trace store.
- Produces proposals from reviewed, structured workflow steps without duplicating private transcripts or operational payloads.
- Prevents duplicate proposals for the same source run and constrains generated capabilities.

### Trade-offs

- This phase learns from completed executions of existing skills, not from arbitrary agent tasks without a skill-run record.
- The quality and generality of a proposal still depend on the local model; the user must inspect the proposal and run preflight before activation.
- Redaction is deliberately conservative but cannot guarantee that all personal information is removed.
- Flutter/Dart/Rust and native platform builds plus device tests remain required before the feature can be considered qualified.
