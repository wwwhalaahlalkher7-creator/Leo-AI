# Leo Alpha v0.26.0 — source validation report

## Checks run in this workspace

| Check | Result | Scope |
|---|---:|---|
| Python source / architecture contract suite | **169/169 passed** | `python -m unittest discover -s scripts/tests -q` |
| Version synchronization | Passed | `config/VERSION`, channel, Flutter pubspec, Cargo workspace and version policy |
| Version bump policy | Passed | `v0.25.0` → `v0.26.0` with MINOR bump |
| J.A.R.V.I.S source archive SHA-256 | Passed | Immutable source baseline; matches `ad07e171884c9d01e256a76944ce337b630b3c30e658e0161f513613c70e6331` |
| NEXUS source archive SHA-256 | Passed | Immutable source baseline; matches `7dc6ce894fa678060db9166c443b65c53a6f7365995d1d157ae82665ccd50349` |
| JSON/TOML/YAML/CSV parsing | Passed | 10 JSON, 8 TOML, 5 YAML and 4 CSV; all CSV rows have consistent column counts |
| ZIP integrity / SHA-256 | Passed after packaging | `unzip -t` and companion SHA-256 verification |

Commands already run:

```bash
python scripts/sync_version.py
python scripts/check_version.py --previous v0.25.0 --kind minor --next v0.26.0
python -m unittest discover -s scripts/tests -q
```

## Toolchain availability

Python is available. Flutter, Dart, Cargo, rustc, Android SDK/NDK and the Windows MSVC build toolchain are not available in the authoring environment.

Consequently, these checks were **not** run:

- `dart format`, `flutter analyze`, `flutter test`
- Rust `cargo fmt`, `cargo test`, `cargo clippy`
- Flutter Rust Bridge code generation
- Android APK and Windows installer/EXE builds
- Physical Android/Windows secure-storage, migration, key rotation, erase and backup/restore tests

The 169 passing tests are Python source/architecture contracts. They do not execute the Rust memory engine, Dart code, AES-GCM/PBKDF2 runtime paths or platform secure storage. The final ZIP passed archive integrity validation and its SHA-256 companion file was checked.

## Memory privacy boundary

The source encrypts memory content, normalized search text, source references and tags with AES-256-GCM. The content fingerprint uses an HKDF-derived HMAC key. SQLite IDs, kinds, timestamps, approval/activation state, schema/encryption version and opaque fingerprints remain metadata. The app UI discloses this. Erase verifies absence of the DB and common SQLite sidecars/key entries but cannot guarantee forensic erasure from snapshots, backups outside Leo or flash wear-levelling.

Backup is bounded to 1,000 records and 5 MiB and imported records become pending/inactive. Backup passphrases cannot be recovered by Leo. Local similarity/conflict detection is heuristic only, and chat memory proposals require a user selecting one user-authored message.

## Dependency and lockfile note

`cryptography` 2.9.0 is added for Dart AES-GCM/PBKDF2 backup. Rust direct crypto crates are pinned in `core/memory/Cargo.toml`, including `aes-gcm`, `base64`, `hmac`, `hkdf` and `rand`. The dependency notices are in `licenses/leo-memory-crypto-dependencies.md`. This source archive does not have generated `Cargo.lock` or `pubspec.lock`; CI must generate, review and commit deterministic lockfiles before binary qualification, and regenerate transitive license notices from those exact lockfiles.

## Conclusion

v0.26.0 is source-implemented and its available Python source-contract suite passes. It is **not** yet a verified Android/Windows build or a platform-qualified release. The remaining tests and acceptance gate are defined in `docs/testing/MEMORY_PRIVACY_AND_BACKUP.md`.
