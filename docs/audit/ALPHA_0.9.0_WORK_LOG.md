# Leo Alpha v0.9.0 — Portable declarative skill interchange

## Implemented in source

- Added `SkillMarkdownCodec` for export/import of a bounded declarative Agent Skills-style `SKILL.md` subset.
- Export includes `name` and `description` frontmatter plus Leo-specific workflow sections.
- Import accepts standard single-file Markdown with simple YAML scalars and simple folded/literal description blocks. Common section aliases are recognized.
- Imported skills are always new `proposed` records with no validation, activation, permission grant or history inherited from source.
- Enforced a 64 KiB document limit, trigger/step/example/capability count limits and field size checks.
- Added native file-picker import/export actions in the skill library UI.
- Changed GGUF and skill selection to the file_picker v12 `pickFile()` API, correcting the previous `FilePickerResult`-style access that was removed in v12.
- Added Dart codec tests for export, round-trip, generic external skill fallback, invalid frontmatter and size-limit rejection.
- Added ADR-0013 and updated the skill policy/architecture.

## Safety limitations

- Only a single Markdown file is imported/exported. Scripts, assets and reference folders are not imported.
- Preflight remains structural/heuristic and does not execute acceptance scenarios.
- Automatic skill extraction from executed task traces remains deferred until the execution engine records actual workflows.
- Skills are declarative guidance only and cannot grant capabilities or approve actions.

## Validation performed

- Cumulative validation in the v0.10.0 workspace confirmed version synchronization, source-archive integrity and the Python architecture/config regression suite. These results validate the current combined source tree; they are not a claim that the isolated v0.9.0 snapshot was separately built.
- Dart/Flutter and Rust toolchain verification is unavailable in this environment; `dart format`, `flutter analyze`, `flutter test`, `cargo fmt`, `cargo test`, Android APK and Windows builds must be completed in the configured CI or a machine with the required SDKs.
