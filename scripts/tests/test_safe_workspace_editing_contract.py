from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class SafeWorkspaceEditingContractTests(unittest.TestCase):
    def test_capability_is_alpha_enabled_for_only_scoped_workspace_files(self):
        policy = json.loads(read("config/leo_capability_policy_v0.2.json"))
        capability = next(item for item in policy["capabilities"] if item["id"] == "files.write")
        self.assertTrue(capability["alpha_supported"])
        self.assertEqual(capability["grant_scope"], "selected_workspace")
        self.assertEqual(capability["risk"], "high")
        self.assertEqual(capability["action_approval"], "every_individual_write")
        self.assertTrue(any("16_kib" in item for item in capability["actions"]))
        self.assertIn("no_subdirectories_no_delete_no_arbitrary_shell", capability["actions"])

    def test_rust_registry_matches_the_user_selected_workspace_scope(self):
        source = read("core/capabilities/src/lib.rs")
        entry = source.split('id: "files.write"', 1)[1].split('CapabilityDefinition {', 1)[0]
        self.assertIn('grant_scope: "selected_workspace"', entry)
        self.assertIn("risk: High", entry)
        self.assertIn("supported_in_alpha: true", entry)
        self.assertIn('"workspace_folder_picker"', entry)

    def test_dart_policy_rejects_traversal_and_platform_reserved_names(self):
        policy = read("apps/leo_app/lib/core/tools/workspace_write_policy.dart")
        for marker in ("maxRelativePathBytes = 160", "maxContentBytes = 16 * 1024", "maxContentCharacters = 10000"):
            self.assertIn(marker, policy)
        for marker in ("name.contains('/')", "name.contains('\\\\')", "name.contains(':')", "name.endsWith('.')", "name.endsWith(' ')"):
            self.assertIn(marker, policy)
        self.assertIn("'CON'", policy)
        self.assertIn("utf8.encode(content).length > maxContentBytes", policy)
        self.assertIn("content.runes.length > maxContentCharacters", policy)

    def test_diff_preview_is_bounded_and_includes_context(self):
        policy = read("apps/leo_app/lib/core/tools/workspace_write_policy.dart")
        self.assertIn("int maxChangedLines = 80", policy)
        self.assertIn("تم اقتطاع بقية المعاينة", policy)
        self.assertIn("oldLines[prefix] == newLines[prefix]", policy)

    def test_protocol_scopes_workspace_write_to_file_operator_and_exact_schema(self):
        protocol = read("apps/leo_app/lib/core/tools/tool_call_protocol.dart")
        self.assertIn("'file_operator' => name == 'files.read_selected' || name == 'files.open_selected' || name == 'workspace.write_file'", protocol)
        self.assertIn("'workspace.write_file' => const {'relative_path', 'content'}", protocol)
        self.assertIn("WorkspaceWritePolicy.validate", protocol)
        self.assertIn("maxPayloadBytes = 40 * 1024", protocol)

    def test_capability_hub_orders_folder_pick_preview_and_user_approval_before_apply(self):
        service = read("apps/leo_app/lib/core/capabilities/capability_hub_service.dart")
        method = service.split("Future<CapabilityExecutionResult> writeWorkspaceTextFile", 1)[1].split("Future<void> _releaseWorkspace", 1)[0]
        self.assertLess(method.index("operation: 'pickWorkspace'"), method.index("'previewWorkspaceWrite'"))
        self.assertLess(method.index("'previewWorkspaceWrite'"), method.index("operation: 'applyWorkspaceWrite'"))
        self.assertLess(method.index("operation: 'applyWorkspaceWrite'"), method.index("actionApproval: () => _showWorkspaceWriteApproval"))
        self.assertIn("expectedHash", method)
        self.assertIn("expectedNewHash", method)
        self.assertIn("if (!outcome.success) await _releaseWorkspace(token)", method)
        self.assertIn("'files.write': {'pickWorkspace', 'applyWorkspaceWrite'}", service)

    def test_only_selected_folder_and_per_write_approval_are_used(self):
        service = read("apps/leo_app/lib/core/capabilities/capability_hub_service.dart")
        self.assertIn("scope: 'selected_workspace'", service)
        self.assertIn("skipActionConfirmation: true", service)  # folder picker only
        self.assertIn("actionApproval: () => _showWorkspaceWriteApproval", service)
        approval = service.split("Future<bool> _showWorkspaceWriteApproval", 1)[1].split("Future<bool> _showConsent", 1)[0]
        self.assertIn("workspaceLabel", approval)
        self.assertIn("before:", approval)
        self.assertIn("after:", approval)
        self.assertIn("موافقة وتطبيق التعديل", approval)

    def test_gateway_preserves_native_backup_cleanup_warning_for_the_user(self):
        gateway = read("apps/leo_app/lib/core/tools/tool_execution_gateway.dart")
        self.assertIn("final nativeNotice = result.data['message']?.toString().trim()", gateway)
        self.assertIn("'$baseSummary $nativeNotice'", gateway)
        self.assertIn("Never persist native error details", gateway)
        self.assertIn("file paths", gateway)
        self.assertIn("file contents", gateway)

    def test_audit_stores_only_fixed_tool_metadata_not_file_arguments(self):
        gateway = read("apps/leo_app/lib/core/tools/tool_execution_gateway.dart")
        record = gateway.split("Future<void> _record(", 1)[1]
        self.assertIn("toolName: call.name", record)
        self.assertIn("summary: switch (status)", record)
        self.assertNotIn("call.arguments", record)
        self.assertNotIn("call.rawBlock", record)

    def test_android_uses_session_scoped_saf_folder_access_and_no_persisted_grant(self):
        plugin = read("packages/leo_platform_capabilities/android/src/main/kotlin/ai/leo/platform/capabilities/LeoPlatformCapabilitiesPlugin.kt")
        self.assertIn("Intent.ACTION_OPEN_DOCUMENT_TREE", plugin)
        self.assertIn("FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION", plugin)
        self.assertIn("workspaceRoots", plugin)
        self.assertIn("while (workspaceRoots.size > 8)", plugin)
        self.assertIn("safeWorkspaceFileName", plugin)
        self.assertIn("MAX_WORKSPACE_TEXT_BYTES = 16 * 1024", plugin)
        self.assertIn("MAX_WORKSPACE_PREVIEW_BYTES = 64 * 1024", plugin)
        self.assertIn("DocumentsContract.renameDocument", plugin)
        self.assertIn("expectedNewHash", plugin)
        self.assertIn("previous file will be restored", plugin)
        self.assertNotIn("takePersistableUriPermission", plugin)

    def test_android_fails_closed_when_provider_cannot_list_or_stage_documents(self):
        plugin = read("packages/leo_platform_capabilities/android/src/main/kotlin/ai/leo/platform/capabilities/LeoPlatformCapabilitiesPlugin.kt")
        self.assertIn("The selected document provider did not return a workspace listing", plugin)
        self.assertIn("document provider cannot create a staging file", plugin)
        self.assertIn("The selected provider cannot atomically stage the previous file", plugin)
        self.assertIn("workspace_conflict", plugin)
        self.assertIn("backupUri", plugin)

    def test_windows_uses_canonical_user_folder_and_rejects_reparse_points(self):
        plugin = read("packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin.cpp")
        self.assertIn("FOS_PICKFOLDERS", plugin)
        self.assertIn("std::filesystem::canonical", plugin)
        self.assertIn("FILE_ATTRIBUTE_REPARSE_POINT", plugin)
        self.assertIn("g_workspace_roots", plugin)
        self.assertIn("IsSafeWorkspaceFilename", plugin)

    def test_windows_stages_hashes_verifies_and_rolls_back_workspace_writes(self):
        plugin = read("packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin.cpp")
        self.assertIn("BCryptOpenAlgorithmProvider", plugin)
        self.assertIn("BCRYPT_SHA256_ALGORITHM", plugin)
        self.assertIn("WriteStagingFile", plugin)
        self.assertIn("ReplaceFileW", plugin)
        self.assertIn("MoveFileExW", plugin)
        self.assertIn("Post-write verification failed", plugin)
        self.assertIn("backup_removed", plugin)
        self.assertIn("CountUnicodeCodePoints", plugin)
        self.assertIn("control-character", plugin)
        cmake = read("packages/leo_platform_capabilities/windows/CMakeLists.txt")
        self.assertIn("bcrypt", cmake)

    def test_rust_proposal_validation_is_role_scoped_and_strictly_bounded(self):
        execution = read("core/orchestration/src/execution.rs")
        self.assertIn('"workspace.write_file" => &["relative_path", "content"]', execution)
        self.assertIn('"file_operator" => matches!(name, "files.read_selected" | "files.open_selected" | "workspace.write_file")', execution)
        self.assertIn("relative_path.trim() != relative_path", execution)
        self.assertIn("content.len() > 16 * 1024", execution)
        self.assertIn("content.chars().count() > 10_000", execution)
        self.assertIn("MAX_TOOL_PROPOSAL_OUTPUT_CHARS: usize = 40_000", execution)
        self.assertIn("لا تنشئ مجلدات أو تحذف أو تنقل أو تعيد تسمية ملفات", execution)

    def test_continuation_and_checkpoints_recognize_workspace_write_only_as_proposal(self):
        continuation = read("apps/leo_app/lib/core/tools/agent_task_continuation.dart")
        checkpoint = read("apps/leo_app/lib/core/tools/agent_task_checkpoint_store.dart")
        bridge = read("core/bridge/src/api/simple.rs")
        self.assertIn("'workspace.write_file'", continuation)
        self.assertIn("'workspace.write_file'", checkpoint)
        self.assertIn('"workspace.write_file"', bridge)

    def test_no_delete_shell_or_arbitrary_process_tool_was_added(self):
        protocol = read("apps/leo_app/lib/core/tools/tool_call_protocol.dart")
        self.assertNotIn("workspace.delete_file", protocol)
        self.assertNotIn("workspace.move_file", protocol)
        self.assertNotIn("process.run", protocol)
        self.assertNotIn("shell.execute", protocol)
        self.assertNotIn("CreateProcess", read("packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin.cpp"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
