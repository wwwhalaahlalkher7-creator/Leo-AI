Leo-AI CI repair notes — v0.27.0 source (ALPHA)

The current Actions checks exposed these issues:

1. The bootstrap workflow attempted to execute shell scripts that Git tracks
   with mode 100644. Linux returned exit code 126 (Permission denied).
2. Flutter Rust Bridge 2.13.0 canonicalizes rust_root, but the configured
   rust_output retained ../../ segments. The generator then failed while
   calculating the Rust module path with StripPrefixError: prefix not found.
3. The Android SDK setup error from the earlier run was already addressed by
   switching android-actions/setup-android to v4 and installing SDK packages
   explicitly. The current Android build reached FRB generation and stopped
   at issue 2, before the native CMake build or APK packaging.

Corrections in this package:

- Invoke scripts/generate_bridge.sh and scripts/prepare_android_runner.sh via
  bash in the temporary bootstrap workflow.
- Invoke Android nested scripts via bash in scripts/build_android_app.sh.
- Set FRB base_dir to the repository root and use root-relative Rust/Dart
  output paths without parent-directory traversal. Set dart_root to the
  Flutter package working directory.
- Add a preflight path-contract check to scripts/generate_bridge.sh.
- Retain Linux FRB generation and artifact transfer to Windows; Windows no
  longer tries to run the failing code generator itself.

No application version is changed. These source corrections have passed the
local structural checks described in docs/audit/CI_FAILURE_ANALYSIS_AND_FIXES.md.
A new GitHub Actions run is still required to prove full dependency resolution,
Dart/Rust tests, Android native compilation and APK packaging. No APK is
claimed as built or platform-qualified by this archive.
