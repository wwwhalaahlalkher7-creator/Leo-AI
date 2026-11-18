# Leo Alpha v0.22.0 work log — Safe workspace editing

## Delivered in source

- Added `workspace.write_file` as an exact, role-scoped proposal available only to `file_operator`.
- Added shared Dart and independent Rust/native validation for direct-child filename syntax, traversal, reserved Windows names, UTF-8 byte bounds, codepoint limits and control characters.
- Added a user-selected Android SAF workspace and a Windows native folder picker. The selected root is represented by a short-lived process-local token; no broad storage permission or persistent SAF grant is requested.
- Added bounded current-file preview, SHA-256 expectation checks, a bounded before/after diff and separate approval for each actual write.
- Added staged native write, post-write digest verification and backup/rollback handling. Same-content proposals are treated as a no-op.
- Added a metadata-only audit result and propagated actionable native cleanup warnings without exposing file contents or arguments in the audit log.
- Added compatibility for checkpointed and resumed agent tasks while ensuring the write itself still passes through Capability Hub approval.
- Added Dart/Rust unit-test source and Python source-contract coverage.

## Boundaries

One UTF-8 text file per action, directly under the chosen folder. Filename max 160 UTF-8 bytes; file content max 16 KiB and 10,000 Unicode code points; existing-file preview max 64 KiB. No nested paths, directory creation, deletion, move, rename, bulk write, shell or arbitrary process execution.

Android SAF providers vary. A provider that cannot enumerate or stage/rename safely is rejected. SAF lacks compare-and-swap rename; an independent writer can race after the final digest recheck. Windows rejects reparse points and verifies the final SHA-256, but a narrow independent-writer race remains there as well. Backup cleanup warnings are surfaced after a successfully verified write so the user is not encouraged to repeat a committed operation.

## Version

- `config/VERSION`: `v0.22.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Platform build code remains `4`; no new installable APK/EXE was built in this authoring environment.

## Validation run in this workspace

- Python source/architecture contract suite: 137 tests passed (`python -m unittest discover -s scripts/tests -q`).
- Version bump policy passed (`v0.21.0` → `v0.22.0`, minor feature bump); version synchronization and both immutable source archive SHA-256 checks passed.
- Configuration parsers passed: 10 JSON, 8 TOML, 5 YAML and 4 structurally consistent CSV files.
- Source contracts cover role scope, argument schema, path/content limits, preview/approval ordering, Android SAF session access, Windows folder/reparse-point policy, staged write/verification/rollback, metadata-only audit and continuation/checkpoint compatibility.

## Not run / pending

Flutter, Dart, Rust/Cargo, FRB generation, Android Gradle/SDK and Windows MSVC/SDK are not available in this authoring environment. Consequently Dart and Rust unit tests, Dart format/analyze, Rust fmt/test/clippy, Kotlin Android plugin compilation, Windows C++ compilation, APK/EXE builds and physical-device filesystem tests were not run. `kotlinc` being present alone is not an Android build environment. This is source-implemented Alpha, not a verified installable build.
