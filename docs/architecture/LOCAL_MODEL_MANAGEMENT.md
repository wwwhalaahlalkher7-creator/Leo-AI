# Leo Local Model Management

Status: Alpha implementation in progress (v0.17.0). Leo includes a platform-neutral GGUF header inspector, validated catalogue, persistent private model library, streaming SHA-256 verification, a typed Flutter Rust Bridge API, and a common native C ABI designed for Android ARM64 and Windows x64. The C++ adapter has passed the host-side fake-llama ABI contract test. Real NDK/MSVC builds and inference on physical Android/Windows devices remain required validation gates.

## Design goals

- Keep model weights outside the app binary and platform package.
- Store only metadata and relative paths in Leo's private model directory.
- Import user-selected GGUF files offline; no model download service is required.
- Stage, inspect, hash, and validate a model before committing its catalogue entry.
- Keep RAM requirements unknown until a reliable estimate exists; never mark an uninspected model as ready.
- Re-check the canonical path, recorded file size, and optional SHA-256 checksum before native loading.
- Keep the catalogue platform-neutral so Android and Windows adapters can share the same data contract.

## Catalogue and import

The initial manifest is `config/models/catalog.json` and begins empty. A user installation maintains its own copy in the app-private data directory. `ModelLibrary` creates or recovers the catalogue, imports a selected `.gguf` into a private staging directory, validates its GGUF header, obtains metadata and file size, calculates SHA-256 with a bounded streaming buffer, then atomically publishes the model file and catalogue update. A failed header check does not create a catalogue record. Catalogue replacement uses a temporary file and backup recovery to avoid leaving a truncated manifest after interruption.

Model entries include a stable ID, display name, relative GGUF path, file size, SHA-256, optional architecture and quantization labels, context length, optional minimum RAM estimate, supported platforms, and import time.

## Safety and integrity

- Absolute paths, parent-directory traversal, backslash separators, and drive-qualified paths are rejected.
- Duplicate model IDs are rejected.
- Only `.gguf` model entries are accepted in this milestone.
- Canonical paths must remain below the app-private model root, including symlink resolution.
- The recorded size is rechecked immediately before loading.
- If a checksum is recorded, Leo recalculates SHA-256 and rejects any mismatch before native model loading.
- Unknown memory requirements mean `NeedsInspection`, never `Ready`.
- Model-load planning estimates the conservative memory threshold before confirmation; the native adapter measures live available physical memory again immediately before allocation and rejects insufficient headroom.
- Model weights are never copied into the APK or Windows executable.

## Runtime status

Android ARM64 and Windows x64 now share the same Rust dynamic-loader module and Leo C ABI (`leo_llama_*`). Android loads `libleo_llama_backend.so` from the packaged native library directory; Windows loads `leo_llama_backend.dll` beside the executable to avoid searching the working directory or `PATH`. The C++ source uses `/proc` memory diagnostics on Linux/Android and Windows `GlobalMemoryStatusEx` / `GetProcessMemoryInfo` on Windows. Windows model paths are received as UTF-8, validated with `std::filesystem::u8path`, then passed unchanged to the pinned llama.cpp build; its `ggml_fopen` converts UTF-8 to UTF-16 and calls `_wfopen`. The Windows adapter uses the static MSVC runtime so deployment does not depend on a separately installed VC runtime.

The adapter supports load, unload, streaming generation, cancellation, KV-context clearing, and process memory diagnostics. Current inherited limits are one active model/session, a 512–4096-token context range, a maximum 1024-token generation per request, and CPU inference only. The Flutter layer now has a generated-bridge source API and a local model screen. Windows inference is wired in source and CI build steps but not yet considered verified until the actual Windows build and offline generation smoke test pass.

## Tests and outstanding work

Rust unit tests cover catalogue validation, traversal rejection, file integrity, model import, invalid GGUF rejection, and duplicate IDs. The host C++ contract test uses a fake llama.cpp API and validates the exported ABI; it does not prove compatibility with the real upstream llama.cpp build. CI now has dedicated Android ARM64 and Windows x64 build paths against the same pinned upstream revision. The local execution environment used for this change does not include Rust/Cargo, Flutter/Dart, the Android NDK, or Windows MSVC, so those platform builds have not been run here. Completion still requires successful CI builds, real offline inference smoke tests on both platforms, and memory/load/unload lifecycle verification.


## Flutter integration (Alpha v0.3.0–v0.4.0)

The Flutter app exposes the Rust model library through `flutter_rust_bridge` 2.13.0. The generated API is sourced from `core/bridge/src/api/simple.rs`; generated glue is produced with `scripts/generate_bridge.sh` and is not hand-edited. The `ModelLibraryPage` uses the platform file picker and `path_provider` to keep imported models in the app-private support directory.

The current controls support listing, importing, GGUF inspection, checksum verification, loading, unloading, cache clearing and removal. Import is local-only and uses the platform file picker, so Leo does not need broad storage permission merely to import a user-selected model. GGUF files are recorded as portable across platforms; loading is enabled only when the current platform reports a loaded native backend.

Model files are large user data and are never committed to Git or bundled by default. This keeps the app package small and leaves model licensing and storage choice explicit.


## Resource policy (Alpha v0.17.0)

Before loading a GGUF, the UI asks the user to select a supported context preset and CPU thread count. The default context is no greater than 2048 tokens to reduce KV-cache pressure. The recommended model thread count reserves one logical processor when possible and is capped at four; the user can choose a lower count without Leo silently changing model quality.

The displayed admission estimate intentionally mirrors `has_sufficient_memory` in `native/llama/src/llama_probe.cpp`:

`GGUF file bytes + 12.5% of file bytes + 384 MiB + 128 MiB × ceil(context_tokens / 2048)`.

This is a conservative threshold heuristic, not a prediction of exact RSS or a live free-memory reading. Immediately before loading, Android reads `MemAvailable` from `/proc/meminfo`; Windows reads `ullAvailPhys` from `GlobalMemoryStatusEx`. If the reading is unavailable or below the threshold, loading fails closed with an actionable Arabic message. Leo does not automatically reduce context or change the model settings.

The runtime card displays resident and peak resident memory only when the native snapshot provides a non-zero measurement. These counters describe the complete Leo process, not memory attributable to llama.cpp alone.
