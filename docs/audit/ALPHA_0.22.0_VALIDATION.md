# Leo Alpha v0.22.0 — source validation report

## Source-level checks completed

| Check | Result | Scope |
|---|---:|---|
| Python architecture/contract suite | **137/137 passed** | `scripts/tests` |
| Version synchronization | **Passed** | `v0.22.0`, `ALPHA`, Flutter pubspec `0.22.0+4`, Cargo workspace `0.22.0`, changelog |
| Source archive integrity | **Passed** | Immutable J.A.R.V.I.S and NEXUS baseline archives; both pinned SHA-256 values match |
| JSON/TOML/YAML/CSV parse | **Passed** | 10 JSON, 8 TOML, 5 YAML and 4 CSV files; CSV column counts consistent |
| ZIP integrity / SHA-256 | **Passed** | 227-file source archive; ZIP CRC test passed and SHA-256 sidecar verified |

Commands run in this workspace:

```bash
python -m unittest discover -s scripts/tests -q
python scripts/check_version.py --previous v0.21.0 --kind minor --next v0.22.0
python scripts/check_version.py
python scripts/verify_sources.py
```

The full configuration parser pass used Python JSON, `tomllib`, PyYAML and CSV parsers; all 10 JSON, 8 TOML, 5 YAML and 4 CSV files passed. The final 227-file ZIP passed `ZipFile.testzip()` and its `.sha256` sidecar was verified with `sha256sum -c`.

The suite includes the `test_safe_workspace_editing_contract.py` tests and the existing agent, permission, voice, memory and task checkpoint contracts. The 137 tests are Python static/source contracts; they do not execute Flutter, Rust, Kotlin, C++, native APIs or actual file-system transactions.

## Toolchain availability

Flutter, Dart, Cargo, rustc and Android SDK/NDK tooling are not installed or not available on PATH in this authoring workspace. Windows MSVC and Windows SDK are also unavailable. `kotlinc`, CMake and Clang are present, but `kotlinc` without the Android Gradle/SDK dependencies cannot validate the Android plugin, and host Clang on Linux cannot compile the Windows plugin.

The following remain **not run**:

- `dart format`, `flutter analyze`, `flutter test`
- `cargo fmt`, `cargo test`, `cargo clippy`
- Flutter Rust Bridge code generation
- Android Gradle/Kotlin plugin build and APK build
- Windows MSVC/C++ plugin and Flutter application build
- Physical Android/Windows tests for folder-picker, approvals, file creation/replacement, rollback and race conditions

## v0.22 implementation boundary

The code adds a tightly scoped `workspace.write_file` capability for the built-in `file_operator`: one UTF-8 text file directly under a folder selected by the user. Filename max 160 UTF-8 bytes; content max 16 KiB and 10,000 Unicode code points; preview of an existing file max 64 KiB. It requires a before/after diff and separate approval per write. It does not add nested paths, directory creation, delete/move/rename, bulk writes, shell or arbitrary process execution.

Android uses a short-lived SAF folder token and does not persist the tree grant. Because SAF providers vary and do not offer compare-and-swap rename, the adapter fails closed where staging/rename is unavailable and cannot eliminate a narrow external-writer race after its final recheck. Windows uses a selected canonical folder, reparse-point rejection, staged replacement, final SHA-256 verification and rollback attempt; a narrow external-writer race remains possible there too.

**Conclusion:** source-level implementation and Python contract tests are complete. Do not describe v0.22.0 as a verified installable build until the missing CI toolchain checks and physical Android/Windows tests pass.
