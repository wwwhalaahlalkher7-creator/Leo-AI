//! Built-in agent routing and task-plan validation.
//!
//! The catalog is bundled with Leo. Users are not required to create agents;
//! the router chooses the smallest useful set for each request.

pub mod execution;

use leo_shared::{TaskPlan, TaskStep};
use serde::Deserialize;
use std::collections::{HashMap, HashSet, VecDeque};
use std::fmt;

pub const MAX_TASK_GOAL_CHARS: usize = 6_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentSelection {
    pub selected_agent_ids: Vec<String>,
    pub rationale: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannedWork {
    pub plan: TaskPlan,
    pub agents: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct AgentCatalog {
    pub schema_version: u32,
    pub status: String,
    pub product: String,
    pub selection_policy: String,
    pub user_agent_creation_required: bool,
    pub agents: Vec<AgentDefinition>,
    #[serde(default)]
    pub rules: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct AgentDefinition {
    pub id: String,
    pub name: String,
    pub domains: Vec<String>,
    pub may_delegate: bool,
    pub required_capabilities: Vec<String>,
}

impl AgentCatalog {
    /// Loads the reviewed, version-controlled catalog shipped with Leo.
    pub fn built_in() -> Result<Self, serde_json::Error> {
        serde_json::from_str(include_str!("../../../config/leo_builtin_agents_v0.1.json"))
    }

    pub fn contains(&self, agent_id: &str) -> bool {
        self.agents.iter().any(|agent| agent.id == agent_id)
    }

    pub fn get(&self, agent_id: &str) -> Option<&AgentDefinition> {
        self.agents.iter().find(|agent| agent.id == agent_id)
    }
}

#[derive(Debug, Clone)]
pub struct AgentRouter {
    catalog: AgentCatalog,
}

impl AgentRouter {
    pub fn new(catalog: AgentCatalog) -> Self {
        Self { catalog }
    }

    pub fn built_in() -> Result<Self, serde_json::Error> {
        Ok(Self::new(AgentCatalog::built_in()?))
    }

    pub fn catalog(&self) -> &AgentCatalog {
        &self.catalog
    }

    /// A deterministic first-pass router. The model planner can later refine
    /// the decision, but it may only select agents present in this catalog.
    pub fn route(&self, request: &str) -> AgentSelection {
        let text = normalize_request(request);
        let mut selected = Vec::<&str>::new();

        let has_programming = contains_any(
            &text,
            &[
                "code",
                "coding",
                "program",
                "debug",
                "flutter",
                "dart",
                "rust",
                "python",
                "كود",
                "برمج",
                "برمجة",
                "تطوير تطبيق",
                "طور التطبيق",
                "أخطاء الكود",
                "اخطاء الكود",
            ],
        ) || contains_any(
            &text,
            &[
                "create app", "build app", "develop app", "create an application",
                "أنشئ تطبيق", "انشئ تطبيق", "أنشئ برنامج", "انشئ برنامج", "طور تطبيق", "طوّر تطبيق",
            ],
        );
        let has_math = contains_any(
            &text,
            &[
                "math", "equation", "calculate", "integral", "limit", "derivative",
                "رياضيات", "معادلة", "احسب", "حساب", "نهاية", "تكامل", "اشتقاق",
            ],
        );
        let has_research = contains_any(
            &text,
            &[
                "research",
                "analyze",
                "analyse",
                "compare",
                "investigate",
                "evidence",
                "ابحث",
                "بحث",
                "حلل",
                "حلّل",
                "قارن",
                "دراسة",
                "مصادر",
                "تحقق من المعلومات",
            ],
        );
        let has_writing = contains_any(
            &text,
            &[
                "write",
                "rewrite",
                "edit",
                "summarize",
                "summary",
                "translate",
                "اكتب",
                "صياغة",
                "حرر",
                "لخص",
                "ترجم",
                "ترجمة",
                "حرر النص",
            ],
        );
        let has_data = contains_any(
            &text,
            &[
                "csv", "json", "dataset", "statistics", "spreadsheet", "تحليل بيانات",
                "إحصاء", "احصاء", "جدول بيانات",
            ],
        );
        let has_files = contains_any(
            &text,
            &[
                "file",
                "folder",
                "rename",
                "organize files",
                "document",
                "مجلد",
                "مجلدات",
                "ملف",
                "ملفات",
                "رتب الملفات",
                "نظم الملفات",
                "انقل الملفات",
                "احذف الملف",
                "اعاده تسمية الملفات",
            ],
        );
        let has_device = contains_any(
            &text,
            &[
                "open app", "launch app", "settings", "calendar", "appointment", "schedule event", "add event", "clipboard", "copy to clipboard", "افتح التطبيق",
                "افتح تطبيق", "إعدادات الجهاز", "اعدادات الجهاز", "شغل التطبيق", "اغلق التطبيق", "التقويم", "موعد", "إضافة موعد", "اضافة موعد", "أنشئ حدث", "انسخ إلى الحافظة", "انسخ النص",
            ],
        );
        let has_communications = contains_any(
            &text,
            &[
                "email",
                "e-mail",
                "send a message",
                "text message",
                "call ",
                "phone",
                "dial",
                "بريد",
                "ارسل رسالة",
                "أرسل رسالة",
                "رسالة إلى",
                "اتصل",
                "اتصال",
                "الهاتف",
                "مكالمة",
                "ارسل ايميل",
                "أرسل بريدا",
                "ارسال بريد",
            ],
        );
        let has_compound_intent = contains_any(
            &text,
            &[
                " then ", " after that ", " and then ", "also", "وبعدها", "بعدها", "ثم", "بالإضافة",
                "بالاضافة", "مع مراجعة", "ثم راجع", "وبعد ذلك",
            ],
        );
        let has_skill_learning = contains_any(
            &text,
            &[
                "skill", "learn this workflow", "save this workflow", "create a skill",
                "مهارة", "مهارات", "تعلم هذه الطريقة", "احفظ الطريقة", "احفظها كمهارة",
                "حول هذه الخطوات إلى مهارة", "حوّل هذه الخطوات إلى مهارة",
            ],
        );

        if has_programming {
            selected.push("programmer");
            if contains_any(
                &text,
                &[
                    "review",
                    "audit",
                    "راجع الكود",
                    "مراجعة الكود",
                    "راجع التطبيق",
                    "راجع",
                    "مراجعة",
                    "دقق",
                    "دقّق",
                    "افحص الكود",
                ],
            ) {
                selected.push("code_reviewer");
            }
        }
        if has_math {
            selected.push("math_science");
        }
        if has_research {
            selected.push("researcher");
        }
        if has_writing {
            selected.push("writer");
        }
        if has_data {
            selected.push("data_analyst");
        }
        if has_files {
            selected.push("file_operator");
        }
        if has_device {
            selected.push("device_operator");
        }
        if has_communications {
            selected.push("communications");
        }
        if has_skill_learning {
            selected.push("skill_curator");
        }

        selected.sort_unstable();
        selected.dedup();

        if selected.is_empty() {
            selected.push("general");
        }

        let specialized_count = selected.len();
        if specialized_count > 1 || (has_compound_intent && specialized_count == 1) {
            selected.insert(0, "planner");
        }
        if has_programming || has_data || (has_compound_intent && specialized_count > 1) {
            selected.push("verifier");
        }

        selected.retain(|id| self.catalog.contains(*id));
        selected.dedup();

        let selected_names = selected
            .iter()
            .map(|id| {
                self.catalog
                    .get(*id)
                    .map(|agent| agent.name.as_str())
                    .unwrap_or(*id)
            })
            .collect::<Vec<_>>();
        let rationale = if selected.len() == 1 && selected[0] == "general" {
            "لم يتم تحديد تخصص متخصص؛ سيستخدم ليو المساعد العام لتجنب إشراك وكلاء غير ضروريين.".to_owned()
        } else if selected.iter().any(|id| *id == "planner") {
            "الطلب يتضمن عدة خطوات أو مجالات؛ سينسق المخطط أصغر فريق متخصص مناسب.".to_owned()
        } else {
            format!(
                "اختير الوكيل الأقرب إلى الطلب: {}.",
                selected_names.join("، ")
            )
        };

        AgentSelection {
            selected_agent_ids: selected.into_iter().map(str::to_owned).collect(),
            rationale,
        }
    }

    /// Builds a validated first-pass DAG for the automatically selected team.
    /// This produces a plan only; a separate execution coordinator must still
    /// check capability grants and obtain action approvals before running tools.
    pub fn build_plan(
        &self,
        task_id: &str,
        request: &str,
    ) -> Result<PlannedWork, PlanValidationError> {
        let goal = request.trim();
        if goal.is_empty() {
            return Err(PlanValidationError::EmptyGoal);
        }
        if goal.chars().count() > MAX_TASK_GOAL_CHARS {
            return Err(PlanValidationError::GoalTooLong { max_chars: MAX_TASK_GOAL_CHARS });
        }
        let selection = self.route(goal);
        let has_planner = selection.selected_agent_ids.iter().any(|id| id == "planner");
        let has_verifier = selection.selected_agent_ids.iter().any(|id| id == "verifier");
        let specialists = selection
            .selected_agent_ids
            .iter()
            .filter(|id| id.as_str() != "planner" && id.as_str() != "verifier")
            .cloned()
            .collect::<Vec<_>>();

        let mut steps = Vec::with_capacity(selection.selected_agent_ids.len());
        if has_planner {
            let planner = self
                .catalog
                .get("planner")
                .expect("built-in planner exists");
            steps.push(TaskStep {
                id: "plan".to_owned(),
                objective: format!("قسّم الهدف إلى خطوات قابلة للتنفيذ: {goal}"),
                agent_id: planner.id.clone(),
                depends_on: Vec::new(),
                required_capabilities: planner.required_capabilities.clone(),
            });
        }

        let mut specialist_step_ids = Vec::with_capacity(specialists.len());
        for (index, agent_id) in specialists.iter().enumerate() {
            let agent = self
                .catalog
                .get(agent_id)
                .ok_or_else(|| PlanValidationError::UnknownAgent {
                    step_id: format!("specialist_{index}"),
                    agent_id: agent_id.clone(),
                })?;
            let step_id = format!("specialist_{index}");
            steps.push(TaskStep {
                id: step_id.clone(),
                objective: format!("نفّذ الجزء المتعلق بتخصص {} من الهدف: {goal}", agent.name),
                agent_id: agent.id.clone(),
                depends_on: if has_planner {
                    vec!["plan".to_owned()]
                } else {
                    Vec::new()
                },
                required_capabilities: agent.required_capabilities.clone(),
            });
            specialist_step_ids.push(step_id);
        }

        if has_verifier {
            let verifier = self
                .catalog
                .get("verifier")
                .expect("built-in verifier exists");
            steps.push(TaskStep {
                id: "verify".to_owned(),
                objective: format!("تحقق من جودة واكتمال النتيجة بالنسبة للهدف: {goal}"),
                agent_id: verifier.id.clone(),
                depends_on: specialist_step_ids.clone(),
                required_capabilities: verifier.required_capabilities.clone(),
            });
        }

        let plan = TaskPlan {
            id: task_id.to_owned(),
            goal: goal.to_owned(),
            state: leo_shared::TaskState::Planned,
            steps,
        };
        validate_task_plan(&plan, &self.catalog)?;
        Ok(PlannedWork {
            plan,
            agents: selection.selected_agent_ids,
        })
    }
}

fn contains_any(normalized_text: &str, needles: &[&str]) -> bool {
    needles
        .iter()
        .any(|needle| normalized_text.contains(&normalize_request(needle)))
}

/// Normalize Arabic orthography and whitespace before deterministic routing.
/// This is intentionally a small, dependency-free normalization layer; it is
/// not a stemmer and must not be treated as semantic understanding.
fn normalize_request(value: &str) -> String {
    let mut normalized = String::with_capacity(value.len());
    for character in value.chars() {
        match character {
            '\u{0640}' => continue, // tatweel
            '\u{064B}'..='\u{065F}' | '\u{0670}' | '\u{06D6}'..='\u{06ED}' => continue,
            'أ' | 'إ' | 'آ' | 'ٱ' => normalized.push('ا'),
            'ؤ' => normalized.push('و'),
            'ئ' | 'ى' => normalized.push('ي'),
            'ة' => normalized.push('ه'),
            other => normalized.extend(other.to_lowercase()),
        }
    }
    normalized.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlanValidationError {
    EmptyGoal,
    GoalTooLong { max_chars: usize },
    EmptySteps,
    DuplicateStepId(String),
    UnknownAgent { step_id: String, agent_id: String },
    UnknownDependency { step_id: String, dependency_id: String },
    SelfDependency(String),
    InvalidInitialResult(String),
    DependencyCycle,
}

impl fmt::Display for PlanValidationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyGoal => write!(formatter, "task goal cannot be empty"),
            Self::GoalTooLong { max_chars } => write!(formatter, "task goal exceeds {max_chars} characters"),
            Self::EmptySteps => write!(formatter, "task plan must contain at least one step"),
            Self::DuplicateStepId(id) => write!(formatter, "duplicate task step id: {id}"),
            Self::UnknownAgent { step_id, agent_id } => {
                write!(formatter, "step {step_id} references unknown agent {agent_id}")
            }
            Self::UnknownDependency { step_id, dependency_id } => write!(
                formatter,
                "step {step_id} references unknown dependency {dependency_id}"
            ),
            Self::SelfDependency(id) => write!(formatter, "step {id} depends on itself"),
            Self::InvalidInitialResult(id) => write!(formatter, "resume state contains an invalid result for step {id}"),
            Self::DependencyCycle => write!(formatter, "task plan contains a dependency cycle"),
        }
    }
}

impl std::error::Error for PlanValidationError {}

pub fn validate_plan(
    goal: &str,
    steps: &[TaskStep],
    catalog: &AgentCatalog,
) -> Result<(), PlanValidationError> {
    if goal.trim().is_empty() {
        return Err(PlanValidationError::EmptyGoal);
    }
    if goal.chars().count() > MAX_TASK_GOAL_CHARS {
        return Err(PlanValidationError::GoalTooLong { max_chars: MAX_TASK_GOAL_CHARS });
    }
    if steps.is_empty() {
        return Err(PlanValidationError::EmptySteps);
    }

    let mut step_ids = HashSet::with_capacity(steps.len());
    for step in steps {
        if !step_ids.insert(step.id.as_str()) {
            return Err(PlanValidationError::DuplicateStepId(step.id.clone()));
        }
        if !catalog.contains(&step.agent_id) {
            return Err(PlanValidationError::UnknownAgent {
                step_id: step.id.clone(),
                agent_id: step.agent_id.clone(),
            });
        }
    }

    let mut indegree = HashMap::<&str, usize>::with_capacity(steps.len());
    let mut dependents = HashMap::<&str, Vec<&str>>::with_capacity(steps.len());
    for step in steps {
        indegree.insert(step.id.as_str(), 0);
    }
    for step in steps {
        for dependency in &step.depends_on {
            if dependency == &step.id {
                return Err(PlanValidationError::SelfDependency(step.id.clone()));
            }
            if !step_ids.contains(dependency.as_str()) {
                return Err(PlanValidationError::UnknownDependency {
                    step_id: step.id.clone(),
                    dependency_id: dependency.clone(),
                });
            }
            *indegree.get_mut(step.id.as_str()).expect("step id inserted") += 1;
            dependents
                .entry(dependency.as_str())
                .or_default()
                .push(step.id.as_str());
        }
    }

    let mut ready = VecDeque::new();
    for (step_id, degree) in &indegree {
        if *degree == 0 {
            ready.push_back(*step_id);
        }
    }
    let mut visited = 0usize;
    while let Some(step_id) = ready.pop_front() {
        visited += 1;
        if let Some(children) = dependents.get(step_id) {
            for child in children {
                let degree = indegree.get_mut(child).expect("dependent step exists");
                *degree -= 1;
                if *degree == 0 {
                    ready.push_back(child);
                }
            }
        }
    }
    if visited != steps.len() {
        return Err(PlanValidationError::DependencyCycle);
    }
    Ok(())
}

/// Convenience validation for a fully formed domain plan.
pub fn validate_task_plan(
    plan: &TaskPlan,
    catalog: &AgentCatalog,
) -> Result<(), PlanValidationError> {
    validate_plan(&plan.goal, &plan.steps, catalog)
}

#[cfg(test)]
mod tests {
    use super::*;
    use leo_shared::TaskState;

    fn router() -> AgentRouter {
        AgentRouter::built_in().expect("built-in catalog must be valid")
    }

    #[test]
    fn bundled_catalog_has_thirteen_builtin_agents_and_no_user_setup_requirement() {
        let catalog = AgentCatalog::built_in().unwrap();
        assert_eq!(catalog.agents.len(), 13);
        assert!(!catalog.user_agent_creation_required);
        assert_eq!(catalog.selection_policy, "automatic");
        assert_eq!(catalog.status, "active_catalog");
        assert!(catalog.contains("programmer"));
        assert!(catalog.contains("verifier"));
    }

    #[test]
    fn simple_math_request_uses_one_specialist() {
        let selection = router().route("احسب نهاية الدالة عندما x تقترب من صفر");
        assert_eq!(selection.selected_agent_ids, vec!["math_science"]);
    }

    #[test]
    fn multi_domain_task_uses_planner_and_relevant_specialists() {
        let selection = router().route(
            "أنشئ تطبيق Flutter ثم راجع الكود وشغّل الاختبارات",
        );
        assert!(selection.selected_agent_ids.contains(&"planner".to_owned()));
        assert!(selection.selected_agent_ids.contains(&"programmer".to_owned()));
        assert!(selection.selected_agent_ids.contains(&"code_reviewer".to_owned()));
        assert!(selection.selected_agent_ids.contains(&"verifier".to_owned()));
    }

    #[test]
    fn general_question_does_not_spawn_a_team() {
        let selection = router().route("ما الفرق بين الذاكرة والمهارات؟");
        assert_eq!(selection.selected_agent_ids, vec!["general"]);
    }

    #[test]
    fn learning_a_reusable_workflow_routes_to_skill_curator() {
        let selection = router().route("احفظ الطريقة التي استخدمناها كمهارة");
        assert_eq!(selection.selected_agent_ids, vec!["skill_curator"]);
    }

    #[test]
    fn opening_a_selected_file_routes_to_the_file_specialist() {
        let selection = router().route("افتح ملف PDF الذي سأختاره");
        assert_eq!(selection.selected_agent_ids, vec!["file_operator"]);
    }

    #[test]
    fn opening_an_installed_app_does_not_route_to_the_programmer() {
        let selection = router().route("افتح تطبيق الكاميرا");
        assert_eq!(selection.selected_agent_ids, vec!["device_operator"]);
    }

    #[test]
    fn calling_a_contact_routes_to_communications_not_device_automation() {
        let selection = router().route("اتصل بأحمد");
        assert_eq!(selection.selected_agent_ids, vec!["communications"]);
    }

    #[test]
    fn arabic_normalization_handles_alef_diacritics_and_taa_marbuta() {
        let selection = router().route("اِحْسَبْ نِهايَة الدّالَّة عند اقتراب x من الصفر");
        assert_eq!(selection.selected_agent_ids, vec!["math_science"]);
    }

    #[test]
    fn multi_agent_plan_has_planning_parallel_specialists_and_final_verification() {
        let work = router()
            .build_plan("task-42", "أنشئ تطبيق Flutter ثم راجع الكود وشغّل الاختبارات")
            .unwrap();
        assert_eq!(work.plan.id, "task-42");
        assert_eq!(work.plan.state, TaskState::Planned);
        let planner = work
            .plan
            .steps
            .iter()
            .find(|step| step.id == "plan")
            .unwrap();
        assert_eq!(planner.agent_id, "planner");
        let specialist_steps = work
            .plan
            .steps
            .iter()
            .filter(|step| step.id.starts_with("specialist_"))
            .collect::<Vec<_>>();
        assert!(specialist_steps.len() >= 2);
        assert!(specialist_steps
            .iter()
            .all(|step| step.depends_on == vec!["plan".to_owned()]));
        let verifier = work
            .plan
            .steps
            .iter()
            .find(|step| step.id == "verify")
            .unwrap();
        assert_eq!(verifier.agent_id, "verifier");
        assert_eq!(verifier.depends_on.len(), specialist_steps.len());
        assert!(validate_task_plan(&work.plan, &router().catalog).is_ok());
    }

    #[test]
    fn one_specialist_request_does_not_spawn_a_planner_team() {
        let work = router().build_plan("math-1", "احسب تكامل x من صفر إلى واحد").unwrap();
        assert_eq!(work.agents, vec!["math_science"]);
        assert_eq!(work.plan.steps.len(), 1);
        assert_eq!(work.plan.steps[0].agent_id, "math_science");
    }

    #[test]
    fn empty_request_cannot_create_a_plan() {
        assert_eq!(
            router().build_plan("empty", "  ").unwrap_err(),
            PlanValidationError::EmptyGoal
        );
    }


    #[test]
    fn oversized_task_goal_is_rejected_before_building_a_dag() {
        let oversized = "x".repeat(MAX_TASK_GOAL_CHARS + 1);
        assert!(matches!(
            router().build_plan("too-long", &oversized),
            Err(PlanValidationError::GoalTooLong { .. })
        ));
    }

    #[test]
    fn valid_task_plan_passes_dependency_validation() {
        let catalog = AgentCatalog::built_in().unwrap();
        let steps = vec![
            TaskStep {
                id: "plan".into(),
                objective: "Break down the task".into(),
                agent_id: "planner".into(),
                depends_on: vec![],
                required_capabilities: vec![],
            },
            TaskStep {
                id: "code".into(),
                objective: "Implement the code".into(),
                agent_id: "programmer".into(),
                depends_on: vec!["plan".into()],
                required_capabilities: vec!["workspace.write".into()],
            },
        ];
        assert!(validate_plan("Build a program", &steps, &catalog).is_ok());
    }

    #[test]
    fn cyclic_task_plan_is_rejected() {
        let catalog = AgentCatalog::built_in().unwrap();
        let steps = vec![
            TaskStep {
                id: "first".into(), objective: "First".into(), agent_id: "planner".into(),
                depends_on: vec!["second".into()], required_capabilities: vec![],
            },
            TaskStep {
                id: "second".into(), objective: "Second".into(), agent_id: "programmer".into(),
                depends_on: vec!["first".into()], required_capabilities: vec![],
            },
        ];
        assert_eq!(validate_plan("Cycle", &steps, &catalog), Err(PlanValidationError::DependencyCycle));
    }

    #[test]
    fn unknown_agent_is_rejected() {
        let catalog = AgentCatalog::built_in().unwrap();
        let steps = vec![TaskStep {
            id: "one".into(), objective: "Do work".into(), agent_id: "not-real".into(),
            depends_on: vec![], required_capabilities: vec![],
        }];
        assert!(matches!(validate_plan("Work", &steps, &catalog), Err(PlanValidationError::UnknownAgent { .. })));
    }

    #[test]
    fn full_domain_plan_is_supported() {
        let catalog = AgentCatalog::built_in().unwrap();
        let plan = TaskPlan {
            id: "task".into(), goal: "Solve and review".into(), state: TaskState::Planned,
            steps: vec![TaskStep {
                id: "solve".into(), objective: "Solve equation".into(), agent_id: "math_science".into(),
                depends_on: vec![], required_capabilities: vec!["compute.safe_math".into()],
            }],
        };
        assert!(validate_task_plan(&plan, &catalog).is_ok());
    }
}
