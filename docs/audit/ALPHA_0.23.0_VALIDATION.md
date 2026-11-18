# Leo Alpha v0.23.0 — source validation report

## Checks run

| Check | Result | Scope |
|---|---:|---|
| Python architecture/source contract suite | **145/145 passed** | All `scripts/tests` test modules |
| Version synchronization | Passed | `config/VERSION`, release channel, Flutter pubspec, Cargo workspace, changelog |
| Version policy | Passed | `v0.22.0` → `v0.23.0`, minor feature increment |
| Immutable source archive verification | Passed | J.A.R.V.I.S and NEXUS pinned SHA-256 values |
| JSON parsing | **10 files passed** | All JSON source/config files |
| TOML parsing | **8 files passed** | All TOML source/config files |
| YAML parsing | **5 files passed** | All YAML/YML source/config files |
| CSV structure | **4 files passed** | All CSV files have consistent row widths |
| ZIP integrity | **Passed** | Final source archive verified with `unzip -t` and adjacent SHA-256 checksum |

Commands already run successfully:

```bash
python scripts/sync_version.py
python scripts/check_version.py --previous v0.22.0 --kind minor --next v0.23.0
python -m unittest discover -s scripts/tests -q
python scripts/verify_sources.py
```

The configuration and CSV scan was run over the complete workspace, excluding generated build/cache directories. All 27 checked structured-data files parsed successfully, with no inconsistent CSV row widths.

## Toolchain availability

The authoring workspace has `clang++`, `cmake`, Java and `kotlinc`, but no `flutter`, `dart`, `cargo` or `rustc`; Android SDK/NDK/Gradle and Windows MSVC/Windows SDK build environments are not available. A standalone `kotlinc` invocation cannot validate this Flutter plugin without the Android and Flutter embedding classpaths.

The following were **not** run: `dart format`, `flutter analyze`, `flutter test`, `cargo fmt`, `cargo test`, `cargo clippy`, FRB regeneration, Kotlin/Gradle Android compilation, MSVC Windows compilation, APK/EXE builds and real-device document/calendar/clipboard tests.

## Capability scope and safety checks

- Document open requires a picker-issued resource and reviewed extension. Android additionally blocks active/executable MIME families and rejects provider MIME mismatches; generic or absent MIME uses an allowlisted extension mapping. Windows rejects directories, reparse points and unknown extensions.
- Calendar integration is a user-owned draft only: Android `ACTION_INSERT`/`CalendarContract.Events.CONTENT_URI`, Windows temporary ICS handoff. There is no direct calendar database mutation and no invitation sending.
- Clipboard integration is write-only, bounded to 16 KiB and 10,000 characters, with visible preview and separate approval for every copy. Leo does not read the prior clipboard.
- Rust proposal extraction checks role/tool pairings and event timezone structure; Dart reparses exact arguments and validates actual dates/duration before Capability Hub dispatch.
- Native operations independently validate their platform payloads.

## Final packaging checks

The final source ZIP was generated from this workspace, tested with `unzip -t`, and its SHA-256 was recalculated. The digest is recorded in the adjacent `Leo_AI_Alpha_v0.23.0_Workspace.zip.sha256` artifact. The ZIP includes the two immutable source archives under `source_refs/`; their pinned hashes were independently verified above.

## Validation boundary

145 passing Python source-contract tests do not establish Dart/Rust/Kotlin/C++ compilation or platform runtime correctness. Do not treat v0.23.0 as a verified installable release until pinned CI and physical Android/Windows tests pass.
