# ADR-0011: User-reviewed memory and bounded chat context

- Status: Accepted
- Version: Alpha v0.7.0

## Context

The v0.6.0 SQLite memory crate provided persistence and bridge operations, but there was no user-facing review workflow or connection to local chat generation.

## Decision

- Expose the store through a Dart `MemoryRepository` abstraction.
- Keep the database under the platform-provided app-private support directory.
- Provide user controls to add, inspect, search, approve, edit, disable/re-enable and delete records.
- Use only Rust search results that are both approved and active.
- Retrieve only when processing a user request; cap retrieval to four hits and a 2,200-character reference block.
- Add one fixed system message declaring saved-memory content untrusted, and place retrieved data in a separate user-role reference message before the current request. The retrieval block never enters persisted chat history.
- If memory lookup fails, continue the user's request without memory rather than blocking generation.
- Do not automatically infer or save new memories in this milestone.

## Security and privacy

- Saved memory content cannot grant tool capability, permissions or action approval.
- The current SQLite database is not encrypted by this layer; the UI must disclose that fact.
- Retrieved data must not be elevated to a system message or executed. Current user statements supersede contradictory remembered content.
- The local database path is derived from the platform app-private support directory and not from user-controlled free-form paths.
