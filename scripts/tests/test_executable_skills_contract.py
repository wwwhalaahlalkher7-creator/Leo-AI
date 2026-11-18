from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ExecutableSkillsContractTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (ROOT / name).read_text(encoding="utf-8")

    def test_skill_runs_are_encrypted_bounded_and_do_not_duplicate_the_user_goal(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_execution_service.dart")
        self.assertIn("FlutterSecureStorage()", service)
        self.assertIn("leo.skill_runs.v1", service)
        self.assertIn("maxRuns = 20", service)
        self.assertIn("maxStoredBytes = 512 * 1024", service)
        self.assertIn("retention = Duration(days: 30)", service)
        self.assertNotIn("'goal': goal", service)
        self.assertNotIn("final String goal;", service)
        self.assertIn("_isEvictable", service)
        self.assertIn("سجل تشغيل المهارات ممتلئ بمهام نشطة", service)

    def test_only_current_active_validated_skill_version_can_execute(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_execution_service.dart")
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        self.assertIn("skill.status != LeoSkillStatus.active || !skill.isValidated", service)
        self.assertIn("skill.id != run.skillId || skill.version != run.skillVersion", service)
        self.assertIn("latestSkill.status != LeoSkillStatus.active", chat)
        self.assertIn("latestSkill.version != selectedSkill.version", chat)
        self.assertIn("_confirmSkillExecution(selectedSkill)", chat)

    def test_skill_contract_is_untrusted_and_does_not_grant_capabilities(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_execution_service.dart")
        self.assertIn("لا تنفذ سكربتات أو أوامر shell", service)
        self.assertIn("كل إجراء خارجي منفصل ويحتاج موافقة المستخدم من Capability Hub", service)
        self.assertIn("required capabilities بيانات وصفية فقط، ولا تمنح الصلاحيات", service)
        self.assertIn("لا تدّع وجود تراجع تلقائي بعد نجاح الكتابة", service)
        self.assertIn("maxExecutionContextChars = 8 * 1024", service)

    def test_run_lifecycle_has_review_gate_and_bounded_action_approvals(self):
        service = self.read("apps/leo_app/lib/core/skills/skill_execution_service.dart")
        self.assertIn("approvals > 3", service)
        self.assertIn("current.status != LeoSkillRunStatus.awaitingReview", service)
        self.assertIn("LeoSkillRunStatus.needsChanges", service)
        self.assertIn("LeoSkillRunStatus.verified", service)
        self.assertIn("final hasMissed =", service)
        self.assertIn("enum LeoSkillStepReviewStatus { pending, confirmed, notCompleted }", service)

    def test_chat_persists_skill_run_before_agent_start_and_blocks_unsafe_tool_handoff(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        self.assertIn("createdRun = await _skillRunRepository.create", chat)
        self.assertIn("buildExecutionContext(", chat)
        self.assertIn("if (_skillRunPersistError != null)", chat)
        self.assertIn("awaitingApproval", chat)
        self.assertIn("_handleAgentToolProposal(event, taskId)", chat)
        self.assertIn("_agentCheckpointPersistError != null", chat)
        self.assertIn("CapabilityHubService()", chat)

    def test_recovery_refuses_finalized_or_mismatched_skill_runs(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        self.assertIn("LeoSkillRunStatus.awaitingReview", chat)
        self.assertIn("LeoSkillRunStatus.verified", chat)
        self.assertIn("LeoSkillRunStatus.failed", chat)
        self.assertIn("حالة الموافقة لا تطابق نقطة الاستعادة", chat)
        self.assertIn("_handleAgentStreamFailure", chat)
        self.assertIn("preserveCheckpoint ? LeoSkillRunStatus.paused : LeoSkillRunStatus.failed", chat)

    def test_stream_failure_preserves_only_an_existing_safe_checkpoint(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        block = chat.split("Future<void> _handleAgentStreamFailure", 1)[1].split("Future<void> _resumeAgentTask", 1)[0]
        self.assertIn("_hasDurableAgentCheckpoint(taskId)", block)
        self.assertIn("_agentTaskCheckpointStore.get(taskId)", chat)
        self.assertIn("LeoSkillRunStatus.paused", block)
        self.assertIn("LeoSkillRunStatus.failed", block)
        self.assertIn("_agentTaskCheckpointStore.remove(taskId)", block)

    def test_skill_preview_discloses_full_guidance_and_manual_acceptance_review(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        preview = chat.split("Future<bool> _confirmSkillExecution", 1)[1].split("Future<void> _recordSkillRunStatus", 1)[0]
        self.assertIn("SelectableText(skill.instructions)", preview)
        self.assertIn("أمثلة التحقق لا تُشغّل آلياً", preview)
        self.assertIn("كل إجراء خارجي", preview)

    def test_skill_library_discloses_that_review_is_user_assertion(self):
        library = self.read("apps/leo_app/lib/features/skills/skill_library_page.dart")
        self.assertIn("تأكيدك يسجل مراجعتك ولا يمثل فحصاً تقنياً مستقلاً", library)
        self.assertIn("LeoSkillRunStatus.awaitingReview", library)
        self.assertIn("LeoSkillRunStatus.needsChanges", library)
        self.assertIn("LeoSkillRunStatus.verified", library)


if __name__ == "__main__":
    unittest.main(verbosity=2)
