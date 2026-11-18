from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RuntimeResilienceContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_context_planner_is_integrated_before_normal_generation(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        planner = self.read("apps/leo_app/lib/core/chat/conversation_context_planner.dart")
        self.assertIn("_contextPlanner.plan(", chat)
        self.assertIn("inputBudgetTokens: _activeInputBudgetTokens", chat)
        self.assertIn("messages: plan.messages", chat)
        self.assertIn("maxNewTokens: _activeMaxNewTokens", chat)
        self.assertIn("older complete turns were omitted", planner)

    def test_capability_policy_remains_after_skill_context(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        self.assertIn("final lastSystemIndex = requestMessages.lastIndexWhere(", chat)
        self.assertIn("requestMessages.insert(\n      lastSystemIndex + 1,", chat)
        helper_start = chat.index("void _insertSystemContextBeforeToolPolicy(")
        helper_end = chat.index("String _buildAgentConversationContext(", helper_start)
        helper = chat[helper_start:helper_end]
        self.assertIn("final policyIndex = messages.lastIndexWhere(", helper)
        self.assertIn("policyIndex < 0 ? 0 : policyIndex", helper)
        self.assertGreaterEqual(chat.count("_insertSystemContextBeforeToolPolicy("), 3)

    def test_continuation_and_recovery_use_the_active_context_output_budget(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        self.assertNotIn("maxNewTokens: 1024", chat)
        self.assertGreaterEqual(chat.count("maxNewTokens: _activeMaxNewTokens"), 4)
        resume_start = chat.index("Future<void> _resumeAgentTask(")
        resume_end = chat.index("Future<void> _refreshRestorableAgentTasks(", resume_start)
        resume = chat[resume_start:resume_end]
        self.assertIn("await _refreshRuntimeContextLimits()", resume)
        restore_start = chat.index("Future<void> _resumeRestoredAgentTask(")
        restore_end = chat.index("Future<void> _discardRestoredAgentTask(", restore_start)
        restore = chat[restore_start:restore_end]
        self.assertIn("await _refreshRuntimeContextLimits()", restore)
        self.assertIn("_activeInputBudgetTokens", chat)

    def test_dispose_marks_inflight_runtime_attempt_as_cancelled_for_metrics(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        start = chat.index("void dispose()")
        end = chat.index("Future<void> _send(", start)
        dispose = chat[start:end]
        self.assertIn("if (requestId != null)", dispose)
        self.assertIn("_runtimeTerminalReceived = true", dispose)
        self.assertIn("_recordRuntimeBenchmark(\n        succeeded: false,", dispose)
        self.assertIn("_runtime.cancel(requestId)", dispose)

    def test_context_planner_keeps_pinned_system_messages_and_latest_turn(self):
        planner = self.read("apps/leo_app/lib/core/chat/conversation_context_planner.dart")
        self.assertIn("message.role == 'system'", planner)
        self.assertIn("message.role == 'user'", planner)
        self.assertIn("final lastTurn = turns.last", planner)
        self.assertIn("never partially retained", planner.lower())
        self.assertIn("ConversationContextException", planner)

    def test_context_budget_uses_actual_loaded_model_context_when_available(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        bridge = self.read("core/bridge/src/api/simple.rs")
        self.assertIn("diagnostics.contextTokens", chat)
        self.assertIn("pub context_tokens: Option<u32>", bridge)
        self.assertIn("context_tokens: status.context_tokens", bridge)
        self.assertIn("_activeMaxNewTokens", chat)

    def test_long_chat_agent_context_no_longer_uses_blind_last_eighteen_cut(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        start = chat.index("String _buildAgentConversationContext(")
        end = chat.index("Future<void> _cancelAgentTask(", start)
        block = chat[start:end]
        self.assertIn("for (final message in messages)", block)
        self.assertNotIn("sublist(messages.length - 18)", block)

    def test_runtime_measurements_are_opt_in_and_metadata_only(self):
        store = self.read("apps/leo_app/lib/core/diagnostics/runtime_benchmark_store.dart")
        self.assertIn("get isEnabled", store)
        self.assertIn("?? false", store)
        self.assertIn("maximumRecords = 80", store)
        self.assertIn("maximumSerializedBytes", store)
        self.assertIn("output_characters", store)
        self.assertNotIn("'prompt':", store)
        self.assertNotIn("'answer':", store)
        self.assertNotIn("'conversation_id':", store)
        self.assertIn("recordIfEnabled", store)

    def test_runtime_benchmark_collection_does_not_affect_chat_result(self):
        chat = self.read("apps/leo_app/lib/features/chat/chat_page.dart")
        self.assertIn("_persistRuntimeBenchmark", chat)
        self.assertIn("Diagnostics must never affect the actual conversation result", chat)
        self.assertIn("_runtimeBenchmarkOptedIn", chat)

    def test_model_library_disables_mutating_session_operations_during_generation(self):
        page = self.read("apps/leo_app/lib/features/models/model_library_page.dart")
        self.assertIn("_diagnostics?.generationActive", page)
        self.assertIn("!(diagnostics?.generationActive ?? false)", page)
        self.assertIn("قياسات أداء المحرك", page)
        self.assertIn("حرف/ث", page)

    def test_model_library_refresh_is_safe_after_route_disposal(self):
        page = self.read("apps/leo_app/lib/features/models/model_library_page.dart")
        start = page.index("Future<void> _refresh() async {")
        end = page.index("Future<void> _importModel()", start)
        refresh = page[start:end]
        self.assertIn("if (!mounted) return;", refresh)
        self.assertIn("if (!mounted) return;\n      setState", refresh)
        self.assertIn("تحديث القياسات", page)

    def test_benchmark_throughput_counts_only_successful_outputs(self):
        store = self.read("apps/leo_app/lib/core/diagnostics/runtime_benchmark_store.dart")
        self.assertIn("final completedRecords = records.where((item) => item.succeeded)", store)
        self.assertIn("completedRecords.fold<int>", store)
        self.assertIn("successRatePercent: successful * 100 / records.length", store)

    def test_rust_remembers_cancel_before_native_generation_callback(self):
        runtime = self.read("core/runtime/src/local_llama_runtime.rs")
        cancel_start = runtime.index("fn cancel(&self, request_id: &str)")
        cancel_end = runtime.index("\n    }", cancel_start)
        cancel = runtime[cancel_start:cancel_end]
        self.assertIn("mark_active_request_cancelled(request_id)", cancel)
        self.assertIn("let _ = engine::cancel_native_generation()", cancel)
        self.assertIn("active.cancel_requested = true", runtime)
        self.assertIn("active.cancel_requested = false", runtime)
        callback_start = runtime.index('unsafe extern "C" fn on_native_token(')
        callback_end = runtime.index("#[cfg(test)]", callback_start)
        callback = runtime[callback_start:callback_end]
        self.assertIn("active_request_cancel_requested(&state.request_id)", callback)
        self.assertIn("let _ = engine::cancel_native_generation()", callback)
        self.assertIn("cancellation_is_remembered_before_native_start_callback", runtime)

    def test_native_session_mutations_use_nonblocking_lock(self):
        native = self.read("native/llama/src/llama_probe.cpp")
        self.assertGreaterEqual(native.count("std::unique_lock<std::mutex> lock(session_mutex, std::try_to_lock)"), 4)
        self.assertIn("kGenerationReserveBytes", native)
        self.assertIn("available_before_generation < kGenerationReserveBytes", native)
        self.assertIn("session_context_token_count.store(loaded_context_tokens", native)
        self.assertIn("session_context_token_count.load(std::memory_order_acquire)", native)

    def test_native_generation_is_cancellable_during_memory_preflight(self):
        native = self.read("native/llama/src/llama_probe.cpp")
        guard = native.index("GenerationLifecycle generation_lifecycle;")
        preflight = native.index("read_available_memory(available_before_generation)")
        cancellation_check = native.index("أُوقف التوليد أثناء فحص الذاكرة", preflight)
        self.assertLess(guard, preflight)
        self.assertLess(preflight, cancellation_check)
        runner = self.read("scripts/tests/native_adapter_contract_runner.py")
        self.assertIn("LEO_TEST_CANCEL_DURING_MEMORY_CHECK", runner)
        self.assertIn("cancelled_during_preflight.start_events == 0", runner)

    def test_native_contract_injects_contention_and_low_memory(self):
        runner = self.read("scripts/tests/native_adapter_contract_runner.py")
        self.assertIn("unload_on_start", runner)
        self.assertIn("load_on_start", runner)
        self.assertIn('"65536"', runner)
        self.assertIn("== -11", runner)
        self.assertIn("== -8", runner)

    def test_native_thread_cap_matches_shared_resource_policy(self):
        native = self.read("native/llama/src/llama_probe.cpp")
        rust = self.read("core/runtime/src/native/engine.rs")
        policy = self.read("apps/leo_app/lib/core/resources/model_resource_policy.dart")
        self.assertIn("kMaxThreads = 4", native)
        self.assertIn("1..=4", rust)
        self.assertIn("maximumModelThreads = 4", policy)


if __name__ == "__main__":
    unittest.main()
