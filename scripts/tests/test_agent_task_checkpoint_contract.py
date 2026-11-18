from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AgentTaskCheckpointContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bridge = (ROOT / "core/bridge/src/api/simple.rs").read_text(encoding="utf-8")
        cls.coordinator = (ROOT / "core/orchestration/src/execution.rs").read_text(encoding="utf-8")
        cls.chat = (ROOT / "apps/leo_app/lib/features/chat/chat_page.dart").read_text(encoding="utf-8")
        cls.store = (ROOT / "apps/leo_app/lib/core/tools/agent_task_checkpoint_store.dart").read_text(encoding="utf-8")
        cls.receipt = (ROOT / "apps/leo_app/lib/core/tools/agent_task_continuation.dart").read_text(encoding="utf-8")
        cls.android_script = (ROOT / "scripts/prepare_android_runner.sh").read_text(encoding="utf-8")
        cls.plan = (ROOT / "docs/planning/LEO_AI_DEVELOPMENT_PLAN_v0.1.0.md").read_text(encoding="utf-8")

    def test_initial_plan_checkpoint_is_emitted_before_first_model_call(self):
        block = self.bridge.split("// Persist the plan before the first model invocation", 1)[1]
        self.assertLess(block.index("on_event(ExecutionEvent::ProgressCheckpoint"), block.index("coordinator.execute_with_initial_results"))
        self.assertIn("results: initial_results.clone()", block)
        self.assertIn("ProgressCheckpoint { results: Vec<AgentStepResult> }", self.coordinator)
        self.assertIn("ProgressCheckpoint { results: checkpoint_results }", self.coordinator)

    def test_checkpoint_is_bounded_strictly_validated_and_restored(self):
        self.assertIn("MAX_AGENT_CHECKPOINT_BYTES: usize = 256 * 1024", self.bridge)
        self.assertIn("fn encode_agent_task_checkpoint", self.bridge)
        self.assertIn("fn decode_agent_checkpoint", self.bridge)
        self.assertIn("validate_task_plan(&plan, &catalog)", self.bridge)
        self.assertIn("checkpoint يحتوي نتيجة دون اعتمادها السابق", self.bridge)
        self.assertIn("AGENT_RESTORE_START", self.bridge)
        self.assertIn("parse_agent_restore_receipt", self.bridge)
        self.assertIn("checkpoint.state != \"running\" || checkpoint.proposal.is_some()", self.bridge)
        self.assertNotIn("pending_agent_continuations", self.bridge)
        self.assertNotIn("MAX_PENDING_AGENT_CONTINUATIONS", self.bridge)

    def test_secure_checkpoint_store_uses_os_secure_storage_and_strict_retention(self):
        pubspec = (ROOT / "apps/leo_app/pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("flutter_secure_storage: ^11.2.0", pubspec)
        self.assertIn("FlutterSecureStorage()", self.store)
        self.assertIn("maxRecords = 8", self.store)
        self.assertIn("maxCheckpointBytes = 256 * 1024", self.store)
        self.assertIn("maxStoredBytes = 640 * 1024", self.store)
        self.assertIn("Duration(days: 7)", self.store)
        self.assertIn("Duplicate task checkpoint IDs", self.store)
        self.assertIn("AgentTaskCheckpointState.readyToResume", self.store)

    def test_ambiguous_external_action_is_never_automatically_replayed(self):
        self.assertIn("confirmInterruptedAction", self.store)
        self.assertIn("تحققت — متابعة", self.chat)
        self.assertIn("لن يعيده Leo تلقائياً", self.chat)
        self.assertIn("إذا كان الإجراء قيد الانتظار", self.chat) if "إذا كان الإجراء قيد الانتظار" in self.chat else None
        self.assertIn("encodeRestore", self.receipt)
        self.assertIn("checkpoint['state'] != 'running'", self.receipt)
        self.assertIn("state == AppLifecycleState.hidden", self.chat)
        self.assertIn("_preserveAgentTaskCheckpointsOnCancel", self.chat)

    def test_resume_receipt_embeds_checkpoint_and_matches_proposal(self):
        for token in ("'checkpoint': checkpoint", "checkpoint['task_id'] != taskId", "checkpoint['state'] != 'awaiting_action'", "maxEnvelopeBytes = 320 * 1024"):
            self.assertIn(token, self.receipt)
        self.assertIn("durableCheckpoint.toolCallId != call.id", self.chat)
        self.assertIn("durableCheckpoint.toolName != call.name", self.chat)
        self.assertIn("markActionSucceeded", self.chat)

    def test_android_runner_disables_backup_for_keystore_bound_storage(self):
        self.assertIn('android:allowBackup="false"', self.android_script)
        self.assertIn("leo_backup_rules.xml", self.android_script)
        self.assertIn("leo_data_extraction_rules.xml", self.android_script)
        self.assertIn('<exclude domain="sharedpref" path="." />', self.android_script)

    def test_checkpoint_writer_validates_input_before_constructing_record(self):
        block = self.store.split("Future<void> saveCheckpoint(", 1)[1].split(
            "Future<AgentTaskCheckpointRecord> markActionSucceeded", 1
        )[0]
        self.assertIn("_validateCheckpoint(decoded, checkpointJson);", block)
        self.assertNotIn("record.checkpointJson", block)
        self.assertLess(block.index("_validateCheckpoint(decoded, checkpointJson)"), block.index("final record ="))

    def test_readme_describes_durable_recovery_not_legacy_volatile_state(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("encrypted in OS-backed secure storage", readme)
        self.assertIn("never repeats it automatically", readme)
        self.assertNotIn("Pending continuation data is kept only in process memory", readme)

    def test_lifecycle_and_checkpoint_failures_preserve_only_last_known_good_state(self):
        self.assertIn("_agentCheckpointPersistError != null", self.chat)
        self.assertIn("_preserveAgentTaskCheckpointsOnCancel.remove(taskId)", self.chat)
        self.assertIn("_preserveAgentTaskCheckpointsOnCancel.remove(taskId);", self.chat)

    def test_checkpoint_dart_tests_cover_store_and_receipt(self):
        store_tests = ROOT / "apps/leo_app/test/core/agent_task_checkpoint_store_test.dart"
        receipt_tests = ROOT / "apps/leo_app/test/core/agent_task_continuation_test.dart"
        self.assertTrue(store_tests.is_file())
        self.assertTrue(receipt_tests.is_file())
        self.assertIn("persists and restores a running checkpoint", store_tests.read_text(encoding="utf-8"))
        self.assertIn("ambiguous interrupted action", store_tests.read_text(encoding="utf-8"))
        self.assertIn("restore envelope accepts only", receipt_tests.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
