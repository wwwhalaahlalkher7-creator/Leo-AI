# Leo Alpha v0.24.0 work log — Agent-guided declarative skill execution

**Version:** `v0.24.0`  
**Channel:** `ALPHA`  
**Build metadata:** `+4` (unchanged; no installable artifact was produced)

## Delivered in source

- Added chat-side dry-run preview and explicit user approval for the selected active, structurally validated skill on eligible multi-agent requests.
- The preview now displays the full additional instruction text, ordered steps, selected acceptance examples, and declared capability labels. It explicitly explains that examples are not auto-run and that external actions still require separate approval.
- Reloaded the skill after the dialog and rechecked ID, version, active status and structural validation before creating a run entry.
- Added `SkillRunRepository` with strict schema validation and OS-backed encrypted storage through `flutter_secure_storage`.
- Added lifecycle tracking for running, paused, awaiting action approval, awaiting review, user-confirmed completion, needs-changes, failed and cancelled runs.
- Added a bounded 8 KiB skill execution envelope for the existing multi-agent DAG. It carries the skill guidance as untrusted model context; it adds no script engine or direct native tool access.
- Added per-step user review UI. A fully reviewed run is labelled `verified` only as a user attestation; no independent acceptance-test runner was added.
- Added capacity/retention limits: 20 records, 512 KiB total and 30-day retention. Only terminal records can be evicted when at capacity; otherwise a new run fails safely.
- Removed the raw user goal from the skill-run record and execution-context builder. The original task goal remains only in the existing task request path.
- Added guards for stale/modified skill versions, missing durable checkpoints, finalized runs, approval/checkpoint mismatches and interrupted tool handoffs.
- Added Dart unit tests for ledger transitions, privacy boundaries, approval limits and per-step review, plus Python source-contract coverage.
- Updated the versioned voice-evaluation template metadata to `v0.24.0` and repaired the roadmap contract test after the milestone headings were extended.

## Important scope boundary

This is agent-guided, model-mediated execution for eligible multi-agent tasks. It is not a deterministic script runner, it does not automatically execute skill acceptance tests, it does not provide general rollback, and it does not bypass the Capability Hub. If skill context validation fails or the 8 KiB budget is exceeded, Leo continues without the skill rather than weakening the boundary.

## Version

- `config/VERSION`: `v0.24.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Flutter package metadata: `0.24.0+4`
- Cargo workspace metadata: `0.24.0`
- `config/BUILD_NUMBER`: `4` (unchanged because no APK/EXE was built)
