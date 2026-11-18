# Leo Alpha v0.21.0 work log — Durable task ledger and restart recovery

## Delivered in source

- Replaced process-local multi-agent continuation state with a bounded durable ledger backed by `flutter_secure_storage` 11.2.0 for the Android and Windows targets.
- Emit a `running` checkpoint before the first local model inference, then checkpoint only successfully completed DAG steps after every successful step.
- Persist task and conversation identity, goal, bounded prompt context, the validated plan, successful results, an optional pending action proposal and the completed-handoff count.
- Validate checkpoint identity, state, tool allowlist, exact proposal identity, size, retention, duplicate IDs and dependency closure. Rust revalidates the full plan against the built-in agent catalog before continuing.
- Added explicit `running`, `awaitingAction` and `readyToResume` store states. The successful action result is written to secure storage before Rust resumes the existing DAG.
- Added a chat recovery panel for restoring or discarding tasks. A task interrupted during reasoning resumes from successful steps; completed steps are not rerun.
- Added a manual recovery gate for the ambiguous crash window after an external proposal was saved but before its result was saved. The user must inspect the external surface and explicitly confirm or cancel. Leo labels the confirmation as user-reported, not independently verified.
- Preserve the most recent known-good checkpoint on lifecycle cancellation or checkpoint persistence failure. An explicit user Stop still removes the task checkpoint. Terminal completion clears stale lifecycle-preservation markers.
- Added Android runner preparation to disable backup and exclude SharedPreferences from cloud backup/device transfer so encrypted preferences are not restored without their Keystore key.
- Added the `flutter_secure_storage` BSD-3-Clause notice, dependency/toolchain documentation, ADR-0026, updated roadmap and current README status.
- Corrected the checkpoint writer's validation order during final review and added a regression contract that prevents referencing the record before it is constructed.

## Version

- `config/VERSION`: `v0.21.0`
- `config/RELEASE_CHANNEL`: `ALPHA`
- Flutter metadata: `0.21.0+4`
- Cargo workspace: `0.21.0`
- Platform build metadata remains `+4` because no installable APK/EXE was produced.

## Verification performed in this workspace

- Python source/architecture contract suite: **121/121 passed** (`python -m unittest discover -s scripts/tests -q`).
- Version synchronization and version-policy bump validation passed (`v0.20.0` → `v0.21.0`, minor bump).
- `python scripts/verify_sources.py` passed; the immutable J.A.R.V.I.R and NEXUS source archive SHA-256 values match the source baseline.
- JSON/TOML/YAML/CSV parsing passed for all current source/config files: 10 JSON, 8 TOML, 5 YAML/YML and 4 CSV files.
- `bash -n scripts/prepare_android_runner.sh` passed.
- The Android runner preparation logic was exercised in a temporary simulated Flutter runner. The generated manifest disabled backup and referenced both generated XML rule files; all three XML files parsed successfully.
- ZIP integrity and final SHA-256 are verified after packaging.

## Not verified here

Flutter, Dart, Cargo and Rust compiler are not installed in this authoring environment. Consequently, Flutter/Dart unit tests and analyzer, Cargo/Rust tests, formatting, clippy, FRB code generation, Android APK/Windows builds and real secure-storage restart tests were **not** run. No physical device was available to test Android Keystore persistence or Windows user-profile/DPAPI persistence. The added Dart/Rust tests must pass in CI before this milestone is considered platform-qualified.

## Safety boundary

- Checkpoints are encrypted local recovery data, not cloud sync, permission grants or authorization tokens.
- An external action pending at process death is never replayed automatically. User review is required to resolve the ambiguity.
- If a secure-storage write fails, Leo cancels and does not present or continue an external action. Any prior known-good checkpoint is retained when present; there is no plaintext fallback.
- The Python tests exercise source/architecture contracts; they do not execute Flutter, Rust or native platform code.
