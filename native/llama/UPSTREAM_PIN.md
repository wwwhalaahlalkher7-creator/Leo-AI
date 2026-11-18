# Pinned llama.cpp source

Leo's Android and Windows native adapters is designed against the llama.cpp source revision used by the NEXUS reference project:

- Repository: `https://github.com/ggml-org/llama.cpp`
- Pinned commit: `cd959bae99ff4bed22bef2604f45241c09bbb8c8`
- Adapter ABI: Leo-owned `leo_llama_*` symbols
- Android ABI: `arm64-v8a`
- Android API: 28
- Windows architecture: x64 (MSVC)
- Windows memory diagnostics: GlobalMemoryStatusEx + GetProcessMemoryInfo
- Inference backend: CPU-only on both initial platforms

The upstream implementation is not vendored in this repository. CI checks out the exact commit into `third_party/llama.cpp` before building the native adapter. This avoids shipping or duplicating upstream source files and keeps the model weights out of the app package.

The native adapter is adapted from the NEXUS reference workspace. The upstream llama.cpp license text is preserved in `licenses/llama.cpp-MIT.txt`.
