# ADR-0026: Durable agent task checkpoints and restart recovery

**Status:** Accepted for Leo Alpha v0.21.0  
**Date:** 2026-11-17

## Context

Leo v0.20.0 could pause a validated multi-agent DAG at a tool proposal and resume it after a successful, user-approved tool handoff. Pending continuation state existed only in process memory and disappeared when the application restarted. Repeating the external action after a crash would be unsafe because the OS may already have accepted the handoff.

## Decision

Persist one bounded local checkpoint record per pending task using `flutter_secure_storage` on Android and Windows. A checkpoint contains the task/session identity, goal, bounded conversation context, validated plan, only successful step results, any pending action proposal, handoff count and a state marker.

The native bridge emits an initial plan checkpoint before the first local inference and updates the checkpoint after every successful step. Flutter serializes checkpoint event handling, writes the checkpoint before presenting any action approval, and writes a successful handoff result before asking Rust to resume the same DAG.

Recovery uses two strictly versioned internal envelopes:

- `leo_task_restore`: resumes only `running` checkpoints that contain no outstanding action proposal.
- `leo_task_resume`: resumes an `awaiting_action` checkpoint only when it includes a matching `success: true` result for the exact task, tool-call ID and tool name.

All checkpoint content is revalidated by Rust against the built-in agent catalog, plan constraints, step identity, successful status, output/attempt bounds, uniqueness and dependency closure before any remaining model step runs.

If the process stops after saving an action proposal but before saving its outcome, the task stays `awaitingAction`. Leo asks the user to inspect the external app/OS surface and either cancel the task or explicitly confirm the handoff. The confirmation is labelled as user-reported, not technically verified. The action is never replayed automatically.

The checkpoint store has maximums of 8 tasks, 256 KiB per checkpoint, 640 KiB total serialized records and 7-day retention. User Stop deletes the checkpoint; background lifecycle cancellation preserves the last checkpoint. There is no cloud synchronization.

On Android, the generated runner disables application backup and excludes SharedPreferences from both cloud backup and device transfer. This prevents encrypted preference payloads from being restored without their Android Keystore key. On Windows, the plugin's C++ ATL component is a build prerequisite.

## Consequences

### Positive

- Tasks can be recovered after a process restart without rerunning completed reasoning steps.
- A checkpoint is available even if the process exits during the first model inference.
- Successful action results are durably recorded before continuing the agent DAG.
- The ambiguous action/result crash window is explicit and requires manual user review; duplicate external actions are not attempted.
- Stored task contents remain local and use the platform secure-storage plugin rather than plaintext preferences/files.

### Trade-offs and limitations

- Checkpoint storage can fail if secure storage is unavailable, corrupted, full or loses its platform key; in that case the action approval path fails closed.
- Old checkpoints expire after seven days and at most eight are kept. They are not synced between devices or backed up.
- A user-confirmed interrupted handoff is not independently verified by Leo.
- Windows ATL availability, Android backup-rule behavior, secure-store recovery and real process restart must be verified in platform CI/device tests.
- Flutter/Dart/Rust/FRB and native builds were not available in the authoring environment; this is source implementation pending CI qualification.

## Rejected alternatives

- Persisting task state in plain JSON or SharedPreferences: rejected because prompts, model outputs and tool results may include private information.
- Automatically retrying an action after restart: rejected because the previous OS handoff may already have occurred.
- Re-running the whole plan after restart: rejected because it wastes resources and may repeat reasoning or produce different proposals.
- Persisting only the action result without the task plan: rejected because the remaining DAG and its dependencies would be lost.
