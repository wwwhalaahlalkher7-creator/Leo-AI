//! Leo adapter around the NEXUS-derived Android/Windows llama.cpp native backend.
//!
//! The native C ABI is kept behind `native::engine`; this layer implements
//! Leo's shared runtime contract and model-catalogue preflight.

use crate::gguf::{inspect_gguf_file, GgufInspection};
use crate::model_catalog::{verify_file_integrity, LocalModelEntry, ModelCatalog};
use crate::{AssistantRuntime, RuntimeError};
use crate::native::engine::{
    self, NativeChatMessage, NativeEngineStatus, NativeGenerationOperation,
    NativeMemoryOperation, NativeMemorySnapshot, NativeModelOperation,
};
use leo_shared::{
    AssistantRequest, ExecutionResult, ExecutionState, MessageRole, RuntimeCapabilities,
    RuntimeDescriptor, RuntimeEvent, RuntimeKind,
};
use std::path::Path;
use std::sync::{Mutex, MutexGuard, OnceLock};

#[derive(Debug, Clone, Copy, Default)]
pub struct LocalLlamaRuntime;

impl LocalLlamaRuntime {
    pub fn status(&self) -> NativeEngineStatus {
        engine::native_engine_status()
    }

    pub fn memory_snapshot(&self) -> NativeMemorySnapshot {
        engine::native_memory_snapshot()
    }

    pub fn inspect_model(&self, path: &Path) -> Result<GgufInspection, RuntimeError> {
        let path_text = path.to_str().ok_or_else(|| RuntimeError {
            code: "invalid_model_path".to_owned(),
            message: "مسار النموذج لا يمكن تحويله إلى نص صالح للنظام.".to_owned(),
        })?;
        inspect_gguf_file(path_text).map_err(|message| RuntimeError {
            code: "gguf_inspection_failed".to_owned(),
            message,
        })
    }

    /// Performs manifest, path, file-size and GGUF-header checks before the
    /// native loader gets access to the selected model file.
    pub fn load_catalog_model(
        &self,
        catalogue: &ModelCatalog,
        model_id: &str,
        model_root: &Path,
        context_tokens: u32,
        threads: u32,
    ) -> Result<NativeModelOperation, RuntimeError> {
        catalogue.validate().map_err(|error| RuntimeError {
            code: "invalid_model_catalogue".to_owned(),
            message: error.to_string(),
        })?;
        let entry = catalogue
            .models
            .iter()
            .find(|entry| entry.id == model_id)
            .ok_or_else(|| RuntimeError {
                code: "model_not_found".to_owned(),
                message: format!("لم يتم العثور على النموذج المحلي: {model_id}"),
            })?;
        let model_path = catalogue
            .resolve_model_path(model_id, model_root)
            .map_err(|error| RuntimeError {
                code: "model_path_rejected".to_owned(),
                message: error.to_string(),
            })?;
        verify_file_integrity(
            &model_path,
            entry.file_size_bytes,
            entry.sha256.as_deref(),
        )
        .map_err(|error| RuntimeError {
            code: "model_file_integrity_failed".to_owned(),
            message: error.to_string(),
        })?;
        let inspection = self.inspect_model(&model_path)?;
        validate_manifest_metadata(entry, &inspection)?;
        if let Some(model_context) = inspection.metadata.context_length {
            if u64::from(context_tokens) > model_context {
                return Err(RuntimeError {
                    code: "context_exceeds_model_limit".to_owned(),
                    message: format!(
                        "السياق المطلوب ({context_tokens}) يتجاوز حد النموذج ({model_context})."
                    ),
                });
            }
        }

        let path_text = model_path.to_str().ok_or_else(|| RuntimeError {
            code: "invalid_model_path".to_owned(),
            message: "مسار النموذج لا يمكن تحويله إلى نص صالح للنظام.".to_owned(),
        })?;
        let result = engine::load_native_model(path_text, context_tokens, threads);
        if !result.success {
            return Err(RuntimeError {
                code: "native_model_load_failed".to_owned(),
                message: result.message.clone(),
            });
        }
        Ok(result)
    }

    pub fn unload_model(&self) -> NativeModelOperation {
        engine::unload_native_model()
    }

    pub fn clear_context_memory(&self) -> NativeMemoryOperation {
        engine::clear_native_context_memory()
    }
}

fn validate_manifest_metadata(
    entry: &LocalModelEntry,
    inspection: &GgufInspection,
) -> Result<(), RuntimeError> {
    if let (Some(expected), Some(actual)) = (
        &entry.architecture,
        &inspection.metadata.architecture,
    ) {
        if !expected.eq_ignore_ascii_case(actual) {
            return Err(RuntimeError {
                code: "model_metadata_mismatch".to_owned(),
                message: "معمارية النموذج لا تطابق البيانات المحفوظة في فهرس Leo.".to_owned(),
            });
        }
    }
    if let Some(actual_context) = inspection.metadata.context_length {
        let expected_context = u64::from(entry.context_length);
        if expected_context > actual_context {
            return Err(RuntimeError {
                code: "model_context_metadata_mismatch".to_owned(),
                message: "حجم السياق المسجل يتجاوز ما يعلنه ملف GGUF.".to_owned(),
            });
        }
    }
    Ok(())
}

impl AssistantRuntime for LocalLlamaRuntime {
    fn descriptor(&self) -> RuntimeDescriptor {
        let status = self.status();
        RuntimeDescriptor {
            id: "local-llama".to_owned(),
            display_name: "Leo Local AI (llama.cpp)".to_owned(),
            kind: RuntimeKind::LocalLlama,
            platform: current_platform_id().to_owned(),
            state: if status.available {
                RuntimeState::Ready
            } else {
                RuntimeState::Unavailable
            },
        }
    }

    fn capabilities(&self) -> RuntimeCapabilities {
        RuntimeCapabilities {
            offline_inference: cfg!(any(
                all(target_os = "android", target_arch = "aarch64"),
                all(target_os = "windows", target_arch = "x86_64")
            )),
            streaming: true,
            cancellation: cfg!(any(
                all(target_os = "android", target_arch = "aarch64"),
                all(target_os = "windows", target_arch = "x86_64")
            )),
            vision: false,
            audio_input: false,
            audio_output: false,
        }
    }

    fn generate(
        &self,
        request: &AssistantRequest,
        emit: &mut dyn FnMut(RuntimeEvent),
    ) -> Result<ExecutionResult, RuntimeError> {
        let status = self.status();
        if !status.available || !status.model_loaded {
            return Err(RuntimeError {
                code: "local_runtime_not_ready".to_owned(),
                message: if status.available {
                    "لم يتم تحميل نموذج GGUF محلي بعد.".to_owned()
                } else {
                    status.message
                },
            });
        }

        let _active = ActiveRequestGuard::acquire(&request.request_id)?;
        emit(RuntimeEvent::Started {
            request_id: request.request_id.clone(),
        });

        let messages = request
            .messages
            .iter()
            .map(|message| NativeChatMessage {
                role: match message.role {
                    MessageRole::System => "system",
                    MessageRole::User => "user",
                    MessageRole::Assistant => "assistant",
                    MessageRole::Tool => "tool",
                }
                .to_owned(),
                content: message.content.clone(),
            })
            .collect::<Vec<_>>();

        let (operation, output) = {
            let mut callback_state = TokenCallbackState {
                request_id: request.request_id.clone(),
                output: String::new(),
                pending_utf8: Vec::new(),
                emit: &mut *emit,
            };
            let operation = engine::generate_native_text(
                &messages,
                request.max_new_tokens,
                request.temperature,
                40,
                0.92,
                0,
                on_native_token,
                (&mut callback_state as *mut TokenCallbackState<'_>).cast(),
            );
            callback_state.flush_pending();
            (operation, std::mem::take(&mut callback_state.output))
        };
        let result = complete_generation(request, operation, &output);
        match &result {
            Ok(execution) if execution.state == ExecutionState::Succeeded => {
                emit(RuntimeEvent::Completed {
                    request_id: request.request_id.clone(),
                    output,
                });
            }
            Ok(_) => emit(RuntimeEvent::Cancelled {
                request_id: request.request_id.clone(),
            }),
            Err(error) => emit(RuntimeEvent::Failed {
                request_id: request.request_id.clone(),
                message: error.message.clone(),
            }),
        }
        result
    }

    fn cancel(&self, request_id: &str) -> Result<bool, RuntimeError> {
        // Remember cancellation even if the native C ABI has not reached its
        // first callback yet. The first native callback consumes this pending
        // state and forwards cancellation after GenerationLifecycle is active.
        if !mark_active_request_cancelled(request_id) {
            return Ok(false);
        }
        let _ = engine::cancel_native_generation();
        Ok(true)
    }
}

fn complete_generation(
    request: &AssistantRequest,
    operation: NativeGenerationOperation,
    output: &str,
) -> Result<ExecutionResult, RuntimeError> {
    if operation.success {
        // The stream already contains the user-visible output. Keep this summary
        // compact so callers do not persist a second full copy of the answer.
        Ok(ExecutionResult {
            execution_id: request.request_id.clone(),
            state: ExecutionState::Succeeded,
            summary: format!(
                "اكتمل التوليد المحلي؛ {} رمزاً، وتم اختصار {} رسالة قديمة عند الحاجة.",
                operation.generated_tokens, operation.trimmed_messages
            ),
            output_references: Vec::new(),
            error_message: None,
        })
    } else if operation.cancelled {
        Ok(ExecutionResult {
            execution_id: request.request_id.clone(),
            state: ExecutionState::Cancelled,
            summary: "أوقف المستخدم التوليد المحلي.".to_owned(),
            output_references: Vec::new(),
            error_message: None,
        })
    } else {
        Err(RuntimeError {
            code: "local_generation_failed".to_owned(),
            message: if operation.message.trim().is_empty() {
                format!("فشل التوليد المحلي بعد {} حرفاً.", output.chars().count())
            } else {
                operation.message
            },
        })
    }
}

fn current_platform_id() -> &'static str {
    #[cfg(all(target_os = "android", target_arch = "aarch64"))]
    {
        "android-arm64"
    }
    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
    {
        "windows-x64"
    }
    #[cfg(not(any(
        all(target_os = "android", target_arch = "aarch64"),
        all(target_os = "windows", target_arch = "x86_64")
    )))]
    {
        "unsupported"
    }
}

#[derive(Default)]
struct ActiveRequestState {
    request_id: Option<String>,
    cancel_requested: bool,
}

fn active_request_lock() -> MutexGuard<'static, ActiveRequestState> {
    static ACTIVE_REQUEST: OnceLock<Mutex<ActiveRequestState>> = OnceLock::new();
    ACTIVE_REQUEST
        .get_or_init(|| Mutex::new(ActiveRequestState::default()))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn mark_active_request_cancelled(request_id: &str) -> bool {
    let mut active = active_request_lock();
    if active.request_id.as_deref() != Some(request_id) {
        return false;
    }
    active.cancel_requested = true;
    true
}

fn active_request_cancel_requested(request_id: &str) -> bool {
    let active = active_request_lock();
    active.request_id.as_deref() == Some(request_id) && active.cancel_requested
}

struct ActiveRequestGuard {
    request_id: String,
}

impl ActiveRequestGuard {
    fn acquire(request_id: &str) -> Result<Self, RuntimeError> {
        let mut active = active_request_lock();
        if active.request_id.is_some() {
            return Err(RuntimeError {
                code: "runtime_busy".to_owned(),
                message: "محرك Leo المحلي ينفذ طلباً آخر حالياً.".to_owned(),
            });
        }
        active.request_id = Some(request_id.to_owned());
        active.cancel_requested = false;
        Ok(Self {
            request_id: request_id.to_owned(),
        })
    }
}

impl Drop for ActiveRequestGuard {
    fn drop(&mut self) {
        let mut active = active_request_lock();
        if active.request_id.as_deref() == Some(self.request_id.as_str()) {
            active.request_id = None;
            active.cancel_requested = false;
        }
    }
}

#[allow(unsafe_code)]
struct TokenCallbackState<'a> {
    request_id: String,
    output: String,
    pending_utf8: Vec<u8>,
    emit: &'a mut dyn FnMut(RuntimeEvent),
}

#[allow(unsafe_code)]
impl TokenCallbackState<'_> {
    fn push_bytes(&mut self, bytes: &[u8]) {
        self.pending_utf8.extend_from_slice(bytes);
        loop {
            match std::str::from_utf8(&self.pending_utf8) {
                Ok(text) => {
                    self.emit_delta(text.to_owned());
                    self.pending_utf8.clear();
                    break;
                }
                Err(error) => {
                    let valid = error.valid_up_to();
                    if valid > 0 {
                        let delta =
                            String::from_utf8_lossy(&self.pending_utf8[..valid]).into_owned();
                        self.pending_utf8.drain(..valid);
                        self.emit_delta(delta);
                        continue;
                    }
                    if let Some(invalid_len) = error.error_len() {
                        self.pending_utf8.drain(..invalid_len);
                        self.emit_delta("�".to_owned());
                        continue;
                    }
                    break;
                }
            }
        }
    }

    fn emit_delta(&mut self, text: String) {
        if text.is_empty() {
            return;
        }
        self.output.push_str(&text);
        (self.emit)(RuntimeEvent::TextDelta {
            request_id: self.request_id.clone(),
            text,
        });
    }

    fn flush_pending(&mut self) {
        if !self.pending_utf8.is_empty() {
            let tail = String::from_utf8_lossy(&self.pending_utf8).into_owned();
            self.pending_utf8.clear();
            self.emit_delta(tail);
        }
    }
}

#[allow(unsafe_code)]
unsafe extern "C" fn on_native_token(
    data: *const std::ffi::c_char,
    length: usize,
    _generated_tokens: u32,
    user_data: *mut std::ffi::c_void,
) -> i32 {
    use std::panic::{catch_unwind, AssertUnwindSafe};

    match catch_unwind(AssertUnwindSafe(|| {
        if user_data.is_null() || (data.is_null() && length > 0) {
            return 0;
        }
        let state = unsafe { &mut *(user_data.cast::<TokenCallbackState<'_>>()) };
        if length == 0 {
            // The initial native callback means GenerationLifecycle is active.
            // Forward a cancellation that arrived while Rust was preparing the
            // C ABI arguments, before the C++ adapter could observe it.
            if active_request_cancel_requested(&state.request_id) {
                let _ = engine::cancel_native_generation();
            }
            return 1;
        }
        let bytes = unsafe { std::slice::from_raw_parts(data.cast::<u8>(), length) };
        state.push_bytes(bytes);
        1
    })) {
        Ok(result) => result,
        Err(_) => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use leo_shared::RuntimeState;

    #[cfg(not(any(
        all(target_os = "android", target_arch = "aarch64"),
        all(target_os = "windows", target_arch = "x86_64")
    )))]
    #[test]
    fn runtime_descriptor_does_not_claim_native_availability_on_unsupported_host() {
        let runtime = LocalLlamaRuntime;
        assert_eq!(runtime.descriptor().state, RuntimeState::Unavailable);
        assert!(!runtime.capabilities().offline_inference);
    }

    #[test]
    fn cancellation_is_remembered_before_native_start_callback() {
        let request_id = "cancel-before-native-start-test";
        let guard = ActiveRequestGuard::acquire(request_id).expect("active request guard");
        assert!(mark_active_request_cancelled(request_id));
        assert!(active_request_cancel_requested(request_id));
        assert!(!mark_active_request_cancelled("another-request"));
        drop(guard);
        assert!(!active_request_cancel_requested(request_id));
    }
}
