from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CapabilityHubContractTests(unittest.TestCase):
    def test_capability_policy_declares_first_use_and_separate_action_approval(self):
        policy = json.loads((ROOT / "config/leo_capability_policy_v0.2.json").read_text(encoding="utf-8"))
        self.assertEqual(policy["permission_request_policy"], "just_in_time_on_first_use")
        self.assertEqual(policy["two_independent_gates"], ["leo_app_consent", "operating_system_permission_or_user_selected_resource"])
        self.assertEqual(policy["action_approval_policy"], "separate_per_consequential_action")
        self.assertTrue(any(item["id"] == "files.read" and item["alpha_supported"] for item in policy["capabilities"]))
        for capability_id in ("files.open_selected", "calendar.create_event", "clipboard.write"):
            self.assertTrue(next(item for item in policy["capabilities"] if item["id"] == capability_id)["alpha_supported"])
        self.assertFalse(next(item for item in policy["capabilities"] if item["id"] == "phone.call_direct")["alpha_supported"])
        microphone = next(item for item in policy["capabilities"] if item["id"] == "audio.microphone")
        self.assertTrue(microphone["alpha_supported"])
        self.assertEqual(microphone["action_approval"], "while_recording_visible")

    def test_rust_capability_store_is_persistent_scoped_and_fails_closed(self):
        source = (ROOT / "core/capabilities/src/lib.rs").read_text(encoding="utf-8")
        self.assertIn("pub struct CapabilityStore", source)
        self.assertIn("UNIQUE(capability_id, scope)", source)
        self.assertIn("ON CONFLICT(capability_id, scope) DO UPDATE", source)
        self.assertIn("pub fn revoke", source)
        self.assertIn("RevokedByOperatingSystem", source)
        self.assertIn("ScopeUpgradeRequired", source)
        self.assertIn("RelativeDatabasePath", source)
        self.assertIn("PRAGMA secure_delete = ON", source)

    def test_permission_and_capability_api_is_exposed_through_rust_bridge(self):
        bridge = (ROOT / "core/bridge/src/api/simple.rs").read_text(encoding="utf-8")
        cargo = (ROOT / "core/bridge/Cargo.toml").read_text(encoding="utf-8")
        self.assertIn('leo-capabilities = { path = "../capabilities" }', cargo)
        for function in (
            "capability_list",
            "permission_check",
            "permission_record_decision",
            "permission_revoke",
            "permission_list",
            "action_confirmation_required",
        ):
            self.assertRegex(bridge, rf"pub fn {function}\b")

    def test_flutter_broker_shows_leo_consent_then_os_permission_then_action_approval(self):
        service = (ROOT / "apps/leo_app/lib/core/capabilities/capability_hub_service.dart").read_text(encoding="utf-8")
        self.assertIn("_showConsent", service)
        self.assertIn("recordDecision", service)
        self.assertIn("requestOsPermission", service)
        self.assertIn("requestMicrophoneAccess", service)
        self.assertIn("openWindowsMicrophonePrivacySettings", service)
        self.assertIn("LeoPermissionStatus.previouslyDenied", service)
        self.assertIn("_showActionApproval", service)
        self.assertIn("if (!osGranted || permission.needsOsPermission)", service)
        self.assertIn("لم ينفذ Leo العملية", service)

    def test_flutter_service_uses_scoped_os_and_app_handoffs(self):
        service = (ROOT / "apps/leo_app/lib/core/capabilities/capability_hub_service.dart").read_text(encoding="utf-8")
        for operation in ("pickFile", "readSelectedText", "openSelectedFile", "createCalendarEventDraft", "copyTextToClipboard", "composeEmail", "openDialer", "composeMessage", "openUrl", "launchAndroidApp", "launchWindowsApp", "readContacts"):
            self.assertIn(f"{operation}(", service)
        self.assertIn("لن يرسلها تلقائياً", service)
        self.assertIn("لن يبدأ المكالمة بنفسه", service)
        self.assertIn("externalEffect: true", service)
        self.assertIn("المستلم: $safeRecipient", service)
        self.assertIn("نص الرسالة:", service)

    def test_android_adapter_uses_saf_and_no_broad_storage_or_package_visibility_permission(self):
        plugin = (ROOT / "packages/leo_platform_capabilities/android/src/main/kotlin/ai/leo/platform/capabilities/LeoPlatformCapabilitiesPlugin.kt").read_text(encoding="utf-8")
        manifest = (ROOT / "packages/leo_platform_capabilities/android/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
        self.assertIn("Intent.ACTION_OPEN_DOCUMENT", plugin)
        self.assertIn("Intent.ACTION_OPEN_DOCUMENT_TREE", plugin)
        self.assertIn("workspaceRoots", plugin)
        self.assertIn("current.requestPermissions", plugin)
        self.assertIn("Intent.ACTION_DIAL", plugin)
        self.assertIn("Intent.ACTION_SENDTO", plugin)
        self.assertIn("selectedDocumentUris", plugin)
        self.assertIn("CalendarContract.Events.CONTENT_URI", plugin)
        self.assertIn("openSelectedFile", plugin)
        self.assertIn("copyTextToClipboard", plugin)
        self.assertIn("during the active app session", plugin)
        self.assertNotIn("takePersistableUriPermission", plugin)
        self.assertIn("not_plain_text", plugin)
        self.assertIn("READ_CONTACTS", manifest)
        self.assertNotIn("MANAGE_EXTERNAL_STORAGE", manifest)
        self.assertNotIn("QUERY_ALL_PACKAGES", manifest)
        self.assertNotIn("requestPermissions", plugin.split("override fun onMethodCall", 1)[0])

    def test_windows_adapter_limits_links_and_requires_picker_selection_for_reads(self):
        plugin = (ROOT / "packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin.cpp").read_text(encoding="utf-8")
        self.assertIn("IFileOpenDialog", plugin)
        self.assertIn("ShellExecuteW", plugin)
        self.assertIn("openMicrophonePrivacySettings", plugin)
        self.assertIn("ms-settings:privacy-microphone", plugin)
        self.assertIn("g_selected_files.find(path) == g_selected_files.end()", plugin)
        self.assertIn("2 * 1024 * 1024", plugin)
        self.assertIn("IsAllowedWebLink", plugin)
        self.assertIn("IsAllowedAppTarget", plugin)
        self.assertIn('value.rfind("https://", 0) == 0', plugin)
        self.assertNotIn('value.rfind("mailto:", 0) == 0 ||', plugin)
        self.assertIn("blocked_target", plugin)
        self.assertIn("HasNoUriControls", plugin)
        self.assertIn("target.size() <= 100000", plugin)
        self.assertIn("IsSafePhoneNumber", plugin)
        self.assertIn("CreateCalendarEventDraft", plugin)
        self.assertIn("OpenSelectedFile", plugin)
        self.assertIn("CopyTextToClipboard", plugin)
        self.assertIn("IsSafeEmailAddress", plugin)
        self.assertIn("IsAllowedAppTarget", plugin)
        self.assertNotIn("system(", plugin)
        self.assertNotIn("CreateProcess", plugin)

    def test_plugin_is_registered_for_android_and_windows(self):
        package = (ROOT / "packages/leo_platform_capabilities/pubspec.yaml").read_text(encoding="utf-8")
        app = (ROOT / "apps/leo_app/pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("android:", package)
        self.assertIn("pluginClass: LeoPlatformCapabilitiesPlugin", package)
        self.assertIn("windows:", package)
        self.assertIn("leo_platform_capabilities:", app)
        self.assertTrue((ROOT / "packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin_c_api.cpp").exists())

    def test_flutter_capability_surface_has_no_raw_dynamic_invocation(self):
        service = (ROOT / "apps/leo_app/lib/core/capabilities/capability_hub_service.dart").read_text(encoding="utf-8")
        self.assertIn("Future<CapabilityExecutionResult> _invoke(", service)
        self.assertNotIn("Future<CapabilityExecutionResult> invoke(", service)
        self.assertIn("bool _operationAllowed(", service)
        self.assertIn("'files.read': {'pickFile', 'readTextFile'}", service)
        self.assertIn("'files.open_selected': {'pickFile', 'openSelectedFile'}", service)
        self.assertIn("'calendar.create_event': {'createCalendarEventDraft'}", service)
        self.assertIn("'clipboard.write': {'copyText'}", service)
        self.assertIn("'device.open_url': {'openUrl'}", service)

    def test_url_and_message_arguments_are_bounded_before_native_handoff(self):
        service = (ROOT / "apps/leo_app/lib/core/capabilities/capability_hub_service.dart").read_text(encoding="utf-8")
        self.assertIn("url.length > 2048", service)
        self.assertIn("parsed.userInfo.isNotEmpty", service)
        self.assertIn("body.length > 4096", service)
        self.assertIn("subject.length > 998 || body.length > 8192", service)
        self.assertIn("_containsUnsafeTextControl(body)", service)
        self.assertIn("mailto.length > 100000", service)
        self.assertIn("externalEffect: true", service)

    def test_provider_preference_is_os_first_and_ui_automation_last(self):
        capability = (ROOT / "core/capabilities/src/lib.rs").read_text(encoding="utf-8")
        self.assertIn("CapabilitySource::OperatingSystem => 0", capability)
        self.assertIn("CapabilitySource::UiAutomationFallback => 5", capability)
        self.assertIn("min_by_key(|provider| source_priority(provider.source))", capability)

    def test_permission_center_is_reachable_from_chat_menu(self):
        chat = (ROOT / "apps/leo_app/lib/features/chat/chat_page.dart").read_text(encoding="utf-8")
        page = (ROOT / "apps/leo_app/lib/features/capabilities/capability_center_page.dart").read_text(encoding="utf-8")
        self.assertIn("_openCapabilities", chat)
        self.assertIn("قدرات الجهاز والصلاحيات", chat)
        self.assertIn("CapabilityCenterPage", chat)
        self.assertIn("إلغاء إذن Leo", page)
        self.assertIn("يُطلب عند أول استخدام", page)


if __name__ == "__main__":
    unittest.main(verbosity=2)
