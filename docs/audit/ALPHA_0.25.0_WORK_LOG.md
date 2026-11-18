# Leo Alpha v0.25.0 work log — Verified workflow-derived skill learning

## Delivered in source

- Added `SkillRunEvidenceReader` as a read-only curation port and made `SkillRunRepository` implement it.
- Added `SkillLearningService.proposeFromVerifiedRun`, which requires a `verified` run, at least two steps, all steps user-confirmed, and an exact match against the retained source skill ID/version and ordered steps.
- Added an opt-in action in the skill library for verified runs. The confirmation dialog describes the local-model input and its pattern-based redaction limitation.
- Added a minimized JSON evidence envelope. It excludes the original chat, user goal, review notes, arbitrary event text, tool arguments/results, file paths/names and file contents.
- Added redaction for common credentials/tokens, email addresses, URLs, Windows and Unix paths, common file names, phone-like strings, long numeric IDs, IPv4 addresses and MAC addresses. Redaction is applied to input and generated proposal text.
- Bound derived proposal capabilities to a subset of the source skill's declared capability IDs.
- Added provenance `verified-run:<task-id>`, service-level duplicate checks and a serialized repository-level uniqueness guard.
- Kept the proposal inactive and retained the prior conversation-based extractor as a separate explicitly user-triggered flow.
- Added Dart tests to the skill learning and skill repository suites and Python contract tests for the new security and integration boundaries.

## Version

- `config/VERSION`: `v0.25.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- `config/BUILD_NUMBER`: `4` (unchanged; no installable artifact was created)
- Flutter pubspec and Cargo workspace metadata synchronized to `0.25.0+4` and `0.25.0` respectively.

## Validation performed in this workspace

- Python contract suite: **164 tests passed** (`python -m unittest discover -s scripts/tests -q`).
- Version synchronization and bump policy check: passed (`v0.24.0` → `v0.25.0`, minor feature bump).
- Original J.A.R.V.I.S and NEXUS archive hashes: verified using the existing source verification script.
- JSON/TOML/YAML/CSV source/config parsing: run using the existing architecture/config contract checks and packaging validation.
- ZIP integrity and SHA-256: performed on the final archive after packaging.

## Not run / qualification boundary

Flutter, Dart, Rust/Cargo, Android Gradle/NDK and Windows MSVC toolchains are not installed in this authoring environment. Therefore the newly authored Dart tests were not executed; no `dart format`, `flutter analyze`, `flutter test`, `cargo fmt/test/clippy`, FRB generation, APK or EXE build, real secure-storage test or real local-model workflow-learning smoke test was run. This milestone is source-implemented Alpha, not a verified installable build.

## Known limitation

The workflow learner operates on previously user-verified skill runs, not arbitrary successful agent tasks without a skill execution record. Pattern-based redaction is best-effort and cannot guarantee removal of every personal identifier or confidential phrase. The UI asks for explicit consent and the generated skill remains inactive for inspection.
