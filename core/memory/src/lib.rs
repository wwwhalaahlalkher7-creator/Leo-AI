//! Local-first, user-controlled long-term memory storage and retrieval.
//!
//! Memory proposals are never available to retrieval until the user approves
//! them. Production access uses AES-256-GCM field encryption with a key supplied
//! by OS-backed secure storage. This crate does not inspect conversations or
//! extract memories by itself; the opt-in curator submits explicit proposals.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose::STANDARD_NO_PAD;
use base64::Engine as _;
use hmac::{Hmac, Mac};
use hkdf::Hkdf;
use leo_shared::{MemoryKind, MemoryRecord};
use rand::rngs::OsRng;
use rand::RngCore;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use std::collections::{BTreeSet, HashMap};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

const DATABASE_SCHEMA_VERSION: i64 = 2;
const ENCRYPTED_PREFIX: &str = "enc:v1:";
const RECORD_ENCRYPTED_PREFIX: &str = "enc:v2:";
const KEYED_DIGEST_PREFIX: &str = "hmac:v2:";
const KEY_CHECK_VALUE: &str = "leo-memory-key-check-v1";
const MAX_CONTENT_CHARACTERS: usize = 20_000;
const MAX_TAGS: usize = 20;
const MAX_TAG_CHARACTERS: usize = 64;
const MAX_CANDIDATES: usize = 1_000;
const MAX_SEARCH_RESULTS: usize = 20;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryEntry {
    pub record: MemoryRecord,
    pub updated_at_utc: String,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MemorySearchHit {
    pub entry: MemoryEntry,
    pub score: f64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MemoryStoreError {
    EmptyId,
    InvalidId,
    EmptyContent,
    ContentTooLong,
    InvalidTimestamp,
    TooManyTags,
    InvalidTag,
    SourceReferenceTooLong,
    EmptyQuery,
    InvalidResultLimit,
    RelativeDatabasePath,
    InvalidEncryptionKey,
    EncryptionKeyRequired,
    EncryptionKeyInvalid,
    DuplicateMemory,
    NotFound,
    UnsupportedSchema(i64),
    Storage(String),
}

impl fmt::Display for MemoryStoreError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyId => write!(formatter, "memory ID cannot be empty"),
            Self::InvalidId => write!(formatter, "memory ID contains unsupported characters"),
            Self::EmptyContent => write!(formatter, "memory content cannot be empty"),
            Self::ContentTooLong => write!(formatter, "memory content exceeds the local limit"),
            Self::InvalidTimestamp => write!(formatter, "memory timestamp is invalid"),
            Self::TooManyTags => write!(formatter, "memory contains too many tags"),
            Self::InvalidTag => write!(formatter, "one or more memory tags are invalid"),
            Self::SourceReferenceTooLong => {
                write!(formatter, "memory source reference is too long")
            }
            Self::EmptyQuery => write!(formatter, "memory search query cannot be empty"),
            Self::InvalidResultLimit => write!(formatter, "memory search result limit is invalid"),
            Self::RelativeDatabasePath => {
                write!(formatter, "memory database path must be absolute and app-private")
            }
            Self::InvalidEncryptionKey => write!(formatter, "memory encryption key must contain exactly 32 bytes"),
            Self::EncryptionKeyRequired => write!(formatter, "the encrypted memory database key is unavailable"),
            Self::EncryptionKeyInvalid => write!(formatter, "memory encryption key is invalid or the database was modified"),
            Self::DuplicateMemory => write!(formatter, "an equivalent memory already exists"),
            Self::NotFound => write!(formatter, "memory record was not found"),
            Self::UnsupportedSchema(version) => {
                write!(formatter, "memory database schema {version} is newer than this Leo build")
            }
            Self::Storage(message) => write!(formatter, "memory storage error: {message}"),
        }
    }
}

impl std::error::Error for MemoryStoreError {}

pub struct MemoryStore {
    database_path: PathBuf,
    connection: Connection,
    encryption_key: Option<[u8; 32]>,
}

impl MemoryStore {
    /// Opens a legacy/plaintext store. Production bridge calls use
    /// `open_encrypted`; this path remains for migration tests and controlled
    /// development fixtures. It refuses an encrypted database.
    pub fn open(database_path: impl AsRef<Path>) -> Result<Self, MemoryStoreError> {
        Self::open_internal(database_path.as_ref(), None)
    }

    /// Opens the local memory database with a 256-bit key held by the OS
    /// secure-storage service. Content, tags, source references and search
    /// indexes are authenticated-encrypted before reaching SQLite.
    pub fn open_encrypted(
        database_path: impl AsRef<Path>,
        encryption_key: &[u8],
    ) -> Result<Self, MemoryStoreError> {
        let key: [u8; 32] = encryption_key
            .try_into()
            .map_err(|_| MemoryStoreError::InvalidEncryptionKey)?;
        Self::open_internal(database_path.as_ref(), Some(key))
    }

    fn open_internal(
        database_path: &Path,
        encryption_key: Option<[u8; 32]>,
    ) -> Result<Self, MemoryStoreError> {
        if !database_path.is_absolute() {
            return Err(MemoryStoreError::RelativeDatabasePath);
        }
        if let Some(parent) = database_path.parent().filter(|path| !path.as_os_str().is_empty()) {
            fs::create_dir_all(parent).map_err(storage_error)?;
        }
        let connection = Connection::open(database_path).map_err(storage_error)?;
        connection
            .busy_timeout(Duration::from_secs(5))
            .map_err(storage_error)?;
        connection
            .execute_batch(
                "PRAGMA foreign_keys = ON;
                 PRAGMA journal_mode = WAL;
                 PRAGMA synchronous = FULL;
                 PRAGMA secure_delete = ON;
                 PRAGMA trusted_schema = OFF;",
            )
            .map_err(storage_error)?;
        migrate(&connection)?;
        let store = Self {
            database_path: database_path.to_path_buf(),
            connection,
            encryption_key,
        };
        if let Some(key) = store.encryption_key {
            store.ensure_encrypted(&key)?;
        } else {
            let encrypted_rows: i64 = store.connection.query_row(
                "SELECT COUNT(*) FROM memory_records WHERE encryption_version > 0",
                [],
                |row| row.get(0),
            ).map_err(storage_error)?;
            let has_key_marker: bool = store.connection.query_row(
                "SELECT EXISTS(SELECT 1 FROM memory_security WHERE id = 1)",
                [],
                |row| row.get::<_, i64>(0),
            ).map_err(storage_error)? == 1;
            if encrypted_rows > 0 || has_key_marker {
                return Err(MemoryStoreError::EncryptionKeyRequired);
            }
        }
        Ok(store)
    }

    fn ensure_encrypted(&self, key: &[u8; 32]) -> Result<(), MemoryStoreError> {
        let marker: Option<String> = self.connection.query_row(
            "SELECT key_check_envelope FROM memory_security WHERE id = 1",
            [],
            |row| row.get(0),
        ).optional().map_err(storage_error)?;
        let has_marker = marker.is_some();
        if let Some(envelope) = marker.as_deref() {
            let decrypted = decrypt_field(envelope, key, "key_check")
                .map_err(|_| MemoryStoreError::EncryptionKeyInvalid)?;
            if decrypted != KEY_CHECK_VALUE {
                return Err(MemoryStoreError::EncryptionKeyInvalid);
            }
        } else {
            let encrypted_sample: Option<(String, String)> = self.connection.query_row(
                "SELECT id, content FROM memory_records WHERE encryption_version = 1 LIMIT 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            ).optional().map_err(storage_error)?;
            if let Some((id, sample)) = encrypted_sample {
                decrypt_record_field(&sample, key, &id, "content")
                    .map_err(|_| MemoryStoreError::EncryptionKeyInvalid)?;
            }
        }

        let needs_payload_upgrade: bool = self.connection.query_row(
            "SELECT EXISTS(
                SELECT 1 FROM memory_records
                WHERE encryption_version = 0
                   OR content NOT LIKE 'enc:v2:%'
                   OR normalized_content NOT LIKE 'enc:v2:%'
                   OR tags_json NOT LIKE 'enc:v2:%'
                   OR (source_reference IS NOT NULL AND source_reference NOT LIKE 'enc:v2:%')
                   OR content_sha256 NOT LIKE 'hmac:v2:%'
             )",
            [],
            |row| row.get::<_, i64>(0),
        ).map_err(storage_error)? == 1;
        if has_marker && !needs_payload_upgrade {
            return Ok(());
        }

        let transaction = self.connection.unchecked_transaction().map_err(storage_error)?;
        let legacy_rows = {
            let mut statement = transaction.prepare(
                "SELECT id, content, normalized_content, source_reference, tags_json, encryption_version
                 FROM memory_records
                 WHERE encryption_version = 0
                    OR content NOT LIKE 'enc:v2:%'
                    OR normalized_content NOT LIKE 'enc:v2:%'
                    OR tags_json NOT LIKE 'enc:v2:%'
                    OR (source_reference IS NOT NULL AND source_reference NOT LIKE 'enc:v2:%')
                    OR content_sha256 NOT LIKE 'hmac:v2:%'
                 ORDER BY id",
            ).map_err(storage_error)?;
            let rows = statement.query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, i64>(5)?,
                ))
            }).map_err(storage_error)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(storage_error)?
        };
        for (id, content_raw, normalized_raw, source_raw, tags_raw, version) in legacy_rows {
            let content = if version == 1 {
                decrypt_record_field(&content_raw, key, &id, "content")?
            } else {
                content_raw
            };
            let normalized = if version == 1 {
                decrypt_record_field(&normalized_raw, key, &id, "normalized_content")?
            } else {
                normalized_raw
            };
            let source = if version == 1 {
                source_raw.as_deref()
                    .map(|value| decrypt_record_field(value, key, &id, "source_reference"))
                    .transpose()?
            } else {
                source_raw
            };
            let tags = if version == 1 {
                decrypt_record_field(&tags_raw, key, &id, "tags_json")?
            } else {
                tags_raw
            };
            let encrypted_content = encrypt_record_field(&content, key, &id, "content")?;
            let encrypted_normalized = encrypt_record_field(&normalized, key, &id, "normalized_content")?;
            let encrypted_source = source
                .as_deref()
                .map(|value| encrypt_record_field(value, key, &id, "source_reference"))
                .transpose()?;
            let encrypted_tags = encrypt_record_field(&tags, key, &id, "tags_json")?;
            let keyed_hash = keyed_sha256_hex(&normalized, key)?;
            transaction.execute(
                "UPDATE memory_records SET content=?2, normalized_content=?3,
                 source_reference=?4, tags_json=?5, content_sha256=?6,
                 encryption_version=1 WHERE id=?1",
                params![id, encrypted_content, encrypted_normalized, encrypted_source, encrypted_tags, keyed_hash],
            ).map_err(storage_error)?;
        }
        let new_marker = encrypt_field(KEY_CHECK_VALUE, key, "key_check")?;
        transaction.execute(
            "INSERT INTO memory_security (id, key_check_envelope) VALUES (1, ?1)
             ON CONFLICT(id) DO NOTHING",
            [new_marker],
        ).map_err(storage_error)?;
        transaction.commit().map_err(storage_error)?;
        self.connection.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);").map_err(storage_error)?;
        Ok(())
    }

    /// Reports whether the existing database is empty, legacy plaintext or
    /// encrypted. This lets the UI avoid replacing a missing key with a new one.
    pub fn storage_status(database_path: impl AsRef<Path>) -> Result<String, MemoryStoreError> {
        let database_path = database_path.as_ref();
        if !database_path.is_absolute() {
            return Err(MemoryStoreError::RelativeDatabasePath);
        }
        if !database_path.exists() || fs::metadata(database_path).map_err(storage_error)?.len() == 0 {
            return Ok("empty".to_owned());
        }
        let connection = Connection::open(database_path).map_err(storage_error)?;
        let version: i64 = connection.pragma_query_value(None, "user_version", |row| row.get(0)).map_err(storage_error)?;
        if version < 2 {
            return Ok("legacy_plaintext".to_owned());
        }
        let encrypted_rows: i64 = connection.query_row(
            "SELECT COUNT(*) FROM memory_records WHERE encryption_version > 0",
            [],
            |row| row.get(0),
        ).map_err(storage_error)?;
        let marker: Option<String> = connection.query_row(
            "SELECT key_check_envelope FROM memory_security WHERE id = 1",
            [],
            |row| row.get(0),
        ).optional().map_err(storage_error)?;
        Ok(if encrypted_rows > 0 || marker.is_some() { "encrypted" } else { "legacy_plaintext" }.to_owned())
    }

    /// Destroys the app-private memory database and its SQLite sidecars. The
    /// caller deletes the secure-storage key only after this returns true.
    pub fn erase_database(database_path: impl AsRef<Path>) -> Result<bool, MemoryStoreError> {
        let database_path = database_path.as_ref();
        if !database_path.is_absolute() {
            return Err(MemoryStoreError::RelativeDatabasePath);
        }
        if database_path.exists() {
            let connection = Connection::open(database_path).map_err(storage_error)?;
            connection.execute_batch(
                "PRAGMA secure_delete = ON; PRAGMA journal_mode = WAL;"
            ).map_err(storage_error)?;
            let has_table: bool = connection.query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='memory_records')",
                [], |row| row.get::<_, i64>(0),
            ).map_err(storage_error)? == 1;
            if has_table {
                connection.execute("DELETE FROM memory_records", []).map_err(storage_error)?;
            }
            connection.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);").map_err(storage_error)?;
            drop(connection);
        }
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let candidate = if suffix.is_empty() {
                database_path.to_path_buf()
            } else {
                PathBuf::from(format!("{}{}", database_path.display(), suffix))
            };
            if candidate.exists() {
                fs::remove_file(candidate).map_err(storage_error)?;
            }
        }
        Ok(!database_path.exists()
            && !PathBuf::from(format!("{}-wal", database_path.display())).exists()
            && !PathBuf::from(format!("{}-shm", database_path.display())).exists())
    }

    pub fn database_path(&self) -> &Path {
        &self.database_path
    }

    /// Stores a pending proposal. Pending records never appear in search.
    pub fn propose(&self, mut record: MemoryRecord) -> Result<MemoryEntry, MemoryStoreError> {
        record.user_approved = false;
        self.insert_record(record, false)
    }

    /// Stores a record explicitly approved by the user.
    pub fn save_approved(
        &self,
        mut record: MemoryRecord,
    ) -> Result<MemoryEntry, MemoryStoreError> {
        record.user_approved = true;
        self.insert_record(record, true)
    }

    fn insert_record(
        &self,
        mut record: MemoryRecord,
        active: bool,
    ) -> Result<MemoryEntry, MemoryStoreError> {
        record.tags = normalize_tags(record.tags)?;
        validate_record(&record)?;
        let normalized_content = normalize_for_search(&record.content, &[]);
        let tags_json = serde_json::to_string(&record.tags).map_err(storage_error)?;
        let (stored_content, stored_normalized, stored_source, stored_tags, content_hash, encryption_version) =
            self.encode_record_fields(&record, &normalized_content, &tags_json)?;

        let result = self.connection.execute(
            "INSERT INTO memory_records (
                id, kind, content, normalized_content, source_reference,
                tags_json, content_sha256, created_at_utc, updated_at_utc,
                user_approved, active, encryption_version
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, ?9, ?10, ?11)",
            params![
                record.id,
                memory_kind_name(record.kind),
                stored_content,
                stored_normalized,
                stored_source,
                stored_tags,
                content_hash,
                record.created_at_utc,
                bool_to_integer(record.user_approved),
                bool_to_integer(active),
                encryption_version,
            ],
        );

        match result {
            Ok(_) => {
                let updated_at_utc = self
                    .read_updated_at(&record.id)?
                    .unwrap_or_else(|| record.created_at_utc.clone());
                Ok(MemoryEntry {
                    record,
                    updated_at_utc,
                    active,
                })
            }
            Err(rusqlite::Error::SqliteFailure(code, _))
                if code.code == rusqlite::ErrorCode::ConstraintViolation =>
            {
                Err(MemoryStoreError::DuplicateMemory)
            }
            Err(error) => Err(storage_error(error)),
        }
    }

    pub fn approve(&self, memory_id: &str) -> Result<MemoryEntry, MemoryStoreError> {
        let changed = self.connection.execute(
            "UPDATE memory_records
             SET user_approved = 1, active = 1,
                 updated_at_utc = strftime('%Y-%m-%dT%H:%M:%fZ','now')
             WHERE id = ?1 AND user_approved = 0",
            [memory_id],
        ).map_err(storage_error)?;
        if changed != 1 {
            return Err(MemoryStoreError::NotFound);
        }
        self.get(memory_id)?.ok_or(MemoryStoreError::NotFound)
    }

    pub fn set_active(
        &self,
        memory_id: &str,
        active: bool,
    ) -> Result<MemoryEntry, MemoryStoreError> {
        let changed = self.connection.execute(
            "UPDATE memory_records
             SET active = ?2, updated_at_utc = strftime('%Y-%m-%dT%H:%M:%fZ','now')
             WHERE id = ?1 AND user_approved = 1",
            params![memory_id, bool_to_integer(active)],
        ).map_err(storage_error)?;
        if changed != 1 {
            return Err(MemoryStoreError::NotFound);
        }
        self.get(memory_id)?.ok_or(MemoryStoreError::NotFound)
    }

    /// A user's explicit edit keeps approval but recalculates normalized text
    /// and the deduplication hash. Rejected proposals must be approved first.
    pub fn update_approved(
        &self,
        memory_id: &str,
        content: &str,
        tags: Vec<String>,
        source_reference: Option<String>,
    ) -> Result<MemoryEntry, MemoryStoreError> {
        let existing = self.get(memory_id)?.ok_or(MemoryStoreError::NotFound)?;
        if !existing.record.user_approved {
            return Err(MemoryStoreError::NotFound);
        }
        let mut record = existing.record;
        record.content = content.trim().to_owned();
        record.tags = normalize_tags(tags)?;
        record.source_reference = source_reference;
        validate_record(&record)?;
        let normalized_content = normalize_for_search(&record.content, &[]);
        let tags_json = serde_json::to_string(&record.tags).map_err(storage_error)?;
        let (stored_content, stored_normalized, stored_source, stored_tags, content_hash, _encryption_version) =
            self.encode_record_fields(&record, &normalized_content, &tags_json)?;

        self.connection.execute(
            "UPDATE memory_records
             SET content = ?2, normalized_content = ?3, source_reference = ?4,
                 tags_json = ?5, content_sha256 = ?6,
                 updated_at_utc = strftime('%Y-%m-%dT%H:%M:%fZ','now')
             WHERE id = ?1 AND user_approved = 1",
            params![
                memory_id,
                stored_content,
                stored_normalized,
                stored_source,
                stored_tags,
                content_hash,
            ],
        ).map_err(map_write_error)?;
        self.get(memory_id)?.ok_or(MemoryStoreError::NotFound)
    }

    /// Removes a proposal (reject) or a user-approved memory (forget).
    pub fn delete(&self, memory_id: &str) -> Result<bool, MemoryStoreError> {
        self.connection
            .execute("DELETE FROM memory_records WHERE id = ?1", [memory_id])
            .map(|removed| removed == 1)
            .map_err(storage_error)
    }

    pub fn get(&self, memory_id: &str) -> Result<Option<MemoryEntry>, MemoryStoreError> {
        let mut statement = self.connection.prepare(
            "SELECT id, kind, content, source_reference, tags_json,
                    created_at_utc, updated_at_utc, user_approved, active, encryption_version
             FROM memory_records WHERE id = ?1",
        ).map_err(storage_error)?;
        let key = self.encryption_key;
        statement
            .query_row([memory_id], |row| row_to_entry(row, key, 9))
            .optional()
            .map_err(storage_error)
    }

    pub fn list(
        &self,
        include_pending: bool,
        limit: usize,
    ) -> Result<Vec<MemoryEntry>, MemoryStoreError> {
        let limit = limit.clamp(1, 1_001) as i64;
        let mut statement = self.connection.prepare(
            "SELECT id, kind, content, source_reference, tags_json,
                    created_at_utc, updated_at_utc, user_approved, active, encryption_version
             FROM memory_records
             WHERE (?1 = 1 OR user_approved = 1)
             ORDER BY updated_at_utc DESC, id DESC
             LIMIT ?2",
        ).map_err(storage_error)?;
        let key = self.encryption_key;
        let rows = statement
            .query_map(params![bool_to_integer(include_pending), limit], |row| row_to_entry(row, key, 9))
            .map_err(storage_error)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(storage_error)
    }

    /// Searches only approved and active memories. Pending proposals, disabled
    /// memories and deleted records are never exposed to model context.
    pub fn search(
        &self,
        query: &str,
        limit: usize,
    ) -> Result<Vec<MemorySearchHit>, MemoryStoreError> {
        if limit == 0 || limit > MAX_SEARCH_RESULTS {
            return Err(MemoryStoreError::InvalidResultLimit);
        }
        let mut query_tokens = tokens(&normalize_for_search(query, &[]));
        query_tokens.sort_unstable();
        query_tokens.dedup();
        if query_tokens.is_empty() {
            return Err(MemoryStoreError::EmptyQuery);
        }
        let mut statement = self.connection.prepare(
            "SELECT id, kind, content, source_reference, tags_json,
                    created_at_utc, updated_at_utc, user_approved, active,
                    normalized_content, encryption_version
             FROM memory_records
             WHERE user_approved = 1 AND active = 1
             ORDER BY updated_at_utc DESC, id DESC
             LIMIT ?1",
        ).map_err(storage_error)?;
        let key = self.encryption_key;
        let rows = statement.query_map([MAX_CANDIDATES as i64], |row| {
            let entry = row_to_entry(row, key, 10)?;
            let normalized_raw: String = row.get(9)?;
            let encryption_version: i64 = row.get(10)?;
            let normalized = if encryption_version == 1 {
                let key = key.ok_or_else(|| sql_conversion_error(9, "encrypted memory key is missing"))?;
                decrypt_record_field(&normalized_raw, &key, &row.get::<_, String>(0)?, "normalized_content")
                    .map_err(|error| sql_conversion_error(9, &error.to_string()))?
            } else {
                normalized_raw
            };
            Ok((entry, normalized))
        }).map_err(storage_error)?;
        let candidates = rows.collect::<Result<Vec<_>, _>>().map_err(storage_error)?;
        let ranked = rank_candidates(&query_tokens, candidates);
        Ok(ranked.into_iter().take(limit).collect())
    }

    fn encode_record_fields(
        &self,
        record: &MemoryRecord,
        normalized_content: &str,
        tags_json: &str,
    ) -> Result<(String, String, Option<String>, String, String, i64), MemoryStoreError> {
        if let Some(key) = self.encryption_key {
            Ok((
                encrypt_record_field(&record.content, &key, &record.id, "content")?,
                encrypt_record_field(normalized_content, &key, &record.id, "normalized_content")?,
                record.source_reference.as_deref()
                    .map(|value| encrypt_record_field(value, &key, &record.id, "source_reference"))
                    .transpose()?,
                encrypt_record_field(tags_json, &key, &record.id, "tags_json")?,
                keyed_sha256_hex(normalized_content, &key)?,
                1,
            ))
        } else {
            Ok((
                record.content.clone(),
                normalized_content.to_owned(),
                record.source_reference.clone(),
                tags_json.to_owned(),
                sha256_hex(normalized_content.as_bytes()),
                0,
            ))
        }
    }

    /// Re-encrypts all memory payload fields under a new 256-bit key in one
    /// transaction. The caller persists the new key only after this succeeds.
    pub fn rotate_encryption_key(&self, new_key: &[u8]) -> Result<(), MemoryStoreError> {
        let old_key = self.encryption_key.ok_or(MemoryStoreError::EncryptionKeyRequired)?;
        let new_key: [u8; 32] = new_key.try_into().map_err(|_| MemoryStoreError::InvalidEncryptionKey)?;
        let transaction = self.connection.unchecked_transaction().map_err(storage_error)?;
        let rows = {
            let mut statement = transaction.prepare(
                "SELECT id, content, normalized_content, source_reference, tags_json, encryption_version
                 FROM memory_records ORDER BY id",
            ).map_err(storage_error)?;
            let rows = statement.query_map([], |row| Ok((
                row.get::<_, String>(0)?, row.get::<_, String>(1)?,
                row.get::<_, String>(2)?, row.get::<_, Option<String>>(3)?,
                row.get::<_, String>(4)?, row.get::<_, i64>(5)?,
            ))).map_err(storage_error)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(storage_error)?
        };
        for (id, content_raw, normalized_raw, source_raw, tags_raw, version) in rows {
            let content = if version == 1 { decrypt_record_field(&content_raw, &old_key, &id, "content")? } else { content_raw };
            let normalized = if version == 1 { decrypt_record_field(&normalized_raw, &old_key, &id, "normalized_content")? } else { normalized_raw };
            let source = if version == 1 {
                source_raw.as_deref().map(|value| decrypt_record_field(value, &old_key, &id, "source_reference")).transpose()?
            } else { source_raw };
            let tags = if version == 1 { decrypt_record_field(&tags_raw, &old_key, &id, "tags_json")? } else { tags_raw };
            let new_content = encrypt_record_field(&content, &new_key, &id, "content")?;
            let new_normalized = encrypt_record_field(&normalized, &new_key, &id, "normalized_content")?;
            let new_source = source.as_deref().map(|value| encrypt_record_field(value, &new_key, &id, "source_reference")).transpose()?;
            let new_tags = encrypt_record_field(&tags, &new_key, &id, "tags_json")?;
            let new_hash = keyed_sha256_hex(&normalized, &new_key)?;
            transaction.execute(
                "UPDATE memory_records SET content=?2, normalized_content=?3,
                 source_reference=?4, tags_json=?5, content_sha256=?6, encryption_version=1 WHERE id=?1",
                params![id, new_content, new_normalized, new_source, new_tags, new_hash],
            ).map_err(storage_error)?;
        }
        let marker = encrypt_field(KEY_CHECK_VALUE, &new_key, "key_check")?;
        transaction.execute(
            "INSERT INTO memory_security (id, key_check_envelope) VALUES (1, ?1)
             ON CONFLICT(id) DO UPDATE SET key_check_envelope=excluded.key_check_envelope",
            [marker],
        ).map_err(storage_error)?;
        transaction.commit().map_err(storage_error)?;
        self.connection.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);").map_err(storage_error)?;
        Ok(())
    }

    fn read_updated_at(&self, memory_id: &str) -> Result<Option<String>, MemoryStoreError> {
        self.connection.query_row(
            "SELECT updated_at_utc FROM memory_records WHERE id = ?1",
            [memory_id],
            |row| row.get(0),
        ).optional().map_err(storage_error)
    }
}

fn migrate(connection: &Connection) -> Result<(), MemoryStoreError> {
    let current_version: i64 = connection
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .map_err(storage_error)?;
    if current_version > DATABASE_SCHEMA_VERSION {
        return Err(MemoryStoreError::UnsupportedSchema(current_version));
    }
    if current_version == 0 {
        connection.execute_batch(
            "BEGIN IMMEDIATE;
             CREATE TABLE memory_records (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL CHECK (
                    kind IN ('personal','episodic','semantic','procedural','project')
                ),
                content TEXT NOT NULL,
                normalized_content TEXT NOT NULL,
                source_reference TEXT,
                tags_json TEXT NOT NULL,
                content_sha256 TEXT NOT NULL,
                created_at_utc TEXT NOT NULL,
                updated_at_utc TEXT NOT NULL,
                user_approved INTEGER NOT NULL CHECK (user_approved IN (0,1)),
                active INTEGER NOT NULL CHECK (active IN (0,1)),
                encryption_version INTEGER NOT NULL DEFAULT 0 CHECK (encryption_version IN (0,1)),
                UNIQUE(kind, content_sha256)
             );
             CREATE TABLE memory_security (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                key_check_envelope TEXT NOT NULL
             );
             CREATE INDEX memory_records_approval_updated
                ON memory_records(user_approved, active, updated_at_utc DESC);
             CREATE INDEX memory_records_kind_updated
                ON memory_records(kind, updated_at_utc DESC);
             PRAGMA user_version = 2;
             COMMIT;",
        ).map_err(storage_error)?;
    } else if current_version == 1 {
        // v0.25 and earlier stored clear text. The first v0.26 encrypted open
        // converts legacy records in one transaction using the new OS key.
        connection.execute_batch(
            "BEGIN IMMEDIATE;
             ALTER TABLE memory_records ADD COLUMN encryption_version INTEGER NOT NULL DEFAULT 0;
             CREATE TABLE IF NOT EXISTS memory_security (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                key_check_envelope TEXT NOT NULL
             );
             PRAGMA user_version = 2;
             COMMIT;",
        ).map_err(storage_error)?;
    }
    Ok(())
}

fn row_to_entry(
    row: &rusqlite::Row<'_>,
    key: Option<[u8; 32]>,
    encryption_column: usize,
) -> rusqlite::Result<MemoryEntry> {
    let encryption_version: i64 = row.get(encryption_column)?;
    let record_id: String = row.get(0)?;
    let kind_name: String = row.get(1)?;
    let kind = parse_memory_kind(&kind_name).ok_or_else(|| {
        rusqlite::Error::InvalidColumnType(1, "kind".to_owned(), rusqlite::types::Type::Text)
    })?;
    let content_raw: String = row.get(2)?;
    let source_raw: Option<String> = row.get(3)?;
    let tags_raw: String = row.get(4)?;
    let (content, source_reference, tags_json) = if encryption_version == 1 {
        let key = key.ok_or_else(|| sql_conversion_error(2, "encrypted memory key is missing"))?;
        (
            decrypt_record_field(&content_raw, &key, &record_id, "content")
                .map_err(|error| sql_conversion_error(2, &error.to_string()))?,
            source_raw.as_deref()
                .map(|value| decrypt_record_field(value, &key, &record_id, "source_reference"))
                .transpose()
                .map_err(|error| sql_conversion_error(3, &error.to_string()))?,
            decrypt_record_field(&tags_raw, &key, &record_id, "tags_json")
                .map_err(|error| sql_conversion_error(4, &error.to_string()))?,
        )
    } else {
        (content_raw, source_raw, tags_raw)
    };
    let tags: Vec<String> = serde_json::from_str(&tags_json).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(
            4,
            rusqlite::types::Type::Text,
            Box::new(error),
        )
    })?;
    let approved: i64 = row.get(7)?;
    let active: i64 = row.get(8)?;
    Ok(MemoryEntry {
        record: MemoryRecord {
            id: record_id,
            kind,
            content,
            source_reference,
            tags,
            created_at_utc: row.get(5)?,
            user_approved: approved == 1,
        },
        updated_at_utc: row.get(6)?,
        active: active == 1,
    })
}

fn sql_conversion_error(index: usize, message: &str) -> rusqlite::Error {
    rusqlite::Error::FromSqlConversionFailure(
        index,
        rusqlite::types::Type::Text,
        Box::new(std::io::Error::new(std::io::ErrorKind::InvalidData, message.to_owned())),
    )
}

fn encrypt_field(value: &str, key: &[u8; 32], field: &str) -> Result<String, MemoryStoreError> {
    let encrypted = encrypt_with_aad(value, key, field.as_bytes())?;
    Ok(format!("{}{}", ENCRYPTED_PREFIX, encrypted))
}

fn decrypt_field(value: &str, key: &[u8; 32], field: &str) -> Result<String, MemoryStoreError> {
    let encoded = value.strip_prefix(ENCRYPTED_PREFIX)
        .ok_or(MemoryStoreError::EncryptionKeyInvalid)?;
    let payload = STANDARD_NO_PAD.decode(encoded)
        .map_err(|_| MemoryStoreError::EncryptionKeyInvalid)?;
    if payload.len() < 12 + 16 {
        return Err(MemoryStoreError::EncryptionKeyInvalid);
    }
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| MemoryStoreError::InvalidEncryptionKey)?;
    let clear = cipher.decrypt(
        Nonce::from_slice(&payload[..12]),
        Payload { msg: &payload[12..], aad: field.as_bytes() },
    ).map_err(|_| MemoryStoreError::EncryptionKeyInvalid)?;
    String::from_utf8(clear).map_err(|_| MemoryStoreError::EncryptionKeyInvalid)
}

fn record_field_aad(record_id: &str, field: &str) -> String {
    format!("leo-memory-record:v2:{record_id}:{field}")
}

fn encrypt_record_field(
    value: &str,
    key: &[u8; 32],
    record_id: &str,
    field: &str,
) -> Result<String, MemoryStoreError> {
    let aad = record_field_aad(record_id, field);
    let encrypted = encrypt_with_aad(value, key, aad.as_bytes())?;
    Ok(format!("{}{}", RECORD_ENCRYPTED_PREFIX, encrypted))
}

fn decrypt_record_field(
    value: &str,
    key: &[u8; 32],
    record_id: &str,
    field: &str,
) -> Result<String, MemoryStoreError> {
    if value.starts_with(RECORD_ENCRYPTED_PREFIX) {
        let encoded = value.strip_prefix(RECORD_ENCRYPTED_PREFIX)
            .ok_or(MemoryStoreError::EncryptionKeyInvalid)?;
        let payload = STANDARD_NO_PAD.decode(encoded)
            .map_err(|_| MemoryStoreError::EncryptionKeyInvalid)?;
        if payload.len() < 28 {
            return Err(MemoryStoreError::EncryptionKeyInvalid);
        }
        let aad = record_field_aad(record_id, field);
        let cipher = Aes256Gcm::new_from_slice(key)
            .map_err(|_| MemoryStoreError::InvalidEncryptionKey)?;
        let clear = cipher.decrypt(
            Nonce::from_slice(&payload[..12]),
            Payload { msg: &payload[12..], aad: aad.as_bytes() },
        ).map_err(|_| MemoryStoreError::EncryptionKeyInvalid)?;
        return String::from_utf8(clear).map_err(|_| MemoryStoreError::EncryptionKeyInvalid);
    }
    // Read v1 memory records created by the first v0.26 development snapshots.
    decrypt_field(value, key, field)
}

fn encrypt_with_aad(
    value: &str,
    key: &[u8; 32],
    aad: &[u8],
) -> Result<String, MemoryStoreError> {
    let cipher = Aes256Gcm::new_from_slice(key)
        .map_err(|_| MemoryStoreError::InvalidEncryptionKey)?;
    let mut nonce_bytes = [0_u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let encrypted = cipher.encrypt(
        Nonce::from_slice(&nonce_bytes),
        Payload { msg: value.as_bytes(), aad },
    ).map_err(|_| MemoryStoreError::Storage("memory encryption failed".to_owned()))?;
    let mut payload = nonce_bytes.to_vec();
    payload.extend(encrypted);
    Ok(STANDARD_NO_PAD.encode(payload))
}

fn keyed_sha256_hex(value: &str, key: &[u8; 32]) -> Result<String, MemoryStoreError> {
    // Keep the deterministic duplicate fingerprint on a distinct subkey so
    // AES-GCM encryption and HMAC authentication never share raw key material.
    let derivation = Hkdf::<Sha256>::new(Some(&b"leo-memory-key-derivation:v1"[..]), key);
    let mut digest_key = [0_u8; 32];
    derivation
        .expand(b"content-deduplication-hmac:v2", &mut digest_key)
        .map_err(|_| MemoryStoreError::Storage("memory digest key derivation failed".to_owned()))?;
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(&digest_key)
        .map_err(|_| MemoryStoreError::InvalidEncryptionKey)?;
    mac.update(value.as_bytes());
    let digest = mac.finalize().into_bytes();
    Ok(format!(
        "{KEYED_DIGEST_PREFIX}{}",
        digest.iter().map(|byte| format!("{byte:02x}")).collect::<Vec<_>>().join("")
    ))
}

fn validate_record(record: &MemoryRecord) -> Result<(), MemoryStoreError> {
    if record.id.trim().is_empty() {
        return Err(MemoryStoreError::EmptyId);
    }
    if record.id.len() > 128
        || !record.id.chars().enumerate().all(|(index, character)| {
            character.is_ascii_alphanumeric()
                || (index > 0 && matches!(character, '-' | '_' | '.'))
        })
    {
        return Err(MemoryStoreError::InvalidId);
    }
    let content_length = record.content.trim().chars().count();
    if content_length == 0 {
        return Err(MemoryStoreError::EmptyContent);
    }
    if content_length > MAX_CONTENT_CHARACTERS {
        return Err(MemoryStoreError::ContentTooLong);
    }
    if record.created_at_utc.trim().is_empty() || record.created_at_utc.len() > 40 {
        return Err(MemoryStoreError::InvalidTimestamp);
    }
    if record.tags.len() > MAX_TAGS {
        return Err(MemoryStoreError::TooManyTags);
    }
    if record.tags.iter().any(|tag| {
        tag.trim().is_empty()
            || tag.chars().count() > MAX_TAG_CHARACTERS
            || tag.chars().any(char::is_control)
    }) {
        return Err(MemoryStoreError::InvalidTag);
    }
    if record.source_reference.as_ref().is_some_and(|reference| {
        reference.chars().count() > 1_024 || reference.chars().any(char::is_control)
    }) {
        return Err(MemoryStoreError::SourceReferenceTooLong);
    }
    Ok(())
}

fn normalize_tags(tags: Vec<String>) -> Result<Vec<String>, MemoryStoreError> {
    if tags.len() > MAX_TAGS {
        return Err(MemoryStoreError::TooManyTags);
    }
    let mut unique = BTreeSet::new();
    for tag in tags {
        let normalized = tag.split_whitespace().collect::<Vec<_>>().join(" ");
        if normalized.is_empty()
            || normalized.chars().count() > MAX_TAG_CHARACTERS
            || normalized.chars().any(char::is_control)
        {
            return Err(MemoryStoreError::InvalidTag);
        }
        unique.insert(normalized);
    }
    Ok(unique.into_iter().collect())
}

fn normalize_for_search(content: &str, tags: &[String]) -> String {
    let tag_bytes = tags.iter().map(String::len).sum::<usize>();
    let mut combined = String::with_capacity(content.len() + tag_bytes);
    combined.push_str(content);
    for tag in tags {
        combined.push(' ');
        combined.push_str(tag);
    }
    let mut normalized = String::with_capacity(combined.len());
    for character in combined.chars() {
        match character {
            '\u{0640}' => continue,
            '\u{064B}'..='\u{065F}' | '\u{0670}' | '\u{06D6}'..='\u{06ED}' => continue,
            'أ' | 'إ' | 'آ' | 'ٱ' => normalized.push('ا'),
            'ؤ' => normalized.push('و'),
            'ئ' | 'ى' => normalized.push('ي'),
            'ة' => normalized.push('ه'),
            other => normalized.extend(other.to_lowercase()),
        }
    }
    normalized
}

fn tokens(value: &str) -> Vec<String> {
    value
        .split(|character: char| !character.is_alphanumeric())
        .filter(|token| token.chars().count() >= 2)
        .map(str::to_owned)
        .take(128)
        .collect()
}

fn rank_candidates(
    query_tokens: &[String],
    candidates: Vec<(MemoryEntry, String)>,
) -> Vec<MemorySearchHit> {
    if candidates.is_empty() || query_tokens.is_empty() {
        return Vec::new();
    }
    let documents = candidates
        .into_iter()
        .map(|(entry, normalized)| {
            let document_tokens = tokens(&normalized);
            let mut frequencies = HashMap::<String, usize>::new();
            for token in &document_tokens {
                *frequencies.entry(token.clone()).or_default() += 1;
            }
            (entry, document_tokens.len().max(1), frequencies)
        })
        .collect::<Vec<_>>();
    let corpus_size = documents.len() as f64;
    let average_length = documents.iter().map(|(_, length, _)| *length).sum::<usize>() as f64
        / corpus_size;
    let mut document_frequency = HashMap::<&str, usize>::new();
    for token in query_tokens {
        let frequency = documents
            .iter()
            .filter(|(_, _, counts)| counts.contains_key(token))
            .count();
        document_frequency.insert(token.as_str(), frequency);
    }

    let mut results = documents
        .into_iter()
        .filter_map(|(entry, length, frequencies)| {
            let mut score = 0.0;
            for token in query_tokens {
                let term_frequency = *frequencies.get(token).unwrap_or(&0) as f64;
                if term_frequency == 0.0 {
                    continue;
                }
                let doc_frequency = *document_frequency.get(token.as_str()).unwrap_or(&0) as f64;
                let inverse_frequency =
                    (1.0 + (corpus_size - doc_frequency + 0.5) / (doc_frequency + 0.5)).ln();
                const K1: f64 = 1.2;
                const B: f64 = 0.75;
                let length_norm = K1 * (1.0 - B + B * length as f64 / average_length.max(1.0));
                score += inverse_frequency * (term_frequency * (K1 + 1.0))
                    / (term_frequency + length_norm);
            }
            (score > 0.0).then_some(MemorySearchHit { entry, score })
        })
        .collect::<Vec<_>>();
    results.sort_by(|left, right| {
        right.score.total_cmp(&left.score).then_with(|| {
            right
                .entry
                .updated_at_utc
                .cmp(&left.entry.updated_at_utc)
        })
    });
    results
}

fn memory_kind_name(kind: MemoryKind) -> &'static str {
    match kind {
        MemoryKind::Personal => "personal",
        MemoryKind::Episodic => "episodic",
        MemoryKind::Semantic => "semantic",
        MemoryKind::Procedural => "procedural",
        MemoryKind::Project => "project",
    }
}

fn parse_memory_kind(value: &str) -> Option<MemoryKind> {
    match value {
        "personal" => Some(MemoryKind::Personal),
        "episodic" => Some(MemoryKind::Episodic),
        "semantic" => Some(MemoryKind::Semantic),
        "procedural" => Some(MemoryKind::Procedural),
        "project" => Some(MemoryKind::Project),
        _ => None,
    }
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<Vec<_>>()
        .join("")
}

fn bool_to_integer(value: bool) -> i64 {
    if value {
        1
    } else {
        0
    }
}

fn map_write_error(error: rusqlite::Error) -> MemoryStoreError {
    match &error {
        rusqlite::Error::SqliteFailure(code, _)
            if code.code == rusqlite::ErrorCode::ConstraintViolation =>
        {
            MemoryStoreError::DuplicateMemory
        }
        _ => storage_error(error),
    }
}

fn storage_error(error: impl fmt::Display) -> MemoryStoreError {
    MemoryStoreError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TestDatabase(PathBuf);

    impl TestDatabase {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock must be after Unix epoch")
                .as_nanos();
            let root = std::env::temp_dir().join(format!("leo-memory-test-{nonce}"));
            fs::create_dir_all(&root).expect("test directory should be created");
            Self(root.join("memory.sqlite3"))
        }
    }

    impl Drop for TestDatabase {
        fn drop(&mut self) {
            if let Some(parent) = self.0.parent() {
                let _ = fs::remove_dir_all(parent);
            }
        }
    }

    fn record(id: &str, content: &str, approved: bool) -> MemoryRecord {
        MemoryRecord {
            id: id.to_owned(),
            kind: MemoryKind::Project,
            content: content.to_owned(),
            source_reference: Some("conversation:test".to_owned()),
            tags: vec!["Leo".to_owned(), "مشروع".to_owned()],
            created_at_utc: "2026-11-15T10:00:00Z".to_owned(),
            user_approved: approved,
        }
    }

    #[test]
    fn database_path_must_be_absolute() {
        assert!(matches!(
            MemoryStore::open("relative/path/memory.sqlite3"),
            Err(MemoryStoreError::RelativeDatabasePath)
        ));
    }

    #[test]
    fn pending_proposals_are_not_retrievable_until_approved() {
        let database = TestDatabase::new();
        let store = MemoryStore::open(&database.0).unwrap();
        store.propose(record("memory-1", "مشروع Leo يعمل محلياً", true)).unwrap();
        assert!(store.search("مشروع Leo", 5).unwrap().is_empty());
        let approved = store.approve("memory-1").unwrap();
        assert!(approved.record.user_approved);
        assert!(approved.active);
        assert_eq!(store.search("مشروع Leo", 5).unwrap().len(), 1);
    }

    #[test]
    fn only_pending_records_can_transition_through_approval() {
        let database = TestDatabase::new();
        let store = MemoryStore::open(&database.0).unwrap();
        store
            .save_approved(record("memory-approval", "ذاكرة معتمدة", true))
            .unwrap();
        assert_eq!(
            store.approve("memory-approval"),
            Err(MemoryStoreError::NotFound)
        );
        assert!(store.get("memory-approval").unwrap().unwrap().active);
    }

    #[test]
    fn edited_memory_is_reindexed_and_searchable_by_new_content() {
        let database = TestDatabase::new();
        let store = MemoryStore::open(&database.0).unwrap();
        store
            .save_approved(record("memory-edit", "مشروع قديم", true))
            .unwrap();
        store
            .update_approved(
                "memory-edit",
                "مشروع Leo الجديد",
                vec!["Leo".to_owned()],
                None,
            )
            .unwrap();
        assert!(store.search("قديم", 5).unwrap().is_empty());
        assert_eq!(store.search("الجديد", 5).unwrap().len(), 1);
    }

    #[test]
    fn approved_memory_survives_reopening_the_database() {
        let database = TestDatabase::new();
        {
            let store = MemoryStore::open(&database.0).unwrap();
            store
                .save_approved(record(
                    "memory-2",
                    "المستخدم يفضل العمل دون إنترنت",
                    false,
                ))
                .unwrap();
        }
        let store = MemoryStore::open(&database.0).unwrap();
        assert_eq!(store.list(false, 20).unwrap().len(), 1);
    }

    #[test]
    fn arabic_diacritics_and_alef_variants_match_during_search() {
        let database = TestDatabase::new();
        let store = MemoryStore::open(&database.0).unwrap();
        store
            .save_approved(record(
                "memory-3",
                "أُفضّلُ التَّشغيلَ المحلّي",
                true,
            ))
            .unwrap();
        assert_eq!(store.search("افضل التشغيل المحلي", 5).unwrap().len(), 1);
    }

    #[test]
    fn disabled_memories_are_excluded_from_search_but_remain_editable() {
        let database = TestDatabase::new();
        let store = MemoryStore::open(&database.0).unwrap();
        store
            .save_approved(record("memory-4", "مشروع Leo بدون اتصال", true))
            .unwrap();
        store.set_active("memory-4", false).unwrap();
        assert!(store.search("مشروع Leo", 5).unwrap().is_empty());
        let entry = store.set_active("memory-4", true).unwrap();
        assert!(entry.active);
    }

    #[test]
    fn exact_duplicate_content_for_same_kind_is_rejected() {
        let database = TestDatabase::new();
        let store = MemoryStore::open(&database.0).unwrap();
        store.save_approved(record("memory-5", "ذاكرة مكررة", true)).unwrap();
        assert_eq!(
            store.save_approved(record("memory-6", "ذاكرة مكررة", true)),
            Err(MemoryStoreError::DuplicateMemory)
        );
    }

    #[test]
    fn invalid_or_empty_memories_are_rejected() {
        let database = TestDatabase::new();
        let store = MemoryStore::open(&database.0).unwrap();
        assert_eq!(
            store.propose(record("../unsafe", "test", false)),
            Err(MemoryStoreError::InvalidId)
        );
        assert_eq!(
            store.propose(record("memory-empty", "  ", false)),
            Err(MemoryStoreError::EmptyContent)
        );
    }

    #[test]
    fn explicit_delete_removes_a_memory() {
        let database = TestDatabase::new();
        let store = MemoryStore::open(&database.0).unwrap();
        store
            .save_approved(record("memory-7", "يجب حذف هذه الذاكرة", true))
            .unwrap();
        assert!(store.delete("memory-7").unwrap());
        assert!(store.get("memory-7").unwrap().is_none());
    }

    #[test]
    fn encrypted_store_hides_content_and_requires_the_correct_key() {
        let database = TestDatabase::new();
        let key = [7_u8; 32];
        {
            let store = MemoryStore::open_encrypted(&database.0, &key).unwrap();
            store.save_approved(record(
                "encrypted-1",
                "secret memory phrase for local storage",
                true,
            )).unwrap();
            assert_eq!(store.search("secret memory", 5).unwrap().len(), 1);
        }
        let raw = fs::read(&database.0).unwrap();
        assert!(!raw.windows(b"secret memory phrase".len()).any(|w| w == b"secret memory phrase"));
        assert!(matches!(MemoryStore::open(&database.0), Err(MemoryStoreError::EncryptionKeyRequired)));
        assert!(matches!(MemoryStore::open_encrypted(&database.0, &[8_u8; 32]), Err(MemoryStoreError::EncryptionKeyInvalid)));
        let reopened = MemoryStore::open_encrypted(&database.0, &key).unwrap();
        assert_eq!(reopened.list(false, 5).unwrap()[0].record.content, "secret memory phrase for local storage");
    }

    #[test]
    fn legacy_v1_envelopes_are_upgraded_to_record_bound_v2_envelopes() {
        let database = TestDatabase::new();
        let key = [5_u8; 32];
        {
            let store = MemoryStore::open(&database.0).unwrap();
            store.save_approved(record("legacy-envelope", "private legacy payload", true)).unwrap();
        }
        let connection = Connection::open(&database.0).unwrap();
        let (content, normalized, source, tags): (String, String, Option<String>, String) = connection.query_row(
            "SELECT content, normalized_content, source_reference, tags_json FROM memory_records WHERE id='legacy-envelope'",
            [], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        ).unwrap();
        connection.execute(
            "UPDATE memory_records SET content=?1, normalized_content=?2, source_reference=?3, tags_json=?4, encryption_version=1 WHERE id='legacy-envelope'",
            params![
                encrypt_field(&content, &key, "content").unwrap(),
                encrypt_field(&normalized, &key, "normalized_content").unwrap(),
                source.as_deref().map(|value| encrypt_field(value, &key, "source_reference").unwrap()),
                encrypt_field(&tags, &key, "tags_json").unwrap(),
            ],
        ).unwrap();
        connection.execute(
            "INSERT INTO memory_security (id, key_check_envelope) VALUES (1, ?1)",
            [encrypt_field(KEY_CHECK_VALUE, &key, "key_check").unwrap()],
        ).unwrap();
        drop(connection);

        let migrated = MemoryStore::open_encrypted(&database.0, &key).unwrap();
        assert_eq!(migrated.get("legacy-envelope").unwrap().unwrap().record.content, "private legacy payload");
        let connection = Connection::open(&database.0).unwrap();
        let (stored_content, stored_normalized): (String, String) = connection.query_row(
            "SELECT content, normalized_content FROM memory_records WHERE id='legacy-envelope'",
            [], |row| Ok((row.get(0)?, row.get(1)?)),
        ).unwrap();
        assert!(stored_content.starts_with(RECORD_ENCRYPTED_PREFIX));
        assert!(stored_normalized.starts_with(RECORD_ENCRYPTED_PREFIX));
    }

    #[test]
    fn encrypted_record_payloads_are_bound_to_their_row_identity() {
        let database = TestDatabase::new();
        let key = [6_u8; 32];
        {
            let store = MemoryStore::open_encrypted(&database.0, &key).unwrap();
            store.save_approved(record("bound-a", "record alpha secret", true)).unwrap();
            store.save_approved(record("bound-b", "record bravo secret", true)).unwrap();
        }
        let connection = Connection::open(&database.0).unwrap();
        let alpha: String = connection.query_row(
            "SELECT content FROM memory_records WHERE id='bound-a'", [], |row| row.get(0),
        ).unwrap();
        connection.execute(
            "UPDATE memory_records SET content=?1 WHERE id='bound-b'", [alpha],
        ).unwrap();
        drop(connection);
        let reopened = MemoryStore::open_encrypted(&database.0, &key).unwrap();
        assert!(reopened.get("bound-b").is_err());
    }

    #[test]
    fn legacy_plaintext_records_are_encrypted_on_first_keyed_open() {
        let database = TestDatabase::new();
        {
            let store = MemoryStore::open(&database.0).unwrap();
            store.save_approved(record("legacy-1", "legacy private memory", true)).unwrap();
        }
        let key = [9_u8; 32];
        let encrypted = MemoryStore::open_encrypted(&database.0, &key).unwrap();
        assert_eq!(encrypted.search("legacy private", 5).unwrap().len(), 1);
        let raw = fs::read(&database.0).unwrap();
        assert!(!raw.windows(b"legacy private memory".len()).any(|w| w == b"legacy private memory"));
    }

    #[test]
    fn key_rotation_reencrypts_entries_and_rejects_old_key() {
        let database = TestDatabase::new();
        let old_key = [2_u8; 32];
        let new_key = [3_u8; 32];
        {
            let store = MemoryStore::open_encrypted(&database.0, &old_key).unwrap();
            store.save_approved(record("rotate-1", "rotated memory content", true)).unwrap();
            store.rotate_encryption_key(&new_key).unwrap();
        }
        assert!(matches!(MemoryStore::open_encrypted(&database.0, &old_key), Err(MemoryStoreError::EncryptionKeyInvalid)));
        let reopened = MemoryStore::open_encrypted(&database.0, &new_key).unwrap();
        assert_eq!(reopened.search("rotated memory", 5).unwrap().len(), 1);
    }

    #[test]
    fn encrypted_record_digest_uses_a_domain_separated_hmac_subkey() {
        let key = [0x5a_u8; 32];
        let value = "same memory content";
        let digest = keyed_sha256_hex(value, &key).unwrap();
        assert!(digest.starts_with(KEYED_DIGEST_PREFIX));

        let mut legacy_mac = <Hmac<Sha256> as Mac>::new_from_slice(&key).unwrap();
        legacy_mac.update(value.as_bytes());
        let legacy = legacy_mac.finalize().into_bytes().iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<Vec<_>>()
            .join("");
        assert_ne!(digest, legacy);
    }

    #[test]
    fn legacy_unprefixed_keyed_digest_is_rederived_on_open() {
        let database = TestDatabase::new();
        let key = [0x6b_u8; 32];
        let content = "memory legacy digest migration";
        let tags = vec!["Leo".to_owned(), "مشروع".to_owned()];
        let normalized = normalize_for_search(content, &tags);
        {
            let store = MemoryStore::open_encrypted(&database.0, &key).unwrap();
            store.save_approved(record("digest-migrate", content, true)).unwrap();
        }
        let mut legacy_mac = <Hmac<Sha256> as Mac>::new_from_slice(&key).unwrap();
        legacy_mac.update(normalized.as_bytes());
        let legacy_digest = legacy_mac.finalize().into_bytes().iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<Vec<_>>()
            .join("");
        let connection = Connection::open(&database.0).unwrap();
        connection.execute(
            "UPDATE memory_records SET content_sha256=?1 WHERE id='digest-migrate'",
            [legacy_digest.as_str()],
        ).unwrap();
        drop(connection);

        let reopened = MemoryStore::open_encrypted(&database.0, &key).unwrap();
        assert_eq!(reopened.search("legacy digest", 5).unwrap().len(), 1);
        let connection = Connection::open(&database.0).unwrap();
        let migrated: String = connection.query_row(
            "SELECT content_sha256 FROM memory_records WHERE id='digest-migrate'",
            [],
            |row| row.get(0),
        ).unwrap();
        assert!(migrated.starts_with(KEYED_DIGEST_PREFIX));
    }

    #[test]
    fn erase_removes_database_and_sqlite_sidecars() {
        let database = TestDatabase::new();
        let key = [4_u8; 32];
        let store = MemoryStore::open_encrypted(&database.0, &key).unwrap();
        store.save_approved(record("erase-1", "remove all of this", true)).unwrap();
        drop(store);
        assert!(MemoryStore::erase_database(&database.0).unwrap());
        assert!(!database.0.exists());
    }

}
