# Licensing and notices register — preliminary

| Source | Evidence in supplied archive | Current finding | Migration rule |
|---|---|---|---|
| J.A.R.V.I.R | Root `LICENSE` | MIT text present; copyright notice belongs to Hermes Mobile. `THIRD_PARTY_NOTICES.md` says JARVIS began from `veficos/hermes-mobile` and integrates Hermes Agent. | Preserve original license and notices for any reused code; do not rebrand away attribution. Review each vendored dependency. |
| J.A.R.V.I.R third-party | `third_party/xterm/LICENSE`, `third_party/mermaid/LICENSE`, JetBrainsMono font license | Individual notices are present in the archive. | Retain notices if assets/code are copied. |
| NEXUS | `Cargo.toml` workspace metadata says `license = "MIT"`; `licenses/llama.cpp-MIT.txt` is present | No root `LICENSE` file is present in the supplied ZIP. Selected NEXUS GGUF parser/native adapter files have been copied and adapted into this private development workspace for technical work. This does not establish a distribution license. Native llama.cpp source itself is fetched separately at a pinned upstream revision. | Keep adapted NEXUS-derived source private and do not distribute Leo source or binaries until the authoritative NEXUS license text and notice requirements are confirmed. Preserve the upstream llama.cpp license with the native adapter. |
| New Leo files | Authored in this foundation workspace | Project-wide distribution license has not been selected. | Do not publish binaries/source until project ownership and license policy are confirmed. |

This is an archive-level preliminary register, not legal advice. SPDX metadata alone is not a substitute for retaining the actual license text and notices.


## Leo Alpha v0.6.0 additions

- `rusqlite` `0.43.0`: MIT license; the wrapper license text is preserved in `licenses/rusqlite-MIT.txt`.
- Bundled SQLite core: public domain according to the official SQLite copyright notice; see `licenses/SQLite-Public-Domain.md`.
- Dependency license metadata is recorded in `docs/audit/DEPENDENCY_REGISTER.csv`. A complete generated transitive-license report still requires Cargo resolution on the pinned toolchain.


## Leo Alpha v0.14.0 additions

- `crypto` `3.0.8`: BSD-3-Clause; used for incremental SHA-256 model-pack integrity manifests. The upstream license text is retained in `licenses/crypto-BSD-3-Clause.txt`.
- `cross_file` `^0.3.5`: BSD-3-Clause; dev dependency used by the `PlatformFile` fake in voice-pack tests. A notice is retained in `licenses/cross_file-BSD-3-Clause.txt`.

These notices document the declared direct dependency license metadata. The full resolved transitive dependency tree still requires a Dart/Flutter package resolution and generated notice audit on CI.


## Leo Alpha v0.15.0 additions

- Added an optional user-imported Silero VAD ONNX model reference from the upstream `k2-fsa/sherpa-onnx` model inventory. The model weights are not bundled or redistributed by Leo. Review the upstream repository/model notices and any model-specific terms before redistributing the weights or packaging them in a future installer.


## Leo Alpha v0.21.0 additions

- `flutter_secure_storage` `11.2.0`: BSD-3-Clause; used for local encrypted task checkpoints on Android and Windows. The upstream BSD 3-Clause license is retained in `licenses/flutter_secure_storage-BSD-3-Clause.txt`. Package platform/security/build requirements are documented in `docs/audit/TOOLCHAIN_MATRIX.md`.
