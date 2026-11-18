# ADR-0028: OS-native file, calendar and clipboard handoffs

**Status:** Accepted for Leo Alpha v0.23.0  
**Date:** 2026-11-17

## Context

Leo had a narrow OS Capability Hub for file selection, app and URL launch, communications drafts and phone handoff. Three frequent tasks needed a native path without granting broad storage or account permissions: opening a chosen document, preparing a calendar event, and copying text. Adding direct calendar database access or general clipboard reading would unnecessarily widen the permission surface. Opening arbitrary paths or MIME types would also permit unsafe handoffs.

## Decision

Add three separately scoped capabilities, all routed through Flutter's Capability Hub and the existing Leo-consent / OS-resource / per-action approval flow:

1. `files.open_selected` requires the user to choose one file through the native picker for each handoff. Android accepts only the session-selected content URI and a safe extension whose provider MIME is compatible with the extension; dangerous executable, installer, HTML, script and active SVG types are rejected. Windows accepts only a picker-issued path to a regular non-reparse file with a reviewed extension. The OS-associated viewer is opened; Leo does not interpret or execute document contents.
2. `calendar.create_event` validates one bounded event and hands it to the user's calendar editor. Android uses `Intent.ACTION_INSERT` with `CalendarContract.Events.CONTENT_URI` and event extras; no calendar provider read/write permission or direct provider mutation is used. Windows writes a bounded ICS draft under a Leo-owned temporary directory and opens the registered ICS handler. The user must save the draft; Leo does not create a calendar row or invite attendees directly.
3. `clipboard.write` copies one bounded text payload after showing the proposed content and obtaining separate approval for that copy. It is write-only; Leo never reads the prior clipboard contents.

The tool protocol uses role mapping: file opening belongs to `file_operator`; calendar and clipboard belong to `device_operator`. Rust validates the proposal envelope and specialist/tool relationship; Dart reparses the full schema; the native adapter independently checks its platform arguments.

## Consequences

### Positive

- Reuses native OS/document/calendar/clipboard handlers instead of embedding duplicate viewers or calendar databases.
- Keeps file access picker-scoped and calendar interaction user-owned.
- Prevents a persistent capability grant from becoming blanket approval for each document handoff, event draft or clipboard replacement.
- Keeps clipboard integration write-only and calendar integration draft-only.

### Trade-offs and limitations

- Android document providers may return inconsistent MIME metadata. Leo fails closed if a reported non-generic MIME does not match the selected extension. Some otherwise valid provider files may therefore be rejected.
- Windows calendar handling depends on a registered `.ics` association; opening the draft is a handoff, not proof that an event was saved. Temporary drafts older than 48 hours are eligible for cleanup.
- System dialogs and associated apps vary by OEM/Windows installation. Native compilation and physical-device tests remain mandatory.
- A successful OS handoff means that the OS accepted/opened the target; it does not prove the user saved a calendar event or later acted on the clipboard contents.

## Rejected alternatives

- Direct Calendar Provider/database write and broad calendar permissions: rejected in favor of a user-owned draft.
- Reading clipboard content to verify a copy: rejected because clipboard reads are privacy-sensitive and unnecessary.
- Opening arbitrary filesystem paths or any extension: rejected in favor of picker-issued resources and extension/MIME controls.
- Giving agents native API access: rejected; all proposals still flow through the typed Flutter Capability Hub and per-action approval.

## Required validation

- Android: picker cancellation, session URI checks, extension/MIME mismatch, dangerous MIME rejection, missing viewer, calendar app availability, event extras, clipboard approval and copy limits.
- Windows: picker path identity, reparse/directory rejection, extension allowlist, no registered viewer, ICS draft correctness/cleanup, clipboard busy/allocation/SetClipboardData failure.
- Both: first-use consent, OS gate where applicable, per-action approval, denial/cancellation, no sensitive argument persistence, offline behavior, and tool-role isolation.
