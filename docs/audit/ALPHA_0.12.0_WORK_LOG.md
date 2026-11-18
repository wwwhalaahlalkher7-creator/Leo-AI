# Leo Alpha v0.12.0 — Work Log

**Project:** Leo AI  
**Application:** Leo  
**Version:** `v0.12.0`  
**Channel:** `ALPHA`  
**Build metadata:** `3`  
**Date:** 2026-11-16

## Objective

Connect the local chat model to the OS/application-first Capability Hub without giving the model direct access to native channels, shell execution, or OS permissions. Keep the operation allowlist narrow, route every action through existing Leo and OS approval flows, and prevent sensitive arguments/results from leaking into the persisted chat or audit log.

## Implemented

- Added a private-constructor `LeoToolCall` protocol parser. A tool call must be the entire assistant response and contain one version-1 envelope with exactly `version`, `id`, `name` and `arguments`.
- Added a 16 KiB UTF-8 payload ceiling, safe call-ID format, exact per-tool argument keys, string-only argument values, control-character checks, and bounded URL/email/phone/message/app-target validation.
- Added the allowlisted tools `files.read_selected`, `contacts.list`, `email.compose`, `phone.dial`, `messages.compose`, `web.open` and `app.launch`. Windows contacts and SMS are explicitly rejected.
- Added `ToolExecutionGateway`, which routes to typed `CapabilityHubService` methods only. It contains no direct `MethodChannel` or native API calls. The existing Capability Hub remains responsible for first-use Leo consent, OS/resource access checks and independent action confirmation.
- Added a chat execution loop: at most three sequential calls per user turn; tool results are bounded and returned as untrusted `tool` messages to the local model. A denied, cancelled or failed operation is explicitly reported as such and is not retried automatically.
- Added model instructions describing the protocol and platform availability. Raw tool-call blocks are withheld from normal assistant rendering when they are recognized as tool calls.
- Added an audit view linked from the chat menu. The app-private audit stores only the allowlisted tool name, status, timestamp, execution ID and fixed summary. It does not store phone numbers, email addresses, message bodies, contact data, file paths, selected-file contents or tool results. It retains at most 100 entries.
- Added Flutter parser tests and Python source/architecture contract tests.
- Updated README, development roadmap, toolchain matrix, capability-hub architecture notes and ADR-0017.

## Explicit limits

- Email and SMS tools create drafts only; they do not send. Phone opens the dialer only.
- File access uses the system picker and reads only the selected UTF-8 text file; the Capability Hub's existing native limit is 2 MiB. Model-facing tool output is capped at 12,000 characters.
- Contacts and SMS tools are Android-only. Windows app-launch targets remain restricted by the native adapter.
- No arbitrary shell/PowerShell, process execution, file writes/deletes, direct calling, silent sending, microphone capture, administrator operations or general UI automation are exposed.
- Tool calling depends on the local model following the prompted XML/JSON protocol. Invalid calls are rejected; model adherence still needs evaluation with actual GGUF models.
- Audit metadata is stored in app-private SharedPreferences but is not separately encrypted. Tool outputs are transient and are not written to the saved conversation transcript.
- The loop is sequential and limited to three calls; planner-generated execution DAGs and parallel tool invocation are not implemented.

## Validation performed

- `python -m unittest discover -s scripts/tests -v`: **50/50 passed**. This is a Python source/architecture contract suite, not a substitute for compiling Dart or Rust.
- `python scripts/check_version.py`: passed; version/channel/pubspec/Cargo/changelog synchronization confirmed for `v0.12.0`, Alpha, build `3`.
- `python scripts/verify_sources.py`: passed; original J.A.R.V.I.R and NEXUS archives match their recorded SHA-256 hashes.
- Parsed repository configuration: **8 JSON**, **8 TOML**, and **5 YAML/YML** files successfully.

## Not verified in this environment

Flutter Analyze, Dart formatting/tests, Flutter Android/Windows builds, Cargo test/clippy, Rust Flutter-bridge generation, Android native plugin compilation, and Windows native plugin compilation were not run because Flutter, Dart, Rust/Cargo, Android SDK/NDK and the Windows MSVC toolchain are unavailable here. No APK or Windows installer is claimed. The source must pass CI and real-device smoke tests before this milestone can be treated as platform-verified.

## Next milestone

`v0.13.0` — Offline Voice Foundation: select and test local ASR/TTS/VAD engines on Android and Windows, evaluate Arabic and English, implement foreground voice sessions, speech playback interruption and local voice-model packaging separate from the core application. Wake-word background operation remains deferred until its platform and power constraints are validated.
