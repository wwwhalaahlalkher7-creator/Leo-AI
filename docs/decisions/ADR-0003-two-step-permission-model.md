# ADR-0003: Permission grants and action approvals are separate

- Status: Accepted for Alpha foundation
- Date: 2026-11-15

## Decision

Leo requests OS permissions only at first use. A recorded grant is scoped and revocable. Consequential actions (sending, deleting, purchasing, external communication, privileged commands, bulk edits) can still require a separate per-action confirmation.

## Consequences

- Users do not face an upfront permission wall.
- A permission grant cannot be misinterpreted as blanket consent for all future actions.
- Android uses the official runtime permission/storage APIs where applicable; Windows uses a Leo approval layer and native OS access controls, with UAC only when genuinely required.
