# Leo AI — Remaining releases after Alpha v0.27.0

**Current source:** Leo Alpha `v0.27.0`  
**Application:** Leo  
**Targets:** Android and Windows  
**Status:** v0.27.0 is source-implemented. Platform qualification and physical-device validation remain pending. The milestones below are planned, not delivered.

## Delivered through v0.27.0

The workspace includes the v0.26.0 memory privacy controls plus v0.27.0 runtime/conversation resilience: actual loaded-context diagnostics, whole-turn application-side compaction with system-policy pinning, dynamic output allowances for chat/agent continuation/recovery, opt-in metadata-only runtime benchmarks, native nonblocking model-session operations, a memory reserve check, and a Rust-to-C++ pending-cancellation handshake. Exact boundaries and unverified platform checks are recorded in the v0.27.0 work log and validation report.

## Remaining Alpha milestones

| Version | Focus | What must be delivered |
|---|---|---|
| **v0.28.0** | Android qualification | Complete pinned Flutter/Rust/FRB/NDK/llama.cpp pipeline; build Android ARM64 app; test model loading/inference, storage, permissions, offline operation, voice, OS capabilities, encrypted memory and durable task/skill recovery on documented real devices. |
| **v0.29.0** | Windows qualification | Complete Flutter/Rust/FRB/MSVC/CMake/llama.cpp pipeline; validate x64 DLL discovery, local inference, model/voice storage, file picker, OS handoffs, secure storage, encrypted memory and task/skill recovery on supported Windows hosts. |
| **v0.30.0** | Alpha integration freeze | End-to-end v1.0.0 acceptance on both platforms; threat model, dependency/license review, offline regression, accessibility/localization, performance, memory/backup/recovery/privacy gates, upgrade/uninstall testing and release-blocker triage. |

## First buildable application

**`v1.0.0` — BETA entry.** This is the first coherent Leo application that builds and runs on both Android and Windows and meets the agreed baseline: local GGUF chat, rich answer rendering, automatic specialist agents, user-controlled encrypted long-term memory, reviewed and testable declarative skills, safe OS-first capabilities, explicit action approval, useful offline voice and offline-first behavior.

## Beta cycle

The channel changes to `BETA` for the tested `v1.0.0` contents. Feature work is frozen by default. Fixes use patch versions (`v1.0.1`, `v1.0.2`, ...). Any feature or app-resource change increases MINOR and repeats the affected acceptance tests. Beta ends only after device/OS matrix, offline, regression, security, privacy, key-loss recovery, backup/restore, permission-revocation, accessibility, performance and upgrade tests pass.

## Release cycle

The `RELEASE` channel is for final brand/icon locking, production Android and Windows packaging, signing, signature/checksum verification, clean install/upgrade/uninstall tests and publication. If the final icon is changed after the Beta candidate, that app-resource change requires a MINOR bump (for example `v1.1.0`). If the exact production icon is already present and tested in the Beta candidate, signing unchanged contents can use the same public version with `RELEASE` channel.

## Remaining count

- **3 planned Alpha milestones:** `v0.28.0` through `v0.30.0`.
- **1 first integrated application milestone:** `v1.0.0` (BETA entry).
- **Beta correction releases:** as needed, starting at `v1.0.1`; the number is determined by actual defects, not pre-fixed.
- **Release finalization:** after Beta exit; the public version is unchanged for signing-only changes, or increments MINOR if production app resources change.

This is a gated plan. A milestone is not considered complete because source files or a UI exist; its listed exit conditions, automated CI and required physical-platform tests must pass.


## Progress note — 2026-11-18

Android qualification preparation has started: the workspace now pins/checks the Android NDK revision, validates the generated runner and APK packaging contract, and defines a two-device acceptance protocol. This is preparation, not completion of `v0.28.0`; no Android production build or physical-device result is available yet. Keep the current source at `v0.27.0 / ALPHA` until the Android CI and device exit gates pass.

## Progress note — 2026-11-25

Android qualification CI now has an explicit reproducible-dependency gate: the Android build waits for the full-stack checks, requires both lockfiles to be present and committed, and resolves Flutter/Cargo dependencies in locked mode once those files exist. The bootstrap workflow validates newly generated lockfiles before packaging them. This closes a CI policy gap; it does **not** complete Android qualification. The current supplied source still has no `apps/leo_app/pubspec.lock` or workspace `Cargo.lock`, so the Android qualification job is intentionally blocked until the generated bootstrap files are integrated. Flutter/Rust/NDK builds and the two-device functional matrix are still pending. Keep the source at `v0.27.0 / ALPHA`.
