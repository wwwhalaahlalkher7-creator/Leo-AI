//! Bounded, dependency-aware execution for Leo's built-in specialist agents.
//!
//! This coordinator only runs local model reasoning. It does not execute OS,
//! filesystem, network, or communication actions. Those remain behind the
//! Capability Hub and the per-action approval gateway in the Flutter app.

use crate::{validate_task_plan, AgentCatalog, PlanValidationError};
use leo_shared::TaskPlan;
use std::collections::HashMap;

pub const DEFAULT_MAX_ATTEMPTS: u8 = 2;
pub const MAX_ALLOWED_ATTEMPTS: u8 = 3;
pub const DEFAULT_MAX_STEP_OUTPUT_CHARS: usize = 16_000;
pub const MAX_STEP_OUTPUT_CHARS: usize = 40_000;
pub const MAX_TOOL_PROPOSAL_OUTPUT_CHARS: usize = 40_000;
pub const MAX_DEPENDENCY_OUTPUT_CHARS: usize = 4_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentStepStatus {
    Succeeded,
    Failed,
    Skipped,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskExecutionStatus {
    Completed,
    AwaitingToolApproval,
    PartiallyCompleted,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentRunErrorKind {
    Retryable,
    Permanent,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentRunError {
    pub kind: AgentRunErrorKind,
    pub message: String,
}

impl AgentRunError {
    pub fn retryable(message: impl Into<String>) -> Self {
        Self { kind: AgentRunErrorKind::Retryable, message: message.into() }
    }

    pub fn permanent(message: impl Into<String>) -> Self {
        Self { kind: AgentRunErrorKind::Permanent, message: message.into() }
    }

    pub fn cancelled() -> Self {
        Self { kind: AgentRunErrorKind::Cancelled, message: "تم إلغاء المهمة.".to_owned() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DependencyOutput {
    pub step_id: String,
    pub agent_id: String,
    pub output: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentExecutionRequest {
    pub task_id: String,
    pub step_id: String,
    pub agent_id: String,
    pub goal: String,
    pub conversation_context: String,
    pub objective: String,
    pub dependencies: Vec<DependencyOutput>,
    pub attempt: u8,
    pub max_output_chars: usize,
    /// Whether this step may request one reviewed tool handoff. After the
    /// per-turn handoff budget is exhausted, action specialists are explicitly
    /// switched to reasoning-only mode.
    pub allow_tool_proposals: bool,
}

/// Implemented by a local model adapter. The cancellation callback must be
/// checked before expensive work and whenever the underlying runtime allows.
pub trait AgentExecutor {
    fn execute(
        &mut self,
        request: &AgentExecutionRequest,
        is_cancelled: &dyn Fn() -> bool,
        on_delta: &mut dyn FnMut(&str),
    ) -> Result<String, AgentRunError>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExecutionOptions {
    pub max_attempts: u8,
    pub max_step_output_chars: usize,
}

impl Default for ExecutionOptions {
    fn default() -> Self {
        Self {
            max_attempts: DEFAULT_MAX_ATTEMPTS,
            max_step_output_chars: DEFAULT_MAX_STEP_OUTPUT_CHARS,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentStepResult {
    pub step_id: String,
    pub agent_id: String,
    pub status: AgentStepStatus,
    pub attempts: u8,
    pub output: String,
    pub error: Option<String>,
}

/// A single, strictly framed proposal from an action-capable specialist.
/// The proposal is data only: this crate never dispatches or executes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentToolProposal {
    pub step_id: String,
    pub agent_id: String,
    pub call_id: String,
    pub tool_name: String,
    pub raw_call: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AgentToolProposalError {
    MalformedEnvelope { step_id: String },
    UnsupportedTool { step_id: String, agent_id: String },
    MultipleProposals,
}

impl std::fmt::Display for AgentToolProposalError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MalformedEnvelope { step_id } => {
                write!(formatter, "وكيل الأدوات أنتج طلباً غير مطابق للبروتوكول في {step_id}.")
            }
            Self::UnsupportedTool { step_id, agent_id } => {
                write!(formatter, "الوكيل {agent_id} اقترح أداة خارج نطاق تخصصه في {step_id}.")
            }
            Self::MultipleProposals => formatter.write_str(
                "اقترح أكثر من وكيل إجراءً واحداً؛ أوقف Leo التسليم لمنع تنفيذ سلسلة غير معتمدة.",
            ),
        }
    }
}

fn has_inline_control(value: &str) -> bool {
    value.chars().any(char::is_control)
}

/// A strict structural check at the Rust boundary. Dart performs full date
/// parsing immediately before dispatch; this second check prevents malformed
/// or timezone-free proposals from passing the orchestration layer.
fn has_zoned_iso8601_shape(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() < 17 || bytes.len() > 40 || !value.is_ascii() {
        return false;
    }
    let (body_end, valid_zone) = if bytes.last() == Some(&b'Z') {
        (bytes.len() - 1, true)
    } else if bytes.len() >= 22 {
        let offset = bytes.len() - 6;
        let digits = |byte: u8| byte.is_ascii_digit();
        let sign_valid = matches!(bytes[offset], b'+' | b'-');
        let colon_valid = bytes[offset + 3] == b':';
        let digits_valid = digits(bytes[offset + 1]) && digits(bytes[offset + 2])
            && digits(bytes[offset + 4]) && digits(bytes[offset + 5]);
        // Do not subtract ASCII zero until the byte has been proven to be a digit.
        // Model output is untrusted and malformed offsets must never panic here.
        let (hours, minutes) = if digits_valid {
            (
                ((bytes[offset + 1] - b'0') as u16) * 10 + (bytes[offset + 2] - b'0') as u16,
                ((bytes[offset + 4] - b'0') as u16) * 10 + (bytes[offset + 5] - b'0') as u16,
            )
        } else {
            (u16::MAX, u16::MAX)
        };
        (offset, sign_valid && colon_valid && digits_valid && hours <= 14 && minutes <= 59
            && (hours < 14 || minutes == 0))
    } else {
        (0, false)
    };
    if !valid_zone || body_end < 16 {
        return false;
    }
    let core = &bytes[..body_end];
    let required_digit_positions = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15];
    if required_digit_positions.iter().any(|index| !core[*index].is_ascii_digit())
        || core[4] != b'-' || core[7] != b'-' || core[10] != b'T' || core[13] != b':' {
        return false;
    }
    if body_end == 16 {
        return true;
    }
    if core[16] != b':' || body_end < 19 || !core[17].is_ascii_digit() || !core[18].is_ascii_digit() {
        return false;
    }
    if body_end == 19 { return true; }
    core[19] == b'.' && body_end > 20 && core[20..].iter().all(|byte| byte.is_ascii_digit())
}

/// Extract at most one complete proposal from successful action-specialist
/// outputs. The JSON envelope and role/tool pairing are checked here; the
/// Flutter protocol parser performs the full argument and safety validation
/// again immediately before the Capability Hub is invoked.
pub fn extract_agent_tool_proposal(
    results: &[AgentStepResult],
) -> Result<Option<AgentToolProposal>, AgentToolProposalError> {
    const START: &str = "<leo_tool_call>";
    const END: &str = "</leo_tool_call>";
    let mut proposal: Option<AgentToolProposal> = None;

    for result in results.iter().filter(|result| {
        result.status == AgentStepStatus::Succeeded
            && matches!(result.agent_id.as_str(), "file_operator" | "device_operator" | "communications")
    }) {
        let trimmed = result.output.trim();
        if !trimmed.contains(START) && !trimmed.contains(END) {
            continue;
        }
        let Some(payload) = trimmed.strip_prefix(START).and_then(|value| value.strip_suffix(END)) else {
            return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
        };
        if payload.len() > 40 * 1024 {
            return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
        }
        let decoded: serde_json::Value = serde_json::from_str(payload.trim())
            .map_err(|_| AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() })?;
        let Some(envelope) = decoded.as_object() else {
            return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
        };
        if envelope.len() != 4
            || !envelope.contains_key("version")
            || !envelope.contains_key("id")
            || !envelope.contains_key("name")
            || !envelope.contains_key("arguments")
            || envelope.get("version").and_then(serde_json::Value::as_u64) != Some(1)
        {
            return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
        }
        let call_id = envelope.get("id").and_then(serde_json::Value::as_str)
            .filter(|id| !id.is_empty() && id.len() <= 64 && id.chars().all(|character| {
                character.is_ascii_alphanumeric() || matches!(character, '_' | '-')
            }))
            .ok_or_else(|| AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() })?;
        let Some(name) = envelope.get("name").and_then(serde_json::Value::as_str) else {
            return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
        };
        let expected: &[&str] = match name {
            "files.read_selected" | "files.open_selected" => &[],
            "workspace.write_file" => &["relative_path", "content"],
            "calendar.create_event" => &["title", "start_iso", "end_iso", "location", "description"],
            "clipboard.copy_text" => &["content"],
            "email.compose" => &["to", "subject", "body"],
            "phone.dial" => &["number"],
            "messages.compose" => &["number", "body"],
            "web.open" => &["url"],
            "app.launch" => &["target"],
            _ => return Err(AgentToolProposalError::UnsupportedTool {
                step_id: result.step_id.clone(), agent_id: result.agent_id.clone(),
            }),
        };
        let arguments = envelope.get("arguments").and_then(serde_json::Value::as_object);
        let args_match = arguments.is_some_and(|arguments| {
            arguments.len() == expected.len()
                && expected.iter().all(|key| arguments.get(*key).is_some_and(serde_json::Value::is_string))
        });
        if !args_match {
            return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
        }
        if name == "calendar.create_event" {
            let arguments = arguments.expect("validated above");
            let title = arguments.get("title").and_then(serde_json::Value::as_str).unwrap_or_default();
            let start = arguments.get("start_iso").and_then(serde_json::Value::as_str).unwrap_or_default();
            let end = arguments.get("end_iso").and_then(serde_json::Value::as_str).unwrap_or_default();
            let location = arguments.get("location").and_then(serde_json::Value::as_str).unwrap_or_default();
            let description = arguments.get("description").and_then(serde_json::Value::as_str).unwrap_or_default();
            if title.trim().is_empty() || title.chars().count() > 200 ||
                !has_zoned_iso8601_shape(start) || !has_zoned_iso8601_shape(end) ||
                location.chars().count() > 300 || description.chars().count() > 2048 ||
                has_inline_control(title) || has_inline_control(location) ||
                description.chars().any(|character| character == '\u{7f}' ||
                    (character.is_control() && !matches!(character, '\t' | '\r' | '\n'))) {
                return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
            }
        }
        if name == "clipboard.copy_text" {
            let content = arguments.expect("validated above").get("content").and_then(serde_json::Value::as_str).unwrap_or_default();
            if content.is_empty() || content.len() > 16 * 1024 || content.chars().count() > 10_000
                || content.chars().any(|character| character == '\0' || character == '\u{7f}' || (character.is_control() && !matches!(character, '\t' | '\r' | '\n'))) {
                return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
            }
        }
        if name == "workspace.write_file" {
            let arguments = arguments.expect("validated above");
            let relative_path = arguments.get("relative_path").and_then(serde_json::Value::as_str).unwrap_or_default();
            let content = arguments.get("content").and_then(serde_json::Value::as_str).unwrap_or_default();
            if relative_path.is_empty() || relative_path.trim() != relative_path || relative_path.len() > 160 || relative_path == "." || relative_path == ".."
                || relative_path.contains('/') || relative_path.contains('\\') || relative_path.contains(':') || relative_path.ends_with('.') || relative_path.ends_with(' ')
                || relative_path.chars().any(char::is_control)
                || relative_path.chars().any(|character| "<>\"|?*".contains(character))
                || content.chars().count() > 10_000 || content.len() > 16 * 1024
                || content.chars().any(|character| character == '\0' || character == '\u{7f}'
                    || (character.is_control() && !matches!(character, '\t' | '\r' | '\n'))) {
                return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
            }
            let device_name = relative_path.split('.').next().unwrap_or_default().to_ascii_uppercase();
            if matches!(device_name.as_str(), "CON" | "PRN" | "AUX" | "NUL" | "COM1" | "COM2" | "COM3" | "COM4" | "COM5" | "COM6" | "COM7" | "COM8" | "COM9" | "LPT1" | "LPT2" | "LPT3" | "LPT4" | "LPT5" | "LPT6" | "LPT7" | "LPT8" | "LPT9") {
                return Err(AgentToolProposalError::MalformedEnvelope { step_id: result.step_id.clone() });
            }
        }
        let role_allows_tool = match result.agent_id.as_str() {
            "file_operator" => matches!(name, "files.read_selected" | "files.open_selected" | "workspace.write_file"),
            "device_operator" => matches!(name, "web.open" | "app.launch" | "calendar.create_event" | "clipboard.copy_text"),
            "communications" => matches!(name, "email.compose" | "phone.dial" | "messages.compose"),
            _ => false,
        };
        if !role_allows_tool {
            return Err(AgentToolProposalError::UnsupportedTool {
                step_id: result.step_id.clone(), agent_id: result.agent_id.clone(),
            });
        }
        if proposal.is_some() {
            return Err(AgentToolProposalError::MultipleProposals);
        }
        proposal = Some(AgentToolProposal {
            step_id: result.step_id.clone(),
            agent_id: result.agent_id.clone(),
            call_id: call_id.to_owned(),
            tool_name: name.to_owned(),
            raw_call: trimmed.to_owned(),
        });
    }

    Ok(proposal)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TaskExecutionReport {
    pub task_id: String,
    pub status: TaskExecutionStatus,
    pub step_results: Vec<AgentStepResult>,
    pub final_output: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExecutionEvent {
    StepStarted { step_id: String, agent_id: String, attempt: u8 },
    StepDelta { step_id: String, agent_id: String, text: String },
    StepRetry { step_id: String, agent_id: String, attempt: u8, message: String },
    StepSucceeded { step_id: String, agent_id: String, attempts: u8 },
    StepFailed { step_id: String, agent_id: String, attempts: u8, message: String },
    StepSkipped { step_id: String, agent_id: String, reason: String },
    StepCancelled { step_id: String, agent_id: String },
    /// Durable checkpoint candidate containing only successfully completed steps.
    /// The Flutter host persists this event before any external handoff is shown.
    ProgressCheckpoint { results: Vec<AgentStepResult> },
    TaskFinished { status: TaskExecutionStatus },
}

#[derive(Debug, Clone)]
pub struct TaskCoordinator {
    catalog: AgentCatalog,
}

impl TaskCoordinator {
    pub fn new(catalog: AgentCatalog) -> Self {
        Self { catalog }
    }

    /// Execute steps in stable topological order. Leo's current local runtime
    /// is single-generation and resource bounded, so this deliberately runs
    /// one step at a time even when a DAG contains independent branches.
    pub fn execute(
        &self,
        plan: &TaskPlan,
        conversation_context: &str,
        executor: &mut dyn AgentExecutor,
        options: ExecutionOptions,
        is_cancelled: &dyn Fn() -> bool,
        on_event: &mut dyn FnMut(ExecutionEvent),
    ) -> Result<TaskExecutionReport, PlanValidationError> {
        self.execute_with_initial_results(
            plan,
            conversation_context,
            Vec::new(),
            true,
            executor,
            options,
            is_cancelled,
            on_event,
        )
    }

    /// Resumes a paused plan from previously completed step results. Initial
    /// results are accepted only for known plan steps, with matching agent
    /// identities and a successful terminal state. This prevents a caller
    /// from injecting arbitrary execution history or replaying failed steps.
    pub fn execute_with_initial_results(
        &self,
        plan: &TaskPlan,
        conversation_context: &str,
        initial_results: Vec<AgentStepResult>,
        allow_tool_proposals: bool,
        executor: &mut dyn AgentExecutor,
        options: ExecutionOptions,
        is_cancelled: &dyn Fn() -> bool,
        on_event: &mut dyn FnMut(ExecutionEvent),
    ) -> Result<TaskExecutionReport, PlanValidationError> {
        validate_task_plan(plan, &self.catalog)?;

        let max_attempts = options.max_attempts.clamp(1, MAX_ALLOWED_ATTEMPTS);
        let max_output_chars = options
            .max_step_output_chars
            .clamp(1, MAX_STEP_OUTPUT_CHARS);
        let mut results = HashMap::<String, AgentStepResult>::new();
        for result in initial_results {
            let Some(step) = plan.steps.iter().find(|step| step.id == result.step_id) else {
                return Err(PlanValidationError::InvalidInitialResult(result.step_id));
            };
            if step.agent_id != result.agent_id
                || result.status != AgentStepStatus::Succeeded
                || result.error.is_some()
                || !(1..=MAX_ALLOWED_ATTEMPTS).contains(&result.attempts)
                || result.output.chars().count() > MAX_STEP_OUTPUT_CHARS
                || results.contains_key(&result.step_id)
            {
                return Err(PlanValidationError::InvalidInitialResult(result.step_id));
            }
            results.insert(result.step_id.clone(), result);
        }
        // A restored step is trustworthy only when every dependency it relied
        // on is also present in the restored successful checkpoint. A caller
        // must not inject a downstream result while omitting its prerequisites.
        for result in results.values() {
            let Some(step) = plan.steps.iter().find(|step| step.id == result.step_id) else {
                return Err(PlanValidationError::InvalidInitialResult(result.step_id.clone()));
            };
            let dependencies_restored = step.depends_on.iter().all(|dependency_id| {
                results.get(dependency_id).is_some_and(|dependency| {
                    dependency.status == AgentStepStatus::Succeeded && dependency.error.is_none()
                })
            });
            if !dependencies_restored {
                return Err(PlanValidationError::InvalidInitialResult(result.step_id.clone()));
            }
        }
        let mut task_cancelled = false;
        let mut awaiting_tool_approval = false;

        while results.len() < plan.steps.len() {
            // A cancelled executor result is authoritative even if the external
            // cancellation token was not set (for example, runtime cancellation).
            if task_cancelled || is_cancelled() {
                task_cancelled = true;
                for step in &plan.steps {
                    if results.contains_key(&step.id) { continue; }
                    results.insert(step.id.clone(), AgentStepResult {
                        step_id: step.id.clone(),
                        agent_id: step.agent_id.clone(),
                        status: AgentStepStatus::Cancelled,
                        attempts: 0,
                        output: String::new(),
                        error: Some("تم إلغاء المهمة قبل بدء هذه الخطوة.".to_owned()),
                    });
                    on_event(ExecutionEvent::StepCancelled {
                        step_id: step.id.clone(), agent_id: step.agent_id.clone(),
                    });
                }
                break;
            }

            let mut progressed = false;
            for step in &plan.steps {
                if results.contains_key(&step.id) { continue; }

                let failed_dependency = step.depends_on.iter().find_map(|dependency_id| {
                    results.get(dependency_id).filter(|result| {
                        result.status != AgentStepStatus::Succeeded
                    }).map(|result| (dependency_id, result.status))
                });
                if let Some((dependency_id, dependency_status)) = failed_dependency {
                    let reason = format!(
                        "تم تخطي الخطوة بسبب عدم اكتمال الاعتماد {dependency_id} ({dependency_status:?})."
                    );
                    results.insert(step.id.clone(), AgentStepResult {
                        step_id: step.id.clone(), agent_id: step.agent_id.clone(),
                        status: AgentStepStatus::Skipped, attempts: 0,
                        output: String::new(), error: Some(reason.clone()),
                    });
                    on_event(ExecutionEvent::StepSkipped {
                        step_id: step.id.clone(), agent_id: step.agent_id.clone(), reason,
                    });
                    progressed = true;
                    continue;
                }

                if !step.depends_on.iter().all(|id| {
                    results.get(id).is_some_and(|result| result.status == AgentStepStatus::Succeeded)
                }) {
                    continue;
                }

                let dependencies = step.depends_on.iter().filter_map(|id| results.get(id))
                    .map(|result| DependencyOutput {
                        step_id: result.step_id.clone(),
                        agent_id: result.agent_id.clone(),
                        output: truncate_chars(&result.output, MAX_DEPENDENCY_OUTPUT_CHARS),
                    }).collect::<Vec<_>>();

                let mut final_attempt = 0;
                let mut final_output = String::new();
                let mut final_error = None;
                let mut final_status = AgentStepStatus::Failed;

                for attempt in 1..=max_attempts {
                    if is_cancelled() {
                        task_cancelled = true;
                        final_status = AgentStepStatus::Cancelled;
                        final_error = Some("تم إلغاء المهمة أثناء تنفيذ الوكيل.".to_owned());
                        break;
                    }
                    final_attempt = attempt;
                    on_event(ExecutionEvent::StepStarted {
                        step_id: step.id.clone(), agent_id: step.agent_id.clone(), attempt,
                    });
                    let step_output_limit = if step.agent_id == "file_operator" && allow_tool_proposals {
                        MAX_TOOL_PROPOSAL_OUTPUT_CHARS.min(MAX_STEP_OUTPUT_CHARS)
                    } else {
                        max_output_chars
                    };
                    let request = AgentExecutionRequest {
                        task_id: plan.id.clone(),
                        step_id: step.id.clone(),
                        agent_id: step.agent_id.clone(),
                        goal: plan.goal.clone(),
                        conversation_context: truncate_chars(conversation_context, 12_000),
                        objective: step.objective.clone(),
                        dependencies: dependencies.clone(),
                        attempt,
                        max_output_chars: step_output_limit,
                        allow_tool_proposals,
                    };
                    let mut emitted_chars = 0usize;
                    let mut emit_delta = |text: &str| {
                        let remaining = step_output_limit.saturating_sub(emitted_chars);
                        if !text.is_empty() && remaining > 0 {
                            let bounded = truncate_chars(text, remaining);
                            emitted_chars = emitted_chars.saturating_add(bounded.chars().count());
                            on_event(ExecutionEvent::StepDelta {
                                step_id: step.id.clone(),
                                agent_id: step.agent_id.clone(),
                                text: bounded,
                            });
                        }
                    };
                    match executor.execute(&request, is_cancelled, &mut emit_delta) {
                        Ok(output) => {
                            final_output = truncate_chars(output.trim(), step_output_limit);
                            final_status = AgentStepStatus::Succeeded;
                            final_error = None;
                            break;
                        }
                        Err(error) if error.kind == AgentRunErrorKind::Cancelled || is_cancelled() => {
                            task_cancelled = true;
                            final_status = AgentStepStatus::Cancelled;
                            final_error = Some(error.message);
                            break;
                        }
                        Err(error) => {
                            final_error = Some(error.message.clone());
                            if error.kind == AgentRunErrorKind::Retryable && attempt < max_attempts {
                                on_event(ExecutionEvent::StepRetry {
                                    step_id: step.id.clone(), agent_id: step.agent_id.clone(),
                                    attempt, message: error.message,
                                });
                                continue;
                            }
                            final_status = AgentStepStatus::Failed;
                            break;
                        }
                    }
                }

                let action_specialist = matches!(
                    step.agent_id.as_str(),
                    "file_operator" | "device_operator" | "communications"
                );
                let contains_tool_marker = final_output.contains("<leo_tool_call>")
                    || final_output.contains("</leo_tool_call>");
                if final_status == AgentStepStatus::Succeeded
                    && action_specialist
                    && contains_tool_marker
                    && !allow_tool_proposals
                {
                    // The handoff budget has been exhausted. Never allow a
                    // model-generated proposal to leak into a later verifier
                    // prompt or become an implicit side effect.
                    final_status = AgentStepStatus::Failed;
                    final_error = Some("انتهى حد الإجراءات المسموح به لهذه الرسالة؛ لم يُنفذ اقتراح إضافي.".to_owned());
                    final_output.clear();
                }
                match final_status {
                    AgentStepStatus::Succeeded => on_event(ExecutionEvent::StepSucceeded {
                        step_id: step.id.clone(), agent_id: step.agent_id.clone(), attempts: final_attempt,
                    }),
                    AgentStepStatus::Failed => on_event(ExecutionEvent::StepFailed {
                        step_id: step.id.clone(), agent_id: step.agent_id.clone(),
                        attempts: final_attempt,
                        message: final_error.clone().unwrap_or_else(|| "فشلت الخطوة دون تفاصيل إضافية.".to_owned()),
                    }),
                    AgentStepStatus::Cancelled => on_event(ExecutionEvent::StepCancelled {
                        step_id: step.id.clone(), agent_id: step.agent_id.clone(),
                    }),
                    AgentStepStatus::Skipped => unreachable!("a running step cannot be skipped"),
                }
                let pauses_for_tool = final_status == AgentStepStatus::Succeeded
                    && action_specialist
                    && contains_tool_marker
                    && allow_tool_proposals;
                results.insert(step.id.clone(), AgentStepResult {
                    step_id: step.id.clone(), agent_id: step.agent_id.clone(),
                    status: final_status, attempts: final_attempt,
                    output: final_output, error: final_error,
                });
                if final_status == AgentStepStatus::Succeeded {
                    let checkpoint_results = plan.steps.iter()
                        .filter_map(|planned| results.get(&planned.id))
                        .filter(|result| result.status == AgentStepStatus::Succeeded && result.error.is_none())
                        .cloned()
                        .collect::<Vec<_>>();
                    on_event(ExecutionEvent::ProgressCheckpoint { results: checkpoint_results });
                }
                progressed = true;

                if pauses_for_tool {
                    awaiting_tool_approval = true;
                    break;
                }
                if task_cancelled { break; }
            }

            if task_cancelled { continue; }
            if awaiting_tool_approval { break; }
            if !progressed {
                // The DAG validator should make this unreachable. Keep a
                // defensive failure instead of spinning if the state changes.
                return Err(PlanValidationError::DependencyCycle);
            }
        }

        let mut ordered_results = plan.steps.iter().filter_map(|step| results.remove(&step.id))
            .collect::<Vec<_>>();
        let succeeded = ordered_results.iter().filter(|result| result.status == AgentStepStatus::Succeeded).count();
        let status = if task_cancelled || ordered_results.iter().any(|result| result.status == AgentStepStatus::Cancelled) {
            TaskExecutionStatus::Cancelled
        } else if awaiting_tool_approval {
            TaskExecutionStatus::AwaitingToolApproval
        } else if succeeded == ordered_results.len() {
            TaskExecutionStatus::Completed
        } else if succeeded > 0 {
            TaskExecutionStatus::PartiallyCompleted
        } else {
            TaskExecutionStatus::Failed
        };
        let final_output = choose_final_output(&ordered_results);
        on_event(ExecutionEvent::TaskFinished { status });
        Ok(TaskExecutionReport {
            task_id: plan.id.clone(), status, step_results: std::mem::take(&mut ordered_results), final_output,
        })
    }
}

/// Stable, reviewed system instructions for each built-in role. Every agent is
/// explicitly inference-only; native actions are handled elsewhere.
pub fn agent_tool_handoff_instructions(agent_id: &str) -> &'static str {
    match agent_id {
        "file_operator" => "عند طلب المستخدم قراءة ملف يمكنك اقتراح files.read_selected، وعند طلب فتح ملف محدد يمكنك اقتراح files.open_selected بلا وسيطات. وعند طلب إنشاء أو تعديل ملف نصي واحد يمكنك اقتراح workspace.write_file بمفاتيح relative_path وcontent فقط. استخدم اسماً مباشراً واحداً داخل المجلد الذي سيختاره المستخدم؛ لا تستخدم مسارات فرعية أو .. أو أسماء محجوزة، واجعل المحتوى UTF-8 ولا يتجاوز 10,000 حرف و16 KiB. اخرج طلب الأداة وحده داخل <leo_tool_call> و</leo_tool_call> مع version=1 وid آمن. لا تنشئ مجلدات أو تحذف أو تنقل أو تعيد تسمية ملفات، ولا تقترح الكتابة إلا بطلب صريح. اقتراحك ليس إذناً ولا ينفذ شيئاً.",
        "device_operator" => "إذا طلب المستخدم صراحة فتح رابط أو تطبيق، يمكنك اقتراح web.open أو app.launch. ويمكنك اقتراح calendar.create_event لمسودة تقويم وclipboard.copy_text لنسخ نص بموافقة منفصلة. أمثلة كاملة: <leo_tool_call>{\"version\":1,\"id\":\"call_1\",\"name\":\"calendar.create_event\",\"arguments\":{\"title\":\"مراجعة المشروع\",\"start_iso\":\"2026-11-20T10:00:00Z\",\"end_iso\":\"2026-11-20T10:30:00Z\",\"location\":\"المكتب\",\"description\":\"مراجعة الخطة\"}}</leo_tool_call> أو <leo_tool_call>{\"version\":1,\"id\":\"call_2\",\"name\":\"clipboard.copy_text\",\"arguments\":{\"content\":\"النص الذي طلب المستخدم نسخه\"}}</leo_tool_call>. لرابط الويب استخدم arguments={\"url\":\"https://example.com\"}، وللتطبيق arguments={\"target\":\"معرّف التطبيق\"}. يجب أن تكون التواريخ ISO-8601 مع منطقة زمنية. أخرج طلباً واحداً وحده دون أي نص آخر أو Markdown. لا تفتح رابطاً أو تطبيقاً بنفسك ولا تخترع هدفاً غير معلوم. إذا نقصت المعلومات فاسأل المستخدم. اقتراحك ليس إذناً ولا ينفذ شيئاً.",
        "communications" => "إذا طلب المستخدم صراحة إعداد مسودة بريد أو رسالة أو فتح لوحة اتصال، اقترح أداة واحدة فقط. استخدم email.compose بمفاتيح to وsubject وbody، أو messages.compose بمفاتيح number وbody، أو phone.dial بمفتاح number فقط. غلف JSON بـ<leo_tool_call> و</leo_tool_call> واجعل version=1 وid مثل call_1 وname وarguments مطابقين تماماً للمخطط. يجب أن يكون الرد كله طلب الأداة وحده دون Markdown أو شرح. لا ترسل شيئاً ولا تبدأ مكالمة. لا تخترع عنواناً أو رقماً أو محتوى ناقصاً؛ اسأل المستخدم عند الحاجة. اقتراحك ليس إذناً ولا ينفذ شيئاً.",
        _ => "لا تقترح أي أداة أو إجراء. قدم استدلالاً أو إجابة نصية فقط.",
    }
}

pub fn agent_system_instructions(agent_id: &str) -> &'static str {
    let role = match agent_id {
        "planner" => "أنت مخطط المهام في Leo. حلل الهدف والخطوات والاعتماديات والثغرات. لا تنفذ أي إجراء ولا تدّعِ تنفيذ شيء.",
        "general" => "أنت المساعد العام في Leo. قدم إجابة مباشرة دقيقة ومناسبة للطلب.",
        "researcher" => "أنت باحث Leo. ميّز بين الحقائق والاستنتاجات، ولا تخترع مصادر أو مراجع غير متاحة في السياق.",
        "programmer" => "أنت مبرمج Leo. اقترح تنفيذاً برمجياً واضحاً واختبارات مناسبة، لكن لا تعدّل ملفات أو تشغّل أوامر.",
        "code_reviewer" => "أنت مراجع كود Leo. ابحث عن العيوب الأمنية والمنطقية والانحدارات، واربط كل ملاحظة بدليل من المدخلات.",
        "math_science" => "أنت مختص الرياضيات والعلوم في Leo. اعرض الاشتقاق خطوة بخطوة وتحقق من الوحدات والافتراضات والنتيجة.",
        "writer" => "أنت الكاتب والمحرر في Leo. حافظ على المعنى والنبرة المطلوبة وقدم نصاً منسقاً قابلاً للاستخدام.",
        "data_analyst" => "أنت محلل بيانات Leo. وضح المنهج والافتراضات، ولا تستنتج قيماً لا تدعمها البيانات المقدمة.",
        "file_operator" => "أنت مختص الملفات في Leo. يمكنك اقتراح قراءة ملف يختاره المستخدم أو فتح ملف يحدده عبر files.open_selected، أو اقتراح إنشاء/تعديل ملف نصي واحد داخل مجلد يختاره المستخدم عبر workspace.write_file. لا تقترح الكتابة إلا بطلب صريح، ولا تستخدم مسارات من عندك أو مسارات فرعية أو .. ولا تحذف أو تنقل أو تعيد تسمية الملفات. موافقة المستخدم على كل كتابة مطلوبة.",
        "device_operator" => "أنت مختص الجهاز في Leo. يمكنك اقتراح web.open أو app.launch أو calendar.create_event أو clipboard.copy_text عند طلب المستخدم ذلك بوضوح. استخدم JSON المطابق لمخطط الأداة، وأخرج طلباً واحداً داخل leo_tool_call وحده. موعد التقويم مجرد مسودة يجب على المستخدم حفظها داخل تطبيق التقويم؛ ونسخ الحافظة يستبدل محتواها الحالي ويحتاج موافقة. لا تغير إعدادات ولا تنفذ أوامر نظام.",
        "communications" => "أنت مساعد الاتصالات في Leo. يمكنك اقتراح email.compose أو phone.dial أو messages.compose فقط؛ لا ترسل بريداً أو رسائل ولا تبدأ مكالمات أو حجوزات.",
        "skill_curator" => "أنت أمين مهارات Leo. اقترح مهارة قابلة للمراجعة والاختبار؛ لا تفعّلها ولا تنفذ خطواتها.",
        "verifier" => "أنت مدقق جودة Leo. قارن المخرجات بالهدف، وحدد ما تم دعمه وما بقي غير مؤكد أو غير مكتمل.",
        _ => "أنت وكيل متخصص في Leo. أجب عن الجزء المحدد فقط، ولا تنفذ أي إجراء على الجهاز.",
    };
    role
}

fn choose_final_output(results: &[AgentStepResult]) -> String {
    if let Some(verifier) = results.iter().rev().find(|result| {
        result.agent_id == "verifier" && result.status == AgentStepStatus::Succeeded && !result.output.is_empty()
    }) {
        return verifier.output.clone();
    }
    let successful = results.iter().filter(|result| {
        result.status == AgentStepStatus::Succeeded && !result.output.is_empty()
    }).collect::<Vec<_>>();
    if successful.len() == 1 { return successful[0].output.clone(); }
    successful.iter().map(|result| {
        format!("### {}\n{}", result.agent_id, result.output)
    }).collect::<Vec<_>>().join("\n\n")
}

fn truncate_chars(value: &str, limit: usize) -> String {
    let mut chars = value.chars();
    let prefix = chars.by_ref().take(limit).collect::<String>();
    if chars.next().is_some() {
        format!("{prefix}\n… [تم اختصار المخرجات لتقليل استهلاك الذاكرة والسياق] ")
    } else {
        prefix
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::AgentRouter;
    use std::collections::HashMap;

    #[derive(Default)]
    struct FakeExecutor {
        outputs: HashMap<String, String>,
        failures: HashMap<String, u8>,
        calls: HashMap<String, u8>,
    }

    impl AgentExecutor for FakeExecutor {
        fn execute(
            &mut self,
            request: &AgentExecutionRequest,
            is_cancelled: &dyn Fn() -> bool,
            _on_delta: &mut dyn FnMut(&str),
        ) -> Result<String, AgentRunError> {
            if is_cancelled() { return Err(AgentRunError::cancelled()); }
            let count = self.calls.entry(request.step_id.clone()).or_default();
            *count += 1;
            if self.failures.get(&request.step_id).copied().unwrap_or(0) >= *count {
                return Err(AgentRunError::retryable("temporary fake failure"));
            }
            Ok(self.outputs.get(&request.step_id).cloned().unwrap_or_else(|| format!("output:{}", request.step_id)))
        }
    }

    fn build_two_step_plan() -> TaskPlan {
        AgentRouter::built_in().unwrap().build_plan("task-exec", "راجع الكود البرمجي وتحقق من الاختبارات").unwrap().plan
    }

    fn succeeded_tool_step(agent_id: &str, raw_call: &str) -> AgentStepResult {
        AgentStepResult {
            step_id: format!("step-{agent_id}"),
            agent_id: agent_id.to_owned(),
            status: AgentStepStatus::Succeeded,
            attempts: 1,
            output: raw_call.to_owned(),
            error: None,
        }
    }

    #[test]
    fn zoned_iso8601_shape_accepts_valid_offsets_and_rejects_bad_offsets() {
        assert!(has_zoned_iso8601_shape("2026-11-20T10:00Z"));
        assert!(has_zoned_iso8601_shape("2026-11-20T10:00:30+02:00"));
        assert!(has_zoned_iso8601_shape("2026-11-20T10:00:30.123456-05:30"));
        assert!(!has_zoned_iso8601_shape("2026-11-20T10:00"));
        assert!(!has_zoned_iso8601_shape("2026-11-20T10:00+1x:00"));
        assert!(!has_zoned_iso8601_shape("2026-11-20T10:00+14:01"));
        assert!(!has_zoned_iso8601_shape("2026-11-20T10:00+99:99"));
    }

    #[test]
    fn malformed_timezone_bytes_do_not_panic() {
        for value in [
            "2026-11-20T10:00+AA:BB",
            "2026-11-20T10:00+::00",
            "2026-11-20T10:00+00:Q0",
            "2026-11-20T10:00-\u{0660}1:00",
        ] {
            assert!(!has_zoned_iso8601_shape(value));
        }
    }

    #[test]
    fn extracts_only_role_scoped_exact_tool_proposals() {
        let output = r#"<leo_tool_call>{"version":1,"id":"call_1","name":"email.compose","arguments":{"to":"a@example.com","subject":"Hello","body":"Hi"}}</leo_tool_call>"#;
        let proposal = extract_agent_tool_proposal(&[succeeded_tool_step("communications", output)])
            .unwrap().unwrap();
        assert_eq!(proposal.agent_id, "communications");
        assert_eq!(proposal.raw_call, output);
    }

    #[test]
    fn rejects_tool_proposals_outside_the_agents_role_allowlist() {
        let output = r#"<leo_tool_call>{"version":1,"id":"call_1","name":"app.launch","arguments":{"target":"calculator"}}</leo_tool_call>"#;
        let error = extract_agent_tool_proposal(&[succeeded_tool_step("communications", output)])
            .unwrap_err();
        assert!(matches!(error, AgentToolProposalError::UnsupportedTool { .. }));
    }

    #[test]
    fn ignores_failed_steps_and_non_action_agents() {
        let output = r#"<leo_tool_call>{"version":1,"id":"call_1","name":"email.compose","arguments":{"to":"a@example.com","subject":"Hello","body":"Hi"}}</leo_tool_call>"#;
        let mut failed = succeeded_tool_step("communications", output);
        failed.status = AgentStepStatus::Failed;
        let non_action = succeeded_tool_step("researcher", output);
        assert_eq!(extract_agent_tool_proposal(&[failed, non_action]).unwrap(), None);
    }

    #[test]
    fn rejects_malformed_and_multiple_tool_proposals() {
        let malformed = "<leo_tool_call>{not-json}</leo_tool_call>";
        assert!(matches!(
            extract_agent_tool_proposal(&[succeeded_tool_step("communications", malformed)]),
            Err(AgentToolProposalError::MalformedEnvelope { .. })
        ));

        let email = r#"<leo_tool_call>{"version":1,"id":"call_1","name":"email.compose","arguments":{"to":"a@example.com","subject":"Hello","body":"Hi"}}</leo_tool_call>"#;
        let sms = r#"<leo_tool_call>{"version":1,"id":"call_2","name":"messages.compose","arguments":{"number":"12345","body":"Hi"}}</leo_tool_call>"#;
        assert_eq!(
            extract_agent_tool_proposal(&[
                succeeded_tool_step("communications", email),
                succeeded_tool_step("communications", sms),
            ]),
            Err(AgentToolProposalError::MultipleProposals)
        );
    }



    #[test]
    fn file_operator_can_propose_only_a_bounded_single_workspace_text_file() {
        let output = r#"<leo_tool_call>{"version":1,"id":"write_1","name":"workspace.write_file","arguments":{"relative_path":"notes.md","content":"# Notes\nHello"}}</leo_tool_call>"#;
        let proposal = extract_agent_tool_proposal(&[succeeded_tool_step("file_operator", output)])
            .unwrap().unwrap();
        assert_eq!(proposal.tool_name, "workspace.write_file");
        assert_eq!(proposal.agent_id, "file_operator");
    }

    #[test]
    fn file_operator_workspace_proposal_rejects_traversal_reserved_and_oversized_values() {
        let make = |relative_path: &str, content: &str| format!(
            r#"<leo_tool_call>{{"version":1,"id":"write_2","name":"workspace.write_file","arguments":{{"relative_path":{},"content":{}}}}}</leo_tool_call>"#,
            serde_json::to_string(relative_path).unwrap(),
            serde_json::to_string(content).unwrap(),
        );
        let cases = vec![
            ("../outside.txt".to_owned(), "text".to_owned()),
            ("nested/file.txt".to_owned(), "text".to_owned()),
            ("CON.txt".to_owned(), "text".to_owned()),
            (" notes.txt".to_owned(), "text".to_owned()),
            ("notes.txt".to_owned(), "x".repeat(16 * 1024 + 1)),
            ("notes.txt".to_owned(), "x".repeat(10_001)),
        ];
        for (path, content) in cases {
            let output = make(&path, &content);
            assert!(matches!(
                extract_agent_tool_proposal(&[succeeded_tool_step("file_operator", &output)]),
                Err(AgentToolProposalError::MalformedEnvelope { .. })
            ), "unsafe proposal was accepted: {path}");
        }
    }

    #[test]
    fn workspace_write_is_rejected_when_proposed_by_another_specialist() {
        let output = r#"<leo_tool_call>{"version":1,"id":"write_3","name":"workspace.write_file","arguments":{"relative_path":"notes.md","content":"text"}}</leo_tool_call>"#;
        assert!(matches!(
            extract_agent_tool_proposal(&[succeeded_tool_step("device_operator", output)]),
            Err(AgentToolProposalError::UnsupportedTool { .. })
        ));
    }

    fn build_tool_continuation_plan() -> TaskPlan {
        TaskPlan {
            id: "task-tool-continuation".to_owned(),
            goal: "افتح التطبيق ثم أعد صياغة النتيجة وراجعها".to_owned(),
            state: leo_shared::TaskState::Planned,
            steps: vec![
                leo_shared::TaskStep {
                    id: "plan".to_owned(),
                    objective: "ضع خطة قصيرة".to_owned(),
                    agent_id: "planner".to_owned(),
                    depends_on: vec![],
                    required_capabilities: vec![],
                },
                leo_shared::TaskStep {
                    id: "device".to_owned(),
                    objective: "اقترح فتح التطبيق".to_owned(),
                    agent_id: "device_operator".to_owned(),
                    depends_on: vec!["plan".to_owned()],
                    required_capabilities: vec![],
                },
                leo_shared::TaskStep {
                    id: "writer".to_owned(),
                    objective: "أعد صياغة نتيجة الإجراء".to_owned(),
                    agent_id: "writer".to_owned(),
                    depends_on: vec!["device".to_owned()],
                    required_capabilities: vec![],
                },
                leo_shared::TaskStep {
                    id: "verify".to_owned(),
                    objective: "راجع الإجابة".to_owned(),
                    agent_id: "verifier".to_owned(),
                    depends_on: vec!["writer".to_owned()],
                    required_capabilities: vec![],
                },
            ],
        }
    }

    #[test]
    fn coordinator_pauses_at_one_tool_proposal_and_resumes_without_rerunning_completed_steps() {
        let plan = build_tool_continuation_plan();
        let tool_call = r#"<leo_tool_call>{"version":1,"id":"open_1","name":"app.launch","arguments":{"target":"camera"}}</leo_tool_call>"#;
        let mut executor = FakeExecutor::default();
        executor.outputs.insert("device".to_owned(), tool_call.to_owned());
        executor.outputs.insert("writer".to_owned(), "تم تسليم طلب فتح التطبيق إلى النظام.".to_owned());
        executor.outputs.insert("verify".to_owned(), "تمت مراجعة النتيجة.".to_owned());
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());

        let first = coordinator.execute(
            &plan, "سياق المهمة", &mut executor, ExecutionOptions::default(),
            &|| false, &mut |_| {},
        ).unwrap();
        assert_eq!(first.status, TaskExecutionStatus::AwaitingToolApproval);
        assert_eq!(first.step_results.len(), 2);
        assert_eq!(executor.calls.get("plan"), Some(&1));
        assert_eq!(executor.calls.get("device"), Some(&1));
        assert_eq!(executor.calls.get("writer"), None);

        let mut resumed_results = first.step_results.clone();
        let action = resumed_results.iter_mut().find(|result| result.step_id == "device").unwrap();
        action.output = "نتيجة أداة غير موثوقة: تم فتح التطبيق".to_owned();
        let second = coordinator.execute_with_initial_results(
            &plan, "سياق المهمة مع نتيجة الأداة", resumed_results.clone(), true,
            &mut executor, ExecutionOptions::default(), &|| false, &mut |_| {},
        ).unwrap();
        assert_eq!(second.status, TaskExecutionStatus::Completed);
        assert_eq!(executor.calls.get("plan"), Some(&1));
        assert_eq!(executor.calls.get("device"), Some(&1));
        assert_eq!(executor.calls.get("writer"), Some(&1));
        assert_eq!(executor.calls.get("verify"), Some(&1));
    }

    #[test]
    fn coordinator_supports_two_serial_action_handoffs_without_repeating_steps() {
        let plan = TaskPlan {
            id: "task-two-handoffs".to_owned(),
            goal: "افتح التطبيق ثم اتصل بالرقم ثم راجع النتيجة".to_owned(),
            state: leo_shared::TaskState::Planned,
            steps: vec![
                leo_shared::TaskStep {
                    id: "plan".to_owned(), objective: "خطط".to_owned(),
                    agent_id: "planner".to_owned(), depends_on: vec![], required_capabilities: vec![],
                },
                leo_shared::TaskStep {
                    id: "device".to_owned(), objective: "افتح التطبيق".to_owned(),
                    agent_id: "device_operator".to_owned(), depends_on: vec!["plan".to_owned()], required_capabilities: vec![],
                },
                leo_shared::TaskStep {
                    id: "communications".to_owned(), objective: "افتح لوحة الاتصال".to_owned(),
                    agent_id: "communications".to_owned(), depends_on: vec!["device".to_owned()], required_capabilities: vec![],
                },
                leo_shared::TaskStep {
                    id: "writer".to_owned(), objective: "لخص النتيجة".to_owned(),
                    agent_id: "writer".to_owned(), depends_on: vec!["communications".to_owned()], required_capabilities: vec![],
                },
                leo_shared::TaskStep {
                    id: "verify".to_owned(), objective: "تحقق من الملخص".to_owned(),
                    agent_id: "verifier".to_owned(), depends_on: vec!["writer".to_owned()], required_capabilities: vec![],
                },
            ],
        };
        let open_app = r#"<leo_tool_call>{"version":1,"id":"open_1","name":"app.launch","arguments":{"target":"camera"}}</leo_tool_call>"#;
        let dial = r#"<leo_tool_call>{"version":1,"id":"dial_1","name":"phone.dial","arguments":{"number":"000"}}</leo_tool_call>"#;
        let mut executor = FakeExecutor::default();
        executor.outputs.insert("device".to_owned(), open_app.to_owned());
        executor.outputs.insert("communications".to_owned(), dial.to_owned());
        executor.outputs.insert("writer".to_owned(), "تم تسليم لوحة الاتصال إلى النظام.".to_owned());
        executor.outputs.insert("verify".to_owned(), "اكتملت المراجعة.".to_owned());
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());

        let first = coordinator.execute(
            &plan, "سياق المهمة", &mut executor, ExecutionOptions::default(),
            &|| false, &mut |_| {},
        ).unwrap();
        assert_eq!(first.status, TaskExecutionStatus::AwaitingToolApproval);
        assert_eq!(first.step_results.len(), 2);
        let mut first_checkpoint = first.step_results;
        first_checkpoint.iter_mut().find(|result| result.step_id == "device").unwrap().output =
            "نتيجة غير موثوقة: تم فتح التطبيق".to_owned();

        let second = coordinator.execute_with_initial_results(
            &plan, "السياق بعد الإجراء الأول", first_checkpoint, true,
            &mut executor, ExecutionOptions::default(), &|| false, &mut |_| {},
        ).unwrap();
        assert_eq!(second.status, TaskExecutionStatus::AwaitingToolApproval);
        assert_eq!(second.step_results.len(), 3);
        let mut second_checkpoint = second.step_results;
        second_checkpoint.iter_mut().find(|result| result.step_id == "communications").unwrap().output =
            "نتيجة غير موثوقة: فتح لوحة الاتصال".to_owned();

        let third = coordinator.execute_with_initial_results(
            &plan, "السياق بعد الإجراءين", second_checkpoint, true,
            &mut executor, ExecutionOptions::default(), &|| false, &mut |_| {},
        ).unwrap();
        assert_eq!(third.status, TaskExecutionStatus::Completed);
        for step_id in ["plan", "device", "communications", "writer", "verify"] {
            assert_eq!(executor.calls.get(step_id), Some(&1), "step {step_id} ran more than once");
        }
    }

    #[test]
    fn resume_rejects_unknown_or_non_successful_initial_results() {
        let plan = build_tool_continuation_plan();
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let invalid = AgentStepResult {
            step_id: "not-in-plan".to_owned(),
            agent_id: "writer".to_owned(),
            status: AgentStepStatus::Succeeded,
            attempts: 1,
            output: "x".to_owned(),
            error: None,
        };
        let mut executor = FakeExecutor::default();
        let result = coordinator.execute_with_initial_results(
            &plan, "", vec![invalid], true, &mut executor,
            ExecutionOptions::default(), &|| false, &mut |_| {},
        );
        assert!(matches!(result, Err(PlanValidationError::InvalidInitialResult(_))));
    }

    #[test]
    fn resume_rejects_checkpoint_results_with_missing_dependencies() {
        let plan = build_tool_continuation_plan();
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        // A forged writer checkpoint must not be accepted without the `device`
        // result it depends on (or its own `plan` prerequisite).
        let forged = AgentStepResult {
            step_id: "writer".to_owned(),
            agent_id: "writer".to_owned(),
            status: AgentStepStatus::Succeeded,
            attempts: 1,
            output: "تمت الكتابة".to_owned(),
            error: None,
        };
        let mut executor = FakeExecutor::default();
        let result = coordinator.execute_with_initial_results(
            &plan, "", vec![forged], true, &mut executor,
            ExecutionOptions::default(), &|| false, &mut |_| {},
        );
        assert!(matches!(result, Err(PlanValidationError::InvalidInitialResult(step)) if step == "writer"));
        assert!(executor.calls.is_empty());
    }

    #[test]
    fn action_proposal_is_rejected_after_handoff_budget_is_exhausted() {
        let plan = build_tool_continuation_plan();
        let tool_call = r#"<leo_tool_call>{"version":1,"id":"open_1","name":"app.launch","arguments":{"target":"camera"}}</leo_tool_call>"#;
        let mut executor = FakeExecutor::default();
        executor.outputs.insert("device".to_owned(), tool_call.to_owned());
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let report = coordinator.execute_with_initial_results(
            &plan, "", Vec::new(), false, &mut executor,
            ExecutionOptions::default(), &|| false, &mut |_| {},
        ).unwrap();
        assert_ne!(report.status, TaskExecutionStatus::AwaitingToolApproval);
        let action = report.step_results.iter().find(|result| result.step_id == "device").unwrap();
        assert_eq!(action.status, AgentStepStatus::Failed);
        assert!(!action.output.contains("<leo_tool_call>"));
    }

    #[test]
    fn retries_transient_agent_failure_then_completes() {
        let mut executor = FakeExecutor::default();
        executor.failures.insert("specialist_0".to_owned(), 1);
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let report = coordinator.execute(&build_two_step_plan(), "", &mut executor, ExecutionOptions::default(), &|| false, &mut |_| {}).unwrap();
        assert_eq!(report.status, TaskExecutionStatus::Completed);
        assert_eq!(executor.calls.get("specialist_0"), Some(&2));
        assert_eq!(report.step_results.iter().find(|result| result.step_id == "specialist_0").unwrap().attempts, 2);
    }

    #[test]
    fn failed_dependency_skips_verifier_instead_of_using_missing_output() {
        let mut executor = FakeExecutor::default();
        executor.failures.insert("specialist_0".to_owned(), 9);
        let plan = AgentRouter::built_in().unwrap().build_plan("task-fail", "اكتب كود برمجي ثم راجعه").unwrap().plan;
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let report = coordinator.execute(&plan, "", &mut executor, ExecutionOptions { max_attempts: 1, ..Default::default() }, &|| false, &mut |_| {}).unwrap();
        assert!(report.step_results.iter().any(|result| result.status == AgentStepStatus::Failed));
        assert!(report.step_results.iter().any(|result| result.agent_id == "verifier" && result.status == AgentStepStatus::Skipped));
        assert_eq!(report.status, TaskExecutionStatus::PartiallyCompleted);
    }

    struct ExecutorCancelledWithoutToken {
        calls: usize,
    }

    impl AgentExecutor for ExecutorCancelledWithoutToken {
        fn execute(
            &mut self,
            _request: &AgentExecutionRequest,
            _is_cancelled: &dyn Fn() -> bool,
            _on_delta: &mut dyn FnMut(&str),
        ) -> Result<String, AgentRunError> {
            self.calls += 1;
            Err(AgentRunError::cancelled())
        }
    }

    #[test]
    fn executor_cancellation_stops_the_dag_even_when_token_is_false() {
        let plan = build_two_step_plan();
        let mut executor = ExecutorCancelledWithoutToken { calls: 0 };
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let report = coordinator.execute(
            &plan, "", &mut executor, ExecutionOptions::default(), &|| false, &mut |_| {},
        ).unwrap();
        assert_eq!(executor.calls, 1);
        assert_eq!(report.status, TaskExecutionStatus::Cancelled);
        assert!(report.step_results.iter().filter(|result| result.status == AgentStepStatus::Cancelled).count() >= 1);
    }

    #[test]
    fn cancellation_prevents_next_step_from_starting() {
        let mut executor = FakeExecutor::default();
        let cancelled = std::cell::Cell::new(false);
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let report = coordinator.execute(
            &build_two_step_plan(), "", &mut executor, ExecutionOptions::default(),
            &|| cancelled.get(),
            &mut |event| if matches!(event, ExecutionEvent::StepSucceeded { .. }) { cancelled.set(true); },
        ).unwrap();
        assert_eq!(report.status, TaskExecutionStatus::Cancelled);
        assert!(report.step_results.iter().any(|result| result.status == AgentStepStatus::Cancelled));
    }

    #[test]
    fn independent_branch_can_finish_after_another_branch_fails() {
        let mut executor = FakeExecutor::default();
        executor.failures.insert("specialist_0".to_owned(), 9);
        let plan = AgentRouter::built_in().unwrap().build_plan("task-branch", "اكتب نصاً وحلل بيانات CSV").unwrap().plan;
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let report = coordinator.execute(&plan, "", &mut executor, ExecutionOptions { max_attempts: 1, ..Default::default() }, &|| false, &mut |_| {}).unwrap();
        assert!(report.step_results.iter().any(|result| result.status == AgentStepStatus::Succeeded));
        assert_eq!(report.status, TaskExecutionStatus::PartiallyCompleted);
    }

    #[test]
    fn dependency_context_and_agent_outputs_are_bounded() {
        let plan = AgentRouter::built_in().unwrap().build_plan("task-bounds", "أنشئ كوداً ثم راجعه").unwrap().plan;
        let mut executor = FakeExecutor::default();
        executor.outputs.insert("specialist_0".to_owned(), "x".repeat(30_000));
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let report = coordinator.execute(&plan, "", &mut executor, ExecutionOptions::default(), &|| false, &mut |_| {}).unwrap();
        assert!(report.step_results.iter().all(|result| result.output.chars().count() <= MAX_STEP_OUTPUT_CHARS + 100));
    }

    #[test]
    fn execution_options_are_clamped_to_safe_attempt_and_output_limits() {
        let plan = build_two_step_plan();
        let mut executor = FakeExecutor::default();
        executor.failures.insert("specialist_0".to_owned(), 2);
        let coordinator = TaskCoordinator::new(AgentCatalog::built_in().unwrap());
        let report = coordinator.execute(&plan, "", &mut executor, ExecutionOptions { max_attempts: 255, max_step_output_chars: usize::MAX }, &|| false, &mut |_| {}).unwrap();
        assert_eq!(executor.calls.get("specialist_0"), Some(&3));
        assert!(report.step_results.iter().all(|result| result.output.chars().count() <= MAX_STEP_OUTPUT_CHARS + 100));
    }
}
