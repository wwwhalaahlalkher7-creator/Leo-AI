#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/apps/leo_app"
NATIVE_DIR="${ROOT_DIR}/build/android-native/arm64-v8a"
BUILD_MODE="${LEO_ANDROID_BUILD_MODE:-debug}"

case "${BUILD_MODE}" in
  debug) BUILD_MODES=(debug) ;;
  release) BUILD_MODES=(release) ;;
  both) BUILD_MODES=(debug release) ;;
  *)
    echo "ERROR: LEO_ANDROID_BUILD_MODE must be debug, release, or both." >&2
    exit 2
    ;;
esac

"${ROOT_DIR}/scripts/prepare_android_runner.sh"
"${ROOT_DIR}/scripts/generate_bridge.sh"
"${ROOT_DIR}/scripts/build_android_native.sh"

mkdir -p "${APP_DIR}/android/app/src/main/jniLibs/arm64-v8a"
cp "${NATIVE_DIR}/libleo_llama_backend.so" "${APP_DIR}/android/app/src/main/jniLibs/arm64-v8a/"
cp "${NATIVE_DIR}/libc++_shared.so" "${APP_DIR}/android/app/src/main/jniLibs/arm64-v8a/"

cd "${APP_DIR}"
APK_OUTPUT_DIR="${APP_DIR}/build/app/outputs/flutter-apk"
CHECKSUM_FILENAMES=()
for mode in "${BUILD_MODES[@]}"; do
  case "${mode}" in
    debug) flutter build apk --debug --target-platform=android-arm64 ;;
    release) flutter build apk --release --target-platform=android-arm64 ;;
    *)
      echo "ERROR: Internal build mode dispatch failed: ${mode}" >&2
      exit 2
      ;;
  esac
  apk_path="build/app/outputs/flutter-apk/app-${mode}.apk"
  python3 "${ROOT_DIR}/scripts/verify_android_apk.py" "${apk_path}"
  CHECKSUM_FILENAMES+=("app-${mode}.apk")
done
(
  cd "${APK_OUTPUT_DIR}"
  sha256sum "${CHECKSUM_FILENAMES[@]}" > SHA256SUMS.txt
)
echo "Android APK checksums written to ${APK_OUTPUT_DIR}/SHA256SUMS.txt"
