# Leo Alpha v0.5.0 — Automatic agent routing and task-plan preview

Date: 2026-11-15
Channel: ALPHA
Version: v0.5.0

## Implemented in source

- Added a dependency-free Arabic request normalizer that removes common diacritics/tatweel and normalizes alef, hamza forms, alif maqsura and taa marbuta before route matching.
- Expanded Arabic intent phrases for coding, research, file operations, device actions and communications.
- Localized agent-selection rationales in Arabic and kept selected agents allow-listed by the built-in catalogue.
- Added `AgentRouter::build_plan`, producing a validated task DAG with an optional planner stage, specialist steps that can be parallel-ready, and an optional final verifier stage.
- Copied specialist `required_capabilities` into each task step; planning does not grant permissions.
- Exposed typed bridge functions `route_agents` and `preview_task_plan` with DTOs suitable for Flutter Rust Bridge code generation.
- Added bridge-level tests for simple specialist selection, multi-agent plan preview and empty-goal rejection.
- Added architecture static checks for the plan builder and bridge surface.
- Bumped to `v0.5.0` / `ALPHA`; the feature addition increments MINOR and resets PATCH. Build number remains `1` because no installable artifact was created.

## Validation performed in this environment

- `python scripts/check_version.py`: passed; Flutter and Cargo version metadata synchronized.
- `python scripts/verify_sources.py`: passed; both original archives still match their stored SHA-256 values.
- `python -m unittest discover -s scripts/tests -v`: passed (16 tests).
- Host C++ fake-llama adapter contract: passed as part of the test suite.
- Project JSON configuration parsing: passed.

## Not verified here

This environment still lacks Cargo/Rust, Flutter/Dart, Android SDK/NDK, PowerShell and Windows MSVC. Therefore Rust compilation/unit tests, Flutter Rust Bridge generation, Flutter analyze/test, Android APK build, Windows DLL/application build and real model inference were not run. The CI jobs are configured but must run on GitHub before platform success can be claimed.

The deterministic router is a first-pass intent matcher. It is not yet a model-driven planner. The plan is a preview DAG only: separate agent model execution, task scheduling, parallel execution, cancellation, context handoff and final result aggregation remain future implementation work.

## Next engineering step

Implement the execution coordinator that consumes the validated plan, runs agent turns through the active local runtime, passes approved tool calls through the Capability Broker, bounds resource use, and aggregates/verifies results. Do not add direct tool access to agent code.
