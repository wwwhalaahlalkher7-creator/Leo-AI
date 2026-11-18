# Leo Alpha v0.11.0 — Capability Hub and Permission Broker

**Date:** 2026-11-16  
**Project:** Leo AI  
**Application:** Leo  
**Channel:** ALPHA  
**Version:** v0.11.0

## Delivered in source

- Added `leo-capabilities`, a Rust crate that defines capability metadata, provider preference, risk classification, scoped persistent permission decisions, expiry/revocation checks and per-action approval policy.
- Added SQLite-backed permission persistence through rusqlite 0.43.0 with the bundled SQLite feature. The database path is supplied by Flutter from the application-support directory.
- Added typed Rust bridge endpoints for capability listing, permission check/record/revoke/list and action-confirmation policy.
- Added a Flutter Capability Hub service which performs Leo consent, OS/resource permission check, per-action confirmation and native handoff in that order.
- Added a permission-center screen reachable from the chat menu. It lists platform capabilities and stored Leo grants, and revokes Leo-level consent.
- Added a small Flutter plugin with Android Kotlin and Windows C++ adapters.
- Android Alpha adapter uses SAF single-file selection, session-only selected-document UTF-8 preview capped at 2 MiB, contacts permission and capped contact query, app launch, dialer, email/SMS draft handoff and HTTP/HTTPS link opening. It does not take a persistable URI grant.
- Windows Alpha adapter uses the native file picker, selected-file-only UTF-8 preview capped at 2 MiB, registered app target handoff, dialer/mail draft handoff and HTTP/HTTPS link opening. Arbitrary process execution is deliberately absent.
- Added a launcher-intent package visibility query on Android instead of `QUERY_ALL_PACKAGES`.
- Added dedicated mail and telephone paths; generic link opening now accepts only HTTP/HTTPS and requires per-action confirmation.
- Added documentation for architecture, native adapter limits and permission lifecycle.

## Security and behavior boundaries

- No sensitive permission is requested at install, first launch or chat startup.
- A saved Leo grant never overrides current OS state.
- Action confirmation remains independent from a stored capability grant.
- Mail and SMS actions prepare drafts only. Phone dialing opens the dialer only.
- File reading requires a system picker selection and is limited to a 2 MiB UTF-8 preview.
- Windows plugin does not execute arbitrary commands, call `CreateProcess` or request UAC elevation.
- No general UI automation, microphone capture, file writes, direct calling, silent sending, or peer task execution is enabled.
- The permission DB is app-private but not encrypted; permission records must not hold secrets or user content.
- The service/native adapters are not yet connected to a model tool-call executor. Chat-generated tool execution remains a later milestone.

## Validation performed in this environment

- `python scripts/check_version.py` — PASS for v0.11.0 / ALPHA.
- `python scripts/verify_sources.py` — PASS for both preserved source archives and recorded hashes.
- `python -m unittest discover -s scripts/tests -v` — PASS: 39 Python contract tests.
- JSON parsing of capability/version configuration — PASS.
- Source review caught and corrected Android plugin registration metadata, transient-only document grants, UTF-8/NUL file validation, bounded phone/mail/URL inputs, generic link scheme handling, Windows app-target filtering and action preview details.

## Validation not performed

Flutter, Dart, Rust/Cargo, Android SDK/NDK and Windows MSVC SDK are not installed in the present container. Therefore:

- Flutter Rust Bridge code generation has not run.
- `dart format`, `flutter analyze`, Flutter widget tests have not run.
- `cargo fmt`, `cargo test`, `cargo clippy` have not run.
- Android Gradle/plugin build and Windows native plugin build have not run.
- No physical Android or Windows-device operation has been verified.

The Python contract suite passing is not equivalent to a successful native/platform build. The next CI run must execute the full-stack, Android and Windows jobs before this slice is called build-verified.

## Next milestone

**Leo Alpha v0.12.0 — Tool Execution Gateway**

Connect the agent planner and model tool-call format to validated capability invocations. Add strict per-tool schemas, bounded argument validation, action previews, cancellation/timeouts, audit traces and fake-adapter tests. No task may directly call a platform channel or native API outside the broker.
