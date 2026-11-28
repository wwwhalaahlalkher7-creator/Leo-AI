# Leo AI Engineering Production Pipeline

**Applies to:** Leo AI repository, Android and Windows targets  
**Baseline at integration:** `v0.27.0 / ALPHA`  
**Status:** Normative development workflow. This document supplements—not replaces—the product lifecycle, version policy, architecture ADRs, milestone roadmap, and platform qualification protocol.

## 1. Authority and precedence

Use this order when guidance overlaps:

1. Current milestone acceptance criteria and approved Architecture Decision Records (ADRs).
2. `docs/planning/LEO_AI_DEVELOPMENT_PLAN_v0.1.0.md` for product scope, lifecycle and version semantics.
3. `docs/planning/REMAINING_RELEASES_ROADMAP.md` for planned milestone order.
4. This pipeline for the repeatable engineering process.
5. `docs/testing/` and `docs/audit/` for qualification procedures and evidence.

Do not silently change an existing product decision to fit a generic workflow. Record a proposed architectural change as an ADR or milestone decision first.

## 2. Non-negotiable engineering rules

- Keep Alpha as construction, Beta as testing/feature freeze, and Release as final branding, signing and publication.
- Deliver one coherent milestone at a time. Do not start dependent work until its predecessor has passed its exit gate.
- Prefer small, reviewable vertical slices over broad unrelated refactors.
- Preserve the established Flutter/Rust/native boundaries and route platform actions through the existing capability and permission layers.
- Treat generated FRB bindings as generated outputs; change Rust API/configuration and regenerate rather than hand-editing generated files.
- Keep the local assistant's core workflow offline-first; cloud services are not mandatory dependencies.
- Review every new dependency for compatibility, maintenance, license, security, binary/package-size impact and whether an existing dependency already solves the need.
- Never claim a test, build, device check or security property that was not actually executed and observed.
- Do not produce release ZIPs or duplicate archives after every small change. Create a delivery archive only at a requested or meaningful milestone boundary.
- Keep secrets, signing keys and personal data out of source, logs, test fixtures and artifacts.

## 3. Standard production pipeline

### Gate 0 — Baseline and scope

Before editing:
- Identify the current version, release channel, branch/commit and working-tree state.
- Read the relevant milestone, ADRs, architecture boundaries and previous work/validation logs.
- Reproduce the reported issue or establish the current behavior.
- Record affected modules, platform targets, data migrations, generated code and compatibility risks.
- Define explicit acceptance criteria and tests.

**Exit:** a scoped change plan exists; unrelated work is excluded.

### Gate 1 — Architecture and contracts

- Draw or describe the data/control flow across Flutter, Dart services, Rust crates, FRB, C/C++ adapters, platform plugins and persistence as applicable.
- Define ownership of each responsibility and the public contract between layers.
- Check whether an existing service/adapter already provides the capability.
- For schema, storage, bridge or protocol changes, define compatibility and migration/rollback behavior.
- Add or update an ADR when a lasting architecture decision changes.

**Exit:** interfaces, ownership and failure behavior are unambiguous.

### Gate 2 — Implementation (vertical slice)

Implement the smallest complete path from user action to persisted/runtime result and back:
1. Domain types and validation.
2. Repository/storage or external boundary.
3. Service/use-case logic.
4. Runtime/native/platform integration, if required.
5. UI and loading/error/empty states.
6. Tests and documentation.

Keep UI widgets free of domain orchestration. Keep native/FFI calls behind their existing adapters. Fail closed on permission, integrity, validation or platform errors.

**Exit:** feature works end-to-end at source level and has focused regression coverage.

### Gate 3 — Local verification

Run relevant checks from repository root:

```bash
python scripts/check_version.py
python scripts/verify_sources.py
python -m unittest discover -s scripts/tests -v
python scripts/check_dependency_lockfiles.py  # required before platform qualification
bash scripts/generate_bridge.sh
```

When toolchains are available, also run:

```bash
cd apps/leo_app
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test --reporter compact
cd ../..
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Run target-specific native builds using the repository scripts and pinned toolchains:
- Android: `bash scripts/build_android_app.sh`
- Windows native: `./scripts/build_windows_native.ps1`
- Windows runner/app: `./scripts/prepare_windows_runner.ps1`, then `flutter build windows`

Do not mark unavailable toolchain checks as passed. Record them as pending with the reason.

**Exit:** all applicable local checks pass; failures are fixed or explicitly documented as blockers.

### Gate 4 — CI integration

The current `.github/workflows/ci.yml` is the executable CI source of truth. Its jobs are:
- `foundation`: version/source integrity and Python architecture/contract tests.
- `full-stack`: pinned Flutter/Rust toolchains, FRB generation, Dart format/analyze/tests, Rust format/tests/target checks/Clippy, and generated-binding artifact.
- `android-app`: waits for `full-stack`, requires committed Flutter/Rust lockfiles, then uses pinned Java/SDK/NDK/CMake, the llama.cpp checkout and Android ARM64 debug/release qualification APK builds. The former one-time bootstrap workflow has been retired. Both Flutter and Cargo lockfiles are now committed and are checked by the qualification jobs before locked dependency resolution.
- `windows-app`: generated bridge consumption, Windows runner preparation, native DLL build and Windows debug app build.

A change is not CI-qualified until the relevant workflow run completes successfully. If workflow behavior changes, update this document and the workflow together. Keep permissions least-privilege and pin third-party source revisions/tool versions where the repository already requires pinning.

**Exit:** required CI jobs pass and their artifact/log evidence is available.

### Gate 5 — Platform and regression qualification

CI build success is not proof of runtime correctness. Follow `docs/testing/ANDROID_QUALIFICATION_PROTOCOL.md` and the current milestone's platform matrix.

At minimum, validate relevant paths on real supported devices/hosts:
- clean install, upgrade and restart;
- local model import, integrity check, load, inference, unload and cancellation;
- offline behavior and recovery after network restoration;
- storage limits, permission grants/revocation and OS handoffs;
- voice capture/playback and model-pack integrity;
- memory encryption, migration, backup/restore, key rotation and erase;
- task/skill checkpoint recovery and prevention of duplicate external actions;
- memory/CPU pressure, long conversations and error recovery.

Record device/OS/build details, exact steps, expected/actual results and evidence. Do not infer a physical-device result from emulator or CI output.

**Exit:** milestone-specific device/host acceptance criteria pass or the milestone remains explicitly unqualified.

### Gate 6 — Milestone closeout

Update:
- milestone work log and validation report under `docs/audit/`;
- roadmap status and remaining work;
- dependency/migration/license registers when affected;
- tests and ADRs;
- changelog and version only under the existing version policy.

Summarize delivered, tested, not tested, known limitations and follow-up items. Close the milestone only when its acceptance checklist is complete.

### Gate 7 — Beta and Release

- **Alpha:** build and integrate the agreed application scope; engineering builds are not represented as finished consumer releases.
- **Beta:** freeze features by default; run regression, device/OS matrix, security, privacy, accessibility, offline, performance and upgrade qualification. Fixes follow the existing patch/minor version rules.
- **Release:** lock final brand/icon assets, create final packages, sign with production credentials, verify signatures and SHA-256 checksums, then run clean-install/upgrade/smoke checks and publish release notes.

The authoritative numeric version rules remain in `docs/planning/LEO_AI_DEVELOPMENT_PLAN_v0.1.0.md` and `config/version_policy.json`.

## 4. Change sizing and delivery

- One milestone may contain multiple related vertical slices, but each slice must have its own acceptance criteria.
- Split unrelated changes into separate commits/PRs where practical.
- Do not mix formatting-only churn with functional changes unless required by the touched files.
- Preserve user data and backward compatibility; destructive migrations require explicit tests and documented recovery behavior.
- Produce a ZIP only when requested or when a milestone/release handoff needs a portable artifact.

## 5. Definition of Done

A change is done only when:
- acceptance criteria are met;
- architecture boundaries and security/privacy constraints are preserved;
- focused regression tests exist and pass;
- relevant full test suites and CI jobs pass, or unrun checks are clearly listed;
- generated outputs are reproducible;
- docs, work log and roadmap are accurate;
- no known release-blocking issue is hidden by a successful source-level test.

A milestone is **source-implemented** when code and source tests are present; **CI-qualified** when required CI jobs pass; and **platform-qualified** only after required real-device/host tests pass. These labels must not be conflated.
