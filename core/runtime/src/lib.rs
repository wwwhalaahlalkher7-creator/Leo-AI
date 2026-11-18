//! Runtime abstraction and concrete local llama.cpp adapter boundaries.

pub mod gguf;
pub mod model_catalog;
pub mod model_library;
pub mod native;
mod local_llama_runtime;

pub use local_llama_runtime::LocalLlamaRuntime;
pub use model_library::{ModelImportOptions, ModelImportResult, ModelLibrary};
pub use model_catalog::{
    DeviceResources, LocalModelEntry, ModelCatalog, ModelCatalogError, ModelFit,
    sha256_file, verify_file_integrity, verify_file_size,
    MODEL_CATALOG_SCHEMA_VERSION,
};

use leo_shared::{
    AssistantRequest, ExecutionResult, RuntimeCapabilities, RuntimeDescriptor, RuntimeEvent,
};
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeError {
    pub code: String,
    pub message: String,
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for RuntimeError {}

/// Runtime candidate information used by the platform-neutral selector.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeCandidate {
    pub descriptor: RuntimeDescriptor,
    pub capabilities: RuntimeCapabilities,
    pub model_loaded: bool,
}

/// Selects a usable local runtime first. Remote runtimes are considered only
/// when the caller explicitly permits them; offline-only requests never fall
/// through to a network provider.
pub fn select_runtime(candidates: &[RuntimeCandidate], allow_remote: bool) -> Option<usize> {
    candidates
        .iter()
        .enumerate()
        .filter(|(_, candidate)| {
            matches!(
                candidate.descriptor.state,
                leo_shared::RuntimeState::Ready
            ) && candidate.model_loaded
        })
        .filter(|(_, candidate)| {
            allow_remote || candidate.capabilities.offline_inference
        })
        .min_by_key(|(_, candidate)| match candidate.descriptor.kind {
            leo_shared::RuntimeKind::LocalLlama => 0,
            leo_shared::RuntimeKind::Mock => 1,
            leo_shared::RuntimeKind::RemoteOptional => 2,
        })
        .map(|(index, _)| index)
}

/// A pluggable inference engine. UI and orchestration code must depend on this
/// interface rather than directly on llama.cpp, Hermes, or a platform bridge.
/// Shared references allow a separate worker to request cancellation while
/// generation is running on another thread.
pub trait AssistantRuntime: Send + Sync {
    fn descriptor(&self) -> RuntimeDescriptor;
    fn capabilities(&self) -> RuntimeCapabilities;

    fn generate(
        &self,
        request: &AssistantRequest,
        emit: &mut dyn FnMut(RuntimeEvent),
    ) -> Result<ExecutionResult, RuntimeError>;

    fn cancel(&self, request_id: &str) -> Result<bool, RuntimeError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_error_formats_for_logs() {
        let error = RuntimeError {
            code: "model_unavailable".to_owned(),
            message: "No local model is loaded".to_owned(),
        };
        assert_eq!(error.to_string(), "model_unavailable: No local model is loaded");
    }

    #[test]
    fn local_runtime_is_preferred_when_multiple_candidates_are_ready() {
        let candidates = vec![
            RuntimeCandidate {
                descriptor: RuntimeDescriptor {
                    id: "remote".into(),
                    display_name: "Remote".into(),
                    kind: leo_shared::RuntimeKind::RemoteOptional,
                    platform: "any".into(),
                    state: leo_shared::RuntimeState::Ready,
                },
                capabilities: RuntimeCapabilities {
                    offline_inference: false,
                    streaming: true,
                    cancellation: true,
                    vision: false,
                    audio_input: false,
                    audio_output: false,
                },
                model_loaded: true,
            },
            RuntimeCandidate {
                descriptor: RuntimeDescriptor {
                    id: "local".into(),
                    display_name: "Local GGUF".into(),
                    kind: leo_shared::RuntimeKind::LocalLlama,
                    platform: "android".into(),
                    state: leo_shared::RuntimeState::Ready,
                },
                capabilities: RuntimeCapabilities {
                    offline_inference: true,
                    streaming: true,
                    cancellation: true,
                    vision: false,
                    audio_input: false,
                    audio_output: false,
                },
                model_loaded: true,
            },
        ];
        assert_eq!(select_runtime(&candidates, true), Some(1));
        assert_eq!(select_runtime(&candidates, false), Some(1));
    }

    #[test]
    fn offline_only_request_never_selects_remote_runtime() {
        let candidate = RuntimeCandidate {
            descriptor: RuntimeDescriptor {
                id: "remote".into(),
                display_name: "Remote".into(),
                kind: leo_shared::RuntimeKind::RemoteOptional,
                platform: "any".into(),
                state: leo_shared::RuntimeState::Ready,
            },
            capabilities: RuntimeCapabilities {
                offline_inference: false,
                streaming: true,
                cancellation: true,
                vision: false,
                audio_input: false,
                audio_output: false,
            },
            model_loaded: true,
        };
        assert_eq!(select_runtime(&[candidate], false), None);
    }

    #[test]
    fn unavailable_or_unloaded_runtimes_are_ignored() {
        let candidate = RuntimeCandidate {
            descriptor: RuntimeDescriptor {
                id: "local".into(),
                display_name: "Local".into(),
                kind: leo_shared::RuntimeKind::LocalLlama,
                platform: "windows".into(),
                state: leo_shared::RuntimeState::Unavailable,
            },
            capabilities: RuntimeCapabilities {
                offline_inference: true,
                streaming: true,
                cancellation: true,
                vision: false,
                audio_input: false,
                audio_output: false,
            },
            model_loaded: false,
        };
        assert_eq!(select_runtime(&[candidate], false), None);
    }
}
