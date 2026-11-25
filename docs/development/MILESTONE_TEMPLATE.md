# Milestone Template

> Copy this file to `docs/planning/milestones/<VERSION>_<slug>.md` for each milestone.

## Metadata
- Version:
- Stage: ALPHA / BETA / RELEASE
- Status: PLANNED / IN PROGRESS / SOURCE IMPLEMENTED / CI QUALIFIED / PLATFORM QUALIFIED / BLOCKED
- Owner:
- Base commit:
- Target platforms: Android / Windows / both

## 1. Objective
What user-visible or engineering outcome must this milestone deliver?

## 2. Scope
### Included
- 

### Explicitly excluded
- 

## 3. Baseline and findings
- Current behavior:
- Reproduction/evidence:
- Related work log / ADR / roadmap:
- Existing components to reuse:

## 4. Architecture and contracts
- Affected layers:
- Data/control flow:
- Public interfaces / FRB / native ABI:
- Storage/schema changes:
- Permission/security/privacy implications:
- Dependency/license/package-size review:
- Migration, compatibility and rollback:

## 5. Implementation slices
| Slice | Files/modules | Expected result | Dependencies | Status |
|---|---|---|---|---|
| 1 | | | | |

## 6. Acceptance criteria
- [ ] Observable behavior:
- [ ] Error, loading and empty states:
- [ ] Offline/recovery behavior:
- [ ] Backward compatibility/data safety:
- [ ] Security/privacy constraints:
- [ ] Documentation and diagnostics:

## 7. Verification plan
| Check | Command / procedure | Required environment | Result | Evidence |
|---|---|---|---|---|
| Python contracts | `python -m unittest discover -s scripts/tests -v` | Python 3.13 | PENDING | |
| FRB | `bash scripts/generate_bridge.sh` | pinned Flutter + FRB | PENDING | |
| Dart/Flutter | format, analyze, test | pinned Flutter | PENDING | |
| Rust | fmt, test, clippy | pinned Rust | PENDING | |
| Android | build + real-device protocol | Android SDK/NDK + device | PENDING | |
| Windows | native/app build + host tests | Windows/MSVC host | PENDING | |

## 8. Risks and mitigations
| Risk | Likelihood/impact | Mitigation | Residual risk |
|---|---|---|---|

## 9. Results and limitations
- Implemented:
- Tests passed:
- Tests not run and why:
- Known limitations:
- Follow-up work:

## 10. Exit decision
- [ ] Acceptance criteria met.
- [ ] Required CI jobs passed.
- [ ] Required device/host tests passed or explicitly remain pending.
- [ ] Work log and validation report updated.
- [ ] Roadmap and changelog updated where applicable.

**Decision:** ACCEPT / REJECT / BLOCKED  
**Evidence/commit:**
