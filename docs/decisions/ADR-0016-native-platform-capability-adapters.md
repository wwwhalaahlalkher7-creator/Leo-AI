# ADR-0016: Thin native Android and Windows capability adapters

- Status: Accepted for Alpha v0.11.0
- Date: 2026-11-16

## Context

Leo should use applications and tools already available on the user's device instead of embedding duplicate implementations. The base application should remain small and the same capability names should be available to the task engine on both Android and Windows where the platform permits it.

## Decision

- Add a small Flutter plugin containing Android Kotlin and Windows C++ adapters.
- Prefer native pickers, intents, registered app launch targets and application handoffs.
- Limit file access to one file explicitly selected through the system picker per pick operation; directory traversal and writes remain out of scope for this slice.
- Keep Android document URI grants session-only; do not acquire persistable grants for a transient text preview.
- Limit generic URL handling to HTTP/HTTPS. Mail and telephone actions use dedicated, separately-confirmed capabilities.
- Do not add broad package-visibility, external-storage, administrator, arbitrary-process or UI-automation permissions for the first connector slice.
- Keep unsupported capability identifiers in the registry for transparency, but mark them unsupported and refuse invocation.

## Consequences

- Platform behavior may differ; each capability has platform-specific support metadata.
- The file preview surface is UTF-8 text-only, rejects NUL/binary input, and is capped at 2 MiB.
- Windows app launch requires a registered AppsFolder target or an explicit allowlisted `ms-settings` URI.
- Android app visibility is limited to launcher-activity queries, not unrestricted package enumeration.
- Email/SMS are draft handoffs, and dialing is a dialer handoff; Leo does not silently send or call.
- Additional integrations should be optional connectors or small OS adapters rather than bundled duplicate applications.
