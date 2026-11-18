# Leo AI — Development Plan

**Product:** Leo AI
**Application:** Leo
**Starting milestone:** **Leo Alpha v0.1.0**
**Current implementation:** **Leo Alpha v0.27.0 (source implementation; platform validation pending)**
**Plan revision:** 0.1.0
**Status:** Approved planning baseline; implementation is in progress. Current source version: v0.27.0 Alpha. Android and Windows native inference/voice runtime still require successful CI builds and physical-device smoke tests.
**Date:** 2026-11-18

---

## 1. Purpose and delivery model

This document converts the Leo AI foundation architecture into an incremental development roadmap. It defines the delivery stages, version-number rules, work packages, exit criteria, quality gates and the intended first buildable application.

Leo is developed by selectively combining and adapting:

- **J.A.R.V.I.S:** conversation and workspace experience, rich message rendering, streaming, terminal/Git/workspace concepts, and request/approval UI patterns.
- **NEXUS:** local GGUF inference foundations, Rust bridge and runtime structure, model/resource management, local storage, task planning, knowledge retrieval, and optional peer-task foundations.
- **New Leo systems:** durable memory, learned and versioned skills, built-in specialist agents with automatic routing, OS/application-first capability discovery, permission brokerage, safe task execution, and local voice.

The project is a migration and integration, not a clean-room rewrite and not a blind copy of either archive. Original archives remain untouched reference inputs until each reused component has a migration decision and test baseline.

### Non-negotiable requirements

1. Android and Windows are first-class target platforms.
2. Core conversation, local inference, memory, skill use, supported local actions and voice must work without internet when the required model/voice packs are already present.
3. Internet-dependent activities must be identified honestly and queued or declined while offline; Leo must never pretend that an email or online action was sent.
4. OS and installed-app capabilities are preferred over implementing duplicate tools inside Leo. This is a mandatory architecture rule, not a later optimization.
5. Permissions are requested at first use, not at installation or first launch. A capability grant is separate from confirmation of a consequential action.
6. Leo ships with built-in specialist agents and chooses one or more automatically. User-created agents are optional customization only.
7. Memory and learned skills are persistent, inspectable, editable, versioned and removable. A skill must be tested before being promoted for routine use.
8. Agents and models never bypass the Capability Broker, Permission Broker or action policy.
9. Build and migrate incrementally. Do not perform a big-bang merge.
10. Third-party projects are not added until compatibility, maintenance status, license, security and package-size impact are reviewed.

---

## 2. Lifecycle stages

The lifecycle stage is recorded separately from the numeric application version. The numeric version always has exactly three components; the stage label is not an extra numeric component.

| Stage | Meaning | Main activity | Exit condition |
|---|---|---|---|
| **Alpha** | Construction and assembly | Source migration, core architecture, feature implementation, platform adapters, integration and internal builds | First coherent Leo application can be built and run on Android and Windows with the v1.0.0 baseline scope |
| **Beta** | Testing | Feature freeze, real-device testing, compatibility, performance, security, offline and regression testing; only justified corrections or essential changes | All release-blocking acceptance criteria pass and release candidate is approved |
| **Release** | Final product preparation | Apply/lock the final application icon and brand assets, create final platform packages, perform final signing, verify signatures and artifacts, publish release notes and checksums | Final signed artifacts pass clean-install, upgrade and smoke tests |

### Stage boundaries

- **Alpha is the build phase.** The team is expected to add and integrate the required systems. Alpha artifacts are engineering builds and are not represented as a finished consumer product.
- **Beta is the test phase.** New feature work is frozen by default. If an essential new capability must be added, it is versioned under the same rules and the affected Beta tests are repeated.
- **Release is the finalization phase.** The official final icon and final signing are performed here. A prepared icon concept may be reviewed earlier, but the production icon is not considered final until the Release gate.
- The stage label can change while the numeric version stays the same when the application contents have not changed. For example, the same tested `v1.0.0` build may move from Beta candidate to Release candidate if no app files or behavior are altered.
- If a Release-stage change modifies app resources or behavior (for example, replacing the actual icon asset), the numeric version must be bumped under the version policy before the new artifact is issued.

---

## 3. Application version policy

### 3.1 Format

The public application version is always:

```text
vMAJOR.MINOR.PATCH
```

For the initial development baseline:

```text
Leo Alpha v0.1.0
```

This is Leo's custom versioning convention. It resembles a three-part version string, but the meaning of the first component is specifically defined by Leo's product lifecycle below.

### 3.2 Meaning of each component

| Component | Meaning | When it increases | Reset rule |
|---|---|---|---|
| **MAJOR** (first number after `v`) | Application generation / completeness level | `0` means Leo is still in foundational assembly and construction. `1` is the first coherent, buildable Leo application. Increase it again for a major architectural or product-generation change. | When MAJOR increases, MINOR and PATCH reset to `0`. |
| **MINOR** (second number) | Feature or functional change counter | Every delivered feature addition or functional/configuration/resource change that changes the app. Examples: a new connector, a new agent capability, a new screen, or a changed app asset. | When MINOR increases, PATCH resets to `0`. |
| **PATCH** (third number) | Small correction counter | Small fixes that do not add a feature or materially change product behavior: Flutter/Dart/Rust analyzer fixes, static-analysis/test corrections, small defects, stability and compatibility fixes. | PATCH increases while MAJOR and MINOR stay the same. |

### 3.3 Required examples

| Change | Version example | Reason |
|---|---|---|
| Initial project assembly baseline | `v0.1.0` | Leo is in Alpha construction |
| Fix an analyzer warning without adding behavior | `v0.1.1` | Small correction: PATCH |
| Add the JARVIS-derived chat shell as a Leo feature | `v0.2.0` | Functional addition: MINOR |
| Fix a static test exposed by the chat-shell integration | `v0.2.1` | Small correction: PATCH |
| Integrate local NEXUS inference on Android | `v0.3.0` | Functional addition: MINOR |
| Complete the first coherent, buildable Leo application on both supported platforms | `v1.0.0` | First buildable application: MAJOR becomes 1 |
| Fix a Beta crash without adding a feature | `v1.0.1` | Small correction: PATCH |
| Add a new capability during a justified Beta cycle | `v1.1.0` | New functionality: MINOR; affected tests must be repeated |
| Replace the provisional icon asset with the final production icon at Release | `v1.2.0` (if this follows `v1.1.0`) | App resource change: MINOR; run packaging and visual smoke tests |
| Major redesign of the runtime/agent architecture after v1 | `v2.0.0` | New application generation: MAJOR |

The examples show the bumping rule, not a promise that every listed feature will ship in that exact milestone. The actual version is read from the repository's single source-of-truth `VERSION` file.

### 3.4 Bump rules and safeguards

- Never reuse a version number for two different application contents.
- Never decrease or silently rewrite a published version.
- A feature/behavior/resource change increments MINOR and resets PATCH to `0`.
- A small correction increments PATCH only.
- A major generation change increments MAJOR and resets the other two components.
- If a change set contains both a feature and a bug fix, use the higher applicable component (MINOR); do not issue two competing version numbers for the same build.
- Documentation-only edits that do not change the application, its configuration, assets or packaging do not change the application version. The development-plan revision can change independently.
- CI/build sequence numbers may exist as internal build metadata, but they do not replace or alter the public three-part version.
- A final icon is an app-resource change. If the icon is first inserted or changed at Release, MINOR increases. If its exact final files are already included and tested before the Release package is cut, no additional version bump is needed solely for signing the unchanged files.
- The stage (`ALPHA`, `BETA`, `RELEASE`) is stored separately in `RELEASE_CHANNEL` and shown separately in build labels. It is not a fourth version component.

### 3.5 Version source of truth

- `VERSION`: contains the public value, initially `v0.1.0`.
- `RELEASE_CHANNEL`: contains `ALPHA`, initially.
- Build scripts, app About screen, package filenames and release notes must read the version from these files; no duplicated hard-coded versions.
- Flutter's internal `MAJOR.MINOR.PATCH+BUILD` uses `config/BUILD_NUMBER` for the platform build code. BUILD is not part of the public `vMAJOR.MINOR.PATCH` version. Increment it only when creating a new installable artifact that needs a monotonically increasing platform build number.
- A version change requires a matching changelog entry and a CI check that the format and bump category are valid.

---

## 4. First milestone — Leo Alpha v0.1.0

**Milestone type:** Alpha / construction baseline.
**Meaning:** Establish a safe, reproducible development foundation for Leo. This milestone is not yet the first complete user-facing Leo application; that is `v1.0.0` after the Alpha assembly work is complete.

### Work package 0.1.0 — Foundation and source baselining

1. Create the Leo AI repository/workspace with clear application, Rust core, native, connector, configuration, documentation and test boundaries.
2. Preserve the two supplied archives as read-only source references. Record archive hashes, source commit/version data where available, top-level inventories and license notices.
3. Produce a file-by-file migration register classifying each relevant source component as: reuse directly, adapt, reimplement, defer, or reject. Record the reason and expected tests.
4. Establish the Flutter/Dart/Rust/Android NDK/Windows toolchain matrix. Resolve incompatible package and SDK constraints before moving feature code.
5. Create the initial shared domain contracts for `AssistantRuntime`, `AgentProfile`, `TaskPlan`, `MemoryRecord`, `SkillPackage`, `CapabilityDescriptor`, `PermissionGrant`, `ActionApproval` and `ExecutionResult`.
6. Create the version source-of-truth files and enforce the custom version policy in the build/release scripts.
7. Create the CI skeleton: formatting, Flutter analyze/test, Rust format/clippy/test, dependency/license checks and platform build jobs where runners permit.
8. Capture baseline results for both source projects. Do not claim a test passed unless it ran; mark unavailable toolchains and device-only tests as pending.
9. Add a temporary Leo application identity and development icon only as needed for engineering builds. Do not finalize branding or production signing in Alpha.
10. Record architecture decisions for the runtime boundary, agent routing, memory schema, skill format, capability discovery and permission flow before implementation dependencies spread.

### 0.1.0 deliverables

- Leo repository/workspace skeleton.
- `VERSION = v0.1.0` and `RELEASE_CHANNEL = ALPHA`.
- File-by-file JARVIS/NEXUS migration register.
- Dependency and toolchain compatibility matrix.
- License/third-party notice register.
- First architecture decision records and shared type contracts.
- CI checks and truthful baseline test report.
- A traceable Alpha backlog with each issue linked to a requirement and acceptance test.

### 0.1.0 exit criteria

- The two source archives are preserved unchanged and their reusable components are mapped.
- The development environment can reproduce the documented baseline.
- Core module boundaries compile in CI where the required toolchains/runners are available.
- No Hermes-only implementation has been adopted as Leo's mandatory AI runtime.
- The version and release-channel source-of-truth checks pass.
- No application feature is described as complete merely because its interface or stub exists.

---

## 5. Alpha construction roadmap — 0.x

### Live milestone state (2026-11-15)

- `v0.1.0` foundation/source baseline: created.
- `v0.2.0` chat shell/runtime boundary: implementation started; local session persistence, responsive UI, Markdown/code/math foundations, agent catalog/router contracts, task-plan validation, permission policy, and runtime selection are present. Flutter/Rust toolchain verification and native platform handlers remain open, so this milestone is not declared complete.
- `v0.3.0` Android local inference: model catalogue, Rust bridge API, Flutter model management screen and Android native build pipeline are implemented in source; successful NDK build, generated bridge build and physical-device offline inference remain unverified.
- `v0.4.0` Windows local inference: shared Rust dynamic loader, Windows DLL path, Windows memory diagnostics, MSVC CMake configuration and Windows CI packaging are implemented in source; successful Windows compilation and offline inference remain unverified.
- `v0.5.0` built-in agent routing: Arabic-normalized deterministic specialist selection, validated task-plan DAG construction and typed bridge preview endpoints are implemented in source. Independent agent model execution, scheduling, result aggregation and cancellation remain unimplemented; Cargo tests and FRB generation are pending a toolchain-enabled CI run.
- `v0.6.0` local memory foundation and `v0.7.0` user integration are implemented in source. `v0.8.0` adds an app-private skill library with proposal, structural/safety preflight, explicit activation, version history, disable/reject/delete, and bounded retrieval of active validated skills into transient chat context. `v0.9.0` adds declarative Agent Skills-style `SKILL.md` single-file import/export, with imported skills kept as inactive proposals. `v0.10.0` adds an explicit user-triggered action that asks the local model to extract a reusable skill proposal from the currently selected conversation; the transcript is bounded, treated as untrusted, and never used to execute tools. The result is always inactive and must be reviewed, preflighted and explicitly activated. This is not yet automatic learning from completed actions: Leo does not yet have an end-to-end task executor or durable execution trace store. Model-assisted scenario execution, encrypted skill storage and full folder/ZIP resource import remain unimplemented. Rust/SQLite, Dart/Flutter and FRB builds require toolchain-enabled CI validation.



Alpha builds may compile for engineering validation, but `0.x` means the integrated, first buildable Leo application has not yet been declared complete. The following are planned milestone targets. PATCH can advance between them for small fixes.

| Target | Work package | Main content | Exit evidence |
|---|---|---|---|
| **v0.1.0** | Foundation | Source inventory, migration map, toolchains, contracts, CI, version policy | Reproducible foundation and migration decisions |
| **v0.2.0** | Leo shell and JARVIS UI | Responsive Arabic-first chat workspace, local history/persistence, Markdown/math/code rendering, event-channel runtime boundary, no Hermes dependency | UI talks through a stable runtime boundary; local sessions survive restart; native runtime remains explicitly pending |
| **v0.3.0** | NEXUS local runtime on Android | Port NEXUS runtime/model manager, GGUF import/validation, local llama.cpp generation, streaming, cancellation, resource fit estimation | Actual offline generation on supported Android hardware; model lifecycle survives repeated loads/unloads |
| **v0.4.0** | Windows local runtime | Build the Windows x64 llama.cpp DLL, connect it through the shared Rust loader, add Windows memory probes and CI packaging | Actual offline generation on Windows; no UI-only or remote substitute accepted |
| **v0.5.0** | Built-in agents and orchestration foundation | Built-in specialist roster, Arabic-normalized automatic routing, validated task DAG preview, typed Flutter bridge endpoints | Current source delivers a valid specialist-team plan; full agent execution, handoff, aggregation and cancellation remain required before this work package exits |
| **v0.6.0** | Long-term memory foundation | SQLite schema/migrations, five memory kinds, pending/approved lifecycle, CRUD, source references, tags and Arabic-normalized BM25-style retrieval | Store and bridge APIs are implemented in source |
| **v0.7.0** | Memory user integration | Review/search UI, explicit approval/edit/disable/delete, app-private path, bounded and transient prompt retrieval | The user can inspect/control memory; only relevant approved/active records enter a bounded request context and never the saved transcript |
| **v0.8.0** | Skill learning foundation | App-private declarative skill library, workflow proposals, triggers, ordered steps, acceptance examples, structural/safety preflight, explicit activation, version snapshots and bounded active-skill retrieval | Approved validated skills persist across restart and are retrieved for matching requests; preflight is not a model execution test |
| **v0.9.0** | Portable skill interchange | Agent Skills-style `SKILL.md` import/export, validation of metadata and bounded text sections, imported proposals remain inactive, no scripts or permissions are imported | A skill can be exported, imported on another device and reviewed as a proposal without carrying executable code or approval state |
| **v0.10.0** | Conversation-derived skill proposals | Explicit local-model skill extraction from the selected chat, strict structured output validation, inactive proposal state, review/preflight/activation workflow, request cancellation | A supported conversation can produce a safe inactive proposal; no action is executed and unsupported/insufficient transcripts fail closed |
| **v0.11.0** | Capability Hub and permissions | Implemented scoped SQLite permission broker, first-use Leo consent, separate action confirmation, permission center, Android SAF/contacts/dialer/mail/SMS/URL/app-launch adapter, and Windows file-picker/text-preview/protocol/app-target adapter | Connector source is present; native compilation, CI and real-platform tests remain required |
| **v0.12.0** | Tool execution gateway | Strict versioned model tool-call protocol, per-tool schema validation, typed Capability Hub dispatch, three-call sequential loop, bounded untrusted results, metadata audit and denial/cancellation feedback | A local model can request a supported operation from chat; the Capability Hub independently validates Leo consent, OS state and one-action approval. Model adherence and platform builds still require validation |
| **v0.13.0** | Offline voice foundation | Local push-to-talk ASR and local TTS, optional model packs, microphone permission flow, playback controls and model-pack lifecycle | Source implementation integrated; platform builds, ASR/TTS inference and physical-device behavior remain unverified |

### Rules for all Alpha work packages

- A UI mock or unimplemented connector is not a completed feature.
- A platform feature is not complete until the native integration and a real platform test pass.
- Keep large model and voice weight files outside the source repository; manage them as separate, licensed model/voice packs.
- Prefer a common domain contract with platform-specific implementations rather than platform checks spread throughout the Flutter UI.
- Preserve working JARVIS rich-rendering code where it can be cleanly detached from Hermes.
- Preserve NEXUS inference and orchestration foundations where tests and platform boundaries are valid; do not import Android-only assumptions into Windows.
- Do not add a new embedded tool until the Capability Hub has checked for a native OS, installed-app, local CLI/API or MCP alternative.

---

## 6. First buildable application — v1.0.0

`v1.0.0` is the first coherent Leo app that can be built and run as an integrated product on both Android and Windows. It is the MAJOR transition out of the `0.x` foundational assembly series and the expected handoff from Alpha construction to Beta testing.

### Minimum v1.0.0 product scope

1. One Leo Flutter interface based on the JARVIS chat/workspace experience.
2. Local GGUF inference through llama.cpp on Android and Windows, with streaming, cancellation, model selection/import and resource-aware safeguards.
3. Rich answers: Markdown, mathematics, code blocks, tables, and readable file/task results.
4. Built-in specialist agents with automatic single/multi-agent selection; no manual agent creation prerequisite.
5. Persistent, inspectable long-term memory with control to edit/delete/export.
6. Skill creation from completed workflows, validation/testing, user promotion, versioning and rollback.
7. OS/application-first Capability Hub with a useful validated initial connector set on each platform.
8. Just-in-time permission requests, revocation handling, and per-action approvals for sensitive or destructive operations.
9. Offline speech input and output for the languages/voices that pass the agreed device benchmarks; the product must disclose any language/model limitations.
10. Safe local task execution inside approved workspaces; no unrestricted agent shell access by default.
11. Offline-first behavior with no mandatory cloud endpoint, API key, hosted account or online model provider.

### Explicitly not required for v1.0.0 unless the Alpha evidence shows they are necessary

- Distributed inference that splits one model across devices.
- Cross-device task mesh / peer delegation. NEXUS peer code remains a candidate for a later release after separate threat modelling and physical-device tests.
- Fine-tuning/LoRA training on the Android device. Skill learning and durable memory are the first learning mechanisms; weight training is a later advanced capability.
- Universal control of every third-party application. Use official APIs/intents/CLI first and supported UI automation as a fallback; unsupported applications must be reported honestly.
- Cloud search, cloud models or cloud memory as a requirement.
- A bundled large model inside the base installer. Models and voice packs should be independently installable/importable so the base app does not become unnecessarily large.

### v1.0.0 Alpha exit / Beta entry gate

- Android and Windows builds both launch and perform local inference without internet.
- A fresh install and a data-preserving update have been exercised on each platform.
- All v1.0.0 minimum-scope features have implementation evidence, not just screens or stubs.
- No known blocker prevents users from completing the core local assistant workflow.
- Automated unit/integration/static-analysis suites are green, with any unavoidable platform-only tests clearly scheduled in Beta.
- Release-channel changes to BETA only after the Alpha exit review is approved.

---

## 7. Beta testing roadmap — 1.x

Beta is a validation stage. The default policy is feature freeze. The work focuses on finding and correcting defects, platform incompatibilities, performance problems, security issues and poor-quality AI behavior.

### Test tracks

| Track | What must be tested | Evidence required |
|---|---|---|
| Installation and upgrade | Clean install, upgrade from prior build, interrupted update, uninstall/reinstall, data migration | Repeatable test report for Android and Windows |
| Offline behavior | Disable internet and DNS; test chat, memory, skills, files, local voice and supported local actions | No hidden cloud dependency; offline capability matrix |
| Model runtime | Model import, invalid/corrupt files, memory fit, load/unload, cancellation, long conversation, context limits, low-memory failure | Device logs, memory/latency results, crash-free repeated sessions |
| Android integration | Runtime permission request timing, denial, revocation, selected-file access, intents, app visibility, telephony handoff, background/foreground lifecycle | Real-device results on defined Android device tiers |
| Windows integration | Standard-user operation, file scopes, process execution, UI Automation limits, UAC boundaries, microphone access, installed-app handoff | Real Windows test report; no permanent Administrator requirement |
| Agent routing | Simple request uses minimal agents; complex task selects relevant specialists; no unnecessary agent fan-out | Recorded task plans and routing evaluation set |
| Agent safety | Prompt injection, untrusted files, malicious skill content, unauthorized connector call, agent attempting to bypass a permission | All blocked or safely contained; security regression tests |
| Memory | Correct recall, stale facts, conflicts, user correction, deletion, export, migration | Memory test corpus and privacy checks |
| Skill learning | Skill proposal, tests, approval, failed skill, update, rollback, disable/delete, permission isolation | Repeatability evidence across fresh sessions |
| Voice | Arabic and English recognition, accent/noise, punctuation, latency, TTS intelligibility, interruption, wake-word if included | Published benchmark set from real recordings, not a feature checklist |
| Performance | CPU/RAM/GPU use, thermal behavior, battery on Android, startup time and model-switch time | Measurements on minimum and recommended hardware tiers |
| Security and privacy | Local data protection, file sandbox, secrets/logs, IPC, local network exposure, native library supply chain | Threat-model review and remediation register |
| Presentation | Math/LaTeX correctness, code/table rendering, RTL, accessibility, long-output behavior | UI regression and representative answer set |

### Beta version examples

- `v1.0.0`: first Beta candidate after Alpha exit.
- `v1.0.1`, `v1.0.2`: bug/stability/analyzer/test fixes.
- `v1.1.0`: a justified functional addition or behavior/resource change; affected tests repeat and feature freeze is re-established.

### Beta exit criteria

- No open release-blocking defect in core local chat, inference, memory, skills, permissions or essential connectors.
- All mandatory automated tests pass on the pinned toolchain.
- Android and Windows clean-install and upgrade tests pass.
- Offline tests pass for every capability advertised as offline.
- Denied/revoked permissions reliably block actions.
- Sensitive actions have appropriate confirmation and an auditable local result.
- Agent selection quality meets an agreed evaluation set; agents cannot call around policy enforcement.
- Skills can be tested, inspected and rolled back; no skill can grant permissions.
- Arabic/English voice limitations are documented honestly and meet the agreed minimum quality threshold.
- Resource limits and minimum supported device specifications are documented.
- A release candidate is frozen and approved.

---

## 8. Release finalization

Release starts only after Beta exit approval.

### Required Release work

1. Lock the final Leo icon and brand assets for Android and Windows. Prepare all required icon sizes, adaptive icon layers, Windows icon/package assets and in-app branding.
2. Check that no temporary Alpha/Beta icon, debug label, sample data, development endpoint, test credential or verbose private log remains in the production package.
3. Finalize app identifiers, package metadata, permissions declaration, version display and release notes.
4. Create and protect the Android production signing key. Keep it outside source control and back it up securely.
5. Sign Windows packages with the selected production signing arrangement. If a trusted code-signing certificate is unavailable, document the resulting publisher/trust warning and do not imply that a self-signed package is trusted by Windows by default.
6. Generate final packages, checksums and a component/license notice.
7. Verify signatures and hashes after packaging.
8. Run final smoke tests on clean Android and Windows environments, including installation, launch, offline chat, model selection, permission prompt, and update path.
9. Publish release notes that distinguish offline functionality from network-dependent actions.

### Release version handling

- Signing an unchanged binary and changing only release metadata/channel does not by itself require a public version bump.
- Changing the final icon or any other app resource is a MINOR change under Leo's version policy unless that exact resource was already included in the candidate that was tested.
- If an app file changes after Beta approval, rebuild and repeat the relevant regression tests before signing. Never sign a different untested binary just to keep the version label unchanged.

---

## 9. Development workflow and quality rules

### Migration workflow

For each selected subsystem:

1. Inspect the source and its dependencies.
2. Record the decision: reuse, adapt, reimplement, defer or reject.
3. Capture a baseline test or a known limitation.
4. Move/adapt the smallest coherent unit.
5. Add domain-level tests before connecting UI.
6. Connect to the shared interface.
7. Run static analysis and platform tests.
8. Update migration register, changelog and version.
9. Only then begin the next dependent subsystem.

### Required CI checks

- Flutter formatting, analyze and unit/widget tests.
- Rust formatting, clippy and unit/integration tests.
- Bridge/API contract generation or consistency checks.
- Dependency/license and known-vulnerability scan.
- Android build validation.
- Windows build validation on a Windows runner.
- Version-format/channel/changelog checks.
- Connector manifest schema and permission-scope tests.
- No release job may sign or publish from an unreviewed branch or failed test run.

### Release artifacts

During Alpha/Beta, artifacts are marked internal/test builds and must not be presented as final releases. The exact production formats (APK/AAB and Windows installer/portable package) are selected after packaging requirements are validated. The base installer should not contain every model, voice and optional connector; keep these as separately managed packs where practical.

---

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| JARVIS chat UI remains coupled to Hermes | Create and test `AssistantRuntime` boundary before importing AI-dependent features |
| NEXUS Android-only native code blocks Windows | Build Windows adapter as a separate early milestone; require real local generation on Windows before v1.0.0 |
| Flutter/Dart/package constraints conflict | Pin a common toolchain and resolve incompatibilities before feature migration |
| Embedded tools make app large and duplicative | Mandatory OS/app-first Capability Hub; optional connectors are installed/discovered separately |
| One model is too large for lower-end Android devices | Define hardware tiers, model fit checks, quantized model options and graceful fallback |
| Agent routing is unpredictable or expensive in device resources | Use one agent by default, bounded fan-out, explicit task graphs and evaluation tests |
| Skill content contains dangerous steps | Skills are data/workflows, not permission grants; validate scripts, sandbox execution and ask for approval |
| Long-term memory stores incorrect or sensitive facts | Provenance, confidence, explicit memory controls, inspect/edit/delete/export and local-only storage |
| Android app-control expectations exceed OS policy | Official intents/APIs first; disclose unavailable actions; UI automation only where permitted |
| Windows UI Automation cannot control a custom app | Prefer application-specific APIs/CLI; treat UIA as a best-effort fallback |
| Offline promise is undermined by hidden network calls | Automated offline test with network blocked and an inventory of all network-capable modules |
| Third-party model/voice licenses are unclear | Track code and model licenses separately; do not bundle unverified weights |

---

## 11. Post-v1 roadmap candidates

These items are valuable but should not delay the first coherent, genuinely offline Android/Windows app unless testing shows they are prerequisites:

- NEXUS-style encrypted peer discovery and task delegation over the local network.
- More advanced local RAG with embedding models and a vector index.
- Local image/document vision and OCR pipeline.
- Model fine-tuning/LoRA workflows on capable Windows hardware.
- Optional connectors for more installed applications.
- Wake-word background behavior where platform rules and battery tests permit it.
- Expanded model routing and multiple local models with explicit memory budgeting.

Every post-v1 capability remains subject to the same OS/app-first, least-privilege, local-first, versioning and test rules.

---

## 12. Immediate next execution sequence

The first implementation cycle begins with **Leo Alpha v0.1.0** and must proceed in this order:

1. Establish the repository/workspace and commit the version/channel policy.
2. Compute and record hashes of the supplied JARVIS and NEXUS archives; preserve the originals.
3. Produce a file-by-file migration register and dependency/licensing inventory.
4. Run fresh baseline Flutter and Rust checks where toolchains are available; report unavailable tools separately from failures.
5. Pin the common Flutter/Dart/Rust/NDK/Windows build matrix.
6. Create the shared Rust domain contracts and Flutter bridge skeleton.
7. Add CI gates and ensure both platform targets are represented.
8. Review the 0.1.0 exit criteria before raising the first feature milestone.

No source migration or deletion should precede the archive inventory and baseline. No feature is considered complete until its acceptance evidence exists.

---

## 13. Delivered milestone — Alpha v0.12.0

The Capability Hub and Permission Broker introduced in v0.11.0 are now connected to a structured local-model Tool Execution Gateway in v0.12.0. The model can propose one versioned, allowlisted tool call as its entire response. Flutter validates the envelope and exact argument schema, then routes it through typed `CapabilityHubService` methods only. The user turn is limited to three sequential tool calls. Tool results are passed back to the local model as bounded untrusted observations; raw tool blocks and tool outputs are not persisted as chat messages.

The current allowlist covers selected-file text reading, Android contacts reading, email drafts, dialer handoff, Android SMS drafts, HTTP/HTTPS opening and supported installed-app launch. The Capability Hub remains authoritative for first-use Leo consent, operating-system permission/resource selection and separate consequential-action confirmation. Windows contacts and SMS are intentionally unavailable. Email and SMS do not send silently, and phone operations open the dialer without placing a call. A metadata-only audit screen stores the tool name, status, timestamp and fixed non-sensitive summary; it excludes user arguments and operation content.

This is a bounded first execution layer, not unrestricted device automation. Arbitrary shell/PowerShell, direct process execution, file writes/deletes, direct send/call, general UI automation, microphone capture and planner-generated tool DAG execution remain disabled. The loop is sequential and relies on the local model following the structured protocol. The audit preference store is app-private but not separately encrypted.

Python source/architecture contract tests, version checks and source-archive integrity checks are available in this workspace. Dart/Flutter/Rust and platform-native builds remain unverified in this environment because the corresponding SDKs/toolchains are unavailable; CI and physical Android/Windows validation are required before claiming a buildable or installable release.

## 14. Delivered milestone — Leo Alpha v0.13.0: Offline Voice Foundation

- Integrated `sherpa_onnx` 2.0.1 for offline ASR/TTS, `record` 7.2.0 for microphone PCM16 capture, and `audioplayers` 6.8.1 for local WAV playback.
- Added optional user-imported Qwen3-ASR 0.6B INT8 and Supertonic 3 INT8 packs stored outside the base application installer.
- Added bounded streamed pack import, staged replacement/rollback, and an explicit model catalog.
- Added Android/Windows push-to-talk UI, local transcription into the composer, local TTS output, and visible playback controls. The current capture is capped at 30 seconds and transcription starts after the user stops recording.
- Added just-in-time Leo microphone consent, Android runtime permission request, and Windows microphone-privacy settings handoff. Windows per-app permission state is not independently queryable through the selected recorder plugin.
- Added Windows runner preparation for the CMake 3.15/CMP0091 compatibility used by `audioplayers_windows`.

**Alpha 0.13.0 limitations:** no VAD/automatic endpointing, no streaming partial transcription, no wake word or background listening; ASR runs after recording stops (maximum 30 seconds); TTS creates a complete WAV before playback; model packs are not bundled and their provenance is not cryptographically verified by the importer. Arabic and English are model-supported, but Sudanese-dialect accuracy and device performance remain to be tested on real hardware. Build and native compilation checks must pass in CI before the app can be called buildable.

## 15. Delivered milestone — Leo Alpha v0.14.0: Voice integrity and runtime resilience

- Added streamed per-file SHA-256 digests while importing voice packs, avoiding whole-model buffering in memory.
- Added a versioned `.leo-voice-pack.json` manifest with fixed pack identity, relative paths, sizes, hashes and verification state.
- Added strict validation of required manifest entries, duplicate names, per-file and aggregate size bounds, and UTC verification timestamps.
- Preserved complete legacy packs as `legacyUnverified`; a user-triggered audit can create a local baseline without forcing re-import.
- Added a full re-hash operation that detects same-size file changes and disables a pack when the recorded baseline no longer matches.
- Clarified that local hashes are change-detection baselines, not publisher authentication or proof of upstream provenance.
- Added a pure-Dart PCM16 mono WAV encoder, lazy audio-player initialization, playback-generation isolation and deterministic recorder cleanup improvements.
- Added Dart unit tests for WAV output and voice-pack import, baseline creation, verification and tamper detection.

**v0.14.0 validation boundary:** source and Python contract checks can be run in this workspace, but Dart/Flutter tests, Flutter Analyze, Cargo tests, native compilation and physical Android/Windows voice tests remain pending because their SDKs are not installed here. This milestone is source-implemented, not a verified installable build.

## 16. Delivered milestone — Leo Alpha v0.15.0: Voice endpointing and diagnostics

- Added a separate optional Silero VAD model pack, downloaded/imported by the user and stored under the same app-private, bounded, SHA-256-manifest voice-pack system.
- Added fixed 512-sample, 16 kHz VAD frames and silence-based endpointing. A completed speech segment requests the existing transcription path; the original PCM buffer remains the ASR input.
- Preserved the manual push-to-talk stop and 30-second hard cap. Missing, invalid or runtime-failing VAD falls back to manual stop rather than disabling capture.
- Added a user switch for automatic endpointing and official model/documentation actions in the local voice-model library.
- Added app lifecycle handling: leaving the resumed state cancels active microphone capture and stops speech playback. No background listening is introduced.
- Added an explicit native Sherpa/ONNX runtime preflight with user-visible version/error output.
- Added default-off, local-only ASR/TTS metadata diagnostics for model-load duration, inference duration, process RSS high-watermark, runtime versions, UTC completion time and an error stage. No audio, transcript, prompt or file path is recorded; disabling metrics clears stored records.
- Added contract and unit tests for fixed PCM framing, VAD pack import/integrity, and opt-in diagnostics storage.

**v0.15.0 validation boundary:** Python contract tests, version synchronization, JSON/YAML/TOML/CSV parsing and preservation-hash checks can be run in this workspace. Flutter/Dart tests and analysis, Rust/Cargo checks, Android/Windows native builds and real-device VAD/audio behavior remain pending because the SDKs/toolchains and devices are not available here. The process RSS value is a process high-watermark, not a per-operation memory delta.

**v0.15.0 exit criteria:** CI must pass Dart format/analyze/tests and Rust checks; Android ARM64 and Windows x64 debug builds must compile; a physical-device test report must document VAD false stops/missed endpoints, ASR quality, TTS playback, interruption cleanup, latency and peak memory.

## Delivered milestone history

- `v0.11.0`: Capability Hub and persistent JIT Permission Broker (source implemented; platform validation pending).
- `v0.12.0`: Structured Tool Execution Gateway (source implemented; model adherence and platform validation pending).
- `v0.13.0`: Offline Voice Foundation (source implemented; CI/native compilation and physical-device tests pending).
- `v0.14.0`: Voice integrity and runtime resilience (source implemented; CI and physical device tests pending).
- `v0.15.0`: Optional VAD endpointing, lifecycle cleanup and opt-in voice diagnostics (source implemented; CI and physical-device tests pending).
- `v0.16.0`: Local ASR quality evaluation harness and capture-session cancellation safety (source implemented; real-device accuracy/latency and native tests pending).

## 17. Delivered milestone — Leo Alpha v0.16.0: Voice quality evaluation and session safety

- Added a deterministic, local-only ASR evaluation runner for supplied reference/hypothesis text pairs.
- Reports corpus-level WER and CER with Arabic normalization (diacritics, tatweel and alef variants), per-language breakdowns, inference/model-load median and p95 latency, and maximum reported process RSS.
- Enforced a strict input schema that rejects raw audio, audio paths, prompts and unsupported fields. Reports retain only opaque sample IDs and aggregate metrics; reference and recognized text are never copied into the report.
- Added an editable JSON template and automated tests. The template is intentionally a prompt for the developer to populate with genuine, consented test utterances; no fabricated accuracy baseline is shipped.
- Hardened the voice service with a single-flight transcription guard and capture-generation checks. Cancellation invalidates stale recognition results before they can be returned to the composer.

**v0.16.0 validation boundary:** Python evaluation/contract tests can run in the authoring workspace. The actual recognizer accuracy and latency remain unmeasured until real Android and Windows devices are evaluated with the same corpus. Flutter/Dart/Rust/native tests and installable builds are still required.

## 18. Delivered milestone — Leo Alpha v0.17.0: Model resource policy and voice usability

- Added a model-load configuration dialog with GGUF-compatible context presets, a selectable CPU thread budget and a transparent resource estimate.
- Mirrored the native loader's conservative admission formula in a pure-Dart policy module and added unit coverage for the arithmetic, invalid input, context limits and thread budgets.
- Kept the real available-memory check in the native adapter immediately before allocation: Android `MemAvailable` and Windows `GlobalMemoryStatusEx`. The dialog explicitly states that its threshold estimate is not a live free-memory reading.
- Changed the chat model default to a context no greater than 2048 tokens and capped its recommended CPU thread count at four while reserving one logical processor where possible.
- Applied a smaller dynamic thread budget (one or two threads) to VAD, ASR and TTS workloads.
- Added whole-process RSS/peak-RSS visibility and a pre-capture warning when a GGUF chat model is loaded. The user decides whether to continue; Leo does not unload the chat model automatically.

**v0.17.0 validation boundary:** the Python source/architecture suite and the host-side fake-llama C ABI contract can run here. Dart unit tests, Flutter analyze, Rust/Cargo tests, real Android/Windows builds and low-memory physical-device trials remain pending because the corresponding SDKs/toolchains and devices are unavailable. The displayed memory threshold is an estimate; the native adapter remains the authoritative live-memory gate.

**v0.17.0 exit criteria:** CI passes Dart format/analyze/tests and Rust checks; Android ARM64 and Windows x64 builds compile; real-device tests verify low-memory refusal, selected context/thread behavior, voice interruption, and RSS/latency measurements.

## Delivered milestone history

- `v0.11.0`: Capability Hub and persistent JIT Permission Broker (source implemented; platform validation pending).
- `v0.12.0`: Structured Tool Execution Gateway (source implemented; model adherence and platform validation pending).
- `v0.13.0`: Offline Voice Foundation (source implemented; CI/native compilation and physical-device tests pending).
- `v0.14.0`: Voice integrity and runtime resilience (source implemented; CI and physical device tests pending).
- `v0.15.0`: Optional VAD endpointing, lifecycle cleanup and opt-in voice diagnostics (source implemented; CI and physical-device tests pending).
- `v0.16.0`: Local ASR quality evaluation harness and capture-session cancellation safety (source implemented; real-device accuracy/latency and native tests pending).
- `v0.17.0`: GGUF resource planning, conservative CPU budgets and user-confirmed shared-memory voice operation (source implemented; toolchain and real-device validation pending).
- `v0.18.0`: Sequential multi-agent DAG execution, bounded retry, dependency-aware partial results and task cancellation (source implemented; Rust/FRB/Flutter/platform validation pending).
- `v0.19.0`: Role-scoped agent tool proposals through the existing Capability Hub, strict one-proposal validation and untrusted result handoff (source implemented; Rust/Dart/FRB/platform validation pending).

## 19. Delivered milestone — Leo Alpha v0.18.0: Reliable multi-agent execution

- Connected the validated task-plan DAG to a real local inference coordinator. Multi-domain requests selected by the built-in router now run planner, specialist and verifier steps through the loaded GGUF runtime.
- Added explicit step lifecycle results, dependency-aware scheduling, stable sequential execution, retryable/permanent error classification, dependent-step skipping and partial-result reporting.
- Added two attempts by default with a hard maximum of three, a 6,000-character task-goal cap, bounded step/dependency/conversation context, per-agent instruction profiles and final verifier output selection.
- Added request-scoped cancellation from Flutter through the Rust bridge to the active native generation; stream disconnection also requests cancellation.
- Activated automatic multi-agent routing in chat for complex reasoning tasks. Communications, device-operation and file-operation requests, plus explicit edit/run/build instructions, stay on the existing Capability Hub and approval path.
- Kept agent execution inference-only. Agents cannot call shell, mutate files, operate the OS, send messages, make calls or perform network work; roles do not grant permissions.

**v0.18.0 validation boundary:** Python source/architecture tests, version checks and immutable archive checks can run in this authoring workspace. Rust unit tests have been added but Cargo/Rust is unavailable; FRB generation, Dart format/analyze/tests, Android/Windows builds and physical-device multi-agent tests remain pending. This is source-implemented, not an installable verified build.

**v0.18.0 exit criteria:** CI must generate the new FRB bindings; compile/test the scheduler; pass Dart formatting, analysis and widget/unit tests; build Android ARM64 and Windows x64; then verify multi-agent completion, cancellation, failure recovery, tool-boundary enforcement and memory/latency on physical devices.

## 20. Delivered milestone — Leo Alpha v0.19.0: Safe agent tool handoff

- Enabled a narrow proposal-only handoff from three reviewed built-in roles: `file_operator` → `files.read_selected`, `device_operator` → `web.open` / `app.launch`, and `communications` → `email.compose` / `messages.compose` / `phone.dial`.
- Added a Rust-side strict wrapper/JSON/version/ID/argument-shape/role mapping validator with a 16 KiB envelope cap and a maximum of one proposal per agent task. Malformed, duplicate, unsupported or out-of-role proposals fail closed.
- Added a terminal `agent_tool_proposal` event over the existing `AgentTaskEventDto`; no generated bridge schema change is required. The event contains only a proposal and is never executed by Rust.
- Added Dart-side protocol re-parsing and a second role/tool allowlist check immediately before handoff.
- Reused the existing Flutter `ToolExecutionGateway` and `CapabilityHubService` for Leo consent, OS permissions/resource selection, scope validation, user confirmation and typed Android/Windows adapter calls.
- Returned bounded prior-agent notes and the tool result as untrusted context. In v0.19 the agent DAG did not resume after the handoff; that limitation is addressed in v0.20.0.
- Kept edits, writes, deletes, shell commands and unsupported operations unavailable.

**v0.19.0 validation boundary:** Python source/architecture contracts can run in this workspace. Rust/Cargo and Dart/Flutter toolchains are unavailable, so new Rust and Dart tests, formatting, analysis, FRB codegen and native builds were not executed here. Physical Android/Windows approval, denial, cancellation and tool-result tests remain mandatory.

## 21. Delivered milestone — Leo Alpha v0.20.0: Multi-step tool-aware task continuation

### Delivered in source

- Added `AwaitingToolApproval` as an explicit coordinator state. The DAG pauses immediately after a successful action-specialist proposal rather than allowing dependent steps to run before the action result exists.
- Added `execute_with_initial_results` to resume the same validated plan from successful checkpoints. Completed agent steps are not invoked again; only remaining eligible steps continue.
- Added strict restored-checkpoint validation: every result must refer to a known step, match its assigned agent, be successful, have no error, remain within the attempt/output limits, be unique, and include all successful dependencies. A downstream checkpoint without its prerequisites is rejected before any model call.
- Added serial, one-at-a-time action handoffs across a multi-agent task. The user-turn budget remains three tool calls; a model cannot provide a batch of actions or bypass the role/tool allowlists.
- Added exact resume receipts bound to task ID, tool-call ID and tool name. Only the six-field versioned receipt with `success: true` can attempt to resume a matching pending continuation.
- Added process-local pending state with a ten-minute expiry, a maximum of eight pending tasks, one pending continuation per task, and removal only after a matching receipt. Invalid/mismatched receipts do not consume a valid pending continuation.
- Added bounded untrusted context for successful earlier-agent outputs and external tool results. The prior proposal envelope is excluded; no agent note or tool result becomes an instruction or approval.
- Connected Flutter chat to resume the same task only after `ToolExecutionGateway` returns a successful outcome. Denial, cancellation, failure, disposal or bridge errors stop the continuation; no failed action is represented as success.
- Added Rust/Dart unit tests and Python source-contract tests for the pause/resume lifecycle, serial handoff cap, dependency closure, receipt shape/binding, invalid-receipt preservation and untrusted context.

### Safety, state and persistence boundaries

- The resume receipt is an internal bridge protocol check, not a permission grant or approval token. The Capability Hub remains the only path to OS operations and **موافقة المستخدم على كل إجراء** remains mandatory.
- Pending continuations are held in process memory only. They expire after **10 minutes (10 دقائق)**, are limited to **8** simultaneous pending tasks, and are lost **after إعادة تشغيل التطبيق**. Leo **لا يستأنف التنفيذ تلقائياً بعد إعادة تشغيل التطبيق** and never replays an action automatically. Durable, user-reviewed recovery is a separate future milestone.
- The maximum is three successful serial tool handoffs per user turn. Reaching the cap disables further agent proposals for that turn; no unrestricted chain is enabled.
- A successful OS handoff means only what the gateway confirms. It does not mean that a composed email/SMS draft was sent or that a dialer handoff placed a call.

**v0.20.0 validation boundary:** Python architecture/contract tests, version checks, source archive hashes and source/config parsers are available in this workspace. Rust unit tests and Dart unit tests are present but were not run because Cargo/Rust and Flutter/Dart are unavailable. FRB generation, Rust formatting/tests/clippy, Dart formatting/analyze/tests, Android/Windows builds and physical-device multi-action tests remain pending. This is source-implemented Alpha, not a verified installable build.

**v0.20.0 exit criteria:** CI must pass the full Rust and Dart suites, FRB code generation and both platform builds. Physical tests must cover one, two and three serial actions; each approval/denial/cancel branch; malformed/replayed/expired receipts; task cancellation during an action; app process restart; and proof that completed steps are not rerun.

## 22. Delivered milestone — Leo Alpha v0.21.0: Durable task ledger and restart recovery

### Delivered in source

- Replaced the process-local pending continuation map with versioned task checkpoints persisted through `flutter_secure_storage` on the Android and Windows targets.
- Added an initial plan checkpoint before the first model inference, then emitted a fresh checkpoint after every successful DAG step. This means a restart during the first step still has a plan to recover, even when there are no completed results yet.
- Checkpoints carry the task ID, goal, bounded conversation context, validated plan, successful step results only, a pending proposal when one exists, and the completed-handoff count. Rust revalidates the entire plan against the built-in agent catalog and revalidates each result, assigned agent, attempt/output bounds, uniqueness and dependency closure before continuing.
- Added a secure local store bounded to eight pending tasks, 256 KiB per checkpoint, 640 KiB total serialized data and seven-day retention. Each task is linked to the original conversation session. Invalid/duplicate records fail closed.
- Added three durable states: `running`, `awaitingAction`, and `readyToResume`. A successful OS/app handoff result is persisted before Rust receives its resume receipt.
- Added a chat recovery panel to restore or discard saved tasks. `running` tasks resume from successful completed steps; `readyToResume` tasks continue from a saved successful handoff result.
- Added a manual review path for the ambiguous crash window after a proposal was persisted but before the action outcome was saved. Leo asks the user to inspect the external surface and either cancel the task or explicitly confirm the handoff. The saved text identifies this as user-reported rather than independently verified.
- App-background cancellation preserves the last checkpoint; the user's explicit Stop command deletes it. A pending external action is never replayed automatically after a restart.
- Added explicit Android backup/device-transfer exclusions for SharedPreferences plus `android:allowBackup="false"` in the generated runner, preventing encrypted preferences from being restored without the matching Android Keystore key.
- Added Dart tests for store and receipt behavior, Rust checkpoint tests (including an empty initial checkpoint), and Python source-contract tests. Added the BSD-3-Clause notice for the secure-storage dependency.

### Safety and persistence boundaries

- The secure store is local only; no cloud sync or cross-device recovery is implemented.
- A checkpoint is not a permission grant. Every external action still travels through the existing tool allowlist, Capability Hub, OS permission checks and a separate user confirmation.
- If secure persistence fails, Leo cancels the active reasoning operation and does not show the action approval UI. It does not downgrade to plaintext storage.
- If an update fails after an earlier checkpoint was saved, Leo retains that last known-good checkpoint. It does not delete the older recovery point or downgrade to plaintext storage. If no checkpoint had ever been saved, no recovery point is claimed.
- If a task is awaiting an external action at restart, Leo will not guess whether that action ran. Only the user can decide after manually checking the external app/OS state.
- Checkpoints expire after seven days; up to eight are kept. Full checkpoints and model outputs can include private context, so the store is encrypted and strict size-limited.
- The secure storage package `11.2.0` supports Android and Windows; Android uses encrypted storage by default and requires backup exclusions for Keystore-bound preferences. Windows builds require the C++ ATL component. These dependencies remain subject to platform build/device validation. citeturn100353search1turn100353search0

**v0.21.0 validation boundary:** Python architecture/contract tests, version synchronization, source archive checksums and configuration parsers can run in this workspace. New Dart/Rust unit tests are authored but were not run because Flutter/Dart and Cargo/Rust are not installed. FRB codegen, formatting/analyze/clippy, Android/Windows builds, secure-storage integration and physical process-restart tests remain pending. This is source-implemented Alpha, not a verified installable build.

**v0.21.0 exit criteria:** CI must pass all Rust and Dart tests plus formatting/analyze/clippy and FRB regeneration. Android tests must cover Keystore persistence across process death, backup/restore exclusions, upgrade and secure-store corruption. Windows tests must cover DPAPI-backed persistence across process restart and user-profile boundaries. End-to-end tests must cover interruption before first inference, between steps, after an action proposal, after successful action-result persistence, after the second handoff, expiry, manual cancel and explicit user Stop. No action may be automatically repeated.

## 23. Delivered milestone — Leo Alpha v0.22.0: Safe workspace editing

### Delivered in source

- Added a role-scoped `workspace.write_file` tool proposal for `file_operator`, with strict schema validation in Rust and Dart and independent validation in each native adapter.
- Added user-selected workspace access on Android through the Storage Access Framework document-tree picker and on Windows through the native folder picker. Workspace handles are short-lived, in-memory session tokens; Leo does not request broad storage access or retain Android tree grants.
- Limited each operation to creating or replacing one UTF-8 text file directly under the selected folder. The filename is limited to 160 UTF-8 bytes; content is limited to 16 KiB and 10,000 Unicode code points. Path traversal, nested paths, reserved Windows device names, control characters and binary NUL content are rejected.
- Added a bounded before/after preview and SHA-256 checks for the current and proposed content. Every actual write has its own separate user approval showing the selected folder, filename and diff. A file whose contents already match is treated as a no-op.
- Added staged writes, post-write hash verification and backup/rollback handling. Android fails closed when a document provider cannot list or stage/rename safely; Windows uses same-folder staging and the native replacement APIs.
- Kept the audit trail metadata-only. It does not store the filename, file content, diff, prompt or model arguments.
- Added contract coverage for role restrictions, path/content limits, approval order, SAF and Windows adapter boundaries, rollback, cleanup warnings and task checkpoint compatibility.

### Safety and platform limitations

- This is not a general filesystem API. Leo cannot create directories, write nested paths, delete, move or rename files, execute shell/PowerShell, spawn arbitrary processes, or perform bulk writes. The current action affects one file only.
- Android Storage Access Framework providers vary. They do not expose compare-and-swap rename, so an independent external writer can still race between the final recheck and replacement. A failed staging/replacement operation is rejected; a backup that cannot be cleaned after a verified write is reported to the user and is not misreported as a failed write.
- Windows reparse points are rejected and the final file is re-hashed after replacement. A narrow race with an independent external writer between the last check and native replacement remains a platform limitation.
- Rust/Dart tests, formatting/analyzer checks, FRB generation, Kotlin compilation, Windows MSVC compilation, Android/Windows application builds and physical-device tests remain pending in this authoring environment. The implementation is source-complete for this Alpha milestone, not a verified installable build.

**v0.22.0 exit criteria:** CI must pass Rust and Dart suites, format/analyze/clippy and FRB generation. Physical tests must cover new file and replacement, denied/cancelled approval, an external file change between preview and apply, duplicate/invalid names, SAF providers without rename support, low storage, process interruption, backup cleanup failure, Windows reparse points and rollback. Tests must prove no path outside the selected workspace can be modified and the audit contains no file path/content.

## 24. Delivered milestone — Leo Alpha v0.23.0: OS capability expansion

- Added user-selected safe document opening through the Android content URI / Windows file association, with explicit extension allowlists and per-handoff confirmation.
- Added system calendar event-draft handoff on Android through `CalendarContract` insert intent and on Windows through a bounded temporary ICS file opened by the registered handler. Users must save the event themselves; no calendar provider permission or direct database write is used.
- Added write-only system clipboard copy on Android and Windows, with a preview and per-copy approval; Leo does not read the previous clipboard content.
- Expanded Rust capability catalog, policy JSON, role-scoped tool protocol, tool execution gateway and agent routing, with independent native validation and bounded payload/date checks.

**v0.23.0 validation boundary:** Python source/architecture contracts and source/config checks passed in the authoring workspace. Dart/Flutter, Rust/Cargo, Android Gradle/Kotlin and Windows MSVC builds and physical-device handoff tests remain required. Source implementation is not proof of a buildable or installable binary.

## 25. Delivered milestone — Leo Alpha v0.24.0: Agent-guided declarative skill execution

### Delivered in source

- Added a dry-run skill preview in chat for eligible multi-agent requests. It shows the selected active skill's ordered steps, full additional instructions, selected acceptance examples and declared capability metadata. The user must explicitly choose to run the skill; otherwise the task continues without the skill execution envelope.
- Rechecks the skill record after the dialog and requires the same ID/version to remain active and structurally validated before creating a run. A disabled, removed, edited or stale skill is not executed under its previously previewed version.
- Builds a bounded `<leo_skill_execution_contract>` for the existing local agent DAG. Skill instructions, steps, tests and declared capabilities are untrusted context only; the agent can use only existing role-scoped tools, and every external action still requires a separate Capability Hub approval.
- Added `SkillRunRepository` using `flutter_secure_storage`, with strict versioned JSON validation, a maximum of 20 records, a 512 KiB store budget and 30-day retention. It does not duplicate the raw user goal, tool arguments, file paths or file contents.
- Added safe capacity behavior: only terminal records (`verified`, `failed`, `cancelled`) may be evicted. If all slots contain active, paused or review-pending runs, creating another run fails without deleting prior work.
- Added lifecycle tracking for running, paused, awaiting approval, awaiting review, user-confirmed completion, incomplete steps, failure and cancellation. Up to three successful user-approved tool handoffs are counted per run.
- Added a per-step review view in the skill library. All steps must be reviewed; `verified` means the user confirmed all steps, while any step marked incomplete keeps the run in `needsChanges`. The UI explicitly states that this is user review, not independent technical verification.
- Added recovery guards: current skill ID/version/status is rechecked; finalized skill runs are never resumed from stale checkpoints; interrupted external proposals still require manual review; stream failures are marked resumable only when an actual durable checkpoint exists.
- Added Dart unit tests for run persistence, lifecycle transitions, approval limits, step review, privacy, and capacity handling; added Python source-contract tests.

### Safety and limitations

- The skill is declarative guidance to the local agent DAG, not an executable script or deterministic workflow bytecode. No shell, PowerShell, arbitrary process execution, new OS permission or direct native API path is enabled.
- Skill acceptance examples are provided to the agent and shown in the preview, but this milestone does not execute them as an automated test suite. The preview displays the full additional instruction text so the user can inspect the guidance before approving it. User `verified` status is an attestation by the user, not proof of objective completion.
- Every external action remains a separate tool proposal through the allowlist and Capability Hub. The existing per-user-turn limit of three successful serial handoffs remains in force.
- No generic undo is provided for successful actions or completed workspace writes. The existing workspace adapter attempts rollback only when its own staged commit/verification fails.
- Skill run ledger retention is 30 days. If the record store reaches its capacity with no terminal record available to evict, a new skill run is refused rather than dropping an active or review-pending run.

**v0.24.0 validation boundary:** Python source/architecture contracts, version checks, source archive hashes and source/config parsers are run in this workspace. Dart tests are authored but not run; Flutter/Dart, Rust/Cargo, FRB generation, Android Gradle/NDK and Windows MSVC toolchains are not installed in this environment. No APK/EXE build, real secure-storage integration test, restart test or physical agent/skill execution test was performed. This is source-implemented Alpha, not a verified installable build.

**v0.24.0 exit criteria:** CI must pass Dart formatting/analyze/tests, Rust format/test/clippy and FRB regeneration; both target builds must pass. End-to-end tests must cover active/disabled/edited skill selection, preview cancellation, skill-version change during preview, one/three handoffs, denial/cancellation/failure, all review paths, full ledger, secure-store corruption, app interruption, stale checkpoint cleanup and proof no external action is replayed.

## 26. Delivered milestone — Leo Alpha v0.25.0: Verified workflow-derived skill learning

### Delivered in source

- Added a learning path from the skill library for a completed skill run. It is visible only for a run whose final status is `verified`; the user must explicitly confirm the learning action before the local model is called.
- Added the read-only `SkillRunEvidenceReader` port so the learning service can inspect a run without mutating its audit state.
- Required the run to contain at least two steps, with every step marked `confirmed`. The source skill must still exist with the exact ID and version recorded by the run, pass its structural validation report, not be rejected, and have the same unchanged ordered steps.
- Constructed a minimized evidence object from the sanitized skill name/description, confirmed step labels, source version, aggregate approval count and source capability IDs. The evidence excludes conversation messages, the user goal, arbitrary notes, tool call arguments/results, file names, paths and file contents.
- Added conservative pattern-based redaction for email addresses, web URLs, Windows/Unix absolute paths, phone-like strings, long numeric identifiers, bearer/API-key assignments and common provider-token prefixes. Redaction is applied before model input and again to generated proposal strings.
- Bound the proposal's required capability IDs to a subset of the original skill's declared capability IDs; unknown or expanded capability requests are rejected before persistence.
- Stored the proposal as an inactive skill with provenance `verified-run:<task-id>`. Added service-level duplicate detection and a second duplicate guard inside the serialized file repository to prevent concurrent/repeated proposals from the same source run.
- Added an explicit disclosure that pattern-based redaction is not perfect and that generated proposals must be reviewed. Existing conversation-based skill extraction remains a distinct, explicitly user-triggered option.
- Added Dart tests for verified-run eligibility, source version/step matching, redaction, capability subset enforcement and duplicate derivation; added a repository idempotency test and Python source-contract coverage.

### Safety and limitations

- A `verified` skill run means the user confirmed each step in the review UI. It is not an independently measured success signal, and the new learner does not infer objective correctness from it.
- The learner does not ingest free-form review notes, chat transcripts, task goals, tool results, file data or paths. It receives only the compact workflow outline described above.
- Redaction uses known patterns and cannot guarantee removal of arbitrary names, addresses, confidential phrases or unseen secret formats. The learning step is always opt-in and its output stays inactive for user inspection.
- Derived proposals cannot add capabilities beyond the source skill, cannot become active automatically, do not grant permissions and do not execute any tool. Later execution continues to require a current active/validated skill and the existing Capability Hub approvals.
- This does not yet learn new skills from arbitrary agent tasks that did not use the skill-run review flow. It derives a reusable proposal from explicitly reviewed skill executions.

**v0.25.0 validation boundary:** Python source/architecture contract suite, version checks, source archive integrity and configuration parsers were run in the authoring workspace. Dart tests were added but not executed; Flutter/Dart/Rust/Cargo, FRB generation and Android/Windows native build toolchains remain unavailable. No APK/EXE build, local-model inference test, secure-storage device test or physical task/skill execution was run. This is source-implemented Alpha, not a verified installable build.

**v0.25.0 exit criteria:** CI must pass Dart format/analyze/tests, Rust format/test/clippy and FRB generation; physical tests must confirm that only reviewed verified runs can produce proposals, redaction works with representative Arabic/English fixtures, the model cannot expand capability IDs, the same run cannot produce duplicate proposals, and no transcript/tool/file content is sent to the learner. Both native builds remain required.


## 27. Delivered milestone — Leo Alpha v0.26.0: Memory intelligence and privacy

- Added an explicit user-action path to propose one selected user-authored chat message as a memory. The editor opens for inspection/editing; saving creates a pending proposal and the message is not approved or activated. No background conversation scanning or automatic extraction is performed.
- Added deterministic Arabic-aware token normalization, Jaccard similarity and a conservative negation/polarity heuristic for likely duplicates and possible contradictions. It only returns up to five review findings for approved memories of the same kind; it never merges, edits, approves, activates or deletes records.
- Added AES-256-GCM encryption for `content`, `normalized_content`, `source_reference` and `tags_json`, with AAD bound to a record ID and field name. Added migration from plaintext and older v1 encrypted-field envelopes to row-bound v2 envelopes. Wrong/missing keys fail closed rather than replacing the key.
- Added HKDF-SHA256 key separation for keyed duplicate fingerprints. A derived HMAC key is distinct from the AES-GCM key; old unprefixed fingerprints are re-derived as `hmac:v2` during the database upgrade and key rotation.
- Added transactional key rotation with a pending secure-storage key marker, recovery after interrupted key promotion, UI-isolate serialization for all repository reads/writes, and verified removal of the SQLite database, WAL/SHM/journal sidecars and secure-storage key entries. Read-only list/search after erase does not recreate the database/key; a new key is created only on a later explicit memory write.
- Added passphrase-protected AES-256-GCM backup/export/import with PBKDF2-HMAC-SHA256 (210,000 iterations), a 1,000-entry ceiling and 5 MiB bound. Backups intentionally omit source references and approval/activation state; every import becomes a pending, inactive proposal.
- Added Dart tests for duplicate/contradiction review, encrypted backup round-trip, wrong passphrase, malformed/oversized input, and widget-level memory proposal controls; added Rust migration, field/row binding, keyed-fingerprint and erase tests plus Python source contracts.

### Privacy boundaries and limitations

- Memory payload values are encrypted, but SQLite metadata remains visible: IDs, memory kinds, timestamps, approval/activation flags, schema/encryption version and opaque keyed fingerprints. This is disclosed in the Memory UI and is not full-database encryption.
- Secure-storage hardware protection depends on OS and device implementation and has not been verified here. Losing the device key without an external encrypted backup may make local memory unrecoverable.
- The duplicate/contradiction detector is lexical and heuristic. It is not a semantic consistency engine; users must inspect its findings. It never applies them automatically.
- Backup password loss is not recoverable by Leo. Backup import restores content as pending proposals only and intentionally does not restore provenance/source paths or trust state. The 1,000-record and 5 MiB limits are enforced; an oversized export is rejected rather than truncated.
- Erase verifies removal of the app database, standard SQLite sidecars and key entries. It cannot promise forensic removal from filesystem snapshots, device backups, flash wear-levelling or copies made outside Leo.
- Operations are serialized across repository instances in the current Flutter UI isolate. This does not claim cross-process or multi-isolate database serialization.

**v0.26.0 validation boundary:** Python source/architecture contracts, version checks, source archive hashes and configuration parsers were run in this workspace. Dart/Flutter tests and analysis, Rust tests/format/clippy, FRB code generation, APK/EXE builds, secure-storage integration, database migration/rotation/erase on physical devices and cross-platform backup tests were not run because the required SDKs and devices are unavailable. The workspace has no generated `Cargo.lock` or `pubspec.lock`; CI must resolve, review and commit lockfiles before production binary qualification. This is source-implemented Alpha, not a verified installable build.

**v0.26.0 exit criteria:** CI must pass Dart format/analyze/tests, Rust format/test/clippy and FRB generation. Android and Windows qualification must exercise key creation, legacy migration, row/field tamper rejection, wrong/missing key behavior, interrupted rotation, backup interoperability, pending-only imports and database/key deletion. Privacy review must validate metadata disclosure and confirm no automatic conversation ingestion.


## 28. Delivered milestone — Leo Alpha v0.27.0: Runtime and conversation resilience

- Added a model-context-aware `ConversationContextPlanner`. It receives the loaded native context size, reserves an output budget and a framing margin, pins every system instruction and the latest complete user/tool turn, and fills remaining space with newest complete historical turns. It never cuts a user turn in half. A required system policy or current request that cannot fit produces an actionable error rather than silent loss.
- Added an explicit compaction notice when old turns are omitted. The planner's character-based estimate is explicitly best-effort; llama.cpp's actual tokenizer remains the final authority and may remove additional complete older interactions. This native trimming does not discard system messages or the current user/tool cycle.
- Reused the active input/output budget for ordinary chat, multi-agent starts, action continuation and restored agent checkpoints. Skill instructions are inserted before the final Capability Hub system policy so they cannot supersede the security/action boundary.
- Added opt-in metadata-only runtime benchmarks, disabled by default and bounded to 80 records/48 KiB. Records include timestamp, elapsed time, output character count, whole-process RSS/peak, platform and success. They exclude prompts, answers, model identifiers, paths, conversation IDs and request IDs. Throughput is successful output characters per second; failed/cancelled attempts remain in latency and success-rate statistics but do not inflate throughput.
- Added a refreshable, lifecycle-safe benchmark card; model load/unload/context-clear operations are blocked during active generation in the UI and protected independently by native try-lock session operations.
- Added a 96 MiB native pre-generation free-memory reserve and kept the session marked active during memory preflight so Stop remains responsive during that phase. Added a Rust pending-cancellation handshake so Stop arriving after request registration but before the native start callback is forwarded as soon as C++ GenerationLifecycle is active.
- Added Dart tests for planner and benchmark behavior, Rust tests for pre-native cancellation state, Python source-contract tests and host C++ ABI/contention/memory/cancellation tests.

**v0.27.0 limitations:** the application planner is not a tokenizer; native tokenization can still find that a request is too large and perform further complete-turn trimming or fail if the mandatory latest turn cannot fit. Runtime metrics are opt-in local metadata and process RSS is not model-only memory. The 96 MiB reserve is a fixed post-load margin, not a guarantee against all future allocation failures; Android system-wide memory reports may differ from per-app/cgroup limits.

**v0.27.0 validation boundary:** Python source/architecture contracts, host fake-llama C ABI/contention/low-memory/preflight-cancellation checks, source archive hashes, version policy and configuration parsing can run in this workspace. Dart/Flutter tests/analyze, Rust tests/format/clippy, Flutter Rust Bridge code generation, Android/Windows native builds, APK/EXE packaging and real-device long-chat/low-memory/interruption benchmarks remain pending because the SDKs and devices are unavailable. This is source-implemented Alpha, not a verified installable build.

**v0.27.0 exit criteria:** CI must pass Dart format/analyze/tests, Rust format/test/clippy and FRB generation. Physical tests must exercise context fit/compaction with real tokenizers, tool-cycle preservation, Stop before/during/after native start, low-memory failure without a crash, load/unload contention, model switching, long conversations, background/route disposal and opt-in benchmark privacy/retention.

## 29. Remaining Alpha roadmap

The following are planned milestones, not completed features. The order may be adjusted only when integration or security evidence shows that a prerequisite must move earlier. Every Alpha milestone remains subject to source tests and actual Android/Windows CI qualification.

| Version | Planned milestone | Main work and exit condition |
|---|---|---|
| **v0.28.0** | Android integration qualification | Complete pinned Flutter/Rust/FRB/NDK/llama.cpp pipeline; build the Android ARM64 app; test model load/inference, storage, permissions, offline operation, voice, OS capabilities and durable task/skill review on a documented device matrix. |
| **v0.29.0** | Windows integration qualification | Complete Flutter/Rust/FRB/MSVC/CMake/llama.cpp pipeline; validate x64 DLL discovery, local inference, model/voice storage, file picker, app handoffs, permissions and task/skill review on supported Windows hosts. |
| **v0.30.0** | Alpha integration freeze | End-to-end acceptance of v1.0.0 scope on both platforms; threat model, dependency/license review, offline regression, accessibility/localization, memory/performance gates, upgrade/uninstall testing and release-blocker triage. Alpha exits only when the coherent app builds and runs on Android and Windows. |

### v1.0.0 — First coherent application and Beta entry

`v1.0.0` is the first integrated Leo application that builds and runs on both Android and Windows. It is the handoff from Alpha construction to Beta testing, not a declaration that every possible connector or automation target is supported. It must meet the baseline already specified in section 6, including local GGUF chat on both platforms, rich rendering, automatic specialist agents, user-controlled long-term memory, tested and reviewable declarative skills, safe OS-first capabilities, approval-gated actions, usable offline voice and offline-first behavior.

### Beta work after v1.0.0

- Change `RELEASE_CHANNEL` to `BETA` for the same tested contents; feature freeze by default.
- Run full regression, offline, fresh-install/upgrade, performance, security, privacy, permission-revocation and accessibility tests on the device/OS matrix.
- Issue correction-only versions as `v1.0.1`, `v1.0.2`, ... under the patch rule. A feature or app-resource change increments MINOR and requires re-running affected Beta acceptance tests.
- Do not move to Release while any crash, data-loss, privilege-bypass, misleading-success or release-blocking compatibility issue remains open.

### Release work after Beta

- Finalize and lock the production application icon and brand assets, produce the final Android and Windows packages, sign with production keys, verify signatures and checksums, and perform clean-install/upgrade/uninstall smoke tests.
- If the exact production icon/resource changes after the Beta candidate, issue the resulting app contents under the next MINOR version (for example `v1.1.0`) before signing/publishing. If the final icon is already included in the tested Beta candidate and only unchanged binaries are signed, the public version need not change solely for signing; switch the channel to `RELEASE`.
- Publish the final release notes, artifact hashes, supported platform matrix, offline/model requirements and recovery instructions. Never place signing keys in the source archive or CI logs.

### Remaining count

- **3 planned Alpha milestones:** `v0.28.0` through `v0.30.0`.
- **1 first integrated application milestone:** `v1.0.0` (BETA entry).
- **Beta correction releases:** as needed, starting at `v1.0.1`; the number is determined by actual defects, not pre-fixed.
- **Release finalization:** after Beta exit; the public version is unchanged for signing-only changes, or increments MINOR if production app resources change.

This is a gated plan. A milestone is not considered complete because source files or a UI exist; its listed exit conditions, automated CI and required physical-platform tests must pass.

**End of development plan — current source implementation: Leo Alpha v0.27.0.**
