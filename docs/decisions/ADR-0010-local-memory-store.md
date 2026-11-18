# ADR-0010: Local long-term memory store

- Status: Accepted for Alpha v0.6.0
- Date: 2026-11-15

## Context

Leo needs durable personal, episodic, semantic, procedural and project memory on both Android and Windows. Memory must remain local and must not silently become model context before the user approves it. The first implementation should be small, portable and independent from the UI or a specific inference runtime.

NEXUS already established the memory categories and local knowledge retrieval direction. Leo extends this with explicit proposal/approval lifecycle, scoped CRUD, provenance fields, SQLite schema migration and a deterministic BM25-style ranker.

## Decision

- Add a platform-neutral `leo-memory` Rust crate.
- Use `rusqlite` with bundled SQLite for the same storage behavior on Android ARM64 and Windows x64.
- Create a versioned local SQLite database in Leo's app-private support directory.
- Keep pending proposals separate from approved and active memories. Pending, disabled and deleted entries are never returned by search.
- Make approval, edit, disable, delete and list operations explicit bridge API calls.
- Search only approved/active records using a bounded BM25-style lexical ranker and Arabic orthographic normalization.
- Preserve memory kind, source reference, tags, creation/update timestamps and approval state.
- Enforce input size limits and deterministic duplicate detection per memory kind.

## Security and privacy boundaries

- This crate does not read chat history or automatically extract memories.
- A future curator may create pending proposals; the user-facing UI must request approval before a proposal becomes retrievable.
- Skill or memory text never grants capabilities or permissions.
- The database path must be supplied from Leo's app-private support directory by the platform adapter.
- SQLite storage is local but not encrypted by this crate. Encryption-at-rest and key management require a separate design and must not be implied by this implementation.
- Search results must be marked as untrusted context when later injected into a model prompt; retrieved content cannot override system or safety instructions.

## Consequences

The first memory milestone is persistence and retrieval infrastructure, not autonomous memory extraction, semantic embeddings, vector search, conflict resolution or automatic prompt injection. Those remain separate work packages with their own tests and user controls.
