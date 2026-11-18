# ADR-0008: Leo-owned native llama.cpp adapter

- Status: Accepted for Alpha implementation; Android ARM64 and Windows x64 adapters wired in source.
- Date: 2026-11-15

## Context

NEXUS already contains a real llama.cpp adapter and runtime loader, but its concrete implementation is Android-specific. Leo needs a stable cross-platform runtime contract while keeping platform-specific native libraries behind narrow adapters. The native adapter also needs to be independently contract-tested without requiring a device or model weights.

## Decision

Leo adopts the technical structure of the NEXUS llama.cpp C ABI adapter in a Leo-owned ABI (`leo_llama_*`) and retains its own Rust `AssistantRuntime` contract. Android ARM64 packages `libleo_llama_backend.so`; Windows x64 packages `leo_llama_backend.dll`. Both are loaded dynamically through a single Rust backend module, and both are built against the same pinned upstream llama.cpp revision. OS-specific memory probing and build packaging remain platform adapters; the model/runtime domain contract is shared.

Model import and preflight are separate from inference: Leo imports files into private storage, inspects GGUF metadata, hashes the file, validates the catalogue and checks the file again before passing it to the native loader.

## Consequences

- UI and orchestration do not depend directly on llama.cpp symbols.
- The Android adapter can be contract-tested with a fake llama API on a host compiler.
- Android and Windows native binaries remain distinct build artifacts and are not committed to source control.
- Windows inference source and CI packaging are now implemented, but platform support remains provisional until Windows build and offline-generation tests pass.
- The NEXUS source archive has no root LICENSE file. Its adapted source is retained only in this private development workspace pending authoritative license confirmation; distribution must not proceed until that issue is resolved.
- The upstream llama.cpp MIT notice is retained in `licenses/llama.cpp-MIT.txt`.

## Validation

The fake host adapter contract and C ABI symbol checks pass. A real Android NDK/llama.cpp build, Windows MSVC/llama.cpp build, generated Flutter bridge build, and offline inference tests on both platform families remain outstanding.


### Windows deployment and UTF-8 paths (v0.4.0)

The Windows x64 adapter is built as one Leo-owned DLL with the pinned llama.cpp and ggml static libraries folded into it. The MSVC static runtime is selected so the user does not need a separately installed Visual C++ redistributable for this adapter. Rust loads the DLL by an absolute path beside the executable. Model paths remain UTF-8 across the Rust/C ABI; Windows validation uses `std::filesystem::u8path`, while the pinned upstream `ggml_fopen` converts UTF-8 to UTF-16 and calls `_wfopen`. This is source-level integration only until the Windows CI job and a real Windows model-load test pass.
