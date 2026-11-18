# Leo Alpha v0.4.0 — Windows native runtime implementation log

Date: 2026-11-15
Channel: ALPHA
Version: v0.4.0

## Implemented in source

- Generalized the Rust llama.cpp dynamic loader for Android ARM64 and Windows x64.
- Windows resolves `leo_llama_backend.dll` beside the running application executable rather than searching the process working directory or `PATH`.
- Added a Windows native-library build script (`scripts/build_windows_native.ps1`) using the same pinned llama.cpp revision as Android.
- Made the C++ adapter export its stable C ABI through `__declspec(dllexport)` on Windows.
- Added Windows physical-memory and process-memory probes using `GlobalMemoryStatusEx` and `GetProcessMemoryInfo`.
- Added Windows wide-path validation and preserved UTF-8 model paths end-to-end. The pinned ggml implementation converts UTF-8 paths to UTF-16 and uses `_wfopen` on Windows.
- Reused the same CMake adapter target for Android and Windows; Windows links `Psapi` and uses the static MSVC runtime to avoid a separate Visual C++ runtime installation requirement.
- Added Windows CI steps to build the native DLL, build the Flutter Windows runner, and package the DLL beside the executable.
- Removed the import-platform lock from model catalogue entries: GGUF weights are portable; runtime availability is decided by the current platform backend.
- Updated README, ADR-0008, model-management architecture notes, toolchain matrix and development roadmap.
- Bumped the app version to `v0.4.0` because Windows native inference support is a new functional implementation slice. Release channel remains `ALPHA`; build number remains `1` because no installable artifact was built here.

## Validation performed in this environment

- Version policy and Flutter/Cargo version synchronization: passed.
- Python architecture/version/source-integrity suite: passed (15 tests).
- Host C++ fake-llama contract test: passed.
- Windows C++ preprocessor branch syntax check with stub Windows APIs: passed (syntax validation only; not an MSVC build).

## Not verified here

This environment does not contain Cargo/Rust, Flutter/Dart, Android SDK/NDK, or Windows MSVC. Therefore no Rust compilation, FRB generation, Flutter analyze/test, Android native build, Windows DLL build, APK build, Windows app build, or real model inference has been run in this turn. CI is configured for those checks, but a workflow run is required before claiming platform build success.

The Windows DLL path has been designed to load from beside the Flutter executable. The user-data model directory can contain Unicode path components. The adapter validates them through `std::filesystem::u8path`; the pinned upstream `ggml_fopen` performs UTF-8-to-UTF-16 conversion for file access. This still requires a real Windows test under a non-ASCII account profile before Beta.

## Next engineering step

Run CI and resolve any generator or MSVC integration issues. Then test GGUF import, load, streaming output, cancellation, unload/reload, memory telemetry and fully offline generation on one Android ARM64 device and one Windows x64 machine.
