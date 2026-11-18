# ADR-0031: Encrypted local memory and user-controlled curation

**Status:** Accepted for Alpha v0.26.0  
**Date:** 2026-11-18

## Context

Leo's memory foundation already supported local SQLite records, explicit proposals, user approval/activation, bounded retrieval and user deletion. It did not yet provide payload encryption at rest, a recoverable key lifecycle, portable encrypted backups or an explicit way to turn one selected user-authored chat message into a memory proposal. Similarity/conflict handling also needed to remain review-only rather than silently rewriting a user's remembered preferences.

## Decision

### Data protection

- Encrypt `content`, `normalized_content`, `source_reference` and `tags_json` independently with AES-256-GCM.
- Bind each encrypted value with associated data `leo-memory-record:v2:<record-id>:<field-name>` so ciphertext cannot be moved to another record or field without authentication failure.
- Keep the 256-bit data key in the platform secure-storage plugin. If an encrypted database exists but the key is absent or invalid, fail closed; do not create a replacement key.
- Use HKDF-SHA256 with fixed versioned salt/info labels to derive an independent HMAC key for deterministic duplicate fingerprints. The AES key is not passed directly into the HMAC operation.
- Upgrade legacy plaintext and older `enc:v1` values transactionally. Recompute older unprefixed digest values as `hmac:v2` in the same migration transaction.
- Rotate keys by placing the candidate key in a pending secure-storage slot, re-encrypting the database in one SQLite transaction, then promoting the candidate key. On next access, authenticate the pending and active candidates against the database marker to recover an interrupted promotion without discarding the only valid key.

### Privacy and user control

- The user may select one user-authored chat message and open a review editor. Saving creates a pending memory proposal; Leo does not automatically extract memories from conversations.
- Duplicate/possible-contradiction suggestions use local lexical heuristics only. Findings are hints for a human; no merge, overwrite, approval, activation or deletion happens automatically.
- Approved and active memories are the only records eligible for bounded chat retrieval. Retrieved memory is transient request context and is not written into the conversation transcript.
- Export uses password-derived AES-256-GCM encryption (PBKDF2-HMAC-SHA256, 210,000 iterations), with strict size and count caps. Import creates pending, inactive proposals and never restores trust/activation state or source references.
- Erasure removes the memory records, checkpoints the WAL and attempts to remove SQLite main/sidecar files before deleting the secure-storage key. The UI reports verified file/key absence, but must not describe this as forensic erasure. Read-only list/search after erase returns empty without automatically recreating a database or key; the next explicit memory write starts a fresh key/database lifecycle.

## Explicit plaintext metadata

The following SQLite metadata remains visible to a local database/filesystem reader: record ID, memory kind, creation/update timestamps, approval/activation flags, schema/encryption version, and the opaque keyed content fingerprint. This trade-off is documented in the Memory UI; the design does not claim full-database encryption.

## Consequences

### Positive

- Memory content and source references are encrypted at rest and authenticated against record/field substitution.
- Legacy memory can be upgraded without requiring the user to manually export/re-import it.
- Key rotation has a recoverable two-phase secure-storage promotion path.
- Portable backups can move content between devices without moving local trust state or source paths.
- Memory suggestions stay explicitly user-controlled and are isolated from automatic transcript ingestion.

### Trade-offs and limitations

- Platform secure-storage guarantees differ by OS/device; hardware-backed key protection is not asserted until verified on real devices.
- SQLite metadata is not encrypted. The HMAC fingerprint is keyed and opaque, but equality remains observable within one database.
- Pattern/token heuristics are not semantic contradiction detection and can miss paraphrases or flag unrelated records.
- A backup passphrase cannot be recovered by Leo. If the device key is lost and no external backup exists, local memory may be unrecoverable.
- Removing the database and common sidecars is not a forensic erasure guarantee against snapshots, external copies, device backups or flash wear-levelling.
- Current repository serialization protects operations within the Flutter UI isolate only; it is not a cross-process or multi-isolate lock.

## Validation required

Before platform qualification, CI and device tests must cover plaintext/v1 migration, row/field tampering, key loss, interrupted rotation, backup portability, pending-only restore, erase verification, user-message opt-in, metadata disclosure and Arabic/English duplicate/conflict fixtures on Android and Windows.
