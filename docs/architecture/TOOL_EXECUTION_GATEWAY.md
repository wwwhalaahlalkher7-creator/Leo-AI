# Leo Tool Execution Gateway — Alpha v0.12.0

## Purpose

The Tool Execution Gateway connects a structured local-model tool proposal to the existing `CapabilityHubService`. The model never receives a platform channel, native API, raw shell, or OS permission interface.

## Request protocol

A tool request must be the entire assistant response and use one versioned block:

```text
<leo_tool_call>{"version":1,"id":"call_1","name":"web.open","arguments":{"url":"https://example.com"}}</leo_tool_call>
```

The current protocol accepts exactly one call per model response and enforces a 16 KiB UTF-8 payload limit. The envelope must contain only `version`, `id`, `name`, and `arguments`; version must be `1`; IDs are bounded to 64 safe characters; the UTF-8 JSON payload is limited to 16 KiB; arguments are flat string maps with exact allowlisted keys. Tool output is not parsed from prose or fenced code.

Malformed, unknown, unsupported-platform or over-sized calls are rejected before any capability call. The chat response buffer suppresses a possible tool-call prefix until the response is classified, so the raw invocation is not rendered as normal assistant text.

## Alpha tool catalogue

| Tool | Capability | Arguments | Result boundary |
|---|---|---|---|
| `files.read_selected` | `files.read` | `{}` | Opens the system picker; reads only the selected UTF-8 text file. Model result capped at 12,000 characters. |
| `contacts.list` | `contacts.read` | `{}` | Android only; OS permission and Leo consent required; returns at most 30 contacts to the local runtime. |
| `email.compose` | `email.compose` | `to`, `subject`, `body` | Draft handoff only; no silent send. |
| `phone.dial` | `phone.dial` | `number` | Opens the dialer only; no direct call. |
| `messages.compose` | `messages.compose` | `number`, `body` | Android only; SMS draft only; no silent send. |
| `web.open` | `device.open_url` | `url` | HTTP/HTTPS only; user confirmation required by capability broker. |
| `app.launch` | `device.app_launch` | `target` | Hands off to a supported installed app; platform adapter applies its own target checks. |

## Execution sequence

1. Local model receives the system tool protocol and current platform-specific availability.
2. Model may return a single structured request instead of prose.
3. Flutter parser validates the envelope and strict per-tool arguments.
4. The Tool Execution Gateway maps the validated call to one typed `CapabilityHubService` method. It does not call a platform channel directly.
5. `CapabilityHubService` performs Leo first-use consent, OS permission/resource checks and separate per-action confirmation according to risk.
6. Native adapter performs only the narrow OS/app handoff implemented for the platform.
7. Result is returned to the model as a `tool` message, marked as untrusted data. The model must report only what the result confirms.
8. At most three tool calls are allowed in one user turn. A rejected/cancelled/failed call is returned to the model with an instruction not to repeat it.

## Audit and privacy

The app-private SharedPreferences audit log retains up to 100 records with tool name, status, timestamp and a short non-sensitive summary. It deliberately excludes tool arguments, email addresses, phone numbers, message bodies, contacts, paths and file contents. The chat's persisted transcript contains user-visible status notices and the final assistant response, not the raw tool JSON or transient tool result.

The audit preference storage is app-private but is not separately encrypted in this Alpha milestone. It contains metadata only, not secrets or user-provided tool content.

## Security boundaries

- The model cannot set or persist Leo permission grants.
- The model cannot approve its own actions.
- Tool names and arguments are allowlisted and bounded.
- All execution goes through the existing permission broker and action confirmation dialogs.
- Native code stays behind the platform plugin; this gateway has no direct `MethodChannel` calls.
- No arbitrary shell, process, PowerShell, terminal command, file write/delete, general UI automation, silent mail/SMS, direct calling or admin operation is exposed.
- Windows does not expose contacts or SMS tools in this Alpha build.
- Tool output is untrusted and size-limited; a tool result cannot modify policies or grant capabilities.

## Known limitations

- Tool calling is prompt-protocol-based; models may fail to emit valid structured requests. Invalid requests are rejected safely, but model adherence must be benchmarked on selected GGUFs.
- The Alpha loop is sequential and capped at three calls per user turn. There is no parallel tool fan-out.
- No independent planner-generated multi-step tool DAG executes yet; v0.12.0 handles one tool call at a time and lets the model request the next step after reading each result.
- Native dialogs/handoffs are not cancellable by an out-of-band task cancellation API; the user can reject the active approval/picker dialog.
- Tool results are returned only to the local inference runtime. No cloud fallback is configured in this path.
- Full Flutter/Dart/Rust/native build and real-device verification are pending CI/toolchain execution.
