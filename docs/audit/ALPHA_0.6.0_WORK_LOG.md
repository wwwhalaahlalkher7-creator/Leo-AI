# Leo Alpha v0.6.0 — Local memory foundation

Date: 2026-11-15
Channel: ALPHA
Version: v0.6.0

## Implemented in source

- Added the `leo-memory` Rust crate with bundled SQLite for Android/Windows portability.
- Added schema migration `user_version = 1`, WAL mode, busy timeout, foreign keys and secure-delete configuration.
- Added the five memory categories: personal, episodic, semantic, procedural and project.
- Added pending proposal, explicit approval, approved save, edit, enable/disable, list, delete and search operations.
- Search returns only approved and active memories; pending proposals and disabled memories never enter retrieval.
- Added Arabic normalization for alef/hamza variants, diacritics, tatweel, alif maqsura and taa marbuta, then a bounded BM25-style lexical ranker.
- Added source references, tags, approval state, timestamps, deterministic SHA-256 duplicate detection and validation limits.
- Exposed typed bridge endpoints for memory proposal, explicit save, approval, state change, edit, delete, listing and retrieval.
- Added ADR-0010 documenting the local storage and privacy boundaries.

## Validation performed in this environment

- Version policy and Flutter/Cargo version synchronization: passed.
- Original J.A.R.V.I.R and NEXUS archive SHA-256 verification: passed.
- `python -m unittest discover -s scripts/tests -v`: passed (18 tests), including memory-engine architecture contracts.
- SQLite schema migration DDL and approved/active retrieval filter smoke test via Python's SQLite binding: passed. This validates the schema/query contract, not the Rust wrapper implementation.
- Native adapter fake-llama contract and Windows-branch syntax check with stub Windows headers: passed; this is not a real Windows build.

## Not verified here

This environment does not provide Cargo/Rust, Flutter/Dart or Android/Windows platform toolchains. A Cargo lockfile could not be generated locally; dependency resolution and lockfile creation remain CI/toolchain tasks. Therefore Rust compilation/unit tests, SQLite cross-platform builds, Flutter Rust Bridge generation, Flutter analyze/test, Android APK build, Windows application build and live database behavior on target devices have not been run.

The store deliberately does not extract memory from conversations, inject retrieved memory into model prompts, resolve contradictory facts, perform semantic embedding search or encrypt the database. The current bridge is the foundation for those separately tested capabilities. Memory persistence must be invoked with Leo's app-private database path, and retrieved content must be treated as untrusted reference data.

## Next engineering step

Integrate the memory proposal/approval/retrieval flow into the chat experience, with a review UI and explicit user controls. Only approved, active memories may be added to a bounded model context, with provenance labels and a clear way to inspect or remove each memory.
