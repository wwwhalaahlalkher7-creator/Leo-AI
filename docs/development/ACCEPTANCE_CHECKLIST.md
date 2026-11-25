# Engineering Acceptance Checklist

Use this checklist for every meaningful change and milestone. A checked box means evidence exists—not merely that the item was considered.

## Before implementation
- [ ] Current version, channel and baseline commit recorded.
- [ ] Relevant plan, ADRs, architecture docs and prior validation reviewed.
- [ ] Issue reproduced or current behavior measured.
- [ ] Scope, exclusions, affected files/layers and acceptance criteria written.
- [ ] Existing code/dependencies checked before adding a duplicate.
- [ ] Data migration, compatibility, privacy and permission risks assessed.

## During implementation
- [ ] Change follows established Flutter/Rust/FRB/native boundaries.
- [ ] UI does not own domain/business orchestration.
- [ ] Native/FFI work stays behind adapters.
- [ ] Capability/permission broker remains the only route for protected OS actions.
- [ ] Inputs, outputs, errors and resource limits are validated.
- [ ] No secrets or sensitive user content are added to logs/fixtures.
- [ ] Generated FRB files are regenerated, not manually edited.
- [ ] Focused regression tests added.

## Before merge / CI
- [ ] `python scripts/check_version.py`
- [ ] `python scripts/verify_sources.py`
- [ ] `python -m unittest discover -s scripts/tests -v`
- [ ] Flutter `pubspec.lock` and workspace `Cargo.lock` are validated and committed before platform qualification
- [ ] FRB generation and generated-output checks
- [ ] Dart format, Flutter analyze and Flutter tests
- [ ] Rust fmt, tests, target checks and Clippy
- [ ] Relevant Android/Windows native and app builds
- [ ] Required GitHub Actions jobs passed
- [ ] Any unavailable checks explicitly marked PENDING, never PASS

## Platform qualification
- [ ] Clean install, upgrade and restart tested.
- [ ] Core local model workflow tested on target hardware.
- [ ] Offline and recovery paths tested.
- [ ] Permissions, revocation and OS handoffs tested.
- [ ] Storage, migration, backup/restore and erase tested where relevant.
- [ ] Memory/CPU pressure, cancellation and long-session behavior tested.
- [ ] Security/privacy and dependency/license review completed.
- [ ] Device/OS/build details and reproducible evidence recorded.

## Closeout
- [ ] Work log and validation report updated.
- [ ] Roadmap status and remaining work updated.
- [ ] ADR/register/changelog updated when affected.
- [ ] Delivered vs unverified behavior clearly distinguished.
- [ ] Artifact/ZIP created only if requested or at a handoff boundary.

## Status vocabulary
- **Source implemented:** code and source-level tests exist.
- **CI qualified:** required automated CI jobs passed.
- **Platform qualified:** required physical-device/host acceptance tests passed.
- **Blocked:** one or more required gates failed or lack necessary evidence.
