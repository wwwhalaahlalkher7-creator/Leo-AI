# Skill execution and review — Alpha v0.24.0

## What the user approves

For an eligible multi-agent request, Leo may offer one active, structurally validated skill. The dry-run dialog displays:

- the skill name and version;
- every ordered skill step;
- the full additional instruction text;
- a selection of up to five acceptance examples;
- the declared capability labels, explicitly identified as metadata rather than permissions.

The user can continue without the skill or explicitly approve it. Leo reloads the skill after the dialog and rejects it if it was removed, disabled, modified, or no longer structurally validated.

## What execution means

The skill is supplied to Leo's existing local agent DAG as bounded, untrusted procedural guidance. The model still has to plan and interpret the steps. This is not a script runner, and it does not guarantee that every step is performed exactly as written.

All real device or workspace actions remain separate role-scoped proposals. Flutter validates the proposal and dispatches only through the existing Capability Hub. Each consequential action has its own user approval. A skill's declared capability labels do not grant access.

The skill context is capped at 8 KiB. If it exceeds that bound or fails validation, Leo does not execute that skill; it continues the normal task without the skill and shows a notice.

## What happens after execution

Leo records an encrypted run entry and asks the user to review every listed step as completed or not completed. A `verified` status means only that the user confirmed every step. It does not mean that Leo independently ran the skill's acceptance examples or proved the resulting state.

Acceptance examples are sent as guidance and included in the preview. They are not invoked as a test suite in v0.24.0. The user should inspect the resulting files, messages, or application state before confirming a step that involves an external effect.

## Stored data boundary

The run ledger stores a generated task ID, skill ID/name/version, copied step labels, lifecycle state/timestamps, static event text and a bounded number of approved tool handoffs. It does not store the raw task goal, model transcript, tool arguments, file paths, or file contents. The ledger is capped at 20 records / 512 KiB and retains entries for at most 30 days. Active, paused and review-pending entries are not evicted merely to create space; when no terminal entry can be removed, a new run is refused.

## Required qualification before calling this stable

CI must run Dart format/analyze/tests, Rust format/test/clippy and Flutter Rust Bridge regeneration. Android and Windows builds must pass. Device tests must cover skill approval/cancel, stale-version rejection, task interruption, all step-review outcomes, approval and denial of external actions, secure-storage persistence across process restarts, storage corruption, and the capacity/retention limits. No action may be replayed after a restart without a fresh user decision.
