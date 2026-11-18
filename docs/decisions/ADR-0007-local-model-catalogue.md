# ADR-0007: External local model catalogue

- Status: Accepted for Alpha
- Date: 2026-11-15

## Context

Leo must work offline, but bundling large GGUF weights inside the application would inflate Android and Windows installers and make model updates expensive. The app and the model therefore need separate lifecycles.

## Decision

Store GGUF model files in app-private model storage and keep a versioned JSON catalogue containing metadata and safe relative paths. Android and Windows will share the same Rust catalogue contract. Native adapters will inspect GGUF metadata and verify checksums before changing a model to load-ready.

The catalogue must not infer exact RAM requirements solely from the GGUF file size. Unknown requirements remain `NeedsInspection` and cannot be automatically selected as ready.

## Consequences

- App packages stay small and models can be added or removed independently.
- The same model-management policy applies to Android and Windows.
- Model import, native metadata inspection, hashing, and actual llama.cpp loading remain separate implementation tasks.
