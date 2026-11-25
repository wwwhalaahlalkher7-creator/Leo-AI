# Leo AI

**Product name:** Leo
**Project name:** Leo AI
**Current version:** `v0.27.0`
**Release channel:** `ALPHA` — construction and assembly

Leo is being built as an offline-first personal AI assistant for Android and Windows. It combines a local model runtime, automatic specialist-agent orchestration, durable memory, learnable skills, and an OS/application-first capability layer. A cloud service is never a mandatory dependency for the core assistant workflow.

## Engineering workflow

The required development process, milestone template and acceptance checklist are maintained in:
- [`docs/development/ENGINEERING_PRODUCTION_PIPELINE.md`](docs/development/ENGINEERING_PRODUCTION_PIPELINE.md)
- [`docs/development/MILESTONE_TEMPLATE.md`](docs/development/MILESTONE_TEMPLATE.md)
- [`docs/development/ACCEPTANCE_CHECKLIST.md`](docs/development/ACCEPTANCE_CHECKLIST.md)

These documents supplement the existing lifecycle/version policy, architecture ADRs, roadmap and platform qualification protocol; they do not override them. The current executable CI remains `.github/workflows/ci.yml`.

## Delivered milestones and current capabilities

`v0.11.0` added the first OS/application-first Capability Hub slice: a persistent scoped permission broker, just-in-time Leo consent, independent OS/resource checks and separate per-action confirmation. Android supports SAF file selection, local contacts reading, dialer, email/SMS draft, HTTP/HTTPS and launcher-app handoffs. Windows supports the system file picker, selected-file UTF-8 text preview, registered app targets, dialer/mail and HTTP/HTTPS handoffs. File previews are limited to 2 MiB; Android URI access is session-only. Email/SMS are drafts and dialing opens the dialer; Leo does not silently send or call.

`v0.12.0` connects the local chat model to a strict structured tool protocol. The model may propose one allowlisted tool call per response; Flutter validates the envelope and arguments, then dispatches only through typed Capability Hub methods. A user turn is limited to three sequential tool calls. The gateway exposes selected-file reading, Android contacts, email drafts, dialer handoff, Android SMS drafts, HTTP/HTTPS opening and installed-app launch. It preserves all existing first-use permission and per-action confirmation flows, returns bounded untrusted results to the local model, and records metadata-only execution history. The raw tool JSON and sensitive arguments are not added to the visible or persisted chat transcript.

The connector surface remains deliberately limited. v0.22.0 added one-file UTF-8 workspace create/replace directly under a folder selected by the user, with a bounded before/after diff and separate per-write approval. Nested paths, folder creation, file deletion/move/rename, arbitrary shell/process execution, direct calls, administrator operations, general UI automation and peer task receiving remain disabled. Android uses the Storage Access Framework folder picker and a provider-dependent staged rename/backup flow; some providers may reject replacement, in which case Leo fails closed. SAF providers do not expose compare-and-swap rename, so a narrow external-writer race cannot be eliminated. Windows uses a selected canonical folder, reparse-point checks, staging, ReplaceFile/MoveFile and post-write hash verification. v0.23.0 adds three OS handoffs: opening a user-selected safe document, creating a calendar event draft that the user must save, and copying explicitly approved text to the write-only system clipboard. File opening uses an extension allowlist and rejects dangerous provider MIME types; clipboard content is never read by Leo. Alpha v0.13.0 introduced manual offline voice capture and playback; v0.14.0 added local streamed model-pack SHA-256 baselines and playback hardening; v0.15.0 added optional VAD endpointing and opt-in local diagnostics; v0.16.0 added the local Arabic/English ASR evaluation harness and capture-session cancellation protection; v0.17.0 added GGUF resource planning and conservative CPU budgets; v0.18.0 added sequential multi-agent DAG execution; v0.19.0 added a safe, role-scoped agent-to-tool proposal handoff; v0.20.0 added serial, approval-gated continuation of the same agent DAG after successful tool results; and v0.21.0 added encrypted, bounded task checkpoints and user-reviewed restart recovery; v0.22.0 added the bounded, per-write-approved workspace text editor. Voice model packs remain separately user-imported; recognized text is inserted into the composer and is never sent automatically. No wake word or background listening is present. Model adherence and platform behavior still require CI and physical-device verification.

The app also contains a typed Flutter Rust Bridge boundary, a persistent GGUF model catalogue and integrity-checked model import, streaming local chat, long-term memory and review UI, bounded approved-memory retrieval, an app-private skill library, portable declarative `SKILL.md` import/export, and local-model-assisted skill proposals from selected conversations. Skill proposals remain inactive until reviewed, preflighted and explicitly activated. **v0.24.0 added the first agent-guided execution layer for active skills:** Leo previews the ordered steps, asks before starting, supplies the skill's instructions and acceptance examples as untrusted context to its local specialist-agent DAG, and records an encrypted review ledger. The user reviews every step after execution; a run is marked `verified` only to mean that the user confirmed every step, not that Leo ran an independent objective test suite. The ledger does not duplicate the raw user goal, tool arguments, file paths or file contents. It retains at most 20 runs for 30 days and never evicts an active or awaiting-review run to make room. **v0.25.0 adds opt-in workflow-derived skill learning:** from the skill library, the user can request a new inactive proposal based on a run they previously reviewed and marked complete. Only the minimized, pattern-redacted original skill outline and confirmed steps go to the local model; raw conversations, goals, review notes, tool arguments/results, file paths and file contents are excluded. The source skill's exact ID/version and step sequence are rechecked, generated capabilities must be a subset of the original skill's declarations, and a given verified run can produce only one proposal. Redaction is pattern-based, not a guarantee against every form of personal data, so the user reviews the result before preflight and activation. This remains agent-guided, model-mediated execution and learning—not a deterministic SKILL script engine or automatic acceptance-test runner. Complex tasks run through a validated, sequential local multi-agent DAG. For explicit device/file/communication actions inside a multi-agent task, the appropriate specialist may return one strictly framed tool proposal at a time; Flutter reparses it and sends it through the existing Capability Hub. A successful action resumes the same DAG from its validated successful checkpoints; completed steps are not rerun. Up to three successful serial handoffs are allowed per user turn. Agent task recovery checkpoints are encrypted in OS-backed secure storage, capped at eight tasks and seven days; an interrupted reasoning task can resume from successful steps after restart. If an external action was pending when the app stopped, Leo never repeats it automatically and requires the user to inspect the external app and explicitly confirm or cancel. Denial, cancellation or failure stops the agent continuation. The original J.A.R.V.I.R and NEXUS archives remain unchanged under `source_refs/`. **v0.26.0 adds opt-in memory curation and privacy controls:** a user may choose one of their own chat messages and review it as a pending memory proposal; Leo does not silently scan or learn from whole conversations. Local lexical heuristics flag likely duplicates or opposite-polarity records for human review only. Memory content, normalized search text, tags and source references are encrypted with AES-256-GCM using row-and-field-bound associated data. A platform secure-storage key is created and can be rotated with interruption recovery; legacy plaintext and older field envelopes are upgraded transactionally. The HMAC duplicate fingerprint uses a separate HKDF-derived subkey. SQLite record IDs, kinds, timestamps, approval/activation flags, schema/encryption versions and opaque keyed fingerprints remain visible as metadata, as disclosed in the Memory UI. Users can create passphrase-protected AES-GCM/PBKDF2 backups (up to 1,000 records/5 MiB); imports become inactive pending proposals and do not restore source references or approval state. Key deletion and database sidecar removal are checked, but this is not a forensic deletion guarantee against filesystem snapshots or external copies.

## Version source of truth

- `config/VERSION`: `vMAJOR.MINOR.PATCH`
- `config/RELEASE_CHANNEL`: `ALPHA`, `BETA`, or `RELEASE`
- `config/BUILD_NUMBER`: platform build metadata only; it is not a fourth public version component
- `config/version_policy.json`: full version policy

Do not edit the version in `pubspec.yaml` by hand; run `python scripts/sync_version.py` after changing `config/VERSION` or `config/BUILD_NUMBER`.

## Repository map

- `core/memory/` — user-controlled local long-term memory storage and BM25-style retrieval
- `apps/leo_app/lib/core/skills/` — local skill lifecycle, preflight, bounded retrieval and encrypted skill-run review ledger
- `apps/leo_app/lib/core/capabilities/` — permission broker client and OS/app capability hub service
- `apps/leo_app/lib/core/tools/` — strict tool-call protocol, allowlist validation, capability dispatch and metadata audit
- `apps/leo_app/lib/core/voice/` — local voice pack storage, microphone capture, ASR and TTS service
- `apps/leo_app/lib/features/voice/` — offline voice model import and status UI
- `apps/leo_app/lib/features/tools/` — user-visible tool execution audit
- `apps/leo_app/lib/features/capabilities/` — permission center and grant management
- `core/capabilities/` — persistent scoped permission broker and capability registry
- `packages/leo_platform_capabilities/` — Android Kotlin and Windows C++ native OS/application adapters
- `apps/leo_app/lib/features/skills/` — skill library, approval UI and portable SKILL.md import/export
- `apps/leo_app/` — Flutter chat application and conversation UI
- `core/shared/` — platform-independent domain contracts
- `core/runtime/` — local inference runtime abstraction and Android/Windows dynamic native loader
- `core/bridge/` — typed Flutter Rust Bridge API
- `native/llama/` — shared cross-platform llama.cpp C ABI adapter
- `core/orchestration/` — agent routing, task DAG execution and role-scoped proposal validation
- `contracts/` — wire-format and domain contract documentation
- `config/` — version, built-in agent catalog, and capability policies
- `docs/audit/` — source inventory, migration register, baseline reports
- `docs/planning/REMAINING_RELEASES_ROADMAP.md` — remaining Alpha milestones, v1.0.0 Beta entry and Release gates
- `docs/testing/` — reproducible local voice-quality, skill-execution and memory-privacy test protocols
- `docs/architecture/` — system boundaries and architecture decisions
- `source_refs/` — original source archives; do not edit these archives

## Current implementation status

- Chat UI, local history, Markdown/code/math rendering foundations, built-in Arabic-normalized agent routing, validated multi-agent task DAG execution, bounded retry/cancellation/result aggregation, role-scoped agent tool proposals, multi-step tool-aware task continuation through the Capability Hub, encrypted local SQLite memory payloads, Arabic-normalized retrieval, user-facing memory review, duplicate/possible-contradiction review hints, encrypted memory backup/import, key rotation/erase controls, bounded transient approved-memory context, and the proposed/testing/active skill lifecycle with declarative SKILL.md interchange are implemented in source. Memory curation is user-triggered; selecting a user-authored chat message opens an editor and creates a pending proposal only. Memory similarity and polarity checks are lexical heuristics, not semantic proof, and they never update/approve/delete records automatically. Memory payload fields are encrypted, but row IDs, kinds, timestamps, approval/activation flags, schema/encryption version and opaque keyed fingerprints remain plaintext metadata in SQLite. Imports remain pending and inactive; no backup restores trust state or source references. Skill preflight is not LLM execution testing. Skill learning is user-triggered from a selected conversation or a completed skill run whose every step the user confirmed; both paths create inactive proposals. Workflow-derived learning uses minimized, redacted step evidence and cannot add capabilities. Imported and learned skills remain proposals until reviewed, preflighted and explicitly activated.
- The Flutter chat client calls the typed Rust inference bridge; the typed bridge also exposes automatic agent selection, task execution/progress/cancellation, task-plan preview and memory lifecycle/search APIs. Agent tool proposals travel through existing `AgentTaskEventDto` fields and are reparsed by Dart; native execution remains in the typed Flutter Capability Hub. The Flutter memory repository uses the app-private support path; only approved/active relevant records can be added to a bounded, transient generation request. Retrieved memory is never saved as part of the conversation transcript. Generated bridge code is produced by `scripts/generate_bridge.sh`.
- Android ARM64 uses the pinned NDK native build; Windows x64 now has its own MSVC DLL build path against the same upstream llama.cpp revision; this path awaits a successful Windows CI run.
- Multi-step agent/tool continuation now persists bounded task checkpoints in `flutter_secure_storage` for Android and Windows. The store keeps at most eight tasks for seven days, validates checkpoint/task/tool identity and records successful action results before resuming local reasoning. Android runner preparation disables Android backup and excludes SharedPreferences from backup/device transfer; Windows builds require the Visual Studio C++ ATL component. Interrupted external actions are never replayed automatically: the user must manually inspect the external app and explicitly confirm before reasoning resumes. These are source-level integrations until the Flutter/Dart/native build and real restart tests pass.
- Model import, GGUF validation, SHA-256 verification, persistent catalogue management and load/unload controls are implemented in the Rust core and exposed to Flutter.
- Imported GGUF files remain platform-neutral; current platform availability is determined by the installed native backend, not by the OS on which the file was imported.

## Development checks

```bash
python scripts/check_version.py
python scripts/verify_sources.py
python -m unittest discover -s scripts/tests -v

cd apps/leo_app
flutter pub get
flutter_rust_bridge_codegen generate
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

cd ../..
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings

# Android ARM64 app + native adapter (requires pinned Flutter/Rust/NDK toolchains
# and the pinned llama.cpp checkout; builds debug by default)
scripts/build_android_app.sh

# Build and verify both debug and release-mode ARM64 test APKs (not production-signed)
LEO_ANDROID_BUILD_MODE=both scripts/build_android_app.sh

# Windows x64 native adapter (PowerShell, MSVC Build Tools + pinned llama.cpp checkout)
./scripts/build_windows_native.ps1
```

Flutter/Rust SDK availability and platform-specific build prerequisites are recorded in `docs/audit/TOOLCHAIN_MATRIX.md`.


## v0.22.0 workspace editing boundary

- A model may propose one file name directly under a folder the user selects through the native Android/Windows folder picker.
- The proposal is limited to UTF-8 text, 16 KiB, 10,000 Unicode code points and a 160-byte filename; existing files are limited to a 64 KiB preview.
- Leo displays the selected folder, filename and bounded before/after diff. No write occurs until the user separately approves that specific operation.
- Android uses a short-lived SAF tree URI and requires the provider to support staging/rename. Its API cannot provide an atomic compare-and-swap against an external writer; Leo rechecks the file before promotion and restores the backup where possible.
- Windows uses a canonical selected directory, rejects reparse points, stages on the same volume, and uses `ReplaceFileW`/`MoveFileExW` with post-write SHA-256 verification and rollback.
- This is not unrestricted filesystem access. Nested directories, delete, move, rename, shell, process execution and background writes remain disabled. Native builds and real-device checks are still required.

## v0.23.0 OS capability expansion boundary

- `files.open_selected`: the user selects one document for every handoff. Android checks the session-selected content URI, safe extension and provider MIME compatibility; Windows checks the picker-issued path, file attributes and an extension allowlist before opening the registered viewer.
- `calendar.create_event`: Leo validates the event and opens a system calendar draft. Android uses `Intent.ACTION_INSERT` with `CalendarContract.Events.CONTENT_URI`; Windows produces a bounded temporary ICS file and opens its registered handler. The user must save the draft in the calendar app.
- `clipboard.copy_text`: Leo previews the exact proposed text, obtains per-copy approval and writes only the new clipboard text. It never reads the previous clipboard value.
- Each action has its own capability scope and is dispatched through the existing Capability Hub. No direct calendar database writes, invitations, clipboard reads, executable launches, shell access or background actions are enabled by this milestone.

The Android calendar insert handoff follows the documented platform intent contract and millisecond epoch extras; the Windows document/calendar handoffs use registered file associations. Native build and device validation remain required before treating these integrations as qualified.



## v0.24.0 executable declarative skills boundary

- Only an active, structurally validated skill version can be started. Leo shows a dry-run with ordered steps, examples and declared capabilities (which are metadata, not permission grants), then asks the user before starting the skill-guided agent task.
- Skill steps, additional instructions and acceptance examples are added as untrusted context for the existing local specialist-agent DAG. This is not arbitrary script execution, does not create new native permissions and does not bypass role-scoped tools or the Capability Hub.
- The secure skill-run ledger retains task/skill identity, version, procedural steps, lifecycle, approval count and post-run user review. It intentionally does not duplicate the raw user goal or store tool arguments, file paths or file contents.
- The ledger allows 20 records, 512 KiB total and 30-day retention. Only terminal records (`verified`, `failed`, `cancelled`) may be evicted; if all slots are occupied by active or review-pending runs, a new run is refused rather than dropping recoverable work.
- Every step must be reviewed. `verified` means the user confirmed all steps; the acceptance examples are shown as references and are not automatically executed as an independent test suite. A missed step results in `needsChanges`.
- Only a matching active skill version can be restored. A completed/review-pending run is never revived from a stale task checkpoint. An interrupted external handoff still requires manual user review and is never replayed automatically.
- There is no automatic rollback after a successful external action or successful workspace write. The existing workspace adapter's rollback is limited to failed staged commits and verification failure.

The feature is source-implemented. Flutter/Dart tests, Rust/FRB tests, native Android/Windows builds and physical restart/action-review tests remain required before the feature can be called platform-qualified.


## v0.26.0 memory privacy boundary

- Chat-to-memory is explicitly user-triggered from one selected user-authored message. The editor opens first; saving creates a pending proposal. Leo does not ingest all messages or assistant responses in the background.
- Duplicate and possible-contradiction detection uses deterministic token similarity and a small negation/polarity lexicon. It is not semantic reasoning and never applies a change automatically.
- AES-256-GCM encrypts memory content, normalized search text, tags and source references. Associated data binds each field to the record ID. HKDF derives a distinct HMAC key for the keyed duplicate fingerprint.
- Record metadata remains plaintext in SQLite: IDs, memory type, timestamps, approval/activation state, schema/encryption version and opaque keyed fingerprint. The UI warns users about this boundary.
- Portable backup is passphrase-encrypted and bounded to 1,000 records/5 MiB. It omits source references and trust state. Every imported record is a pending, inactive proposal requiring review.
- Local secure-storage behavior, migration, rotation, erase and backup round-trips still require Flutter/Rust tests and physical Android/Windows qualification.


## v0.27.0 runtime and conversation resilience boundary

- The chat path reads the currently loaded native context size, reserves an output allowance and runs a best-effort whole-turn compaction pass. All system instructions and the latest complete user/tool cycle remain pinned. If the current request or mandatory policy cannot fit, Leo explains the limit instead of silently discarding it. The lightweight planner is an estimate; llama.cpp tokenization is the final authority and may trim further complete old interactions.
- The same refreshed context/output budget is used by chat generation, multi-agent task starts, successful tool continuation and restored checkpoints. Skill instructions are inserted before the final Capability Hub system policy so skill text cannot outrank the action boundary.
- An opt-in local performance card stores only attempt latency, output character count, process RSS/peak, platform and success state. It does not store prompt/answer content, model names, paths, conversation IDs or request IDs. Collection defaults to off and is bounded to 80 records/48 KiB. Output throughput is characters/second over successful requests only; memory is whole-process RSS.
- Model lifecycle operations are disabled while generation is active in the UI and rejected by the native nonblocking session lock if a stale UI snapshot races the operation. Native generation reserves an additional 96 MiB of available memory before prompt evaluation and can be stopped during its preflight.
- Cancellation arriving after Rust request registration but before the native start callback is retained and forwarded as soon as the C++ generation lifecycle is active. This avoids losing a very early Stop tap. It is source-level logic until Rust/Flutter tests and device interruption tests pass.


## Android qualification gate (v0.28.0)

The Android CI job builds both ARM64 debug and release-mode test APKs using the generated runner's default test signing configuration (not a production key). Before packaging, Leo checks compile SDK 36, minSdk 28, the stable application ID, the shared pinned NDK and secure-storage backup exclusions; the native build verifies the NDK and llama.cpp revisions. Each APK is checked for ZIP integrity, the Leo native adapter, ARM64 ELF libraries and absence of bundled GGUF/voice model weights. These source/CI checks do not qualify a physical device. The mandatory two-device test matrix and evidence requirements are in `docs/testing/ANDROID_QUALIFICATION_PROTOCOL.md`; do not call Android qualified until those tests and the full platform CI gates pass.
