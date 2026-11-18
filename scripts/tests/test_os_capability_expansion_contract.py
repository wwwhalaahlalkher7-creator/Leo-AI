from __future__ import annotations
import json
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class OsCapabilityExpansionContractTests(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text(encoding="utf-8")
    def test_catalog_and_policy_enable_only_three_reviewed_os_handoffs(self):
        rust = self.read("core/capabilities/src/lib.rs")
        policy = json.loads(self.read("config/leo_capability_policy_v0.2.json"))
        ids = {item["id"] for item in policy["capabilities"]}
        for capability in ("files.open_selected", "calendar.create_event", "clipboard.write"):
            self.assertIn(capability, ids)
            self.assertIn(f'id: "{capability}"', rust)
        self.assertTrue(next(item for item in policy["capabilities"] if item["id"] == "calendar.create_event")["note"].find("silently") >= 0)
        agents = json.loads(self.read("config/leo_builtin_agents_v0.1.json"))
        file_agent = next(agent for agent in agents["agents"] if agent["id"] == "file_operator")
        device_agent = next(agent for agent in agents["agents"] if agent["id"] == "device_operator")
        self.assertIn("files.open_selected", file_agent["required_capabilities"])
        self.assertIn("calendar.create_event", device_agent["required_capabilities"])
        self.assertIn("clipboard.write", device_agent["required_capabilities"])
    def test_open_selected_file_requires_user_picker_and_safe_extension_allowlist(self):
        android = self.read("packages/leo_platform_capabilities/android/src/main/kotlin/ai/leo/platform/capabilities/LeoPlatformCapabilitiesPlugin.kt")
        windows = self.read("packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin.cpp")
        hub = self.read("apps/leo_app/lib/core/capabilities/capability_hub_service.dart")
        self.assertIn("rawUri !in selectedDocumentUris", android)
        self.assertIn("allowedExtensions", android)
        self.assertIn("g_selected_files.find(raw_path) == g_selected_files.end()", windows)
        self.assertIn("IsSafeOpenDocumentExtension", windows)
        self.assertIn("externalEffect: true", hub)
    def test_calendar_is_a_draft_not_direct_calendar_database_write(self):
        android = self.read("packages/leo_platform_capabilities/android/src/main/kotlin/ai/leo/platform/capabilities/LeoPlatformCapabilitiesPlugin.kt")
        windows = self.read("packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin.cpp")
        self.assertIn("Intent.ACTION_INSERT", android)
        self.assertIn("CalendarContract.Events.CONTENT_URI", android)
        self.assertNotIn("WRITE_CALENDAR", self.read("packages/leo_platform_capabilities/android/src/main/AndroidManifest.xml"))
        self.assertIn("CreateCalendarEventDraft", windows)
        self.assertIn("END:VCALENDAR", windows)
        self.assertIn("ShellOpen(draft_path.wstring())", windows)
    def test_clipboard_is_write_only_and_requires_per_copy_confirmation(self):
        android = self.read("packages/leo_platform_capabilities/android/src/main/kotlin/ai/leo/platform/capabilities/LeoPlatformCapabilitiesPlugin.kt")
        windows = self.read("packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin.cpp")
        hub = self.read("apps/leo_app/lib/core/capabilities/capability_hub_service.dart")
        self.assertIn("setPrimaryClip", android)
        self.assertIn("OpenClipboard(nullptr)", windows)
        self.assertNotIn("GetClipboardData", windows)
        self.assertIn("externalEffect: true", hub)
        self.assertIn("لا يقرأ Leo محتوى الحافظة السابق", hub)
    def test_tool_roles_and_protocol_include_new_operations(self):
        protocol = self.read("apps/leo_app/lib/core/tools/tool_call_protocol.dart")
        rust = self.read("core/orchestration/src/execution.rs")
        gateway = self.read("apps/leo_app/lib/core/tools/tool_execution_gateway.dart")
        for tool in ("files.open_selected", "calendar.create_event", "clipboard.copy_text"):
            self.assertIn(tool, protocol)
            self.assertIn(tool, rust)
            self.assertIn(tool, gateway)
        self.assertIn("zonedIso8601", protocol)
        self.assertIn("hasInlineControl(title)", protocol)
        self.assertIn("16 * 1024", protocol)

    def test_android_document_handoff_blocks_active_mime_types_and_maps_unknown_types(self):
        android = self.read("packages/leo_platform_capabilities/android/src/main/kotlin/ai/leo/platform/capabilities/LeoPlatformCapabilitiesPlugin.kt")
        for marker in ("application/vnd.android.package-archive", "application/javascript", "text/html", "image/svg+xml"):
            self.assertIn(marker, android)
        self.assertIn('providerMimeType != "application/octet-stream"', android)
        self.assertIn('providerMimeType !in acceptedMimeTypes', android)
        self.assertIn('"application/vnd.openxmlformats-officedocument.wordprocessingml.document"', android)

    def test_calendar_time_and_inline_fields_are_validated_at_multiple_boundaries(self):
        protocol = self.read("apps/leo_app/lib/core/tools/tool_call_protocol.dart")
        rust = self.read("core/orchestration/src/execution.rs")
        android = self.read("packages/leo_platform_capabilities/android/src/main/kotlin/ai/leo/platform/capabilities/LeoPlatformCapabilitiesPlugin.kt")
        self.assertIn("zonedIso8601.hasMatch(startRaw)", protocol)
        self.assertIn("has_zoned_iso8601_shape(start)", rust)
        self.assertIn("has_inline_control(title)", rust)
        self.assertIn("listOf(title, location).any", android)

    def test_windows_clipboard_partial_failure_is_reported_honestly(self):
        windows = self.read("packages/leo_platform_capabilities/windows/src/leo_platform_capabilities_plugin.cpp")
        self.assertIn("if (!EmptyClipboard())", windows)
        self.assertIn("previous clipboard contents were cleared", windows)
if __name__ == "__main__": unittest.main(verbosity=2)
