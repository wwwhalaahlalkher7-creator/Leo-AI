# ADR-0023: Reliable multi-agent execution coordinator

**Status:** Accepted for Leo Alpha v0.18.0  
**Date:** 2026-11-17

## Context

Leo already contained a built-in agent catalog, deterministic routing and a validated task-plan DAG. Chat still sent every request through one ordinary generation call, so multi-agent plans were previews rather than executable workflows. A correct first executor must work with the single active local GGUF generation supported by the native runtime, remain cancellable from Flutter, and avoid granting agents direct device or OS authority.

## Decision

1. Add a platform-neutral `TaskCoordinator` in `core/orchestration` and validate every plan immediately before execution.
2. Execute ready DAG steps sequentially in stable plan order. Independent steps are not parallelized while the current local engine is single-generation and memory constrained.
3. Pass only bounded conversation context and successful dependency outputs to each specialist. Treat these values as untrusted reference data.
4. Allow one retry by default, with a hard ceiling of three attempts. Keep retryable and permanent failures distinct.
5. Preserve explicit step states: succeeded, failed, skipped and cancelled; task states: completed, partially completed, failed and cancelled.
6. Stream step progress to Flutter and allow cancellation of the active task and its current native generation request.
7. Run each specialist as inference-only. Agents may draft code, text or action plans, but may not run shell commands, modify files, open apps, send communications or perform network operations.
8. Keep all real-world actions behind the existing Flutter Capability Hub, OS permission checks and per-action approval flow. Action-focused communications/device/file requests retain the ordinary chat tool path.
9. Do not persist agent prompts, conversation context, tool arguments or step outputs as a new audit log in this milestone.

## Consequences

### Positive

- Multi-agent plans now execute on the already loaded offline model and produce one verifier-led final result.
- A failed specialist no longer silently feeds missing content to its dependents; dependent steps are marked skipped while independent branches may finish.
- A retryable failure can recover without restarting the entire task.
- Flutter can show progress and cancel the matching task without cancelling an unrelated generation.
- Agent identities remain a selection policy, not a permission system.

### Trade-offs and limitations

- Execution is sequential, not parallel. This is deliberate until a runtime can safely support multiple active contexts and the device resource manager can reserve memory for them.
- The coordinator is source-implemented but Rust tests and FRB bindings need CI generation/validation. Native Android/Windows behavior has not been exercised in this authoring environment.
- This milestone does not let agent steps invoke existing tools or persist resumable task state. Actual tool handoffs remain in the ordinary chat's Capability Hub path.
- Retry currently targets transient runtime-busy failures; it does not retry permanent inference/model errors.

## Rejected alternatives

- Parallel specialist generations on the current singleton native runtime: rejected because they would race for one active generation and increase memory pressure.
- Giving agents raw native APIs or shell access: rejected because it bypasses capability checks and one-action approvals.
- Treating a catalogue entry's required capability list as a grant: rejected because agent roles never imply OS permissions.
