# Workflow-derived skill learning — test protocol

## Entry conditions

A learning proposal may be requested only from a run that:

1. Exists in the encrypted skill-run repository.
2. Has `status == verified`.
3. Contains at least two steps and every step is `confirmed`.
4. Matches a currently retained source skill by exact skill ID and version.
5. Matches the source skill's original ordered step list exactly.
6. Uses a source skill with a passing validation report and `active` or `disabled` status.

No model request should be issued when any condition fails.

## Data sent to the local model

Allowed evidence fields: sanitized skill name, sanitized description, source version, sanitized confirmed step instructions, step count, aggregate approved-action count and source capability IDs.

Excluded fields: chat transcript, task goal, review notes, free-form `lastEvent`, tool arguments, tool results, file names, paths, file contents, clipboard content, contact details and any OS handoff payload.

Pattern-based redaction checks common e-mails, URLs, Windows and Unix paths, common document file extensions, phone-like strings, long numeric identifiers, IPv4/MAC addresses and common bearer/API/provider tokens. This cannot guarantee removal of arbitrary names or all confidential phrases; the UI must disclose that limitation.

## Proposal acceptance

- A model response must satisfy the strict proposal schema and the existing bounds.
- Every generated capability must be a member of the original skill's capability list.
- The result must remain `proposed`, have no validation report and carry `sourceTaskId = verified-run:<task-id>`.
- A second attempt from the same run must be rejected before another model call; repository-level serialized creation must also reject duplicates.
- No tool call or permission change may occur during learning.

## Device/CI checks still required

- Flutter format/analyze/tests and Dart test execution.
- Android and Windows secure-storage integration tests.
- Real local-model generation with Arabic and English examples.
- Redaction fixtures containing real-looking identifiers, paths, file names and common token formats.
- Confirmation cancel/approve, failed model generation, malformed output, capability expansion and duplicate-source scenarios.
- Inspection of the model request payload to ensure only the evidence allowlist reaches the local runtime.
