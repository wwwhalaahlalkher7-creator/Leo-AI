# Leo AI — Foundation & Preparation Plan

**Product:** Leo AI
**Application name:** Leo
**Document status:** Architecture proposal v0.1 — planning only; no source project has been modified.
**Date:** 2026-11-15

---

## 1. Product definition

Leo is a local-first personal AI assistant for Android and Windows. It should work without internet for local reasoning, conversation, memory, learned skills, file and project work, supported device operations, and offline voice. Network-dependent actions (email delivery, online services, external research, remote APIs) are optional capabilities and must be clearly identified as such.

Leo is not just a chat interface and not a single model. It is a local agent platform composed of:

1. A unified conversation and workspace UI.
2. A local model runtime.
3. A task planner and built-in specialist-agent catalog.
4. Long-term memory and a versioned skill-learning system.
5. A capability hub that delegates operations to the operating system and installed applications.
6. A just-in-time permission broker and action-approval policy.
7. Local speech, wake-word and voice-activity components.
8. Optional device-to-device task delegation over the local network.

### Non-negotiable design rules

- **Offline-first:** no cloud service, account, hosted database, or API key is required for core operation.
- **OS/application-first tools:** before adding a new tool implementation, check whether Android, Windows, an installed application, a local CLI/API, or an MCP connector already supplies the capability. Do not embed duplicate tools merely for convenience.
- **Just-in-time permissions:** ask for a permission only when the user requests an action that needs it, not during first launch.
- **Permission is not blanket execution approval:** persistent capability grants and approval for a particular consequential action are separate decisions.
- **Built-in agents:** users should not have to create agents manually. Leo chooses one or more predefined specialists automatically. Custom agents remain an optional advanced feature.
- **Learning must be durable and testable:** a learned skill is saved, versioned, discoverable, and testable; the model must not merely claim it remembers.
- **Least privilege:** every connector receives only the specific scopes needed for the task.
- **Honest offline status:** Leo must say when an operation requires the internet, cellular service, an installed app, or an unavailable permission.
- **Reuse before rewrite:** reuse proven code and public libraries after source, compatibility, maintenance and license review.

---

## 2. Source-project assessment and reuse map

### 2.1 J.A.R.V.I.S — reuse the product/UI layer

The archive is a Flutter application with Android and Windows project targets, a large chat/workspace implementation, a Python FastAPI mobile server, and a Hermes-compatible gateway client.

**High-value candidates to reuse/adapt**

- `lib/chat/`, `lib/chat/content/`, `lib/chat/message_parts/`, `lib/chat/timeline/`: conversation rendering, streaming timeline, message parts, code and rich content presentation.
- `flutter_markdown`, `flutter_math_fork`, `re_highlight`, Mermaid assets: strong base for Markdown, LaTeX, code highlighting and diagrams.
- Session/chat state, history, streaming event handling and reconnect logic: retain concepts and tested UI/state code where the dependencies can be separated from Hermes.
- File/workspace, terminal, Git, SSH and Kanban screens: reuse selectively as workspace features, while moving execution behind Leo's own capability broker.
- `RequestStore`: useful foundation for a unified approval/request queue. It currently handles approval, clarification, secret, sudo and terminal-read request types.
- `voice_store.dart`, `wake_word_store.dart`, voice capture/player components: reuse the Flutter UX and lifecycle patterns, but replace remote transcription/TTS calls with local engines.
- Existing Skills and Skills Hub presentation: reuse/adapt the UI concepts, not the Hermes-dependent backend endpoints.

**Do not carry over as Leo's mandatory foundation**

- Hermes Agent dependency and Hermes Mobile Server as the required runtime.
- `HermesAdapter` as the only AI path.
- `EphemeralMemoryService` as final memory. The source explicitly calls it temporary and non-durable.
- Server-proxied audio transcription/TTS as the offline voice engine.
- Hermes-specific config, profiles, tool protocol assumptions and provider billing screens except where a generic interface can be extracted.

**Evidence in source**

- `docs/architecture/jarvis-foundation.md` describes `HermesAdapter` as the current agent engine and places Android/Windows automation behind future explicit permission boundaries.
- `lib/core/jarvis/memory_service.dart` contains only the in-memory `EphemeralMemoryService` implementation.
- `server/README.md` says the server locates and boots `hermes serve` and proxies its API/WebSocket surface.
- The voice store invokes server API methods for transcription and speech synthesis.

### 2.2 NEXUS Beta 1.6 — reuse the local-runtime and orchestration foundation

The archive contains a Flutter + Rust workspace, a llama.cpp native adapter, GGUF import/validation and fit estimation, SQLite-backed local data, resource telemetry, local knowledge retrieval, agent task planning, and encrypted peer-task networking.

**High-value candidates to reuse/adapt**

- `core/shared`, `core/runtime`, `core/bridge`: Rust workspace boundaries and typed Flutter↔Rust bridge.
- `native/llama/` and `core/runtime/src/native/engine.rs`: GGUF model lifecycle, generation, cancellation, native FFI and memory snapshots.
- Model import, verification, fit estimation, resource telemetry, adaptive inference policy and benchmark modules.
- SQLite data foundations, conversation records and local-data export/privacy center.
- `features/orchestration/`: JSON plan parsing, validation, dependency graph checks, cancellation, resumable task execution and result passing.
- `features/knowledge/`: local text chunking and BM25 retrieval as the first retrieval layer.
- `features/devices/`: peer discovery, pairing, encrypted task transfer and receiver approval, subject to full security and physical-device revalidation.

**Do not copy the agent-creation UX as the main Leo workflow**

NEXUS currently asks the user to create/activate agent records. Its starter templates are explicitly prompt drafts; their source comments say they do not enable agents, assign models, grant tools, or create runtime access. The task page also selects a planner from ready agents. Leo should replace this manual prerequisite with a built-in catalog and automatic routing.

**Important platform gap**

NEXUS's current native model loader is Android-specific. The Rust engine has non-Android unavailable/stub branches and the CMake project is named `nexus_llama_android`. Windows support therefore requires a real native build/adapter and integration tests; the existence of a Flutter Windows target alone does not make the local model engine work on Windows.

**Verification limitation recorded by NEXUS itself**

Its README lists clean-install/upgrade, low-memory, thermal, long-session, Android native build and physical two-device acceptance work still required before Beta stability. This must be treated as pending verification, not assumed complete.

### 2.3 What is deliberately new in Leo

- Capability Registry + Capability Broker for OS/application integrations.
- Just-in-time permission flow on Android and app-level consent on Windows.
- Built-in specialist-agent catalog and automatic agent router.
- A permission-aware agent/tool policy that sits between models and real-world actions.
- A skill-learning pipeline with versioning, testing and explicit promotion.
- Durable structured long-term memory, separate from chat history and learned skills.
- Local audio pipeline and model/voice manager.
- A Windows-native local inference adapter and Windows application automation connector.

---

## 3. Proposed Leo architecture

```text
                         LEO (Flutter UI)
                Chat / Voice / Workspace / Settings
                                  |
                         LEO APPLICATION CORE
                         (Rust + typed bridge)
                                  |
      +---------------------------+---------------------------+
      |             |             |             |             |
      v             v             v             v             v
  AI Runtime    Orchestrator   Memory Core   Skill System  Capability Hub
      |             |             |             |             |
      |        Agent Router       SQLite       Skill Store   Tool Catalog
      |        Task DAG           FTS/BM25      Validator     Permission Broker
      |        Review             Embeddings*   Versioning    Action Policy
      |             |             |             |             |
      +-------------+-------------+-------------+-------------+
                                  |
                     Native / Local Integration Layer
                  +---------------+----------------+
                  |                                |
                  v                                v
             Android Adapter                 Windows Adapter
       Kotlin / Intents / SAF / APIs      Rust/Win32/COM/UIA/CLI
                  |                                |
                  +---------------+----------------+
                                  |
                     Installed Apps / OS Services

    Local model runtime: llama.cpp (GGUF) on Android and Windows
    Local voice runtime: sherpa-onnx and/or whisper.cpp, selected by tests
    Optional connectors: MCP servers and app-provided APIs/CLI integrations
    Optional peer layer: NEXUS encrypted device task transfer

    *Embeddings are an enhancement after the first reliable local BM25 release.
```

### Module boundaries

| Module | Responsibility | Primary base |
|---|---|---|
| `leo_ui` | JARVIS-derived chat/workspace UI | JARVIS Flutter |
| `leo_runtime` | model lifecycle, inference streams, cancellation, resource-aware selection | NEXUS Rust/C++ |
| `leo_orchestrator` | task intent, planning, agent selection, dependencies, review | NEXUS orchestration + new router |
| `leo_agents` | built-in agent definitions and policies | New, informed by NEXUS templates |
| `leo_memory` | long-term memory, retrieval, provenance, retention | New + NEXUS SQLite/knowledge |
| `leo_skills` | portable skill packages, learning, validation, versions | JARVIS skill UI concepts + Agent Skills format |
| `leo_capabilities` | discover and call system/app/connector capabilities | New + optional MCP |
| `leo_permissions` | permission state, in-context prompting, consent history | New + JARVIS request queue |
| `leo_voice` | offline ASR, VAD, wake word, TTS | New + JARVIS voice UX |
| `leo_devices` | optional peer pairing and task delegation | NEXUS device layer |
| `platform/android` | native Android intents, runtime permissions, SAF and providers | New Kotlin adapter |
| `platform/windows` | Windows shell, Win32/COM, UI Automation and native runtime | New Windows adapter |

---

## 4. Permission and approval architecture

### 4.1 The required first-use flow

1. User asks Leo to perform a task.
2. Leo's planner identifies which capability is required (e.g. microphone, contacts, selected folder, phone call, email composer, app UI control).
3. `PermissionBroker` checks both Leo's stored grant and the actual operating-system permission/access state.
4. If not granted, Leo shows a short explanation: what will be accessed, why, and whether access can be limited to one item/folder or a broader resource.
5. If accepted, Leo invokes the appropriate native OS permission flow or app-level grant UI.
6. The decision and scope are stored locally. Denial does not block unrelated Leo features.
7. Before executing the task, `ActionPolicy` checks whether this particular action also needs a one-time confirmation.
8. Leo executes through the connector and reports a verifiable result.

No permissions are requested just because the app was installed or opened.

### 4.2 Permission grant versus action confirmation

These are intentionally separate:

- **Capability grant:** “Leo may access my selected documents / microphone / contacts / an app connector.” This can be remembered and revoked later.
- **Action confirmation:** “Send this email now”, “place this call”, “delete these files”, “run this script”, “send this SMS”. This remains a per-action decision for consequential or irreversible actions, even if the capability was previously granted.

A user can opt into an explicit, narrow trusted automation rule later, such as “allow Leo to rename files only inside this selected folder”, but Leo must never convert a general permission into unrestricted authority.

### 4.3 Android behavior

Use Android-native permissions and privacy-preserving APIs:

- Dangerous runtime permissions are requested in context, at the first action that needs them.
- Prefer Storage Access Framework document/folder selection over broad storage access.
- Prefer `ACTION_DIAL` when the user should confirm a call in the phone app; request direct-call permission only for a feature that truly places the call.
- Use intents/share sheets for supported email, message and file handoffs rather than embedding duplicate clients.
- Query/resolve only required app intents. Do not assume Leo can freely enumerate every installed app; Android package visibility is restricted.
- Special-access settings (where applicable) require a separate explanation and system settings flow. They are not equivalent to normal runtime permissions.
- Accessibility-based UI control is a constrained fallback, not the default integration strategy; evaluate Android and store policy before enabling it.

### 4.4 Windows behavior

Windows does not provide one universal Android-style permission dialog for arbitrary desktop application capabilities. Leo therefore needs its own scoped consent UI and must rely on Windows security boundaries:

- Run as the signed-in user with standard privileges by default.
- Ask inside Leo when a capability is first needed (e.g. selected folder, microphone, process launch, UI automation, a particular connector).
- Use the system's own permission/privacy controls where Windows provides them, and explain settings navigation when it does not.
- Do not run Leo permanently as Administrator.
- Use UAC only when a specific operation genuinely requires elevation. The prompt authorizes that elevated operation/process; it is not a blanket Leo permission.
- Keep elevated helpers separate, narrowly scoped and short-lived if a future feature requires them.
- UI Automation is a fallback for applications without an API, not a substitute for a stable app integration.

### 4.5 Capability scope examples

| Capability | First-use grant | Additional per-action confirmation |
|---|---|---|
| Microphone / speech input | OS microphone permission | No for each utterance while recording is visibly active; always show recording state |
| Contacts read | OS contacts permission or selected contact flow | Confirm before sharing/exporting contact data |
| Phone call | Native call capability or dialer handoff | Confirm recipient/number before direct call; dialer handoff leaves final call action to user |
| Email | Open mail app or configured mail connector | Confirm recipient, subject and body before sending |
| SMS/message | Native app handoff or explicitly supported connector | Confirm recipient and message before sending |
| Files read/write | Selected files/folder or chosen scope | Confirm destructive changes and broad batch operations |
| Terminal/process execution | Leo capability grant scoped to workspace/commands | Confirm untrusted scripts, destructive commands and privileged changes |
| App UI automation | App-specific UI automation grant | Confirm actions with external effects or uncertain target |
| Peer task execution | Pair device and allow task category | Receiver approves each incoming task by default |

---

## 5. Built-in agents and automatic selection

### 5.1 Principle

Leo ships with a ready-to-use roster of specialist agents. They are selected by Leo; users do not need to create them. The user can later customize, disable or add agents from advanced settings, but this is optional.

An agent is a role profile, not necessarily a separate model process. It contains:

- role and task description;
- system instructions;
- task types it is suited to;
- required skills;
- allowed capability categories (never an actual permission grant);
- expected output contract;
- optional preferred model profile;
- verification checklist.

All agents call the same guarded capability broker. An agent role cannot bypass user permissions.

### 5.2 Initial built-in catalog

| Agent | Main responsibility |
|---|---|
| Planner / Coordinator | Understand request, classify risk, break complex work into a dependency graph and assign specialists |
| General Assistant | Direct conversation, everyday tasks and simple requests |
| Researcher | Search local files and knowledge; compare evidence; online research only if the user enables it |
| Programmer | Read, create, modify, run and test project code within approved workspaces |
| Code Reviewer | Independently review diffs, tests, security and regressions |
| Math & Science Specialist | Equations, derivations, numerical work, science and technical reasoning |
| Writer & Editor | Documents, emails, summaries and language work |
| Data Analyst | Tables, CSV/JSON, statistics and local reports |
| File & Workspace Operator | Organize, find, rename, convert and manage user-approved files |
| Device & App Operator | Work with Android/Windows functions and installed applications through approved connectors |
| Communications Assistant | Prepare calls, messages, meetings and emails; actual transmission follows permission/action policy |
| Quality / Verification Agent | Check whether task outputs meet requirements and whether claimed actions actually succeeded |

### 5.3 Automatic routing policy

- Small, single-domain request: one specialist or the general assistant.
- Cross-domain request: Planner creates a task graph and dispatches only the necessary agents.
- High-impact request: add a verifier/reviewer and require confirmation at the appropriate action boundary.
- Independent subtasks may run in parallel only when the runtime and available memory permit it.
- On a device with one active inference session, tasks must be scheduled sequentially or in bounded batches; do not promise parallel model inference that the hardware/runtime cannot provide.
- Avoid needless multi-agent calls. More agents are not automatically better; use the smallest team that can complete and verify the task.

The current NEXUS planner/executor and dependency validation are useful implementation foundations, but its user-selected ready-agent prerequisite should be removed from the default flow.

---

## 6. Memory and skill learning

### 6.1 Separate the concepts

- **Conversation history:** what was said.
- **Long-term memory:** facts, preferences, decisions and relevant past events.
- **Knowledge library:** imported material and documents that Leo can retrieve.
- **Skills:** reusable procedures for doing work.
- **Model training:** changing model weights (e.g. LoRA/fine-tuning); this is a later, optional capability and is not the same as remembering or learning a skill.

### 6.2 Memory stores

Use SQLite as the first durable source of truth, then add retrieval improvements without making the database depend on a hosted service.

Suggested memory categories:

1. Profile/preferences — user-approved stable preferences.
2. Episodic — key events and completed work.
3. Semantic — durable facts and decisions with source/provenance.
4. Project — per-project context, constraints and decisions.
5. Procedural — references to skill versions rather than duplicating complete procedures in free-form memory.

Each memory record should carry provenance, confidence, timestamp, scope, sensitivity class and retention metadata. Provide inspect/edit/delete/export controls. Keep sensitive data out of memory unless the user specifically requests retention.

### 6.3 Skill-learning lifecycle

1. Leo completes a task and identifies a reusable procedure.
2. It proposes a skill with a concise name, purpose, prerequisites and expected result.
3. It records a sanitized sequence of steps; credentials, tokens and private payloads are never copied into the skill.
4. It creates a portable `SKILL.md` package and, if needed, reference files or scripts.
5. A validator checks metadata, referenced files, command safety, declared capability requirements and possible prompt-injection content.
6. Leo runs a dry-run or test case in a constrained workspace.
7. The user approves saving/enabling the skill.
8. Leo stores a version and can later compare, roll back, disable or delete it.
9. When a future task matches the skill description, Leo loads the full instructions only then (progressive disclosure).

A skill can describe a capability requirement, but it cannot grant that permission. The Capability Broker checks it at execution time.

### 6.4 Portable format

Use the open Agent Skills folder pattern as the starting format (`SKILL.md`, optional `scripts/`, `references/`, `assets/`). Add Leo-specific metadata in a separate manifest such as `leo.skill.yaml` for version, platform support, required capabilities, tests and trust status. Keep the skill itself readable and portable.

---

## 7. Capability Hub — mandatory OS/app-first design

This is a core Leo requirement, not a later optimization.

### 7.1 Resolution order

For each requested operation, Leo should try the following order:

1. Native OS API or Android/Windows system contract.
2. Public API / URI scheme / CLI / COM automation exposed by the installed application.
3. An already-installed local connector or MCP server.
4. A small Leo-native adapter only when no suitable existing capability exists.
5. UI automation as a last-resort fallback when supported, permitted and testable.

### 7.2 Examples

- Email: hand off to the installed mail app or a user-configured local mail connector; do not build a mail client.
- Phone and SMS: use Android telephony/dialer and message-app handoff; do not recreate phone/SMS apps.
- Files: use Android SAF and Windows Shell/file APIs; do not ship a second general file manager engine.
- Git: use an installed Git executable on Windows, or a minimal optional packaged runtime only when the user has no Git installation and explicitly chooses it.
- Office: integrate with existing document formats and installed Office/LibreOffice APIs/protocols instead of bundling an office suite.
- Browser: use the default browser and registered protocols, with dedicated browser automation only when a well-defined use case needs it.

### 7.3 MCP policy

MCP is a connector protocol, not permission bypass. Leo can discover/configure local MCP servers and expose their declared tools to the orchestrator. Each tool still requires schema validation, trust review, permission checks and action policy. Prefer local stdio or local-only transports for offline connectors. Network MCP servers must be opt-in and visibly marked as online.

### 7.4 Keeping the app small

- Do not embed full applications, browser engines, office suites, mail clients or duplicate utilities.
- Use OS APIs and installed app providers.
- Make model and voice packs separate downloadable/importable assets, not embedded in the base application binary.
- Keep optional connectors modular and install only when needed.
- Include only small, security-critical core primitives in Leo (e.g. a safe calculator, permission broker, file-scope validator); avoid tool bloat.

---

## 8. Model and voice runtime

### 8.1 Text inference

Use llama.cpp as the primary local GGUF inference engine. NEXUS already contains a working Android native integration and lifecycle concepts; extend the abstraction to support a Windows native build. Keep one platform-neutral Rust API for model load/unload, context sizing, streaming generation, cancellation, memory snapshots and diagnostics.

Do not choose a single universal model until hardware targets are defined. The model manager should:

- inspect model metadata and quantization;
- estimate RAM/VRAM and context requirements;
- benchmark on the actual device;
- select model/context/thread/backend profiles;
- unload or switch models safely;
- show when a requested task exceeds local hardware limits.

Windows should support CPU first, then GPU acceleration by detected backend (e.g. CUDA/Vulkan/other supported backends) where available. Android should support CPU first and evaluate device-specific GPU/NPU backends rather than assume every phone exposes the same acceleration.

### 8.2 Offline voice shortlist

Evaluate two candidate stacks before committing:

- `sherpa-onnx`: cross-platform offline ASR/TTS, VAD, keyword spotting and other audio functions; its repository lists Android and Windows support, with Apache-2.0 licensing.
- `whisper.cpp`: multilingual offline speech recognition with Android and Windows support; MIT licensing. Evaluate it particularly for Arabic recognition accuracy, but benchmark real Arabic and Sudanese-accent samples before choosing it as the default.

A sensible first prototype is to compare sherpa-onnx streaming ASR against whisper.cpp batch/near-real-time ASR; use the same short Arabic test set for both. VAD and wake-word can be separate lightweight components. TTS needs its own Arabic voice quality benchmark; do not assume that support for Arabic text guarantees natural Sudanese Arabic speech.

Wake-word always-on listening must respect Android background microphone limits and visible microphone state. Windows can support a different background lifecycle and hotkey/wake strategy.

### 8.3 Model assets

No actual GGUF/ONNX model-weight bundle was found in either supplied archive. Leo will need a model-pack manager. To provide first-run offline operation, ship an optional offline installer/model pack or allow users to preload/import model files. Model packs and voice packs should be independently versioned and licensed.

---

## 9. Platform adapters

### 9.1 Android

- Kotlin adapter exposed to Flutter/Rust through a narrow typed channel.
- Android intents, content providers, contacts/calendar/telephony APIs when allowed, Storage Access Framework, app links and share sheets.
- Use runtime permissions at first use, and selected-resource grants wherever possible.
- Use package visibility queries only for required integrations.
- Do not promise silent control over every third-party app. Where no public API exists, explain the limitation and present a user-driven handoff or a specifically evaluated UI automation route.

### 9.2 Windows

- Native helper/adapter under the current user identity.
- Use Shell/Win32/COM and application-specific command/API integration first.
- Use Microsoft UI Automation for accessible UI controls when no stable API exists.
- Evaluate `windows-rs` for Rust bindings and `FlaUI` as a reference/optional .NET automation component. FlaUI can add a .NET packaging/runtime consideration, so it is not automatically a base dependency.
- Use UAC only for operations that truly require administrator elevation.

### 9.3 Cross-device

NEXUS peer discovery and encrypted task transfer can be retained as a later feature. It should be optional and local-network-only by default. Each receiving device must approve incoming tasks and must independently check its local permissions. Peer pairing does not transfer permissions from one device to another.

---

## 10. External GitHub components to evaluate

The following repositories were located and their READMEs/licensing signals were reviewed. They are candidates, not automatic dependencies; pin a release/commit and complete a license/security/size review before vendoring or linking them into a release.

| Repository | Potential use in Leo | Notes |
|---|---|---|
| `ggml-org/llama.cpp` | Local text model inference on Android and Windows | GGUF inference, CPU/GPU backends, MIT; keep NEXUS's wrapper and rework the Windows platform adapter. |
| `k2-fsa/sherpa-onnx` | Offline voice stack | ASR, TTS, VAD, keyword spotting; Android and Windows; Apache-2.0. Verify models separately. |
| `ggml-org/whisper.cpp` | Alternative multilingual ASR engine | Android/Windows, C/C++, offline Whisper inference; MIT. Compare with sherpa using Arabic recordings. |
| `agentskills/agentskills` | Portable skill package convention | `SKILL.md` with optional scripts/references/assets and progressive loading; Apache-2.0 for code/spec, docs CC-BY-4.0. |
| `modelcontextprotocol/rust-sdk` | MCP client/server integration from Rust | Official Rust SDK; inspect version/spec compatibility and mixed licensing during lockfile pinning. Do not make MCP mandatory for core features. |
| `microsoft/windows-rs` | Typed Rust bindings to Windows APIs | Candidate for direct OS integration; review focused crates/features to avoid unnecessary binary/dependency size. |
| `FlaUI/FlaUI` | Optional Windows UI Automation fallback | .NET wrapper over Microsoft UI Automation; MIT. Consider only if native Rust UIA integration is not efficient enough. |

Additional platform references:

- Android runtime permissions should be requested in context; the system recommends that the app explain why the permission is required.
- Android Storage Access Framework allows a user to select documents/folders and grant URI-scoped access rather than granting broad storage access.
- Windows UI Automation can expose and manipulate many UI elements, but it is not guaranteed to work with every application or custom control.
- Windows UAC is an elevation consent boundary, not a general-purpose permission manager for every Leo feature.

---

## 11. Proposed repository structure

This is a target layout, not a command to create every directory immediately. Start from the existing projects and migrate incrementally.

```text
leo/
  app/                         # JARVIS-derived Flutter application
    lib/chat/                  # retained conversation UI
    lib/workspace/             # files, terminal, Git, artifacts
    lib/features/              # memory, skills, agents, models, devices
    android/                   # Kotlin platform adapter
    windows/                   # Windows runner + native helper integration
  core/
    shared/                    # platform-neutral domain types
    runtime/                   # model lifecycle and inference interfaces
    bridge/                    # Flutter/Rust typed API
    orchestrator/              # task plans and agent routing
    agents/                    # built-in agent catalog and dispatch policy
    memory/                    # long-term memory and retrieval
    skills/                    # skill package format and learning lifecycle
    capabilities/              # tool registry and connector host
    permissions/               # grants, scopes and consent records
    policy/                    # risk levels and action confirmation
    devices/                    # optional peer execution
  native/
    llama/                     # pinned llama.cpp build integration
    voice/                     # ASR/VAD/KWS/TTS build integration
  connectors/
    manifests/                 # metadata only; no large bundled apps
  assets/
    agents/                    # built-in role profiles
    skills/                    # built-in skill packs
  model-packs/                 # external/downloadable assets; not committed to Git
  voice-packs/                 # external/downloadable assets; not committed to Git
  docs/
    architecture/
    security/
    decisions/
```

---

## 12. Delivery phases and gates

### Phase 0 — Foundation & compatibility (this preparation)

- Inventory source files and reusable modules.
- Confirm Flutter/Dart/Rust/NDK/Visual Studio toolchain versions.
- Pin upstream commits and license notices.
- Define shared Rust domain contracts and capability/permission schemas.
- Decide app identity, package IDs, data directories and migration plan.

**Exit gate:** a migration map exists; no source has been moved or deleted without a passing test baseline.

### Phase 1 — Unified Leo shell and local inference

- Establish Leo identity from JARVIS UI.
- Detach the chat UI from Hermes-only runtime assumptions.
- Integrate NEXUS model manager and Android native engine.
- Port/build llama.cpp for Windows and add a shared runtime API.
- Add offline model-pack import and first-run setup.

**Exit gate:** the same Flutter chat interface generates locally on one Android test device and one Windows test machine, with streaming and cancellation.

### Phase 2 — Memory and built-in agents

- Add SQLite long-term memory schema and migration tests.
- Add built-in agent catalog and automatic router.
- Reuse NEXUS task graph/validation/execution foundations.
- Add a task-result verification stage.

**Exit gate:** user can issue multi-domain tasks without creating agents manually; agent selection and results are observable and reproducible.

### Phase 3 — Skills and learning

- Add `SKILL.md` importer/reader and Leo manifest.
- Add task-to-skill proposal, test, approval, version and rollback lifecycle.
- Enforce that skills never grant permissions themselves.

**Exit gate:** a skill taught in one session is persisted, can be inspected, and is successfully reused in a separate session after app restart.

### Phase 4 — Capability Hub and permissions

- Implement the capability registry and native connectors.
- Implement first-use prompts, stored scopes, revocation and audit trail.
- Implement per-action confirmations for high-impact actions.
- Start with a small validated group: files, microphone, dialer/email handoff, app launch, clipboard/share, and Windows process/file integrations.

**Exit gate:** all connectors fail closed when access is denied or revoked; no action silently exceeds its declared scope.

### Phase 5 — Offline voice

- Benchmark candidate Arabic ASR engines.
- Add TTS, VAD, wake-word, interruption and voice activity lifecycle.
- Make model/voice packs independent of base app installation.

**Exit gate:** measurable Arabic test set scores, latency, memory, battery/CPU and interruption behavior are documented on Android and Windows.

### Phase 6 — Advanced agents and device mesh

- Add adaptive multi-agent plans and reviewer agent.
- Add peer placement based on RAM, model availability, thermal and battery information.
- Add receiver-side approval and resumable result transfer.

**Exit gate:** physical two-device tests confirm that permissions remain local and every incoming remote action requires receiver approval.

---

## 13. Initial acceptance checklist

### Offline guarantees

- First launch can be completed without network if model packs are already present.
- Chat, memory, skill lookup, local files and local inference work with network disabled.
- Leo does not make hidden requests to cloud providers.
- Online-only capabilities display the exact reason they cannot run offline.

### Permission guarantees

- No sensitive permission prompt on first app launch.
- The first use of a capability triggers a clear explanation and platform-appropriate request.
- Denying one permission does not disable unrelated features.
- Revoking OS access is detected before the next operation.
- Persistent access is scoped to the selected resource where possible.
- Sending messages/email, placing calls, deleting data and running risky scripts have appropriate per-action confirmation.
- Windows never runs with permanent administrator privileges by default.

### Agent guarantees

- Default user flow requires no manual agent creation.
- Leo chooses one or more built-in agents from task needs.
- Agents cannot bypass Capability Broker or Permission Broker.
- Complex plans have validated dependencies and can be cancelled/resumed.
- Leo does not claim parallel execution where the local runtime is serialized.

### Skill and memory guarantees

- Saved skills survive restart and have version history.
- A skill cannot grant itself access or embed secrets.
- Memory records can be inspected, corrected and deleted.
- Memory retrieval includes provenance and avoids presenting uncertain recall as fact.

### Platform guarantees

- Android and Windows independently pass clean-install, upgrade, process-death, low-memory and offline tests.
- Local inference actually runs on both platforms; UI-only Windows support is not accepted as completion.
- Arabic and English voice quality are benchmarked on real recordings.

---

## 14. Decisions already recommended

1. **Base app:** JARVIS Flutter UI and workspace, not the Hermes server architecture.
2. **Local AI:** NEXUS Rust/C++ runtime + llama.cpp, extended to Windows.
3. **Agents:** built-in specialist roster with automatic selection; manual agent creation is optional only.
4. **Permissions:** first-use request through a unified broker; Android native permission where available; Windows Leo consent + native Windows security/UAC boundaries.
5. **Actions:** capability grant and per-action confirmation are separate.
6. **Tools:** OS/app-first Capability Hub is a mandatory release requirement.
7. **Skills:** use the Agent Skills folder convention as a portable base, with Leo-specific capability/test metadata.
8. **Voice:** benchmark sherpa-onnx and whisper.cpp; do not select based on feature lists alone.
9. **Network:** local-only core. Internet features are optional and explicitly marked.
10. **Migration:** preserve source projects as references and migrate one subsystem at a time with tests; avoid a destructive big-bang merge.

---

## 15. Open technical validations before implementation

These are engineering validations, not questions that block the architecture:

- Establish minimum supported Android RAM/CPU/device tier and minimum Windows RAM/CPU/GPU tier before selecting default models.
- Verify NEXUS native build and model loading from the actual source archive on Android hardware.
- Build the NEXUS native adapter for Windows and test llama.cpp ABI/lifecycle parity.
- Verify Flutter/Dart/Rust toolchain compatibility; the source archives currently declare different Dart minimum versions.
- Test JARVIS chat/widget code after removing the Hermes-only connection layer.
- Benchmark Arabic and Sudanese-accent ASR/TTS model options.
- Audit all transitive licenses, model-weight licenses, fonts, audio voices and third-party assets.
- Evaluate the Android policy and platform limitations for each telephony, messaging, package-visibility and accessibility integration.
- Define a safe local execution sandbox per platform before enabling arbitrary shell/code execution.

---

**End of v0.1.** The next engineering action after this planning baseline is Phase 0: produce a file-by-file migration map and a clean build/test baseline for both supplied archives before touching application code.
