import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ModelResourcePolicyContractTests(unittest.TestCase):
    def test_resource_estimator_matches_native_admission_formula(self):
        policy = (ROOT / "apps/leo_app/lib/core/resources/model_resource_policy.dart").read_text(encoding="utf-8")
        native = (ROOT / "native/llama/src/llama_probe.cpp").read_text(encoding="utf-8")
        self.assertIn("modelFileSizeBytes ~/ BigInt.from(8)", policy)
        self.assertIn("BigInt.from(384) * _bytesPerMiB", policy)
        self.assertIn("BigInt.from(128) * _bytesPerMiB", policy)
        self.assertIn("model_bytes / 8ULL", native)
        self.assertIn("384ULL * kMiB", native)
        self.assertIn("128ULL * kMiB", native)
        self.assertIn("MemAvailable:", native)
        self.assertIn("GlobalMemoryStatusEx", native)
        self.assertIn("kMaxThreads = 4", native)

    def test_model_load_ui_exposes_context_thread_and_memory_preflight(self):
        page = (ROOT / "apps/leo_app/lib/features/models/model_library_page.dart").read_text(encoding="utf-8")
        self.assertIn("تهيئة موارد النموذج", page)
        self.assertIn("contextTokens: configuration.contextTokens", page)
        self.assertIn("threads: configuration.threads", page)
        self.assertIn("تقدير الذاكرة المطلوبة", page)
        self.assertIn("سيعيد المحرك فحص الذاكرة الفعلية قبل التحميل", page)

    def test_speech_workers_use_a_smaller_dynamic_cpu_budget(self):
        policy = (ROOT / "apps/leo_app/lib/core/resources/model_resource_policy.dart").read_text(encoding="utf-8")
        voice = (ROOT / "apps/leo_app/lib/core/voice/leo_voice_service.dart").read_text(encoding="utf-8")
        self.assertIn("recommendedVoiceThreads", policy)
        self.assertEqual(voice.count("ModelResourcePolicy.recommendedVoiceThreads("), 3)
        self.assertIn("maximumVoiceThreads = 2", policy)

    def test_chat_warns_before_asr_when_local_chat_model_is_loaded(self):
        chat = (ROOT / "apps/leo_app/lib/features/chat/chat_page.dart").read_text(encoding="utf-8")
        self.assertIn("_confirmVoiceResourcePressure", chat)
        self.assertIn("diagnostics.modelLoaded", chat)
        self.assertIn("لن يفرّغ Leo نموذج المحادثة تلقائياً", chat)
        self.assertIn("runtimeDiagnostics()", chat)

    def test_voice_evaluation_template_targets_this_release(self):
        template = json.loads((ROOT / "config/voice_eval_template.json").read_text(encoding="utf-8"))
        self.assertEqual(template["metadata"]["app_version"], (ROOT / "config/VERSION").read_text(encoding="utf-8").strip())


if __name__ == "__main__":
    unittest.main()
