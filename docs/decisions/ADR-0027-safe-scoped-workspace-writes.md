# ADR-0027: Safe, scoped workspace writes

**Status:** Accepted for Leo Alpha v0.22.0  
**Date:** 2026-11-17

## Context

Leo can read a file selected by the user and can propose typed device/app handoffs through the Capability Hub. Its agent workflow did not yet have a narrowly scoped way to create or update a useful text artifact. Giving a model a raw filesystem path, arbitrary write API, shell command or process executor would bypass the selected-resource boundary and materially expand the attack surface.

## Decision

Add one role-scoped tool, `workspace.write_file`, available only to the built-in `file_operator` specialist. The model supplies an exact relative filename and UTF-8 content; it never supplies an absolute path, URI, native method name or root directory.

The operation is constrained as follows:

- The user selects one workspace folder through the platform's native picker at the time of the operation.
- Each action creates or replaces exactly one direct child file. Nested paths and directory creation are not supported.
- The filename is at most 160 UTF-8 bytes. Content is at most 16 KiB and 10,000 Unicode code points. Traversal, path separators, reserved Windows device names, control characters and NUL are rejected.
- Leo obtains a preview of the current file and proposed content, validates expected-current and proposed SHA-256 digests, and displays a bounded diff.
- Every actual write requires an individual user approval after the preview. A no-op where the existing bytes already equal the proposal causes no write.
- Native code independently validates the arguments, stages the new content, verifies the final bytes and attempts rollback/backup recovery when replacement fails.
- The task gateway returns a bounded result. Its audit trail remains metadata-only and does not persist paths, filenames, file content, diff, prompts or model arguments.

## Platform implementation

### Android

Use `ACTION_OPEN_DOCUMENT_TREE` with read/write grant flags. The adapter stores a bounded, short-lived in-memory token-to-tree mapping and does not persist the tree grant. It discovers only the direct child with the exact requested name, rejects ambiguous duplicates and bounds preview reads. Replacement uses staging and a backup document where supported. The adapter fails closed when the provider cannot list, stage or rename safely.

SAF document providers do not provide a compare-and-swap rename primitive. The adapter rechecks the original digest before applying the change, but an independent writer can still race between that recheck and the provider's rename operation. This residual limitation is disclosed rather than represented as an atomic guarantee.

### Windows

Use the native folder picker, canonicalize the selected folder, reject reparse-point traversal, and retain only a bounded short-lived in-memory workspace token. Stage in the selected folder, use `ReplaceFileW` for an existing target or no-replace `MoveFileExW` for a new target, then verify the resulting SHA-256. Attempt rollback from the backup after a failed verification.

A narrow race with an independent external writer can still occur between the final digest check and native replacement. Physical Windows qualification remains required.

## Explicitly rejected

- Arbitrary absolute or relative nested paths supplied by the model.
- Directory creation, recursive writes or bulk file changes.
- File deletion, moving, renaming or directory manipulation.
- Shell/PowerShell, arbitrary process execution or scripts.
- Automatic approval or reuse of a previous action approval.
- Persistent broad Android storage permissions or persistent SAF tree grants.
- Recording paths or file contents in the audit log.

## Consequences

### Positive

- Introduces a practical writing capability without opening general filesystem access.
- Reuses the existing first-use consent, selected-resource broker and per-action approval policy.
- Gives users a reviewable before/after diff and a bounded single-file result.
- Keeps the model proposal untrusted and native adapters independently validate it.

### Trade-offs and limitations

- A single direct-child text file per action is intentionally restrictive; nested workspace edits and multi-file patches are deferred.
- Android SAF provider behavior varies, so some cloud/document providers may reject safe staging or rename and consequently fail closed.
- Filesystem races with independent external writers cannot be eliminated on both platforms by the selected APIs.
- Rust/Dart test execution, FRB generation, Android/Windows native compilation and physical-device validation remain release gates.

## Validation required before qualification

CI must run Dart and Rust tests, format/analyze/clippy, FRB generation, and Android/Windows builds. Platform tests must cover create, replace, no-op, invalid names, oversized content, approval denial/cancel, file changed after preview, external provider limitations, low storage, stage/promotion failure, rollback, backup cleanup failure, Windows reparse points, process interruption and proof that no file outside the selected root can be changed.
