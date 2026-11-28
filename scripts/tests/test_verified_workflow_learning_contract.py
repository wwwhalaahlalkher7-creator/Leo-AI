from __future__ import annotations

import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from dart_source import flat  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


class VerifiedWorkflowLearningContractTests(unittest.TestCase):
    def read(self, path: str) -> str:
        return (ROOT / path).read_text(encoding="utf-8")

    def test_learning_requires_a_terminal_user_verified_run(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_learning_service.dart")
        self.assertIn("proposeFromVerifiedRun", service)
        self.assertIn("run.status != LeoSkillRunStatus.verified", service)
        self.assertIn("LeoSkillStepReviewStatus.confirmed", service)
        self.assertIn("run.steps.length < 2", service)

    def test_source_skill_identity_and_version_are_bound_to_the_run(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_learning_service.dart")
        self.assertIn(flat("candidate.id == run.skillId"), flat(service))
        self.assertIn(flat("candidate.version == run.skillVersion"), flat(service))
        self.assertIn(flat("entry.value.instruction == sourceSkill!.steps[entry.key]"), flat(service))
        self.assertIn(flat("!sourceSkill.isValidated"), flat(service))
        self.assertIn(flat("LeoSkillStatus.active, LeoSkillStatus.disabled"), flat(service))

    def test_learning_input_is_data_minimized_and_excludes_sensitive_operational_data(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_learning_service.dart")
        self.assertIn("_sanitizeLearningText", service)
        self.assertIn("[بريد محذوف]", service)
        self.assertIn("[مسار محذوف]", service)
        self.assertIn("[رقم محذوف]", service)
        self.assertIn("[سر محذوف]", service)
        self.assertIn("[اسم ملف محذوف]", service)
        self.assertIn("[عنوان شبكة محذوف]", service)
        self.assertIn("[معرف جهاز محذوف]", service)
        self.assertIn("confirmed_steps", service)
        self.assertNotIn("run.lastEvent", service)
        self.assertNotIn("step.note", service)
        self.assertNotIn("run.toolResult", service)

    def test_learning_never_passes_chat_transcript_or_tool_arguments_from_a_run(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_learning_service.dart")
        block = service.split("Future<LeoSkill> proposeFromVerifiedRun", 1)[1].split("String _buildTranscript", 1)[0]
        self.assertNotIn("_buildTranscript", block)
        self.assertNotIn("conversation.messages", block)
        self.assertNotIn("toolArguments", block)
        self.assertNotIn("toolResult", block)
        self.assertNotIn("fileContents", block)

    def test_generated_capabilities_must_be_a_subset_of_source_capabilities(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_learning_service.dart")
        self.assertIn("allowedCapabilities: allowedCapabilities", service)
        self.assertIn("!allowedCapabilities.contains(value)", service)
        self.assertIn("sourceSkill.requiredCapabilities.toSet()", service)

    def test_derived_proposals_are_inactive_and_have_provenance(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_learning_service.dart")
        self.assertIn("sourceTaskId: sourceTaskId", service)
        self.assertIn("verified-run:$taskId", service)
        self.assertIn("لا تمنح الصلاحيات ولا تنفذ أي أداة", service)
        self.assertIn("اقتراحاً غير نشط", service)

    def test_repository_prevents_duplicate_proposals_from_the_same_run(self):
        repository = self.read("apps/leo_app/lib/core/skills/skill_repository.dart")
        self.assertIn("cleanSourceTaskId.startsWith('verified-run:')", repository)
        self.assertIn("item.sourceTaskId == cleanSourceTaskId", repository)

    def test_read_only_run_evidence_port_is_used(self):
        execution = self.read("apps/leo_app/lib/core/skills/skill_execution_service.dart")
        learning = self.read("apps/leo_app/lib/core/skills/skill_learning_service.dart")
        self.assertIn("abstract interface class SkillRunEvidenceReader", execution)
        self.assertIn("implements SkillRunEvidenceReader", execution)
        self.assertIn("SkillRunEvidenceReader? runRepository", learning)

    def test_skill_library_requires_explicit_consent_and_local_runtime(self):
        library = self.read("apps/leo_app/lib/features/skills/skill_library_page.dart")
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        self.assertIn("_learnFromCompletedRun", library)
        self.assertIn("استخلاص محلي", library)
        self.assertIn("لن تُرسل المحادثة أو هدف المهمة", library)
        self.assertIn("run.status == LeoSkillRunStatus.verified", library)
        self.assertIn("runtime: _runtime", chat)
        self.assertIn("runRepository: _skillRunRepository", chat)

    def test_derived_proposal_ui_is_available_only_for_verified_runs(self):
        library = self.read("apps/leo_app/lib/features/skills/skill_library_page.dart")
        self.assertIn(flat("run.status == LeoSkillRunStatus.verified && widget.runtime != null"), flat(library))
        self.assertIn(flat("proposeFromVerifiedRun(run.taskId)"), flat(library))


if __name__ == "__main__":
    unittest.main(verbosity=2)
