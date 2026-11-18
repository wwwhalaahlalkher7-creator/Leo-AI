Leo-AI CI fixes for failed run 44300239883

Files to replace in the repository:
  .github/workflows/ci.yml
  scripts/build_android_app.sh

What changed:
1. Upgrade android-actions/setup-android from v3 to v4 and skip the obsolete
   default package install. Android SDK packages are installed explicitly.
2. Invoke shell scripts with bash because the repository stores them as mode
   100644 (not executable). This applies both to CI steps and nested Android
   build-script calls.
3. Generate Flutter Rust Bridge outputs once on Ubuntu and upload them as an
   artifact. The Windows job downloads those generated files instead of running
   FRB codegen on Windows, where this run failed with the known Windows path
   canonicalization error: "prefix not found".
4. Make the Windows build depend on successful full-stack generation and tests.

Application version is not changed.
No APK signing or release publication is added.

Apply by replacing the two repository files with the same paths above, then
push to main or run Leo CI manually from GitHub Actions.
