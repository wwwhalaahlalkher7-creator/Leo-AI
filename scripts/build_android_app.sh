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

# Scripts are tracked as mode 100644, so always invoke them through bash.
bash "${ROOT_DIR}/scripts/prepare_android_runner.sh"
bash "${ROOT_DIR}/scripts/generate_bridge.sh"
bash "${ROOT_DIR}/scripts/build_android_native.sh"

mkdir -p "${APP_DIR}/android/app/src/main/jniLibs/arm64-v8a"
cp "${NATIVE_DIR}/libleo_llama_backend.so" "${APP_DIR}/android/app/src/main/jniLibs/arm64-v8a/"
cp "${NATIVE_DIR}/libc++_shared.so" "${APP_DIR}/android/app/src/main/jniLibs/arm64-v8a/"

cd "${APP_DIR}"
APK_OUTPUT_DIR="${APP_DIR}/build/app/outputs/flutter-apk"
ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
ZIPALIGN="${ANDROID_SDK}/build-tools/36.0.0/zipalign"
if [[ ! -x "${ZIPALIGN}" ]]; then
  ZIPALIGN="$(command -v zipalign || true)"
fi
if [[ -z "${ZIPALIGN}" || ! -x "${ZIPALIGN}" ]]; then
  echo "ERROR: Android build-tools 36.0.0 zipalign is required for 16 KB APK alignment verification." >&2
  exit 2
fi
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
  "${ZIPALIGN}" -c -P 16 -v 4 "${apk_path}"
  CHECKSUM_FILENAMES+=("app-${mode}.apk")
done
(
  cd "${APK_OUTPUT_DIR}"
  sha256sum "${CHECKSUM_FILENAMES[@]}" > SHA256SUMS.txt
)
echo "Android APK checksums written to ${APK_OUTPUT_DIR}/SHA256SUMS.txt"
