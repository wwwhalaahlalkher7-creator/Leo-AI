# Memory privacy, encryption and backup validation protocol

This is the required platform-validation checklist for v0.26.0. It is a test protocol, not a claim that the listed device tests have already passed.

## 1. Local storage and migration

1. Create a fresh memory database and confirm a random 32-byte key is stored in platform secure storage.
2. Save approved and pending records. Confirm only `content`, `normalized_content`, `source_reference` and `tags_json` are AES-GCM envelopes in SQLite; IDs, kinds, timestamps, flags, encryption version and keyed fingerprints remain metadata.
3. Search and read records with the correct key; confirm wrong keys and missing keys fail closed and never generate a replacement key.
4. Create a legacy plaintext fixture; open via the encrypted repository and confirm a transaction upgrades all payload columns and the fingerprint. Confirm the database no longer contains the unique fixture plaintext.
5. Create an older `enc:v1` fixture with the old unprefixed keyed digest; open and confirm it migrates to row/field-bound `enc:v2` and `hmac:v2`.
6. Copy one record's ciphertext into another record or move it from `content` to another field. Confirm authentication fails and no plaintext fallback is attempted.
7. Test interrupted first migration and database write failure. The database must remain either at the prior valid state or fail closed; it must never show partially migrated values.

## 2. Key lifecycle

1. Rotate the key with multiple approved and pending records; confirm all remain searchable and the old key is rejected.
2. Simulate secure-storage failure when writing the pending key, during database rotation, when promoting the pending key, and when deleting the pending key.
3. On next repository access, confirm the valid key is recovered by authenticating the database marker. Never overwrite the database or keys when neither candidate authenticates.
4. Confirm repository operations (search/list/propose/edit/approve/delete) are serialized with rotation and erase within one Flutter UI isolate.
5. Erase the memory store. Verify the SQLite database, `-wal`, `-shm`, `-journal` and active/pending key entries are absent. Verify the API does not report success if one remains.
6. Repeat on supported Android and Windows versions. Record secure-storage implementation details; do not assume hardware backing without platform evidence.

## 3. Backup and restore

1. Export a backup containing approved, disabled and pending records. Confirm the file does not contain fixture plaintext and is encrypted/authenticated.
2. Import on another device/platform with the correct passphrase. Confirm every item is a pending, inactive proposal; source references, record IDs, approval and activation state are not restored.
3. Confirm an incorrect passphrase and a one-byte ciphertext/MAC modification are rejected without creating any proposal.
4. Confirm malformed envelopes, invalid base64/field lengths, unknown schema versions, more than 1,000 entries and files over 5 MiB are rejected.
5. Test 1,000 records at or below the byte cap; test an export with 1,001 records is rejected rather than truncated.
6. Confirm a password with fewer than 12 characters, more than 256 UTF-8 bytes or leading/trailing whitespace is rejected; document that a lost backup password cannot be recovered.

## 4. Curation and retrieval

1. Select a user-authored chat message and choose “اقتراح كذاكرة”. Confirm the editor opens before persistence and cancel leaves the database unchanged.
2. Save an edited proposal and confirm it remains pending/inactive and is not injected into chat context.
3. Confirm assistant-authored messages do not display the memory suggestion action and the app does not scan conversation history automatically.
4. Use Arabic fixtures with diacritics/alef variants and English positive/negative examples. Confirm likely duplicates/possible contradictions produce review hints only.
5. Confirm different memory kinds are not compared, no more than five findings are returned, and no hint triggers edit/merge/delete/approval/activation.
6. Confirm chat retrieval includes only records where `userApproved && active`, is bounded, transient and not saved into the transcript.

## 5. Privacy disclosure and release gate

- Check the UI explicitly discloses plaintext SQLite metadata: IDs, kinds, timestamps, approval/activation flags, schema/encryption version and opaque keyed fingerprints.
- Check the UI warns that losing the secure-storage key without a backup may make local memory unrecoverable.
- Check backup passphrase policy and the pending-only import behavior are clearly explained.
- Check deletion wording does not promise forensic removal from snapshots, backups, external copies or flash storage.
- Do not mark v0.26 platform-qualified until Dart/Rust/FRB tests, Android and Windows builds, and real-device runs above have evidence attached to CI/release records.
