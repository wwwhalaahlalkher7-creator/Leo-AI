#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CPP_SOURCE_DIR="${LLAMA_CPP_SOURCE_DIR:-${ROOT_DIR}/third_party/llama.cpp}"
ANDROID_NDK="${ANDROID_NDK:-${ANDROID_NDK_HOME:-}}"
EXPECTED_LLAMA_REVISION="cd959bae99ff4bed22bef2604f45241c09bbb8c8"
BUILD_DIR="${ROOT_DIR}/build/llama-android"
INSTALL_DIR="${ROOT_DIR}/build/llama-android-install"
OUTPUT_DIR="${ROOT_DIR}/build/android-native/arm64-v8a"

if [[ -z "${ANDROID_NDK}" || ! -f "${ANDROID_NDK}/build/cmake/android.toolchain.cmake" ]]; then
  echo "ERROR: ANDROID_NDK must point to an installed Android NDK." >&2
  exit 2
fi
NDK_PROPERTIES="${ANDROID_NDK}/source.properties"
if [[ ! -f "${NDK_PROPERTIES}" ]]; then
  echo "ERROR: Android NDK source.properties is missing; cannot verify the pinned toolchain." >&2
  exit 2
fi
actual_ndk_revision="$(sed -n 's/^[[:space:]]*Pkg.Revision[[:space:]]*=[[:space:]]*//p' "${NDK_PROPERTIES}" | head -n 1 | tr -d '\r')"
if [[ "${actual_ndk_revision}" != "30.0.16248370" ]]; then
  echo "ERROR: Android NDK revision mismatch." >&2
  echo "Expected: 30.0.16248370" >&2
  echo "Actual:   ${actual_ndk_revision:-unknown}" >&2
  exit 2
fi
if [[ ! -f "${LLAMA_CPP_SOURCE_DIR}/CMakeLists.txt" || ! -d "${LLAMA_CPP_SOURCE_DIR}/.git" ]]; then
  echo "ERROR: LLAMA_CPP_SOURCE_DIR must be a git checkout of the pinned llama.cpp source." >&2
  exit 2
fi

actual_revision="$(git -C "${LLAMA_CPP_SOURCE_DIR}" rev-parse HEAD)"
if [[ "${actual_revision}" != "${EXPECTED_LLAMA_REVISION}" ]]; then
  echo "ERROR: llama.cpp revision mismatch." >&2
  echo "Expected: ${EXPECTED_LLAMA_REVISION}" >&2
  echo "Actual:   ${actual_revision}" >&2
  exit 2
fi

command -v cmake >/dev/null 2>&1 || { echo "ERROR: cmake is required." >&2; exit 2; }
command -v ninja >/dev/null 2>&1 || { echo "ERROR: ninja is required." >&2; exit 2; }
command -v readelf >/dev/null 2>&1 || { echo "ERROR: readelf is required." >&2; exit 2; }

cmake -S "${ROOT_DIR}/native/llama" -B "${BUILD_DIR}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-28 \
  -DANDROID_STL=c++_shared \
  -DLLAMA_CPP_SOURCE_DIR="${LLAMA_CPP_SOURCE_DIR}" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_IS_DEV=OFF \
  -DGGML_BACKEND_DL=OFF \
  -DGGML_CPU=ON \
  -DGGML_CPU_ALL_VARIANTS=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_OPENMP=OFF \
  -DGGML_LLAMAFILE=OFF \
  -DLLAMA_OPENSSL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_COMMON=OFF \
  -DGGML_BUILD_TESTS=OFF \
  -DGGML_BUILD_EXAMPLES=OFF
cmake --build "${BUILD_DIR}" --target leo_llama_backend --parallel "$(nproc)"
cmake --install "${BUILD_DIR}" --config Release

mkdir -p "${OUTPUT_DIR}"
probe="$(find "${INSTALL_DIR}/lib" -maxdepth 1 -type f -name 'libleo_llama_backend.so' -print -quit)"
if [[ -z "${probe}" ]]; then
  echo "ERROR: native adapter shared library was not produced." >&2
  exit 1
fi
cp "${probe}" "${OUTPUT_DIR}/libleo_llama_backend.so"

libcxx_shared="$(find "${ANDROID_NDK}/toolchains/llvm/prebuilt" \
  -path '*/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so' \
  -print -quit)"
if [[ -z "${libcxx_shared}" ]]; then
  echo "ERROR: libc++_shared.so was not found in the Android NDK." >&2
  exit 1
fi
cp "${libcxx_shared}" "${OUTPUT_DIR}/libc++_shared.so"

readelf -h "${OUTPUT_DIR}/libleo_llama_backend.so" | grep -F 'AArch64'
symbols="$(readelf -Ws "${OUTPUT_DIR}/libleo_llama_backend.so")"
for symbol in \
  leo_llama_backend_init \
  leo_llama_version \
  leo_llama_load_model \
  leo_llama_inference_available \
  leo_llama_cancel_generation \
  leo_llama_generate \
  leo_llama_unload_model \
  leo_llama_is_model_loaded \
  leo_llama_loaded_context_tokens \
  leo_llama_last_error \
  leo_llama_memory_snapshot \
  leo_llama_clear_context_memory; do
  if [[ "${symbols}" != *"${symbol}"* ]]; then
    echo "ERROR: missing native adapter export: ${symbol}" >&2
    exit 1
  fi
done

(
  cd "${OUTPUT_DIR}"
  sha256sum libleo_llama_backend.so libc++_shared.so > SHA256SUMS.txt
)
ls -lh "${OUTPUT_DIR}"
echo "Android ARM64 native adapter build and ABI checks passed."
