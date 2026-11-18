# Leo Alpha v0.26.0 work log — Memory intelligence and privacy

## Delivered in source

- Added opt-in “suggest as memory” action to user-authored chat messages. It opens the memory editor and stores only a pending proposal after user confirmation; no background chat scanning.
- Added local deterministic Arabic token normalization, Jaccard similarity and negation/polarity hints for likely duplicates and possible contradictions. Findings never mutate memory automatically.
- Added AES-256-GCM field encryption for memory content, normalized search value, source reference and tags, with AAD bound to record ID and field name.
- Added migration from older plaintext and v1 envelopes to row-bound v2 envelopes. Added fail-closed key verification and a key-check envelope.
- Added HKDF-SHA256 domain separation for the deterministic HMAC content fingerprint. New hashes use `hmac:v2`; legacy unprefixed fingerprints are recomputed during migration.
- Added a secure-storage key store, interrupted-rotation recovery via a pending key, and global UI-isolate serialization across repository instances. Read-only list/search now returns empty without recreating a database or key immediately after explicit erase; a fresh key is created only when the user writes a new memory.
- Added key rotation and verified erase of DB, SQLite sidecars and active/pending secure-storage values.
- Added password-protected AES-256-GCM backup/import using PBKDF2-HMAC-SHA256 at 210,000 iterations, with 1,000 record / 5 MiB bounds. Imported items are pending and inactive; source references and trust state are omitted.
- Added Rust unit tests for row binding, old envelope migration, HKDF/HMAC key separation, digest migration, key rotation and erase; Dart tests for backup and intelligence/UI; Python static contract coverage.
- Added `ADR-0031`, memory test protocol, dependency license notes and updated roadmap.

## Version

- `config/VERSION`: `v0.26.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Flutter version metadata: `0.26.0+4`
- Cargo workspace version: `0.26.0`
- Build number remains `4`; no APK or EXE was produced.

## Engineering review improvement

During final review, the duplicate fingerprint initially reused the same raw key bytes as AES-GCM. This was hardened in v0.26.0 before packaging: HKDF derives a separately labelled HMAC subkey, and old fingerprints are version-detected and recalculated transactionally. Added Rust tests cover domain separation and upgrade behavior. These Rust tests are source-added but could not be executed in this authoring environment.

## Validation performed

- `python -m unittest discover -s scripts/tests -q`: 169 tests passed.
- `python scripts/sync_version.py`: passed.
- `python scripts/check_version.py --previous v0.25.0 --kind minor --next v0.26.0`: passed.
- Original J.A.R.V.I.S and NEXUS archive verification: both pinned SHA-256 values matched on the final rerun.
- - Configuration parse checks: 10 JSON, 8 TOML, 5 YAML and 4 CSV files parsed; all CSV records have consistent column counts.
- Final source ZIP integrity (`unzip -t`) and companion SHA-256 verification: passed.

## Not run

Flutter/Dart/Rust/Cargo SDKs, FRB generator and Android/Windows native build environments are not installed. Therefore Dart tests, Dart formatting/analyze, Rust tests/format/clippy, FRB code generation, APK/EXE builds, platform secure-storage, migration/key-rotation/erase device tests and cross-platform backup interoperability tests were not executed. This is a source-implemented Alpha milestone, not an installable-build claim.

## Follow-up gate

CI must generate and review `Cargo.lock` and `pubspec.lock`, run the full native toolchain checks and attach Android/Windows test evidence described in `docs/testing/MEMORY_PRIVACY_AND_BACKUP.md` before v0.26.0 can be called platform-qualified.
