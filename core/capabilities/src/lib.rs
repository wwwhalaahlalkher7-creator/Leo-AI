//! Capability discovery, least-privilege provider selection, and a persistent
//! just-in-time permission broker. Native adapters must re-check operating
//! system state immediately before each sensitive operation.

use leo_shared::{CapabilitySource, PermissionGrant, RiskLevel};
use rusqlite::{params, Connection, OptionalExtension};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

const SCHEMA_VERSION: i64 = 1;
const MAX_ID_LENGTH: usize = 96;
const MAX_SCOPE_LENGTH: usize = 512;
const MAX_TIMESTAMP_LENGTH: usize = 40;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PermissionGateDecision {
    RequestFirstUse,
    Allowed,
    PreviouslyDenied,
    ExpiredGrant,
    OperatingSystemPermissionRequired,
    RevokedByOperatingSystem,
    ScopeUpgradeRequired,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CapabilityStoreError {
    RelativeDatabasePath,
    InvalidId,
    InvalidScope,
    InvalidTimestamp,
    InvalidLimit,
    UnsupportedSchema(i64),
    NotFound,
    Storage(String),
}

impl fmt::Display for CapabilityStoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::RelativeDatabasePath => {
                write!(f, "permission database path must be absolute and app-private")
            }
            Self::InvalidId => write!(f, "capability or grant identifier is invalid"),
            Self::InvalidScope => write!(f, "permission scope is invalid"),
            Self::InvalidTimestamp => {
                write!(f, "timestamp must be an RFC3339 UTC value ending in Z")
            }
            Self::InvalidLimit => write!(f, "permission list limit is outside the allowed range"),
            Self::UnsupportedSchema(version) => write!(
                f,
                "permission database schema {version} is newer than this Leo build"
            ),
            Self::NotFound => write!(f, "permission grant was not found"),
            Self::Storage(message) => write!(f, "permission storage error: {message}"),
        }
    }
}

impl std::error::Error for CapabilityStoreError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PermissionRecord {
    pub grant: PermissionGrant,
    pub updated_at_utc: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityDefinition {
    pub id: &'static str,
    pub display_name: &'static str,
    pub description: &'static str,
    pub platforms: &'static [&'static str],
    pub provider_order: &'static [&'static str],
    pub grant_scope: &'static str,
    pub risk: RiskLevel,
    pub available_offline: bool,
    pub supported_in_alpha: bool,
}

impl CapabilityDefinition {
    pub fn supports_platform(&self, platform: &str) -> bool {
        self.platforms
            .iter()
            .any(|candidate| *candidate == platform)
    }
}

/// Built-in capability metadata. The OS/app connector is selected at runtime;
/// no provider is assumed to exist merely because the capability is listed.
pub fn built_in_capabilities() -> Vec<CapabilityDefinition> {
    use RiskLevel::{Critical, High, Low, Moderate, ReadOnly};

    vec![
        CapabilityDefinition {
            id: "files.read",
            display_name: "Read selected files",
            description: "Read a file explicitly selected by the user through the system picker.",
            platforms: &["android", "windows"],
            provider_order: &[
                "platform_file_picker",
                "installed_app_api",
                "mcp_connector",
                "leo_adapter",
            ],
            grant_scope: "selected_files",
            risk: ReadOnly,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "files.open_selected",
            display_name: "Open selected file",
            description: "Open a file explicitly selected by the user in its registered document viewer; executable and script-like file types are blocked.",
            platforms: &["android", "windows"],
            provider_order: &["operating_system_file_handler"],
            grant_scope: "selected_file_open",
            risk: Moderate,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "calendar.create_event",
            display_name: "Create calendar event draft",
            description: "Hand a validated event draft to the user's calendar app; the user must save it there.",
            platforms: &["android", "windows"],
            provider_order: &["operating_system_calendar_intent", "registered_ics_handler"],
            grant_scope: "calendar_event_draft",
            risk: High,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "clipboard.write",
            display_name: "Copy text to system clipboard",
            description: "Replace the current system clipboard with user-reviewed text after separate per-copy approval.",
            platforms: &["android", "windows"],
            provider_order: &["operating_system_clipboard_api"],
            grant_scope: "system_clipboard_write",
            risk: Moderate,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "files.write",
            display_name: "Write selected files",
            description: "Create or replace one UTF-8 text file directly inside a folder selected by the user, after a before/after diff and explicit per-write approval.",
            platforms: &["android", "windows"],
            provider_order: &["workspace_folder_picker", "leo_adapter"],
            grant_scope: "selected_workspace",
            risk: High,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "device.app_launch",
            display_name: "Open an installed application",
            description: "Open an application selected by the user or requested in the task.",
            platforms: &["android", "windows"],
            provider_order: &["operating_system", "installed_application"],
            grant_scope: "selected_application",
            risk: Low,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "device.open_url",
            display_name: "Open a web link",
            description: "Open an HTTP or HTTPS link in the user's registered browser. Mail and telephone handoffs use their own capabilities.",
            platforms: &["android", "windows"],
            provider_order: &["operating_system", "installed_application"],
            grant_scope: "link_handoff",
            risk: Moderate,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "phone.dial",
            display_name: "Open the dialer",
            description: "Prepare a phone number in the system dialer; the user confirms the call there.",
            platforms: &["android", "windows"],
            provider_order: &["operating_system_dialer"],
            grant_scope: "dialer_handoff",
            risk: Moderate,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "phone.call_direct",
            display_name: "Place a direct phone call",
            description: "Place a call directly after OS permission and per-call confirmation.",
            platforms: &["android"],
            provider_order: &["android_telephony_api"],
            grant_scope: "call_phone_permission",
            risk: Critical,
            available_offline: true,
            supported_in_alpha: false,
        },
        CapabilityDefinition {
            id: "email.compose",
            display_name: "Compose an email",
            description: "Prepare an email in the user's installed mail application.",
            platforms: &["android", "windows"],
            provider_order: &["installed_mail_app", "mcp_connector", "app_api"],
            grant_scope: "mail_app_handoff",
            risk: High,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "messages.compose",
            display_name: "Compose a message",
            description: "Prepare an SMS or message in an installed messaging application.",
            platforms: &["android"],
            provider_order: &["installed_messaging_app"],
            grant_scope: "messaging_app_handoff",
            risk: High,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "contacts.read",
            display_name: "Read contacts",
            description: "Read contacts only after Leo consent and the Android contacts permission.",
            platforms: &["android"],
            provider_order: &["android_contacts_provider"],
            grant_scope: "contacts_read",
            risk: Moderate,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "audio.microphone",
            display_name: "Use the microphone",
            description: "Capture microphone audio while a visible recording or voice session is active.",
            platforms: &["android", "windows"],
            provider_order: &["operating_system_audio_api"],
            grant_scope: "microphone_access",
            risk: Moderate,
            available_offline: true,
            supported_in_alpha: true,
        },
        CapabilityDefinition {
            id: "process.run",
            display_name: "Run a local process",
            description: "Run a restricted allowlisted command inside an approved workspace.",
            platforms: &["windows"],
            provider_order: &["installed_cli", "native_process_api"],
            grant_scope: "workspace_and_command_policy",
            risk: High,
            available_offline: true,
            supported_in_alpha: false,
        },
        CapabilityDefinition {
            id: "system.admin_operation",
            display_name: "Perform an administrator operation",
            description: "Perform one narrowly scoped operation through a separately reviewed elevated helper.",
            platforms: &["windows"],
            provider_order: &["narrow_elevated_helper"],
            grant_scope: "one_operation_uac",
            risk: Critical,
            available_offline: true,
            supported_in_alpha: false,
        },
        CapabilityDefinition {
            id: "app.ui_automation",
            display_name: "Control an application interface",
            description: "Use official APIs first; UI automation is a restricted fallback.",
            platforms: &["android", "windows"],
            provider_order: &[
                "official_app_api",
                "mcp_connector",
                "ui_automation_fallback",
            ],
            grant_scope: "per_application",
            risk: High,
            available_offline: true,
            supported_in_alpha: false,
        },
        CapabilityDefinition {
            id: "peer.task_receive",
            display_name: "Receive a task from a paired device",
            description: "Receive a task from a paired Leo device after reviewing that task.",
            platforms: &["android", "windows"],
            provider_order: &["paired_local_peer"],
            grant_scope: "paired_device",
            risk: High,
            available_offline: true,
            supported_in_alpha: false,
        },
    ]
}

/// Checks Leo's stored consent independently from the current operating-system
/// grant. A persisted Leo decision can never override OS revocation.
pub fn check_permission(
    grant: Option<&PermissionGrant>,
    requested_scope: &str,
    operating_system_granted: bool,
    now_utc: &str,
) -> Result<PermissionGateDecision, CapabilityStoreError> {
    validate_scope(requested_scope)?;
    validate_timestamp(now_utc)?;

    let Some(grant) = grant else {
        return Ok(PermissionGateDecision::RequestFirstUse);
    };
    if grant.scope != requested_scope {
        return Ok(PermissionGateDecision::ScopeUpgradeRequired);
    }
    if !grant.granted {
        return Ok(PermissionGateDecision::PreviouslyDenied);
    }
    if let Some(expiry) = grant.expires_at_utc.as_deref() {
        validate_timestamp(expiry)?;
        if timestamp_key(expiry)? <= timestamp_key(now_utc)? {
            return Ok(PermissionGateDecision::ExpiredGrant);
        }
    }
    if !operating_system_granted {
        return Ok(PermissionGateDecision::RevokedByOperatingSystem);
    }
    Ok(PermissionGateDecision::Allowed)
}

/// Determines whether the user must confirm this particular action. Permission
/// grants are not blanket consent to send, delete, overwrite or execute.
pub fn action_requires_confirmation(
    risk: RiskLevel,
    external_effect: bool,
    destructive: bool,
) -> bool {
    matches!(risk, RiskLevel::High | RiskLevel::Critical)
        || destructive
        || (external_effect && risk == RiskLevel::Moderate)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityProvider {
    pub id: String,
    pub source: CapabilitySource,
    pub available: bool,
}

/// OS APIs and official app APIs win. UI automation remains a last resort.
pub fn select_provider(providers: &[CapabilityProvider]) -> Option<&CapabilityProvider> {
    providers
        .iter()
        .filter(|provider| provider.available)
        .min_by_key(|provider| source_priority(provider.source))
}

fn source_priority(source: CapabilitySource) -> u8 {
    match source {
        CapabilitySource::OperatingSystem => 0,
        CapabilitySource::InstalledApplication => 1,
        CapabilitySource::LocalCommand => 2,
        CapabilitySource::McpConnector => 3,
        CapabilitySource::LeoNativeAdapter => 4,
        CapabilitySource::UiAutomationFallback => 5,
    }
}

pub struct CapabilityStore {
    database_path: PathBuf,
    connection: Connection,
}

impl CapabilityStore {
    pub fn open(database_path: impl AsRef<Path>) -> Result<Self, CapabilityStoreError> {
        let database_path = database_path.as_ref();
        if !database_path.is_absolute() {
            return Err(CapabilityStoreError::RelativeDatabasePath);
        }
        if let Some(parent) = database_path
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
        {
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
                 PRAGMA synchronous = NORMAL;
                 PRAGMA secure_delete = ON;
                 PRAGMA trusted_schema = OFF;",
            )
            .map_err(storage_error)?;
        migrate(&connection)?;

        Ok(Self {
            database_path: database_path.to_path_buf(),
            connection,
        })
    }

    pub fn database_path(&self) -> &Path {
        &self.database_path
    }

    pub fn record_decision(
        &self,
        grant_id: &str,
        capability_id: &str,
        scope: &str,
        granted: bool,
        granted_at_utc: &str,
        expires_at_utc: Option<&str>,
    ) -> Result<PermissionRecord, CapabilityStoreError> {
        validate_id(grant_id)?;
        validate_id(capability_id)?;
        validate_scope(scope)?;
        validate_timestamp(granted_at_utc)?;
        if let Some(expiry) = expires_at_utc {
            validate_timestamp(expiry)?;
        }

        self.connection
            .execute(
                "INSERT INTO permission_decisions (
                    id, capability_id, scope, granted, granted_at_utc,
                    expires_at_utc, updated_at_utc
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?5)
                 ON CONFLICT(capability_id, scope) DO UPDATE SET
                    id = excluded.id,
                    granted = excluded.granted,
                    granted_at_utc = excluded.granted_at_utc,
                    expires_at_utc = excluded.expires_at_utc,
                    updated_at_utc = excluded.updated_at_utc",
                params![
                    grant_id,
                    capability_id,
                    scope,
                    bool_to_i64(granted),
                    granted_at_utc,
                    expires_at_utc
                ],
            )
            .map_err(storage_error)?;

        self.get(capability_id, scope)?
            .ok_or(CapabilityStoreError::NotFound)
    }

    pub fn get(
        &self,
        capability_id: &str,
        scope: &str,
    ) -> Result<Option<PermissionRecord>, CapabilityStoreError> {
        validate_id(capability_id)?;
        validate_scope(scope)?;
        self.connection
            .query_row(
                "SELECT id, capability_id, scope, granted, granted_at_utc,
                        expires_at_utc, updated_at_utc
                 FROM permission_decisions
                 WHERE capability_id = ?1 AND scope = ?2",
                params![capability_id, scope],
                row_to_record,
            )
            .optional()
            .map_err(storage_error)
    }

    pub fn check(
        &self,
        capability_id: &str,
        scope: &str,
        operating_system_granted: bool,
        now_utc: &str,
    ) -> Result<PermissionGateDecision, CapabilityStoreError> {
        validate_id(capability_id)?;
        let grant = self.get(capability_id, scope)?;
        if grant.is_none() && self.has_other_scope(capability_id, scope)? {
            return Ok(PermissionGateDecision::ScopeUpgradeRequired);
        }
        check_permission(
            grant.as_ref().map(|record| &record.grant),
            scope,
            operating_system_granted,
            now_utc,
        )
    }

    pub fn revoke(
        &self,
        capability_id: &str,
        scope: &str,
        revoked_at_utc: &str,
    ) -> Result<bool, CapabilityStoreError> {
        validate_id(capability_id)?;
        validate_scope(scope)?;
        validate_timestamp(revoked_at_utc)?;

        let changed = self
            .connection
            .execute(
                "UPDATE permission_decisions
                 SET granted = 0, updated_at_utc = ?3
                 WHERE capability_id = ?1 AND scope = ?2",
                params![capability_id, scope, revoked_at_utc],
            )
            .map_err(storage_error)?;
        Ok(changed == 1)
    }

    pub fn list(&self, limit: usize) -> Result<Vec<PermissionRecord>, CapabilityStoreError> {
        if limit == 0 || limit > 500 {
            return Err(CapabilityStoreError::InvalidLimit);
        }
        let mut statement = self
            .connection
            .prepare(
                "SELECT id, capability_id, scope, granted, granted_at_utc,
                        expires_at_utc, updated_at_utc
                 FROM permission_decisions
                 ORDER BY updated_at_utc DESC, capability_id ASC
                 LIMIT ?1",
            )
            .map_err(storage_error)?;
        let rows = statement
            .query_map([limit as i64], row_to_record)
            .map_err(storage_error)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(storage_error)
    }

    fn has_other_scope(
        &self,
        capability_id: &str,
        scope: &str,
    ) -> Result<bool, CapabilityStoreError> {
        self.connection
            .query_row(
                "SELECT EXISTS(
                    SELECT 1 FROM permission_decisions
                    WHERE capability_id = ?1 AND scope <> ?2
                 )",
                params![capability_id, scope],
                |row| row.get::<_, i64>(0),
            )
            .map(|value| value == 1)
            .map_err(storage_error)
    }
}

fn migrate(connection: &Connection) -> Result<(), CapabilityStoreError> {
    let version: i64 = connection
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .map_err(storage_error)?;
    if version > SCHEMA_VERSION {
        return Err(CapabilityStoreError::UnsupportedSchema(version));
    }
    if version == 0 {
        connection
            .execute_batch(
                "BEGIN IMMEDIATE;
                 CREATE TABLE permission_decisions (
                    id TEXT NOT NULL PRIMARY KEY,
                    capability_id TEXT NOT NULL,
                    scope TEXT NOT NULL,
                    granted INTEGER NOT NULL CHECK (granted IN (0, 1)),
                    granted_at_utc TEXT NOT NULL,
                    expires_at_utc TEXT,
                    updated_at_utc TEXT NOT NULL,
                    UNIQUE(capability_id, scope)
                 );
                 CREATE INDEX idx_permission_capability
                    ON permission_decisions(capability_id, granted);
                 PRAGMA user_version = 1;
                 COMMIT;",
            )
            .map_err(storage_error)?;
    }
    Ok(())
}

fn row_to_record(row: &rusqlite::Row<'_>) -> rusqlite::Result<PermissionRecord> {
    let granted: i64 = row.get(3)?;
    Ok(PermissionRecord {
        grant: PermissionGrant {
            id: row.get(0)?,
            capability_id: row.get(1)?,
            scope: row.get(2)?,
            granted: granted == 1,
            granted_at_utc: row.get(4)?,
            expires_at_utc: row.get(5)?,
        },
        updated_at_utc: row.get(6)?,
    })
}

fn validate_id(value: &str) -> Result<(), CapabilityStoreError> {
    if value.is_empty()
        || value.len() > MAX_ID_LENGTH
        || !value
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
    {
        return Err(CapabilityStoreError::InvalidId);
    }
    Ok(())
}

fn validate_scope(value: &str) -> Result<(), CapabilityStoreError> {
    let trimmed = value.trim();
    if trimmed.is_empty()
        || trimmed.len() > MAX_SCOPE_LENGTH
        || trimmed.chars().any(char::is_control)
    {
        return Err(CapabilityStoreError::InvalidScope);
    }
    Ok(())
}

fn validate_timestamp(value: &str) -> Result<(), CapabilityStoreError> {
    let bytes = value.as_bytes();
    let fixed_shape = bytes.len() >= 20
        && bytes.len() <= MAX_TIMESTAMP_LENGTH
        && bytes.get(4) == Some(&b'-')
        && bytes.get(7) == Some(&b'-')
        && bytes.get(10) == Some(&b'T')
        && bytes.get(13) == Some(&b':')
        && bytes.get(16) == Some(&b':')
        && bytes.last() == Some(&b'Z');
    if !fixed_shape {
        return Err(CapabilityStoreError::InvalidTimestamp);
    }

    let is_digit = |index: usize| bytes.get(index).is_some_and(u8::is_ascii_digit);
    for index in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18] {
        if !is_digit(index) {
            return Err(CapabilityStoreError::InvalidTimestamp);
        }
    }

    let number = |start: usize, end: usize| -> u32 {
        value[start..end].parse::<u32>().unwrap_or(u32::MAX)
    };
    let year = number(0, 4);
    let month = number(5, 7);
    let day = number(8, 10);
    let hour = number(11, 13);
    let minute = number(14, 16);
    let second = number(17, 19);
    let leap_year = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days_in_month = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap_year => 29,
        2 => 28,
        _ => 0,
    };
    if year == 0
        || day == 0
        || day > days_in_month
        || hour > 23
        || minute > 59
        || second > 60
    {
        return Err(CapabilityStoreError::InvalidTimestamp);
    }

    if bytes.len() > 20 {
        if bytes.get(19) != Some(&b'.') || bytes.len() < 22 {
            return Err(CapabilityStoreError::InvalidTimestamp);
        }
        let fractional = &bytes[20..bytes.len() - 1];
        if fractional.is_empty()
            || fractional.len() > 9
            || !fractional.iter().all(u8::is_ascii_digit)
        {
            return Err(CapabilityStoreError::InvalidTimestamp);
        }
    }
    Ok(())
}

fn timestamp_key(value: &str) -> Result<(u32, u32, u32, u32, u32, u32, u32), CapabilityStoreError> {
    validate_timestamp(value)?;
    let number = |start: usize, end: usize| -> u32 {
        value[start..end].parse::<u32>().unwrap_or_default()
    };
    let mut fractional = if value.len() > 20 {
        value[20..value.len() - 1].to_owned()
    } else {
        String::new()
    };
    while fractional.len() < 9 {
        fractional.push('0');
    }
    let nanos = if fractional.is_empty() {
        0
    } else {
        fractional.parse::<u32>().unwrap_or_default()
    };
    Ok((
        number(0, 4),
        number(5, 7),
        number(8, 10),
        number(11, 13),
        number(14, 16),
        number(17, 19),
        nanos,
    ))
}

fn bool_to_i64(value: bool) -> i64 {
    if value { 1 } else { 0 }
}

fn storage_error(error: impl fmt::Display) -> CapabilityStoreError {
    CapabilityStoreError::Storage(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_db() -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("leo-capabilities-{nonce}.sqlite3"))
    }

    fn grant(scope: &str, granted: bool) -> PermissionGrant {
        PermissionGrant {
            id: "permission-1".into(),
            capability_id: "files.read".into(),
            scope: scope.into(),
            granted_at_utc: "2026-11-15T00:00:00Z".into(),
            expires_at_utc: None,
            granted,
        }
    }

    #[test]
    fn first_use_requests_consent_only_when_capability_is_used() {
        assert_eq!(
            check_permission(None, "selected-folder", false, "2026-11-15T00:00:00Z").unwrap(),
            PermissionGateDecision::RequestFirstUse
        );
    }

    #[test]
    fn a_user_can_explicitly_regrant_after_a_previous_denial() {
        let denied = grant("selected-folder", false);
        assert_eq!(
            check_permission(Some(&denied), "selected-folder", true, "2026-11-16T00:00:00Z").unwrap(),
            PermissionGateDecision::PreviouslyDenied
        );
        let regranted = grant("selected-folder", true);
        assert_eq!(
            check_permission(Some(&regranted), "selected-folder", true, "2026-11-16T00:00:00Z").unwrap(),
            PermissionGateDecision::Allowed
        );
    }

    #[test]
    fn fractional_expiry_comparison_normalizes_precision() {
        let grant = PermissionGrant {
            expires_at_utc: Some("2026-11-15T00:00:00Z".into()),
            ..grant("selected-folder", true)
        };
        assert_eq!(
            check_permission(
                Some(&grant),
                "selected-folder",
                true,
                "2026-11-15T00:00:00.001Z",
            )
            .unwrap(),
            PermissionGateDecision::ExpiredGrant
        );
        assert_eq!(
            check_permission(
                Some(&grant),
                "selected-folder",
                true,
                "2026-11-14T23:59:59.999Z",
            )
            .unwrap(),
            PermissionGateDecision::Allowed
        );
    }

    #[test]
    fn a_saved_grant_never_overrides_os_revocation() {
        assert_eq!(
            check_permission(
                Some(&grant("selected-folder", true)),
                "selected-folder",
                false,
                "2026-11-15T00:00:00Z",
            )
            .unwrap(),
            PermissionGateDecision::RevokedByOperatingSystem
        );
    }

    #[test]
    fn different_scope_requires_explicit_upgrade() {
        assert_eq!(
            check_permission(
                Some(&grant("one-folder", true)),
                "another-folder",
                true,
                "2026-11-15T00:00:00Z",
            )
            .unwrap(),
            PermissionGateDecision::ScopeUpgradeRequired
        );
    }

    #[test]
    fn denied_permissions_remain_denied_until_user_changes_decision() {
        assert_eq!(
            check_permission(
                Some(&grant("selected-folder", false)),
                "selected-folder",
                true,
                "2026-11-15T00:00:00Z",
            )
            .unwrap(),
            PermissionGateDecision::PreviouslyDenied
        );
    }

    #[test]
    fn expired_permissions_are_not_allowed() {
        let mut record = grant("selected-folder", true);
        record.expires_at_utc = Some("2026-11-15T00:00:00Z".into());
        assert_eq!(
            check_permission(
                Some(&record),
                "selected-folder",
                true,
                "2026-11-16T00:00:00Z",
            )
            .unwrap(),
            PermissionGateDecision::ExpiredGrant
        );
    }

    #[test]
    fn high_risk_and_external_side_effects_need_action_confirmation() {
        assert!(action_requires_confirmation(RiskLevel::Low, false, true));
        assert!(action_requires_confirmation(RiskLevel::Moderate, true, false));
        assert!(action_requires_confirmation(RiskLevel::Critical, false, false));
        assert!(!action_requires_confirmation(RiskLevel::Low, false, false));
    }

    #[test]
    fn provider_selection_prefers_native_os_and_official_app_integrations() {
        let providers = vec![
            CapabilityProvider {
                id: "ui".into(),
                source: CapabilitySource::UiAutomationFallback,
                available: true,
            },
            CapabilityProvider {
                id: "mcp".into(),
                source: CapabilitySource::McpConnector,
                available: true,
            },
            CapabilityProvider {
                id: "app".into(),
                source: CapabilitySource::InstalledApplication,
                available: true,
            },
            CapabilityProvider {
                id: "os".into(),
                source: CapabilitySource::OperatingSystem,
                available: true,
            },
        ];
        assert_eq!(
            select_provider(&providers).map(|provider| provider.id.as_str()),
            Some("os")
        );
    }

    #[test]
    fn registry_is_cross_platform_but_marks_unsupported_actions_as_not_yet_ready() {
        let entries = built_in_capabilities();
        assert!(entries
            .iter()
            .any(|entry| entry.id == "files.read" && entry.supported_in_alpha));
        assert!(entries
            .iter()
            .any(|entry| entry.id == "app.ui_automation" && !entry.supported_in_alpha));
        assert!(!entries
            .iter()
            .find(|entry| entry.id == "phone.call_direct")
            .unwrap()
            .supports_platform("windows"));
    }

    #[test]
    fn permission_store_persists_grants_denials_and_revocations() {
        let path = temp_db();
        {
            let store = CapabilityStore::open(&path).unwrap();
            let saved = store
                .record_decision(
                    "grant-files",
                    "files.read",
                    "folder:/selected",
                    true,
                    "2026-11-15T00:00:00Z",
                    None,
                )
                .unwrap();
            assert!(saved.grant.granted);
            assert_eq!(
                store
                    .check(
                        "files.read",
                        "folder:/selected",
                        true,
                        "2026-11-15T00:01:00Z"
                    )
                    .unwrap(),
                PermissionGateDecision::Allowed
            );
            assert_eq!(
                store
                    .check(
                        "files.read",
                        "folder:/other",
                        true,
                        "2026-11-15T00:01:00Z"
                    )
                    .unwrap(),
                PermissionGateDecision::ScopeUpgradeRequired
            );
            store
                .record_decision(
                    "grant-email",
                    "email.compose",
                    "mail_app_handoff",
                    false,
                    "2026-11-15T00:02:00Z",
                    None,
                )
                .unwrap();
            assert_eq!(
                store
                    .check(
                        "email.compose",
                        "mail_app_handoff",
                        true,
                        "2026-11-15T00:03:00Z"
                    )
                    .unwrap(),
                PermissionGateDecision::PreviouslyDenied
            );
            assert!(store
                .revoke(
                    "files.read",
                    "folder:/selected",
                    "2026-11-15T00:04:00Z"
                )
                .unwrap());
            assert_eq!(
                store
                    .check(
                        "files.read",
                        "folder:/selected",
                        true,
                        "2026-11-15T00:05:00Z"
                    )
                    .unwrap(),
                PermissionGateDecision::PreviouslyDenied
            );
            assert_eq!(store.list(10).unwrap().len(), 2);
        }
        let _ = fs::remove_file(path);
    }

    #[test]
    fn malformed_timestamps_are_rejected() {
        assert_eq!(
            validate_timestamp("not-a-dateT00:00:00Z"),
            Err(CapabilityStoreError::InvalidTimestamp)
        );
        assert_eq!(
            validate_timestamp("2026-13-50T28:80:80Z"),
            Err(CapabilityStoreError::InvalidTimestamp)
        );
    }

    #[test]
    fn relative_database_paths_are_rejected() {
        assert_eq!(
            CapabilityStore::open("relative/permissions.sqlite3").err(),
            Some(CapabilityStoreError::RelativeDatabasePath)
        );
    }
}
