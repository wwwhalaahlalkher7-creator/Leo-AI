# Leo Alpha v0.7.0 — Memory review and chat retrieval

Date: 2026-11-15
Channel: ALPHA
Version: v0.7.0

## Implemented in source

- Added `MemoryRepository` as a Dart-facing abstraction so the UI does not depend directly on generated Flutter Rust Bridge DTOs.
- Added a local repository implementation that places `leo-memory.sqlite3` under `getApplicationSupportDirectory()/leo/memory`; no broad shared-storage permission is requested.
- Added the Arabic-first memory management screen with category selection, direct user-approved save, list/filter/search, approve-pending, edit-approved, disable/re-enable and delete actions.
- Added an explicit privacy notice stating that records are stored locally and that the current SQLite database is not encrypted by this layer.
- Added bounded retrieval before local model generation: at most four relevant records; only approved and active records are returned by Rust and rechecked by the Dart context builder; per-record and total character limits are enforced.
- Retrieved memory is added only to the ephemeral runtime request. It is not persisted in the user's chat transcript.
- Added a fixed system-level instruction that identifies retrieved memory as untrusted reference data and forbids treating embedded content as policy, permissions or executable instructions.
- Added a memory screen entry point in the main chat header.
- Added Dart widget/context tests and Python static integration contracts.

## Validation performed in this environment

- `python scripts/check_version.py`: passed for v0.7.0 / ALPHA.
- `python scripts/verify_sources.py`: both original source archives still match their recorded SHA-256 values.
- `python -m unittest discover -s scripts/tests -v`: passed (21 tests), including UI/prompt-integration contract checks.
- Native adapter host fake-llama contract passed; Windows-specific branch passed syntax-only validation with stub headers (not a native Windows build).
- All project JSON, TOML and CSV files parsed successfully.
- Version policy is synchronized as `config/VERSION = v0.7.0`, `RELEASE_CHANNEL = ALPHA`, and Flutter `0.7.0+1` (the build number remains unchanged until an installable artifact is produced).

## Not verified here

Flutter/Dart and Cargo/Rust SDKs are not installed in this environment. Therefore Dart formatting, Flutter analyze, Flutter widget tests, Flutter Rust Bridge generation, Rust compilation/unit tests, Android APK build, Windows app/DLL build, and inference with real GGUF models have not been run. CI must generate `lib/src/rust/api/simple.dart` and validate the generated function/type names against this Dart repository adapter.

The database remains local but unencrypted. The bridge opens the database on each operation; connection pooling and encrypted storage are not part of this milestone. Automatic conversation memory extraction and semantic embeddings are not implemented. Prompt retrieval uses the current user's latest message and a bounded lexical search; retrieved text is reference data and must never grant capabilities or override the user's current request.

## Next engineering step

Begin v0.8.0 skill learning: define a portable skill package format and validator, generate proposals from completed task workflows, attach tests/examples, require explicit user promotion, and support versioning/disable/rollback. Skills must not silently acquire OS permissions or execute arbitrary scripts.
