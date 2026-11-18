//! Persistent, app-private GGUF model library.
//!
//! Import is deliberately offline: the user selects a local file through the
//! platform file picker, Leo copies it into its private model directory,
//! inspects the GGUF header, calculates a streaming SHA-256 digest, and only
//! then commits the catalogue entry.

use crate::gguf::{inspect_gguf_file, GgufInspection};
use crate::model_catalog::{
    is_valid_model_id, sha256_file, LocalModelEntry, ModelCatalog, ModelCatalogError,
};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard};

const CATALOG_FILE: &str = "catalog.json";
const CATALOG_BACKUP_FILE: &str = ".catalog.json.backup";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelImportOptions {
    pub id: String,
    pub display_name: String,
    /// Used only when the GGUF header does not declare a context length.
    pub context_length_override: Option<u32>,
    pub supported_platforms: Vec<String>,
    pub imported_at_utc: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelImportResult {
    pub entry: LocalModelEntry,
    pub inspection: GgufInspection,
}

pub struct ModelLibrary {
    root: PathBuf,
    catalogue: Mutex<ModelCatalog>,
}

impl ModelLibrary {
    /// Opens an existing library or creates an empty one in the supplied
    /// app-private directory. A backup is restored if a previous process was
    /// interrupted while replacing the catalogue.
    pub fn open(root: impl AsRef<Path>) -> Result<Self, ModelCatalogError> {
        fs::create_dir_all(root.as_ref())
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        let root = root
            .as_ref()
            .canonicalize()
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        recover_catalogue(&root)?;

        let catalogue_path = root.join(CATALOG_FILE);
        let catalogue = if catalogue_path.exists() {
            let json = fs::read_to_string(&catalogue_path)
                .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
            ModelCatalog::from_json(&json)?
        } else {
            let catalogue = ModelCatalog::default();
            persist_catalogue(&root, &catalogue)?;
            catalogue
        };

        Ok(Self {
            root,
            catalogue: Mutex::new(catalogue),
        })
    }

    pub fn catalogue(&self) -> ModelCatalog {
        self.lock_catalogue().clone()
    }

    pub fn model_path(&self, model_id: &str) -> Result<PathBuf, ModelCatalogError> {
        self.lock_catalogue()
            .resolve_model_path(model_id, &self.root)
    }

    /// Imports one GGUF without changing the catalogue until the copied file
    /// has passed format inspection and integrity calculation.
    pub fn import_gguf(
        &self,
        source: &Path,
        options: ModelImportOptions,
    ) -> Result<ModelImportResult, ModelCatalogError> {
        if !is_valid_model_id(&options.id) {
            return Err(ModelCatalogError::InvalidId(options.id));
        }
        if options.display_name.trim().is_empty() {
            return Err(ModelCatalogError::EmptyDisplayName(options.id));
        }
        if !source
            .extension()
            .and_then(|value| value.to_str())
            .is_some_and(|extension| extension.eq_ignore_ascii_case("gguf"))
        {
            return Err(ModelCatalogError::InvalidModelFileName(
                source.display().to_string(),
            ));
        }

        let mut catalogue = self.lock_catalogue();
        if catalogue.models.iter().any(|model| model.id == options.id) {
            return Err(ModelCatalogError::ModelAlreadyExists(options.id));
        }

        let models_dir = self.root.join("models");
        fs::create_dir_all(&models_dir)
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        let canonical_models_dir = models_dir
            .canonicalize()
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        if !canonical_models_dir.starts_with(&self.root) {
            return Err(ModelCatalogError::ModelPathOutsideRoot(
                models_dir.display().to_string(),
            ));
        }

        let final_path = canonical_models_dir.join(format!("{}.gguf", options.id));
        if final_path.exists() {
            return Err(ModelCatalogError::ModelAlreadyExists(options.id));
        }

        let staging_dir = self.root.join(".staging");
        fs::create_dir_all(&staging_dir)
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        let staging_dir = staging_dir
            .canonicalize()
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        if !staging_dir.starts_with(&self.root) {
            return Err(ModelCatalogError::ModelPathOutsideRoot(
                staging_dir.display().to_string(),
            ));
        }
        let staging_path = staging_path(&staging_dir, &options.id);

        let prepared = (|| {
            fs::copy(source, &staging_path)
                .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
            File::open(&staging_path)
                .and_then(|file| file.sync_all())
                .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;

            let inspection = inspect_gguf_file(&staging_path.to_string_lossy())
                .map_err(ModelCatalogError::InvalidGguf)?;
            if inspection.size_bytes == 0 {
                return Err(ModelCatalogError::EmptyFile(options.id.clone()));
            }
            let detected_context = inspection
                .metadata
                .context_length
                .and_then(|value| u32::try_from(value).ok());
            let context_length = options
                .context_length_override
                .or(detected_context)
                .filter(|value| *value > 0)
                .ok_or_else(|| ModelCatalogError::InvalidContextLength(options.id.clone()))?;
            if detected_context.is_some_and(|detected| context_length > detected) {
                return Err(ModelCatalogError::InvalidContextLength(options.id.clone()));
            }

            let sha256 = sha256_file(&staging_path)?;
            let entry = LocalModelEntry {
                id: options.id.clone(),
                display_name: options.display_name.clone(),
                relative_path: format!("models/{}.gguf", options.id),
                format: "GGUF".to_owned(),
                file_size_bytes: inspection.size_bytes,
                sha256: Some(sha256),
                architecture: inspection.metadata.architecture.clone(),
                quantization: None,
                context_length,
                min_required_ram_bytes: None,
                supported_platforms: options.supported_platforms.clone(),
                imported_at_utc: options.imported_at_utc.clone(),
            };
            Ok((entry, inspection))
        })();

        let (entry, inspection) = match prepared {
            Ok(value) => value,
            Err(error) => {
                let _ = fs::remove_file(&staging_path);
                return Err(error);
            }
        };

        let mut next_catalogue = catalogue.clone();
        next_catalogue.models.push(entry.clone());
        if let Err(error) = next_catalogue.validate() {
            let _ = fs::remove_file(&staging_path);
            return Err(error);
        }
        // A hard link publishes only a fully copied and inspected file, and
        // fails atomically when another import already owns this model ID.
        if let Err(error) = fs::hard_link(&staging_path, &final_path) {
            let _ = fs::remove_file(&staging_path);
            return Err(ModelCatalogError::Storage(error.to_string()));
        }
        let _ = fs::remove_file(&staging_path);
        if let Err(error) = persist_catalogue(&self.root, &next_catalogue) {
            let _ = fs::remove_file(&final_path);
            return Err(error);
        }
        *catalogue = next_catalogue;

        Ok(ModelImportResult { entry, inspection })
    }

    /// Removes the catalogue record first; an orphan file is safer than a
    /// catalogue entry that points at a missing file after an interrupted
    /// deletion. The file is removed only after the manifest commit succeeds.
    pub fn remove_model(&self, model_id: &str) -> Result<bool, ModelCatalogError> {
        let mut catalogue = self.lock_catalogue();
        let Some(index) = catalogue.models.iter().position(|model| model.id == model_id) else {
            return Ok(false);
        };
        let removal_path = catalogue
            .resolve_model_path(model_id, &self.root)
            .ok();
        let mut next_catalogue = catalogue.clone();
        next_catalogue.models.remove(index);
        persist_catalogue(&self.root, &next_catalogue)?;
        *catalogue = next_catalogue;
        drop(catalogue);

        // A canonical path obtained before removing the record is safe to
        // unlink. If the model file was already missing, leave the catalogue
        // clean and report that the record itself was removed successfully.
        if let Some(path) = removal_path {
            let _ = fs::remove_file(path);
        }
        // If canonical resolution failed (for example because a symlink was
        // replaced), leave the file untouched rather than risk unlinking a
        // path outside the app-private model root.
        Ok(true)
    }

    fn lock_catalogue(&self) -> MutexGuard<'_, ModelCatalog> {
        self.catalogue
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

fn staging_path(staging_dir: &Path, model_id: &str) -> PathBuf {
    static NEXT_IMPORT: AtomicU64 = AtomicU64::new(1);
    let nonce = NEXT_IMPORT.fetch_add(1, Ordering::Relaxed);
    staging_dir.join(format!("{model_id}-{}-{nonce}.gguf", std::process::id()))
}

fn recover_catalogue(root: &Path) -> Result<(), ModelCatalogError> {
    let catalogue_path = root.join(CATALOG_FILE);
    let backup_path = root.join(CATALOG_BACKUP_FILE);
    match (catalogue_path.exists(), backup_path.exists()) {
        (false, true) => fs::rename(backup_path, catalogue_path)
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?,
        (true, true) => fs::remove_file(backup_path)
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?,
        _ => {}
    }
    Ok(())
}

fn persist_catalogue(root: &Path, catalogue: &ModelCatalog) -> Result<(), ModelCatalogError> {
    let json = catalogue.to_json_pretty()?;
    static NEXT_WRITE: AtomicU64 = AtomicU64::new(1);
    let nonce = NEXT_WRITE.fetch_add(1, Ordering::Relaxed);
    let temporary_path = root.join(format!(
        ".catalog.json.tmp-{}-{nonce}",
        std::process::id()
    ));
    let catalogue_path = root.join(CATALOG_FILE);
    let backup_path = root.join(CATALOG_BACKUP_FILE);

    let write_result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary_path)
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        file.write_all(json.as_bytes())
            .and_then(|_| file.sync_all())
            .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        drop(file);

        if catalogue_path.exists() {
            if backup_path.exists() {
                fs::remove_file(&backup_path)
                    .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
            }
            fs::rename(&catalogue_path, &backup_path)
                .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
            if let Err(error) = fs::rename(&temporary_path, &catalogue_path) {
                let _ = fs::rename(&backup_path, &catalogue_path);
                return Err(ModelCatalogError::Storage(error.to_string()));
            }
            // The new manifest is committed. A stale backup is recoverable
            // cleanup metadata, not a reason to roll back the import.
            let _ = fs::remove_file(&backup_path);
        } else {
            fs::rename(&temporary_path, &catalogue_path)
                .map_err(|error| ModelCatalogError::Storage(error.to_string()))?;
        }
        if let Ok(directory) = File::open(root) {
            let _ = directory.sync_all();
        }
        Ok(())
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&temporary_path);
    }
    write_result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temporary_directory() -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("leo-model-library-{stamp}"));
        fs::create_dir_all(&path).unwrap();
        path
    }

    fn push_u32(target: &mut Vec<u8>, value: u32) {
        target.extend_from_slice(&value.to_le_bytes());
    }

    fn push_u64(target: &mut Vec<u8>, value: u64) {
        target.extend_from_slice(&value.to_le_bytes());
    }

    fn push_string(target: &mut Vec<u8>, value: &str) {
        push_u64(target, value.len() as u64);
        target.extend_from_slice(value.as_bytes());
    }

    fn tiny_gguf() -> Vec<u8> {
        let mut bytes = b"GGUF".to_vec();
        push_u32(&mut bytes, 3);
        push_u64(&mut bytes, 1); // tensor count
        push_u64(&mut bytes, 2); // metadata count
        push_string(&mut bytes, "general.architecture");
        push_u32(&mut bytes, 8); // string value
        push_string(&mut bytes, "llama");
        push_string(&mut bytes, "llama.context_length");
        push_u32(&mut bytes, 4); // uint32 value
        push_u32(&mut bytes, 2048);
        bytes
    }

    fn import_options() -> ModelImportOptions {
        ModelImportOptions {
            id: "test-model".to_owned(),
            display_name: "Test GGUF".to_owned(),
            context_length_override: None,
            supported_platforms: vec!["android-arm64".to_owned()],
            imported_at_utc: "2026-11-15T00:00:00Z".to_owned(),
        }
    }

    #[test]
    fn imports_valid_gguf_and_persists_integrity_metadata() {
        let root = temporary_directory();
        let source = root.join("selected.gguf");
        fs::write(&source, tiny_gguf()).unwrap();
        let library_root = root.join("leo-library");
        let library = ModelLibrary::open(&library_root).unwrap();

        let result = library.import_gguf(&source, import_options()).unwrap();
        assert_eq!(result.entry.architecture.as_deref(), Some("llama"));
        assert_eq!(result.entry.context_length, 2048);
        assert!(result.entry.sha256.as_ref().is_some_and(|value| value.len() == 64));
        let stored_path = library.model_path("test-model").unwrap();
        assert_eq!(fs::read(source).unwrap(), fs::read(stored_path).unwrap());

        let reopened = ModelLibrary::open(&library_root).unwrap();
        assert_eq!(reopened.catalogue().models.len(), 1);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_invalid_gguf_without_creating_a_catalogue_entry_or_model_file() {
        let root = temporary_directory();
        let source = root.join("broken.gguf");
        fs::write(&source, b"not a gguf file").unwrap();
        let library_root = root.join("leo-library");
        let library = ModelLibrary::open(&library_root).unwrap();
        assert!(matches!(
            library.import_gguf(&source, import_options()),
            Err(ModelCatalogError::InvalidGguf(_))
        ));
        assert!(library.catalogue().models.is_empty());
        assert!(!library_root.join("models/test-model.gguf").exists());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn duplicate_model_ids_are_rejected() {
        let root = temporary_directory();
        let source = root.join("selected.gguf");
        fs::write(&source, tiny_gguf()).unwrap();
        let library = ModelLibrary::open(root.join("leo-library")).unwrap();
        library.import_gguf(&source, import_options()).unwrap();
        assert!(matches!(
            library.import_gguf(&source, import_options()),
            Err(ModelCatalogError::ModelAlreadyExists(_))
        ));
        fs::remove_dir_all(root).unwrap();
    }
}
