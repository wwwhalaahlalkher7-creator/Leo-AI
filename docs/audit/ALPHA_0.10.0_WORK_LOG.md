# Leo Alpha v0.10.0 — Work Log

## Delivered in source

- Added the chat menu action **تعلم مهارة من هذه المحادثة**.
- Added `SkillLearningService`, which sends the selected conversation to the local `AssistantRuntimeClient` using a Skill Curator prompt.
- Bounds extraction to the latest 20 user/assistant messages and 9,000 transcript characters; model output is bounded to 24,000 characters and generation to 1,000 tokens.
- Requires both user and assistant messages and rejects a model response that declines skill creation or fails strict field/length validation.
- Persists the result through `SkillRepository.createProposal`; the proposal starts inactive and has no validation report. No tools, commands, applications or external actions are executed during extraction.
- Preserves capability IDs as descriptive metadata only; the skill cannot grant permissions.
- Cancels the in-flight extraction request when the chat page is disposed.
- Added Dart unit tests for successful extraction, insufficient evidence, unsafe capability IDs, and a conversation without both roles. Added Python architecture/config regression assertions.
- Updated skill policy, architecture document, roadmap, changelog and version metadata to `v0.10.0`.

## Important scope boundary

This milestone is **explicitly user-triggered skill drafting from conversation text**. It is not autonomous learning from completed actions. Leo does not yet have the end-to-end task executor and durable execution trace store needed to know which operations actually ran successfully. The extractor therefore must not claim that discussed work was executed. All generated skills remain proposals until a user reviews, preflights and activates them.

## Validation performed in this environment

- `python scripts/sync_version.py` — passed; synchronized Flutter/Rust metadata to `0.10.0+1`.
- `python scripts/check_version.py` — passed for `v0.10.0 / ALPHA`.
- `python scripts/verify_sources.py` — passed; both supplied source archives match their recorded SHA-256 values.
- `python -m unittest discover -s scripts/tests -v` — passed: 27 Python tests.
- Dart unit tests were added but not executed because Flutter/Dart SDKs are unavailable in this environment.
- `cargo test`, `cargo fmt`, Flutter Analyze, Dart format, Flutter tests, FRB code generation, Android APK build and Windows build were not run because the respective toolchains are unavailable.

No Android APK or Windows installer/binary is claimed as built or verified.
