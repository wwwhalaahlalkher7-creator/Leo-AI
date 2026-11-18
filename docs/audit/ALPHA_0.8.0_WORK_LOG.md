# Leo Alpha v0.8.0 — Skill Learning Foundation

## Implemented in source

- Added an app-private offline skill library persisted as versioned JSON.
- Added skill lifecycle states: proposed, testing, active, disabled and rejected.
- Added a user-facing Skill Library reachable from the chat header's Libraries menu.
- Added skill authoring fields for description, triggers, instructions, ordered steps, examples, declared capabilities and optional source task ID.
- Added structural/safety preflight checks. Sensitive-action instructions must explicitly mention user confirmation/approval; attempts to bypass safety or permissions are rejected.
- Added explicit user activation after a passing preflight; skills are never activated automatically.
- Added skill revision snapshots. Editing an inactive skill creates a new proposed minor skill version and clears the previous validation.
- Added relevance matching for active and validated skills; at most two skills are added to transient generation context, within a bounded character budget.
- Skill guidance is explicitly marked untrusted and cannot grant capabilities or bypass per-action approvals.
- Added a built-in Skill Curator specialist and deterministic routing for skill-learning requests.
- Added Dart unit/widget tests for lifecycle, persistence, validation, retrieval boundaries and navigation.
- Added skill policy configuration and ADR-0012.

## Important limitations

- This is the reviewed skill-library foundation, not autonomous learning from executed tasks. Leo's task engine currently builds/validates plans but does not yet execute and persist complete workflows. The source task ID can be attached manually; automatic task-log capture is deferred.
- The preflight checks are structural and heuristic. Test examples are stored as acceptance scenarios but are **not run against the LLM** in this milestone.
- Skills are declarative instructions only. Embedded scripts are not executed.
- Skills currently persist in app-private JSON and are not separately encrypted.
- Skill context is supplied to chat generation; automatic execution of device/app actions is still behind the future Capability Broker and execution engine.
- Portable Agent Skills `SKILL.md` folder import/export is not yet implemented.

## Validation performed in this environment

- Python architecture/version/source-integrity checks are run as available.
- Flutter/Dart SDK and Rust toolchain are not installed in this environment; Dart formatting, Flutter Analyze, Flutter tests, Cargo format/tests/Clippy, Android APK build and Windows build cannot be claimed as executed here.
- CI is configured to run the full toolchain checks after checkout.
