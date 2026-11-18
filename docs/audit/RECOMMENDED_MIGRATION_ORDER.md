# Recommended component migration order

This is the initial order for the 0.x Alpha roadmap. It is based on the paths and subsystem boundaries found in the supplied archives. A component must still pass import/dependency tracing before it is copied.

## 0.1.0 — baseline already recorded

- Freeze the two source archives and record their hashes.
- Map all source files and dependencies.
- Establish common domain contracts and version policy.

## 0.2.0 — J.A.R.V.I.S presentation layer

1. Review and isolate `lib/chat/content/` first: `compact_markdown.dart`, `math_view.dart`, `code_block.dart`, `code_highlighter.dart`, `resizable_markdown_table.dart`, `mermaid_view.dart`, streaming text helpers, and media renderers.
2. Review chat presentation widgets under `lib/chat/transcript/`, `lib/chat/timeline/`, and `lib/chat/widgets/`.
3. Trace the dependencies of `lib/core/chat_message.dart`, `lib/core/chat_message_codec.dart`, `lib/core/stores/chat_store.dart`, and `lib/screens/chat_screen.dart` before adapting them. Replace Hermes event/tool payload assumptions with Leo domain contracts.
4. Extract an app shell from `lib/screens/app_shell.dart` and `lib/main.dart`; keep the current Leo Flutter shell as the clean landing point until the migrated widgets work.
5. Use a `MockRuntime` in tests so the chat UI can stream, cancel and show failures without any Hermes service or internet connection.

Do not migrate `server/` wholesale. Do not retain a direct `ApiClient` dependency in chat widgets.

## 0.3.0 — NEXUS Android local runtime

1. Adapt `core/runtime/src/gguf.rs` and its model inspection tests.
2. Review `native/llama/src/llama_probe.cpp` against the pinned upstream llama.cpp ABI and retain the source pin from NEXUS documentation.
3. Adapt `core/runtime/src/native/engine.rs` behind `AssistantRuntime`; no NEXUS `nexus_*` symbols should leak into the Leo domain contract.
4. Adapt `core/bridge/src/api/simple.rs` and regenerate Flutter Rust Bridge bindings after Leo contract changes.
5. Bring over model import/verification and fit estimation from `lib/src/features/models/` only after app-local file permissions and resource limits are designed.
6. Validate load/generate/stream/cancel/unload/reload on a physical Android ARM64 device while offline.

## 0.4.0 — Windows local runtime

- Create a Windows llama.cpp backend using the same runtime contract and compatible GGUF handling.
- Detect CPU/GPU backend availability on Windows; do not claim GPU acceleration unless a real backend is compiled and tested.
- Use the Windows Flutter runner from J.A.R.V.I.S as a host shell candidate, not as a substitute for the inference adapter.
- Verify offline inference on a real Windows machine.

## 0.5.0 and later — orchestration, memory, skills, capabilities, voice

- Use NEXUS's plan validation and task persistence as references, but seed Leo's built-in agent roster and select agents automatically.
- Adapt NEXUS knowledge and SQLite work into typed, provenance-aware memory.
- Add a skill package format with tests, user promotion, versioning and rollback.
- Build Capability Hub connectors OS/app-first, with grant scopes separate from action confirmation.
- Add sherpa-onnx / whisper.cpp voice candidates only after Arabic/English latency and quality tests on both platforms.
