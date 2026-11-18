# Leo Capability Hub — Alpha v0.12.0 (Capability execution integration)

## Purpose

The Capability Hub is Leo's platform-neutral access layer for Android and Windows. It resolves each requested operation through operating-system APIs and installed applications before considering MCP connectors or Leo-owned adapters. It is deliberately separate from chat UI, model runtimes and agent prompts.

## Non-negotiable flow

Every operation must pass the following stages in order:

1. Resolve the capability identifier from the built-in registry.
2. Confirm the capability is supported on the current platform and in this Alpha slice.
3. Check Leo's persisted consent for the declared scope.
4. If no valid Leo consent exists, explain the capability, scope and expected data/effect and ask at first use.
5. Independently check/request the OS permission or require a user-selected resource. A stored Leo grant never overrides OS revocation.
6. Decide whether this particular action needs confirmation. High/Critical actions, destructive actions and Moderate external side effects require a separate one-action approval.
7. Execute only through the selected native or installed-app adapter.
8. Return a typed success/cancelled/error result. Never claim that a handoff succeeded merely because it was requested.

A capability grant is not a blanket authorization to send, delete, overwrite, call, run a process or automate an application.

## Native capability support matrix (introduced in v0.11.0)

| Capability | Android | Windows | Alpha boundary |
|---|---|---|---|
| Pick a file and preview UTF-8 text | Supported | Supported | User selects every file; preview limited to 2 MiB |
| Launch an installed app | Supported | Supported | Android package launch; Windows registered AppsFolder/ms-settings target only |
| Open a web link | Supported | Supported | HTTP/HTTPS only; separate confirmation |
| Compose email | Supported | Supported | Opens a mail draft; never sends |
| Open dialer | Supported | Supported | Handoff only; never places a call |
| Compose SMS | Supported | Not supported | Android draft only; never sends |
| Read contacts | Supported | Not supported | Android runtime permission; first 500 phone rows |
| Write files | Not supported | Not supported | Future milestone |
| Direct phone call | Not supported | Not supported | Future milestone and OS-policy review |
| Microphone capture | Not supported | Not supported | Reserved for Voice milestone |
| General process execution | Not supported | Not supported | Requires execution gateway and sandbox/allowlist |
| Administrator operations | Not supported | Not supported | No elevated helper in Alpha |
| General UI automation | Not supported | Not supported | Official API/CLI first; automation remains last resort |
| Peer task receive | Not supported | Not supported | Later distributed-task milestone |

## Native adapter boundaries

### Android

- Uses the Storage Access Framework for file selection; it does not request broad external-storage access.
- Declares `READ_CONTACTS` only. Runtime permission is requested after Leo consent and only when `contacts.read` is invoked.
- Declares a launcher-intent visibility query for package launch instead of `QUERY_ALL_PACKAGES`.
- Uses `ACTION_DIAL`, `ACTION_SENDTO` for mail/SMS drafts, and `ACTION_VIEW` for HTTP/HTTPS only.
- Selected content URIs are accepted for single-file reading only during the current app session; Alpha does not request persistent URI grants. Directory selection and writes are not exposed yet. The text preview is capped at 2 MiB and rejects NUL/binary data.

### Windows

- Uses `IFileOpenDialog` for user-selected files.
- A file may be read only when its path was returned by Leo's file picker in the current app session. The set is bounded to 64 selections and previews are capped at 2 MiB; NUL/binary data is rejected.
- Uses `ShellExecuteW` for web/mail/tel handoffs and registered application targets; it does not call `CreateProcess`, `system()` or arbitrary command interpreters.
- The app remains at standard user integrity. No automatic UAC elevation exists in this Alpha slice.

## Persistence and revocation

`leo-capabilities` persists Leo-level consent decisions in SQLite under the Flutter application-support directory. Records are keyed by `(capability_id, scope)` and retain the decision, creation/expiry and update timestamps. The broker re-checks the current OS state at invocation time. Revoking a Leo grant does not pretend to revoke an Android or Windows system setting; the permission center explains this distinction.

The current permission database is app-private but not encrypted. Do not put secrets, access tokens or raw contact data in its permission records. Scopes in Alpha are capability labels, not arbitrary file paths.

## Provider resolution order

1. Native operating-system API or picker.
2. Official installed-application API, intent, deep link or supported CLI.
3. Existing local connector or MCP server.
4. Small Leo-owned adapter when no suitable provider exists.
5. UI automation only as a last resort, subject to platform and store policies.

The registry records provider preferences; actual provider availability still needs runtime discovery. A declared provider is not evidence that it exists on a device.

## Current integration boundary

As of Alpha v0.12.0, the local chat model can propose a single structured tool call in a strict `<leo_tool_call>` envelope. The Flutter Tool Execution Gateway validates the exact tool name and argument schema, then dispatches only through typed `CapabilityHubService` methods. It never calls a platform channel directly. The existing service remains responsible for Leo consent, current OS/resource permission checks and independent per-action confirmation.

The initial allowlist is deliberately narrow: selected-file text read, contacts read (Android), email draft, dialer handoff, SMS draft (Android), HTTP/HTTPS open and installed-app launch. A user turn is limited to three sequential calls. Tool results are returned as untrusted data to the local model and are capped at 12,000 characters. User-denied, cancelled and failed operations are represented explicitly; the model is instructed not to retry a rejected call.

The audit view stores only tool name, status, timestamp and a short summary (up to 100 records). It does not store arguments, email addresses, numbers, message bodies, contact data, file paths or file contents. Audit storage is app-private but not separately encrypted. No arbitrary shell/PowerShell, file write/delete, direct call, silent send, admin operation or general UI automation is exposed. Model adherence, Dart/Rust code generation, platform builds and real-device operations still require CI and physical-device validation.

## Required verification

- Rust unit tests for scope, expiry, denial, revocation, provider order and action approval.
- FRB code generation after the Rust API changes.
- Dart format, analyze and widget/unit tests.
- Android Gradle build and real-device checks for SAF, contacts permission, dialer, mail/SMS drafts and package launch.
- Windows MSVC build and real-device checks for COM picker, UTF-8 file reads, URL/app handoffs and denial paths.
- Manual tests proving no email/SMS is sent and no call is placed by Leo.
