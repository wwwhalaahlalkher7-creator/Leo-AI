# Leo Alpha v0.23.0 work log — OS capability expansion

## Delivered in source

- Added `files.open_selected`, requiring a session-selected file through the native picker. Android validates the content URI, extension allowlist, blocked active MIME types and extension/MIME compatibility before an `ACTION_VIEW` handoff. Windows validates the picker-issued path, rejects directories/reparse points and non-allowlisted extensions, then opens the registered document handler.
- Added `calendar.create_event` with strict ISO-8601 timezone-bearing input, title/location control-character checks, bounded event duration and text lengths. Android opens the system calendar editor with `ACTION_INSERT`; Windows creates a bounded temporary ICS draft and opens the registered `.ics` handler. The user saves the event in the target app.
- Added `clipboard.copy_text` as a write-only OS capability. The proposed text is previewed and approved for each copy; Leo does not read the prior clipboard. Windows now reports the partial-failure case where `EmptyClipboard` succeeded but installing the new Unicode text failed.
- Added all three capabilities to the Rust catalogue and JSON policy, updated role-scoped tool protocol, Dart gateway and Capability Hub routes, and added the correct capability metadata to the built-in file/device specialists.
- Kept `files.open_selected` with `file_operator`; calendar and clipboard stay with `device_operator`. The router no longer routes ordinary file-open requests to both file and device specialists.
- Tightened Android MIME compatibility so a known provider MIME mismatch fails closed; if the provider returns no MIME or generic octet-stream, Leo uses a safe MIME mapped from the allowlisted extension.
- Added stricter timezone-shape validation at the Rust proposal boundary and a second Dart date parser/offset check before native dispatch; Rust offset parsing avoids arithmetic until digits have been validated.
- Updated README chronology, development plan, capability policy and forward roadmap to identify v0.23.0 as delivered and v0.24.0–v0.30.0 as remaining Alpha milestones.

## Version

- `config/VERSION`: `v0.23.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Build metadata remains `+4`; no new installable APK/EXE was built in this environment.

## Validation performed

- Python architecture/source contract suite: **145/145 passed** (`python -m unittest discover -s scripts/tests -q`).
- Version synchronization and minor-bump policy check from `v0.22.0` to `v0.23.0`: passed.
- Original J.A.R.V.I.R and NEXUS archive hash verification: passed.
- JSON/TOML/YAML/CSV source/config parsing and CSV row-shape validation: see the validation report.
- Source-level contract checks cover OS capability catalog/policy, role routing, MIME allowlist/mismatch protection, calendar draft-only semantics, write-only clipboard and action-approval boundaries.

## Not verified in this authoring environment

Flutter, Dart, Cargo/Rust, Android SDK/NDK/Gradle and Windows MSVC build tools are not installed. Therefore `flutter analyze`, `flutter test`, `dart format`, `cargo fmt/test/clippy`, FRB code generation, Android Gradle/Kotlin compilation, Windows native compilation, APK/EXE builds and real-device OS handoff tests were not run. The Python tests verify source contracts; they do not compile the Dart, Rust, Kotlin or C++ implementations. This is source-implemented Alpha, not a verified installable build.
