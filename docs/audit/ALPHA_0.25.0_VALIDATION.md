# Leo Alpha v0.25.0 — source validation report

## Source-level verification

| Check | Result | Scope |
|---|---:|---|
| Python architecture and contract suite | **164/164 passed** | All `scripts/tests` modules, including verified-workflow learning contracts |
| Version synchronization | Passed | `config/VERSION`, channel, Flutter pubspec, Cargo workspace and changelog |
| Version bump policy | Passed | Minor feature bump from `v0.24.0` to `v0.25.0` |
| Original source archive verification | Passed | Immutable J.A.R.V.I.S and NEXUS ZIP SHA-256 baselines |
| JSON / TOML / YAML / CSV | Passed | Existing repository architecture/config parser checks |
| Dart unit tests | Added, not run | Skill learning and repository tests were authored; Dart SDK unavailable |
| Native Android / Windows | Not run | Platform build toolchains unavailable |

Commands run:

```bash
python scripts/sync_version.py
python scripts/check_version.py --previous v0.24.0 --kind minor --next v0.25.0
python -m unittest discover -s scripts/tests -q
python scripts/verify_sources.py
```

## v0.25.0 implementation inspected

- Learning is exposed only for run records in `verified` state.
- Every run step must be confirmed; the exact original skill ID/version and ordered steps are matched before generation.
- The learning input is an allowlisted minimized object, not a conversation transcript or tool payload.
- Pattern-based privacy scrubbing is applied before runtime input and to generated proposal fields.
- Generated capabilities must be a subset of source skill capabilities.
- Proposal provenance is unique per verified run, enforced both in the service and inside the serialized file repository.
- A learning proposal remains inactive and requires existing preflight and explicit activation.

## Toolchain availability and test boundary

The active workspace does not have `flutter`, `dart`, `cargo` or `rustc`. Android SDK/NDK and Windows MSVC build tools are also unavailable. Therefore these checks were not run:

- `dart format`, `flutter analyze`, `flutter test` (including the new v0.25.0 tests)
- `cargo fmt`, `cargo test`, `cargo clippy`
- Flutter Rust Bridge code generation
- Android APK and Windows application builds
- Secure-storage behavior on actual Android/Windows devices
- Real local-model generation and end-to-end skill-learning UI flow

The passing Python suite verifies source contracts and architecture assertions. It does not execute Dart, Rust, Flutter plugins, secure storage or the local model. This archive is a source-implemented Alpha milestone, not a verified installable build.

## Privacy boundary

The curation request excludes original chats, task goals, free-form review notes, tool arguments/results, file names/paths and file contents. Redaction detects common email/URL/path/file-name/phone/token/identifier patterns, but is not a guarantee against arbitrary names or unseen confidential data. The confirmation UI tells the user to inspect the generated proposal before use.
