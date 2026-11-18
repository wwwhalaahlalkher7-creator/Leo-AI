//! Initial domain contracts for Leo Alpha v0.1.0.
//!
//! These types deliberately avoid platform SDKs and serialization dependencies.
//! Adapters must translate native/API data into these stable domain types.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeKind {
    LocalLlama,
    RemoteOptional,
    Mock,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeState {
    Unavailable,
    Ready,
    Loading,
    Generating,
    Unloading,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeDescriptor {
    pub id: String,
    pub display_name: String,
    pub kind: RuntimeKind,
    pub platform: String,
    pub state: RuntimeState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageRole {
    System,
    User,
    Assistant,
    Tool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssistantMessage {
    pub role: MessageRole,
    pub content: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AssistantRequest {
    pub request_id: String,
    pub conversation_id: String,
    pub messages: Vec<AssistantMessage>,
    pub max_new_tokens: u32,
    pub temperature: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RuntimeCapabilities {
    pub offline_inference: bool,
    pub streaming: bool,
    pub cancellation: bool,
    pub vision: bool,
    pub audio_input: bool,
    pub audio_output: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeEvent {
    Started { request_id: String },
    TextDelta { request_id: String, text: String },
    Completed { request_id: String, output: String },
    Cancelled { request_id: String },
    Failed { request_id: String, message: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AgentRole {
    General,
    Planner,
    Researcher,
    Programmer,
    CodeReviewer,
    MathScience,
    Writer,
    DataAnalyst,
    WorkspaceOperator,
    DeviceOperator,
    Communications,
    QualityReviewer,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentProfile {
    pub id: String,
    pub display_name: String,
    pub role: AgentRole,
    pub description: String,
    pub system_instructions: String,
    pub required_capabilities: Vec<String>,
    pub skill_ids: Vec<String>,
    pub built_in: bool,
    pub enabled: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskState {
    Draft,
    Planned,
    AwaitingApproval,
    Running,
    Completed,
    Failed,
    Cancelled,
    Interrupted,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TaskStep {
    pub id: String,
    pub objective: String,
    pub agent_id: String,
    pub depends_on: Vec<String>,
    pub required_capabilities: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TaskPlan {
    pub id: String,
    pub goal: String,
    pub state: TaskState,
    pub steps: Vec<TaskStep>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryKind {
    Personal,
    Episodic,
    Semantic,
    Procedural,
    Project,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryRecord {
    pub id: String,
    pub kind: MemoryKind,
    pub content: String,
    pub source_reference: Option<String>,
    pub tags: Vec<String>,
    pub created_at_utc: String,
    pub user_approved: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkillState {
    Proposed,
    Testing,
    Active,
    Disabled,
    Rejected,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillMetadata {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
    pub state: SkillState,
    pub source_task_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CapabilitySource {
    OperatingSystem,
    InstalledApplication,
    LocalCommand,
    McpConnector,
    LeoNativeAdapter,
    UiAutomationFallback,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RiskLevel {
    ReadOnly,
    Low,
    Moderate,
    High,
    Critical,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityDescriptor {
    pub id: String,
    pub display_name: String,
    pub source: CapabilitySource,
    pub platform: String,
    pub actions: Vec<String>,
    pub risk: RiskLevel,
    pub available_offline: bool,
    pub required_permissions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PermissionGrant {
    pub id: String,
    pub capability_id: String,
    pub scope: String,
    pub granted_at_utc: String,
    pub expires_at_utc: Option<String>,
    pub granted: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApprovalDecision {
    Pending,
    Approved,
    Rejected,
    Expired,
    Revoked,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionApproval {
    pub id: String,
    pub capability_id: String,
    pub action_summary: String,
    pub impact_summary: String,
    pub decision: ApprovalDecision,
    pub one_time: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionState {
    Succeeded,
    Failed,
    Cancelled,
    Rejected,
    PartiallySucceeded,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecutionResult {
    pub execution_id: String,
    pub state: ExecutionState,
    pub summary: String,
    pub output_references: Vec<String>,
    pub error_message: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn built_in_agent_roles_are_explicit_and_stable() {
        let role = AgentRole::Programmer;
        assert_eq!(role, AgentRole::Programmer);
    }

    #[test]
    fn permissions_are_separate_from_per_action_approvals() {
        let grant = PermissionGrant {
            id: "grant-1".to_owned(),
            capability_id: "contacts.read".to_owned(),
            scope: "user-selected-contacts".to_owned(),
            granted_at_utc: "2026-11-15T00:00:00Z".to_owned(),
            expires_at_utc: None,
            granted: true,
        };
        let approval = ActionApproval {
            id: "approval-1".to_owned(),
            capability_id: "communications.email.send".to_owned(),
            action_summary: "Send one prepared message".to_owned(),
            impact_summary: "An email leaves the device".to_owned(),
            decision: ApprovalDecision::Pending,
            one_time: true,
        };
        assert!(grant.granted);
        assert_eq!(approval.decision, ApprovalDecision::Pending);
    }

    #[test]
    fn memory_kinds_keep_procedural_knowledge_separate() {
        assert_ne!(MemoryKind::Procedural, MemoryKind::Episodic);
    }
}
