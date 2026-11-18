# ADR-0015: Persistent just-in-time permission broker

- Status: Accepted for Alpha v0.11.0
- Date: 2026-11-16

## Context

Leo must be prepared to access a broad range of device/application capabilities, while users decide whether to grant each capability at the moment it is first needed. Platform permission state is not a substitute for user consent inside Leo, and app-level consent cannot override a permission revoked in Android or Windows settings.

## Decision

- Use a central Rust `leo-capabilities` broker with a persistent SQLite store.
- Persist decisions by capability identifier and declared scope.
- Ask for Leo consent at first use, then independently request/check OS access or require a system-selected resource.
- Re-check current OS state for each operation.
- Require separate one-action approval for High/Critical, destructive or Moderate external-effect actions.
- Keep the native adapter limited to OS/app handoffs; it does not choose an agent, interpret a prompt or approve an action.
- Keep the permission database in the app-private application-support directory. The current database is not encrypted and must not contain secrets or user content.

## Consequences

- The permission center can show and revoke Leo-level grants.
- OS permissions can be revoked outside Leo; the broker must fail closed when it detects that state.
- A new or expanded scope requires a new Leo consent decision.
- Permission decisions and one-action approvals are separate records/concepts.
- UI and bridge generation must be updated whenever capability DTOs or permission-state enums change.
