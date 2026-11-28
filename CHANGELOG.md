## v0.27.0 — ALPHA

### Added
- Added a model-context-aware conversation planner. It reads the loaded native context size, reserves space for output and prompt framing, retains pinned system instructions and the latest complete user/tool turn, and compacts older complete turns without cutting a partial interaction.
- Added an explicit compaction notice so the local model is told that older history was omitted and must not be inferred. Oversized current requests or mandatory system instructions fail with an actionable message rather than being silently truncated.
- Applied the same context/output budget to normal chat, newly started multi-agent tasks, tool continuations and restored task checkpoints. The native tokenizer remains authoritative and performs the final complete-turn fit check.
- Added opt-in metadata-only generation measurements: attempt latency, successful output characters per second, process RSS/peak RSS, platform and outcome. Collection is disabled by default, bounded to 80 records/48 KiB, and excludes prompts, answers, model names, paths and conversation identifiers.
- Added a refresh control and lifecycle-safe loading for the performance card; model load/unload/context-clear operations remain blocked during active generation and the native adapter independently fails fast on session contention.
- Hardened the runtime cancellation handshake: Rust remembers a cancellation that arrives after request registration but before the native start callback, then forwards it as soon as the native generation lifecycle is active. A request disposed with the chat page is recorded as an unsuccessful/cancelled benchmark sample when measurements are enabled.
- Added Rust, Dart and Python contract coverage for whole-turn context planning, pinned policy order, dynamic output budgets, metadata-only benchmarks, native contention, low-memory preflight and cancellation races.

### Fixed
- Fixed Flutter test/native-asset startup failing because `native_toolchain_rust` could not find `rust-toolchain.toml` inside `core/bridge`. Added an exact crate-local copy of the pinned workspace toolchain and strengthened bridge preflight/regression tests to require the copy to remain synchronized.
- Fixed empty-state collection mutation in chat history and the local skill library by ensuring repository write paths operate on growable copies/lists.
- Fixed task-checkpoint snapshots returning fixed-length lists even though save, update and remove flows must mutate them.
- Classified opposite-polarity memory candidates as possible contradictions before applying the high-similarity duplicate rule.
- Made workspace diff previews explicitly report when removed or added lines were clipped by the preview limit.
- Tightened conversation-context estimation and reserve behavior so a prompt at the exact estimated budget is compacted while preserving the newest complete historical turn and a first goal when they fit.
- Replaced widget-test `pumpAndSettle` waits with bounded frame pumping on screens containing intentionally repeating animations/indeterminate progress indicators.
- Kept encrypted agent-checkpoint restoration off the chat's first-render critical path. The chat becomes interactive after its core preferences load, then applies recovered task checkpoints when secure storage responds.
- Updated widget tests to use an in-memory secure-store adapter for skill-run history, await simulated keyboard submit actions, and assert the current engine-status copy instead of an obsolete label.
- Restored the explicit skill-context boundary wording that untrusted skills receive no permissions or privileges.

### Runtime and privacy boundaries
- Application-side token budgeting uses a lightweight character-based estimate; it is not the model tokenizer. The native llama.cpp tokenizer remains final and may remove additional complete older turns. The latest request and mandatory system instructions are never silently dropped.
- Runtime benchmarks are local opt-in metadata, not a token/s benchmark. Throughput is measured in output characters per second and includes successful requests only; latency/success rate include failed and cancelled attempts. RSS measures the whole Leo process rather than model allocations alone.
- The native generation reserve is a fixed 96 MiB check after the model is loaded. It does not prove that the operating system can satisfy every later allocation, and Android/Linux available-memory reporting can differ from per-process/cgroup limits.
- The pending-cancellation handshake and context changes are source-implemented. Rust/Dart/Flutter/FRB tests, APK/EXE builds and physical long-chat/interruption/low-memory tests still require the pinned CI toolchains and devices.

### Fixed
- Fixed an invalid Dart string (`' $1 '`) in the speech text preparation of `leo_voice_service.dart` that stopped `dart format` and compilation. Inline-code and Markdown-link text now use `replaceAllMapped`, so the captured text is kept exactly.
- Applied `dart format` (Dart 3.13.1, the CI version) to the whole Flutter app and its tests so the CI format gate passes.
- Contract tests that inspect Dart source now compare formatting-independent text (`scripts/tests/dart_source.py`), so future `dart format` runs do not break them.

## v0.26.0 — ALPHA

### Added
- Added opt-in chat-message memory proposals: the user can choose one of their own messages and open a review editor; Leo never scans or saves every conversation automatically. The message is stored as a pending proposal and cannot enter model context until separately approved and activated.
- Added conservative local Arabic/English normalization, token-set similarity and polarity checks to flag possible duplicates and contradictions. Findings are review hints only; there is no automatic merge, overwrite, approval or deletion.
- Added AES-256-GCM encryption for memory content, normalized search text, tags and source references, with associated data bound to both the memory record ID and field name. Added a local key-check envelope and migration from older plaintext/v1 field envelopes to row-bound v2 envelopes.
- Added HKDF-SHA256 domain separation for the deterministic HMAC content fingerprint, so the duplicate index uses a derived subkey rather than reusing the AES-GCM key directly. Existing legacy fingerprints are recomputed during the transactional upgrade.
- Added OS secure-storage key creation, interrupted-rotation recovery, explicit key rotation and verified deletion of the SQLite database, WAL/SHM/journal sidecars and stored key material.
- Added password-encrypted portable memory backup using AES-256-GCM and PBKDF2-HMAC-SHA256 (210,000 iterations), bounded to 1,000 entries and 5 MiB. Backup import validates the authenticated envelope and creates pending proposals only; source references and approval/activation state are not restored.
- Serialized memory repository operations within the Flutter UI isolate so search, edits, key rotation and erase do not race each other.
- Added Rust, Dart and Python tests for encrypted storage contracts, legacy upgrades, row/field binding, key lifecycle, backup bounds, review-only intelligence and opt-in chat proposals.

### Privacy and limitations
- SQLite metadata remains visible to the local filesystem/database reader: record IDs, memory kinds, creation/update timestamps, approval/activation flags, schema/encryption version and opaque keyed fingerprints. The privacy UI discloses this; do not describe the database as fully encrypted.
- The device encryption key is held by the platform secure-storage plugin; hardware-backed guarantees vary by OS/device and have not been confirmed on physical devices in this workspace.
- Duplicate/contradiction detection is deterministic and lexical, not semantic proof. It can miss paraphrases or produce false positives; all findings require human review.
- Backup passphrases are not recoverable by Leo. Imported records are pending, inactive proposals; importing a backup never restores trust or activation state. Key loss without a separate backup may make local memories unrecoverable.
- Verified deletion checks that the app database, its SQLite sidecars and secure-storage key entries are absent. This is not a forensic guarantee against filesystem snapshots, external copies, flash wear-levelling or backups made outside Leo.
- Python source/architecture contracts, version policy, original source archive integrity and configuration parsing were run in this authoring workspace. Dart/Flutter/Rust/Cargo tests, FRB generation, APK/EXE builds, secure-store runtime checks, migration/rotation/erase on physical devices and backup interoperability tests remain pending because the native toolchains/devices are unavailable. This is source-implemented Alpha, not a verified installable build.

### Exit criteria before platform qualification
- CI must pass Dart format/analyze/tests, Rust format/test/clippy, Flutter Rust Bridge generation and both native builds.
- Android and Windows device tests must exercise first-key creation, legacy plaintext migration, v1 envelope migration, wrong/missing key fail-closed behavior, key rotation interruptions, restore, erase and secure-storage platform differences.
- Backup tests must verify wrong passphrase rejection, tampered ciphertext rejection, 1,000-entry/5 MiB limits, cross-platform export/import, and pending-only status after import.
- Privacy review must confirm that no raw transcript is collected automatically, that imported records remain inactive, and the user-facing metadata disclosure matches the SQLite schema.

## v0.25.0 — ALPHA

### Added
- Added explicit, local-model-assisted workflow learning from completed skill runs that the user has reviewed and marked fully verified. The learning action is available only on verified run records in the skill library and requires a separate user confirmation.
- Added a read-only `SkillRunEvidenceReader` boundary. Learning requires the exact original skill ID/version, a passing validation report, an unchanged ordered step list, at least two steps and user confirmation for every step.
- Added a minimized evidence envelope containing only the sanitized skill name/description, confirmed step instructions, source version, aggregate approved-action count and the source skill's existing capability-ID allowlist. It excludes the original conversation, user goal, free-form review notes, tool arguments/results, file names, paths and contents.
- Added pattern-based redaction for common email addresses, URLs, Windows/Unix paths, phone-like numbers, long numeric identifiers, bearer/API-key values and common provider token prefixes before sending evidence to the local model; generated proposal text is redacted again before persistence.
- Added strict capability-subset validation: a workflow-derived proposal cannot request a capability absent from the source skill. The result is always a proposed/inactive skill with synthetic acceptance cases and the provenance `verified-run:<task-id>`.
- Added duplicate-provenance protection in both the learning service and serialized skill repository, preventing repeated proposals from the same verified run.
- Added Dart unit tests for verified-only eligibility, redaction, source-version binding, capability expansion rejection, duplicate derivation and repository-level idempotency; added Python source-contract coverage.

### Safety and limitations
- `verified` means the user attested that every step completed; it is not objective proof that the output is correct. The model receives only a minimized step outline, not a replayable transcript or tool result.
- Redaction is pattern-based and cannot guarantee removal of every personal identifier or confidential phrase. The confirmation dialog discloses this limitation; users should not include sensitive information in reusable skill instructions and must inspect the generated proposal before validation/activation.
- Learning does not activate the proposal, grant permissions, run tools or expand the source skill capability allowlist. Every later external action still requires the ordinary Capability Hub consent and per-action approval.
- Existing user-triggered conversation-based skill extraction remains available as a separate path; this milestone adds verified-run learning rather than silently learning from all chats.
- Python source-contract tests were run in this workspace. Dart/Flutter and Rust/Cargo toolchains and Android/Windows native build environments are unavailable here, so Dart tests, formatting/analyze, native compilation, APK/EXE builds and physical local-model learning tests remain pending. This is source-implemented Alpha, not a verified installable build.

## v0.24.0 — ALPHA

### Added
- Added the first agent-guided execution path for active, structurally validated declarative skills. A matching skill is previewed with ordered steps, acceptance examples and capability metadata; the user must approve the run before its context is added to the existing multi-agent DAG.
- Added a version-bound execution envelope that treats skill text and acceptance examples as untrusted data, keeps the user goal ephemeral to the request, rejects stale/disabled skill versions and constrains actions to the existing role-scoped tool protocol and Capability Hub.
- Added an encrypted `flutter_secure_storage` skill-run ledger with lifecycle states, per-step user review, tool-approval count and review history. The ledger does not duplicate raw user goals, tool arguments, file paths or file contents.
- Added bounded retention and capacity protection: maximum 20 records, 512 KiB serialized storage and 30-day retention. Only terminal runs may be evicted; active, paused and review-pending runs are preserved, and a new run is refused if the ledger is full of non-evictable records.
- Added restart-recovery guards so a completed or review-pending skill run cannot be revived by a stale task checkpoint. Agent stream failures preserve a skill run as paused only when a durable checkpoint can actually be read.
- Added Dart unit tests for skill-run lifecycle, active-version checks, approval limits, user step review, encrypted store round-trip, privacy boundaries and safe record eviction; added Python source-contract checks.

### Safety and limitations
- Skills are agent guidance, not executable scripts. No shell, PowerShell, arbitrary process execution, direct native method access, permission grant or auto-approved action is introduced.
- Skill `testCases`/acceptance examples are included as references for the agent and the user; they are not run by a deterministic automated acceptance-test engine in this milestone. `verified` records that the user confirmed every step, not that Leo independently proved every outcome.
- Each external action continues through the existing tool schema, role allowlist, task checkpoint and Capability Hub. The existing three successful handoffs per user turn remain the limit.
- There is no generic rollback of a completed task or successful external action. The workspace adapter still attempts rollback only when its own staged write/verification fails.
- Flutter/Dart/Rust tests, analysis, FRB generation, Android/Windows native builds and physical-device validation remain pending because the corresponding SDKs/build tools are not installed in this authoring environment. This is source-implemented Alpha, not a verified installable build.

## v0.23.0 — ALPHA

### Added
- Expanded the OS-first capability layer with opening a user-selected document in its registered viewer, event-draft handoff to the system calendar, and explicit text-only clipboard copy.
- Added Android document-viewer handoff using the session-selected SAF URI and read-only URI grant. The adapter allows only reviewed document/media extensions and blocks executable, script, shortcut, installer, HTML and unknown types.
- Added Windows document opening only for a file selected through Leo's picker, rejecting directories, reparse points and non-allowlisted extensions before using the registered file association.
- Added calendar event draft handoff: Android uses the platform Calendar insert intent without requesting calendar database permission; Windows creates a bounded UTF-8 ICS draft in a Leo-owned temporary directory and opens the registered calendar handler. The user must save the event in that app.
- Added write-only system clipboard integration on Android and Windows. Leo never reads the old clipboard value; the user sees a bounded preview and must approve every clipboard replacement.
- Added strict tool schemas, role boundaries, native parameter validation, bounded event/time and clipboard payload checks, audit integration and cross-platform capability policy entries.
- Added routing for calendar/clipboard/device requests and expanded contract tests for file type gating, calendar draft semantics, and clipboard write-only behavior.

### Safety and limitations
- File opening is limited to a reviewed extension allowlist; no executable or script-like file is launched by this tool. The user chooses each file and confirms the external handoff.
- Calendar integration only opens a draft/editor. Leo does not directly write the calendar database, save an event, or send invitations.
- Clipboard integration is write-only and overwrites the current clipboard only after a per-action confirmation. Leo does not inspect the existing clipboard content.
- Android and Windows native compilation, Dart/Rust tests, build artifacts and physical device validation still require the pinned CI/device matrix. This is source-implemented Alpha, not a verified installable build.

## v0.22.0 — ALPHA

### Added
- Added a role-scoped `workspace.write_file` proposal for `file_operator`, limited to creating or replacing one UTF-8 text file directly under a folder selected by the user.
- Added shared Dart validation for a 160-byte filename, 16 KiB content, 10,000 Unicode code points, prohibited path syntax, reserved Windows device names and control characters. Rust independently validates the model proposal; both native adapters revalidate the request.
- Added Android Storage Access Framework folder selection with short-lived session tokens and a Windows folder picker with canonical-root and reparse-point checks. No broad storage permission or persisted Android tree grant is requested.
- Added before/after preview, expected-current and proposed SHA-256 checks, a separate per-write approval dialog, staged write, post-write verification and rollback/backup handling.
- Added bounded workspace-write tool results and preserved actionable warnings when a verified write leaves a cleanup backup. The audit trail continues to store only fixed tool metadata, not filenames or file contents.
- Added Dart, Rust and Python contract tests for policy limits, role authorization, diff approval, platform adapter safety, cleanup and checkpoint/continuation compatibility.

### Safety and limitations
- Only one direct child file can be created or replaced per tool action. Nested paths, directory creation, deletion, moving, renaming, shell, arbitrary process execution and bulk writes remain disabled.
- Android SAF providers vary. The adapter fails closed when listing, staging or rename operations are unavailable. SAF does not expose compare-and-swap rename, so rechecking narrows but cannot eliminate a race with an independent external writer. A failed cleanup may leave a clearly named `Leo-Backup` file for user review.
- Windows stages within the selected folder, verifies the SHA-256 of the final file and attempts rollback after a failed verification. External filesystem races between the final check and the native replacement remain a platform limitation.
- Flutter/Dart/Rust, Android and Windows toolchain tests and physical-device validation remain pending in this workspace; this is source-implemented Alpha, not a verified installable build.

## v0.21.0 — ALPHA

### Added
- Replaced process-only agent continuation state with durable, bounded task checkpoints persisted through `flutter_secure_storage` on Android and Windows.
- Emit an initial plan checkpoint before the first model inference, then update it after each successful DAG step. A task interrupted during its first inference can now be restored from the plan with no completed results.
- Persisted checkpoint state, task/session identity, validated plan, completed successful step results, pending action proposal and completed handoff count; strict size, schema, dependency, duplicate and identity checks run before recovery.
- Added three explicit durable states: reasoning in progress, awaiting an external action, and ready to resume after a saved successful result.
- Added a recovery panel in chat to resume or discard saved tasks, plus explicit manual review for the ambiguous crash window where an external handoff may have happened but its result was not saved.
- Preserve the last checkpoint when active local reasoning is cancelled because the app enters the background; a user-requested Stop still deletes that task checkpoint.
- If a later secure-store write fails, retain any earlier known-good checkpoint, cancel the active task and keep external approval blocked; no plaintext fallback is used.
- Added an Android runner preparation step that disables app backup and excludes SharedPreferences from cloud backup and device transfer so encrypted preferences cannot be restored without their Android Keystore key.
- Added Dart store/receipt tests and Python source contracts for persistence, expiry, recovery state, initial checkpoint timing and safe handling of interrupted external actions.

### Safety and boundaries
- Up to eight pending tasks, a 256 KiB checkpoint per task, a 640 KiB aggregate secure-store budget, and seven-day retention. These are local recovery records, not a cloud sync or backup feature.
- A successful action result is written securely before the DAG resumes. If the app exits between the OS handoff and saving the outcome, Leo asks the user to inspect the external app and explicitly confirm or cancel; it never repeats the action automatically.
- Checkpoints preserve completed reasoning outputs and the plan; Rust validates the plan against the built-in agent catalog and revalidates dependencies before invoking any remaining agent.
- Android uses the secure-storage plugin's default encrypted storage path; Windows uses the plugin's platform secure-storage implementation. Windows builds require the C++ ATL component in Visual Studio Build Tools. These platform requirements still need CI/device validation.

### Validation boundary
- Python source/architecture contract checks, version synchronization, source archive checksums and source/config parsing were run in the authoring workspace.
- Flutter/Dart tests and analysis, Rust tests/format/clippy, FRB code generation, Android APK/Windows builds and real process-restart tests were not run because the corresponding toolchains/devices are not available in this environment.

## v0.20.0 — ALPHA

### Added
- Added a resumable, tool-aware agent task flow: the coordinator pauses the same validated DAG at the action specialist's proposal and resumes from the previously successful step checkpoints only after the Capability Hub confirms a successful action outcome.
- Added strict checkpoint validation for known step IDs, matching agent IDs, successful terminal state, bounded attempts/output, uniqueness, and dependency closure. A downstream result cannot be restored without all of its successful prerequisites.
- Added a versioned resume receipt bound to the pending task ID, tool call ID and tool name. Receipts require an exact six-field schema and an explicit `success: true`; failed, cancelled, mismatched, expired or replayed receipts are rejected.
- Added serial multi-action continuation with a maximum of three successful handoffs per user turn. The model cannot submit a batch; every action returns through the existing role allowlist, Capability Hub, OS permission checks and separate user confirmation.
- Added bounded pending-state controls: at most eight in-memory continuations, a ten-minute TTL, one pending continuation per task, and removal after a matching successful receipt. Invalid receipts do not consume a valid pending state.
- Added bounded, explicitly untrusted context for earlier specialist outputs and tool results. Prior successful steps are retained as checkpoints and are not executed a second time.
- Added Flutter receipt construction and chat orchestration that resumes only after a successful `ToolExecutionOutcome`; denial, cancellation, failure, page disposal or bridge failure terminates the chain safely.
- Added coordinator, bridge, Dart and Python contract tests for pause/resume, dependency closure, receipt validation, replay rejection, handoff budget and untrusted-context boundaries.

### Safety and persistence boundaries
- Pending continuation state is held only in process memory. It expires after ten minutes, is limited to eight pending tasks, and is lost when Leo's process exits or the app restarts. There is no automatic execution recovery after restart in this milestone.
- Only successful Capability Hub outcomes can produce a resume receipt. A resume receipt is a bridge protocol guard, not a user approval token; the actual approval remains inside the Capability Hub.
- Tool proposals remain one-at-a-time and role-scoped. Tool execution remains in Flutter/native adapters; Rust only coordinates reasoning and validates continuation state.
- Denied, cancelled or failed actions do not resume the DAG and are not represented as successful actions.

### Validation boundaries
- Python architecture/contract suite, version synchronization, source archive integrity and source/config parsing are run in this authoring environment.
- Rust unit tests and Dart unit tests are added but cannot be run here because Cargo/Rust and Flutter/Dart SDKs are unavailable. FRB code generation, Rust format/test/clippy, Dart format/analyze/test, Android/Windows builds and real-device multi-action tests remain pending.
- This is source-implemented Alpha, not a verified installable build.

## v0.19.0 — ALPHA

### Added
- Added a strict agent-to-tool proposal handoff for the built-in `file_operator`, `device_operator` and `communications` specialists. Specialists may propose only the tools assigned to their reviewed role; they never invoke native APIs.
- Added Rust-side envelope framing, version, ID, argument-key/type and role/tool-pair checks, a 16 KiB payload cap and a one-proposal-per-agent-task limit. Multiple, malformed or out-of-role proposals fail closed.
- Added a terminal `agent_tool_proposal` stream event. Flutter reparses the full proposal using the existing versioned allowlist before accepting the handoff.
- Routed accepted proposals through the existing Capability Hub, preserving first-use Leo consent, operating-system permission/resource checks, scope validation and separate action confirmation.
- Returned bounded non-proposal agent notes as transient untrusted context, then returned the bounded tool result to the local model for the final response. The agent DAG itself does not resume or execute again after handoff.
- Added an explicit role/tool allowlist in Flutter, explicit action-intent routing, and fallback to the ordinary sequential tool loop for turns with more than one action-focused specialist.
- Added Rust and Dart test cases for role-boundary enforcement, malformed envelopes, duplicate proposals and handoff revalidation.

### Safety and scope boundaries
- Only one tool proposal is handed off per multi-agent task. Multi-action requests involving multiple action specialists use the ordinary chat tool loop instead.
- Supported role mappings are: `file_operator` → `files.read_selected`; `device_operator` → `web.open` / `app.launch`; `communications` → `email.compose` / `messages.compose` / `phone.dial`.
- The Rust coordinator never executes a proposal. Flutter remains the only dispatcher, and the Capability Hub remains authoritative for consent, OS access and user approval.
- Proposal arguments, agent notes and tool results are transient request context. The existing metadata-only audit continues to exclude arguments, content, file paths and file data.
- Denied/cancelled/failed outcomes are returned as untrusted tool results with an instruction not to retry the rejected operation. No success is claimed unless the gateway confirms the OS handoff.

### Validation boundaries
- Python source/architecture contract tests and source-integrity checks can be run in this authoring environment. Rust and Dart unit tests are added but not executed because Cargo/Rust and Flutter/Dart are unavailable.
- FRB bindings are structurally unchanged: the handoff uses the existing `AgentTaskEventDto` string fields with a new event kind. FRB generation and compile verification remain required in CI.
- Android/Windows builds and physical-device approval/denial/cancellation tests remain pending. This is a source-implemented Alpha milestone, not a verified installable build.

## v0.18.0 — ALPHA

### Added
- Connected automatic multi-agent routing to a real local execution coordinator. Complex reasoning requests are split into a validated dependency graph and run through the already loaded local GGUF runtime.
- Added bounded sequential DAG execution with per-agent prompts, bounded conversation/dependency context, incremental progress events, deterministic step ordering and a final verifier handoff.
- Added up to two attempts per step by default (hard-capped at three), explicit failed/skipped/cancelled states, partial-result aggregation and cancellation of the currently active native generation.
- Added automatic multi-agent use in chat for complex reasoning requests. Communication, device-operation and file-operation intents continue through the existing Capability Hub / approval path.
- Added regression contracts for automatic routing, retry, cancellation, failed dependencies, partial results and output bounds.

### Safety and resource boundaries
- Multi-agent execution is local-model reasoning only and is sequential because the current native runtime permits one active generation and must respect device memory/CPU limits.
- Agents cannot execute shell, filesystem, network, communication or device actions. Tool execution remains exclusively in the separate Capability Hub and one-action approval loop.
- Agent outputs and prior conversation context are treated as untrusted reference data; step outputs are capped at 16,000 characters by default and dependency excerpts at 4,000 characters.
- No user prompts, full conversation transcripts or tool arguments are written to an agent-task audit store. This milestone does not add task persistence.

### Validation boundaries
- The Python architecture/contract checks validate source wiring and policy boundaries. Rust unit tests are added for the scheduler but cannot be run in this authoring environment because Cargo/Rust are unavailable.
- Flutter format/analyze/tests, FRB code generation, Android/Windows builds and physical-device multi-agent latency/cancellation tests remain required in CI and on target devices.

## v0.17.0 — ALPHA

### Added
- Added a model-load resource configuration dialog with supported context presets, an explicit CPU thread selector and a live estimate of the native loader's conservative RAM admission threshold.
- Added a resource policy that mirrors the native GGUF memory gate: model file size + 12.5% margin + 384 MiB base reserve + 128 MiB per rounded-up 2048 context tokens.
- Reduced default chat inference concurrency to at most four logical CPU threads while reserving one logical processor where possible; voice VAD/ASR/TTS use a smaller dynamic budget capped at two threads.
- Added process RSS and peak-RSS visibility to the local model runtime card, explicitly identifying these values as whole-process metrics.
- Added a confirmation warning before local ASR when a GGUF chat model is already loaded; Leo never unloads the user's chat model automatically.
- Added Dart policy tests and Python source-contract tests for memory estimation, context limits, thread budgeting and the voice-resource warning.

### Resource and validation boundaries
- The UI estimate is not a reading of current free RAM. The native Android/Windows adapter independently reads live available physical memory immediately before model allocation and blocks the load when the conservative threshold is not met.
- Thread counts are safe defaults and user-adjustable for GGUF loading; speech workers choose a conservative CPU-only thread count. No GPU execution provider is enabled in this milestone.
- Flutter/Dart/Rust toolchain checks and physical-device model/voice tests remain pending because the relevant SDKs and devices are unavailable in the authoring environment.

## v0.16.0 — ALPHA

### Added
- Added a local ASR evaluation harness that computes corpus-level WER/CER, Arabic/English normalization, per-language breakdowns, inference/model-load median and p95 latency, and process-memory high-watermark summaries.
- Added an evaluation template and test suite so Arabic, English and mixed-language results can be compared across Android/Windows devices without uploading recordings.
- Evaluation reports deliberately exclude reference and recognized transcript text; sample IDs are opaque, and the input schema rejects audio paths, prompts and raw audio fields.
- Added single-flight capture/transcription protection and capture-generation cancellation checks so a cancelled or stale ASR result cannot be inserted after the current voice session has moved on.

### Validation boundaries
- The evaluation harness scores supplied text transcripts; it does not claim any recognition-accuracy result until real device samples are recorded and scored.
- No audio corpus, user transcript, model weight or device-private data is included in the source package.
- Flutter/Dart/Rust tests, native Android/Windows builds and actual device latency/accuracy measurements remain pending in a toolchain-enabled environment.

## v0.15.0 — ALPHA

### Added
- Added an optional user-imported Silero VAD pack and local silence-based recording endpointing at 16 kHz using fixed 512-sample frames.
- Preserved manual stop and the strict 30-second recording cap; unavailable or failing VAD degrades safely to manual stop.
- Added app lifecycle cleanup that cancels active capture and stops voice playback when the app leaves the resumed state.
- Added a native Sherpa/ONNX runtime preflight screen and default-off, local-only ASR/TTS timing and process-memory diagnostics.
- Added unit/contract coverage for PCM frame assembly, VAD pack integrity and privacy-bounded opt-in metrics.

### Privacy and validation boundaries
- Diagnostics store metadata only; audio, transcripts, prompts, model paths and model contents are excluded. Process RSS is the process high-watermark, not a per-inference memory delta.
- No wake word, background recording, partial live transcript or streaming TTS is introduced.
- Flutter/Dart/Rust toolchain tests, Android/Windows native builds and physical-device checks remain pending in this authoring environment.

## v0.14.0 — ALPHA

### Added and improved
- Added streamed SHA-256 manifests for imported Qwen3-ASR and Supertonic voice packs, without buffering model weights in memory.
- Added duplicate-filename rejection, manifest schema/path/size checks, an explicit full-pack integrity audit and clear legacy-unverified/baseline/verified/failed states.
- Preserved existing complete voice packs without manifests; users can create a local integrity baseline without reimporting the model.
- Added a pure-Dart PCM16 mono WAV encoder and removed the TTS voice path's dependency on the sherpa native WAV writer.
- Made audio-player initialization lazy and made playback completion generation-scoped to prevent stale TTS tasks from completing newer playback.
- Tightened microphone stream cleanup and reject malformed odd-byte PCM16 chunks.
- Added Dart tests for WAV encoding and voice-pack integrity lifecycle, with `cross_file` used only by the test adapter.

### Integrity and validation boundaries
- SHA-256 manifests are local change-detection baselines, not signed provenance. They do not prove publisher identity or verify official upstream checksums.
- Flutter/Dart/Rust and Android/Windows build toolchains are unavailable in the authoring environment. Dart tests, static analysis, native builds and real-device voice tests remain to be run by CI and on hardware.

## v0.13.0 — ALPHA

### Added
- Added an offline voice foundation for Android and Windows using `sherpa_onnx` 2.0.1, `record` 7.2.0 and `audioplayers` 6.8.1.
- Added optional, user-imported Qwen3-ASR 0.6B INT8 and Supertonic 3 INT8 voice packs stored in Leo's app-private support directory; model weights are not bundled in the base installer.
- Added push-to-talk audio capture (PCM16, mono, 16 kHz), local Arabic/English transcription and local Arabic/English text-to-speech synthesis. The ASR model pack is documented for 30 languages; TTS language selection in this build remains a simple Arabic/English heuristic.
- Added chat composer transcription insertion; recognized speech is never sent automatically.
- Added local playback controls for assistant messages and a voice-model library with official model and documentation links.
- Added a 30-second voice-command cap, streamed pack import with file/pack size bounds, staged installation and replacement rollback. Qwen ASR file import uses separate model-root and tokenizer-folder picker rounds; the UI automatically stops microphone capture at the 30-second limit; the duration notice matches the actual cap; stale TTS requests are discarded after Stop or a newer request; Supertonic speaker ID 0 matches the upstream sample invocation.
- Enabled the microphone capability through Leo's just-in-time consent flow; Android then requests the OS permission, while Windows opens its microphone privacy settings on first use.
- Added a Windows runner preparation step that applies the CMake 3.15/CMP0091 compatibility required by audioplayers 6.8.1.

### Limitations
- This is push-to-talk, not wake-word detection or continuous background listening; there is no VAD/automatic end-of-utterance detection or partial live transcript yet.
- ASR runs after the user stops recording; partial live transcription is not enabled. TTS synthesizes a local WAV before playback and is not streaming.
- The Qwen3-ASR pack is approximately 0.94 GB from the documented model-file sizes. The Supertonic pack is separate. Users must obtain and import both packs themselves; voice weights are not included in APK/EXE.
- File import validates expected names, sizes, non-empty contents and the staged directory structure; it does not cryptographically prove model origin. Do not import model files from untrusted sources.
- Windows does not provide a runtime permission-query contract through the selected recorder plugin. Leo records its own consent, opens Windows microphone privacy settings on first use, and relies on Windows to enforce access when capture starts.
- Arabic/Sudanese-dialect recognition quality, voice naturalness, latency, memory use and battery use require real-device evaluation. No dialect-specific accuracy claim is made.
- Flutter/Dart, Rust, Android and Windows build toolchains are not installed in this authoring environment; static source checks do not constitute successful APK/EXE builds or native compilation. CI and device testing remain required.

# Changelog

## v0.12.0 — ALPHA

### Added
- Connected structured local-model tool requests to the Capability Hub using a strict `<leo_tool_call>` protocol. Calls must be the entire assistant response, use protocol version 1, carry exactly one allowlisted tool and remain within a 16 KiB UTF-8 payload.
- Added exact per-tool argument schemas and bounded validation for email, phone, message and URL inputs; unknown tools, unknown keys, non-string arguments, unsafe URL schemes, control characters, multiple blocks and malformed envelopes are rejected.
- Added typed dispatch for selected-file reading, Android contacts reading, email draft, dialer handoff, Android SMS draft, HTTP/HTTPS open and installed-app launch. Every dispatch reuses `CapabilityHubService`; the model has no direct MethodChannel or native API entry point.
- Added a sequential chat tool loop with a maximum of three calls per user turn, untrusted tool-result messages, explicit handling for cancelled/denied/failed actions, and suppression of raw tool-call JSON from the visible transcript.
- Added a metadata-only local execution audit and a chat-menu page to inspect tool name, status, timestamp and short summary. The audit stores no tool arguments or user content.
- Added platform-specific tool availability instructions and Flutter parser tests plus Python contract tests.

### Security and behavior boundaries
- The existing broker remains authoritative for just-in-time Leo consent, OS/resource permission and separate action confirmation. Model-generated output cannot grant permissions or approve actions.
- Email and SMS remain draft-only; phone calls open the dialer only. Selected-file reads still use the native system picker and remain limited to selected UTF-8 text. Tool output is untrusted and capped at 12,000 characters.
- The current allowlist does not include arbitrary shell/PowerShell, file writes/deletes, direct calls, silent sending, microphone capture, admin actions or general UI automation. Windows does not expose contacts or SMS tools in this build.
- Tool audit metadata is app-private but not separately encrypted. It intentionally excludes message bodies, phone numbers, email addresses, contact content, file paths and file content.
- Tool calling depends on local model adherence to the prompted protocol; malformed requests are rejected. The loop is sequential and capped at three calls per user turn.

### Validation limitations
- Python source/architecture contract suite: 50/50 passed. Version synchronization, preservation hashes and JSON/TOML/YAML parsing passed. Dart/Flutter, Rust/Cargo, Android SDK/NDK and Windows native toolchains remain unavailable in this environment, so no Flutter test/analyze or Android/Windows build is claimed. CI and physical-device verification are still required.

## v0.11.0 — ALPHA

### Added
- Added a persistent Rust `leo-capabilities` broker backed by app-private SQLite, with scoped decisions, denial/revocation, expiry checks and OS-state revalidation.
- Added a built-in cross-platform capability catalogue and typed Flutter Rust Bridge endpoints for catalogue listing, permission checks/decisions, revocation and separate consequential-action confirmation.
- Added the Flutter Capability Hub service: Leo first explains and requests its own consent, then requests/checks the native OS permission or a user-selected resource, and finally asks for separate confirmation for high-risk/external actions.
- Added a permission center reachable from the chat menu. It shows platform capabilities, their Alpha availability and stored Leo grants, and can revoke Leo's own grant without pretending to revoke a system-level permission.
- Added an Android native plugin using the Storage Access Framework, runtime contacts permission and local contacts query, dialer handoff, email/SMS draft handoff, HTTP/HTTPS opening and launcher-app launch.
- Added a Windows native plugin using the system file picker, a 2 MiB UTF-8 text preview restricted to files selected in the current app session, ShellExecute handoffs for HTTP/HTTPS, mail/tel drafts and restricted registered app targets.
- Added native plugin contract checks, bridge API tests and a Flutter permission-center widget test.

### Security and behavior boundaries
- No sensitive permission is requested at installation, first launch or chat startup.
- A saved Leo grant never overrides current OS permission state; scope changes require new Leo consent.
- Email and SMS operations only open a prepared draft. They do not send silently. Dialing opens the dialer and does not place a direct call.
- File reads are limited to a user-selected document in the current app session and a 2 MiB UTF-8 text preview. Android persistable URI grants are not retained; NUL/binary content is rejected. Directory traversal, writes, broad storage access and arbitrary paths are not enabled.
- Windows runs at standard user level; administrator operations, general process execution and UI automation are not enabled. Native file and URI inputs have explicit size/control-character validation.
- Generic web opening is restricted to HTTP/HTTPS and requires an individual external-action confirmation. Mail and dialer use dedicated handoff capabilities.
- Model-driven tool-call execution is not connected yet. The Capability Hub is an available typed service/native layer for the upcoming execution gateway, not a claim that Leo can already autonomously execute all these actions from a conversation.
- The Android plugin declares a launcher-intent `<queries>` filter rather than broad `QUERY_ALL_PACKAGES`; Windows app identifiers are restricted to selected registered app targets and a short `ms-settings` allowlist.

### Validation limitations
- Python source/architecture contract tests: 39/39 passed. JSON/TOML/YAML parsing, version synchronization and preservation hashes for both original source archives also passed. Flutter, Dart, Rust, Android SDK/NDK and Windows SDK toolchains are not installed here, so Rust compilation, FRB code generation, Dart analysis/tests and Android/Windows plugin builds remain to be confirmed by CI.
- Windows native plugin source is not compile-verified locally. A successful Windows CI build and real-device testing are required before treating its connector behavior as production-ready.


All notable Leo application changes are recorded here. Documentation-only changes do not require an application version bump.

## v0.10.0 — ALPHA

### Added
- Added an explicit **Learn a skill from this conversation** action to the chat library menu.
- Added local-model-assisted extraction of reusable workflow proposals from the selected conversation, bounded to the latest 20 eligible messages and 9,000 transcript characters.
- Added strict JSON/schema and length validation for model-generated skill proposals; proposals are always saved as inactive `proposed` skills.
- Added safeguards instructing the local model to treat the transcript as untrusted data, avoid inventing execution evidence or capability identifiers, and preserve per-action approval for consequential steps.
- Added request cancellation when the chat page is disposed, and tests for valid proposals, insufficient evidence, unsafe capability identifiers and empty conversations.
- Kept the portable single-file `SKILL.md` import/export delivered in v0.9.0 and corrected the v12 file-picker API usage in the GGUF model import screen.

### Limitations
- Skill extraction is explicitly user-triggered and analyzes conversation text; it does not prove that discussed steps were actually executed.
- No task execution trace store exists yet, so automatic post-execution learning is not implemented.
- Extracted skills remain inactive until the user reviews, preflights and explicitly activates them.
- Skill tests are not yet run against a sandboxed model or real application.
- Flutter/Dart and Rust SDK checks and Android/Windows builds were not run in this environment because the toolchains are unavailable.


## v0.9.0 — ALPHA

### Added
- Added portable declarative `SKILL.md` export and import using Agent Skills-style YAML frontmatter and Markdown sections.
- Added support for simple and folded YAML description scalars, workflow triggers, steps, acceptance scenarios and declared capability identifiers.
- Imported skills always enter as inactive proposals with no inherited approval, validation state, history or permissions.
- Restricted imports to small Markdown documents; executable scripts and bundled resource folders are not imported or run.
- Switched file picking to the v12 `pickFile()` API and corrected the existing GGUF model import screen to use the same API.
- Added codec round-trip, external skill import, invalid metadata and size-limit tests.

### Limitations
- This is declarative `SKILL.md` interchange, not full folder/ZIP import. Scripts, assets and reference folders are ignored and unsupported.
- Preflight remains structural and heuristic; scenario examples are not executed against a model or application.
- The Skill Curator does not yet auto-extract skills from completed execution traces because Leo's end-to-end task execution and trace store are still under development.
- Flutter/Dart and Rust toolchain checks and Android/Windows builds require CI/toolchain validation; they were not run in this environment.


## v0.8.0 — ALPHA

### Added
- Added an offline app-private skill library with proposed, testing, active, disabled and rejected lifecycle states.
- Added user-facing skill authoring, inspection, revision history, structural/safety preflight, explicit activation, disable, reject and delete controls.
- Added bounded trigger-based retrieval of active and validated skills as transient untrusted guidance for local chat.
- Added a built-in Skill Curator agent and automatic routing for workflow-learning requests.
- Added skill policy configuration, architecture documentation and lifecycle/context/UI tests.

### Limitations
- Preflight is structural and heuristic; stored example scenarios are not yet simulated against a model.
- Automatic skill extraction from completed executed tasks is deferred until Leo's task engine records real execution workflows.
- Skills are declarative; embedded scripts are not executed. Skills cannot grant permissions or approve actions.
- App-private skill JSON is not separately encrypted. Portable `SKILL.md` pack import/export is deferred.
- Flutter/Dart and Rust toolchain checks and Android/Windows builds require CI/toolchain validation; they were not run in the local environment.

## v0.7.0 — ALPHA

### Added
- Added the Arabic-first long-term memory review screen with manual memory creation, approval, editing, pause/resume and deletion.
- Added a typed Flutter memory repository backed by Leo's app-private SQLite database path.
- Added relevant-memory retrieval before local generation, capped to four results and a bounded character budget.
- Added a fixed system-level boundary that marks retrieved memories as untrusted reference data; memory context is transient and is not saved in conversation history.
- Added privacy disclosure in the memory screen, including the current lack of database encryption.
- Added Dart contract tests for bounded memory context and the memory review screen.

### Notes
- The current memory flow is user-curated: Leo does not autonomously extract facts from chat yet.
- Embeddings, conflict resolution, export/import and encryption remain future work.
- Flutter/Rust code generation, Dart analysis/tests, Rust compilation/tests and platform builds require CI/toolchain validation; they were not run in this environment.


## v0.6.0 — ALPHA

### Added
- Added a standalone `leo-memory` crate backed by bundled SQLite for Android and Windows.
- Added versioned local storage for personal, episodic, semantic, procedural and project memories.
- Added a proposal-first lifecycle: pending memories are excluded from retrieval until user approval; approved memories can be edited, disabled, re-enabled, listed and deleted.
- Added Arabic-normalized BM25-style retrieval over approved and active memories, with bounded candidate/result counts.
- Added source references, tags, timestamps, input validation and deterministic duplicate detection.
- Added typed bridge endpoints for memory lifecycle and search operations.
- Documented local-memory privacy boundaries and the fact that this SQLite layer is not encrypted by itself.

### Notes
- v0.6.0 delivered the storage and bridge foundation only. The user-facing review screen and bounded generation-context retrieval were added in v0.7.0; automatic memory extraction, contradiction handling, embeddings and encryption remain follow-up work.
- Rust compilation, SQLite target builds, Flutter Rust Bridge generation and platform builds require the pinned toolchain CI; they were not run in this environment.

## v0.5.0 — ALPHA

### Added
- Automatic built-in agent routing now normalizes common Arabic orthographic variants before selecting specialists.
- Added a validated task-plan DAG builder: the planner prepares the task, relevant specialists can run as parallel branches, and the verifier depends on the specialist results.
- Added typed Flutter Rust Bridge endpoints for specialist selection and task-plan preview.
- Added bridge-level contract tests for single-specialist selection, multi-agent plans and empty-goal rejection.
- Windows native adapter now uses the static MSVC runtime to avoid a separate Visual C++ redistributable dependency.
- Corrected Windows process virtual-memory telemetry to report `VirtualSize` rather than pagefile/commit usage.
- Confirmed the pinned llama.cpp/ggml revision handles UTF-8 file paths on Windows through `ggml_fopen`; the adapter now passes model paths unchanged after native filesystem validation.

### Notes
- Agent routing and task-plan preview are implemented, but independent agent model executions, scheduling, concurrent execution, result aggregation and cancellation remain future orchestration work.
- Windows native source and CI wiring remain unverified until the Windows CI build and a real Windows model-load/inference test pass.
- No platform build, native Windows DLL compilation, Android APK build or Rust/Flutter compile was available in this environment.

## v0.4.0 — ALPHA

### Added
- Windows x64 native llama.cpp backend path using the same Leo C ABI as Android ARM64.
- Windows physical-memory and process-memory diagnostics through Windows system APIs.
- Pinned Windows native build script and CI packaging path for the native DLL.
- Windows runtime loading from the application executable directory rather than the working directory or PATH.
- Portable GGUF catalogue imports: model files are no longer marked as supported only on the operating system where they were imported.

### Notes
- Windows CPU inference is implemented in source and wired into the Windows build pipeline, but has not yet been compiled or exercised on a Windows host in this environment.
- Android remains CPU-only with its existing NDK pipeline. Beta validation still requires real device tests on both platforms.

## v0.3.0 — ALPHA

- Replace the temporary Flutter MethodChannel runtime stub with a typed Flutter Rust Bridge boundary and a generated-code workflow.
- Connect chat generation and cancellation to the Rust `AssistantRuntime` contract; stream native text deltas and avoid duplicate terminal failures.
- Add a persistent app-private GGUF model library with validation, SHA-256 integrity checks, atomic catalogue updates, crash-recovery metadata, import, load, unload and removal operations.
- Add an Arabic-first local-model management screen with OS file picking, device-private storage, runtime diagnostics and memory controls.
- Add Flutter Rust Bridge Native Assets build-hook configuration and CI code generation.
- Add version consistency checks for the Cargo workspace in addition to Flutter.

### Current limitations

- The real llama.cpp adapter is implemented for Android ARM64 only; Windows native inference remains a planned Alpha milestone.
- The Android NDK build is configured in CI but has not been executed in this development environment.
- Rust/Flutter code generation, analysis, tests and platform builds must pass on CI or a machine with the pinned SDKs before this milestone is considered verified.
- The adapted NEXUS source remains private pending confirmation of its redistribution license; no unverified adapted files are being released as third-party open source.

## v0.2.0 — ALPHA

- Replace the foundation-only Flutter screen with Leo's responsive Arabic-first chat workspace.
- Add local conversation persistence, session history, conversation deletion, and first-message titles.
- Add a native runtime event-channel boundary for future Rust/llama.cpp integration; missing native runtime handlers are reported honestly.
- Add Markdown, fenced code, and LaTeX message rendering foundations based on the J.A.R.V.I.S chat experience.
- Implement the built-in agent catalog loader, deterministic specialist routing, and task dependency/cycle validation in Rust.
- Add the first capability broker policy crate with OS-first provider resolution, just-in-time permission state checks, and separate action-confirmation rules.

## v0.1.0 — ALPHA

- Establish Leo AI foundation workspace and module boundaries.
- Preserve the original J.A.R.V.I.S and NEXUS source archives as immutable references.
- Add initial shared domain contracts and runtime boundaries.
- Add custom version policy validation and source baseline records.
