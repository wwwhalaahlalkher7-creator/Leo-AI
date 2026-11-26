# FRB 2.13.0 path fix — 2026-11-26

## Root cause confirmed from the pinned generator source

`Config::from_config_file` in FRB 2.13.0 overwrites the YAML `base_dir` with
the config file's parent. `compute_rust_crate_dir` canonicalizes the crate
root, while `compute_rust_output_path` does not canonicalize an explicitly
configured output. FRB later calls `strip_prefix` between those mismatched
path representations, which fails when the configured output contains `..`.

## Corrected configuration contract

- Omit `base_dir`; FRB assigns it from `apps/leo_app/flutter_rust_bridge.yaml`.
- Keep `rust_root: ../../core/bridge`; FRB canonicalizes this path.
- Omit `rust_output`; FRB's fallback derives `src/frb_generated.rs` from the
  canonicalized crate root, producing `core/bridge/src/frb_generated.rs`.
- Set `dart_output: lib/src/rust`; the effective base directory is the
  Flutter app directory.
- Keep `dart_root: .`.

The generation script preflight checks these same anchors, rejects any
configured `rust_output`, and verifies all generated Rust/common/IO/Web
bindings. A hermetic generator shim covers the canonical fallback behavior.

## Validation boundary

Python suite: 219/219 passed. Version synchronization, source archive hashes,
Python compile checks, shell syntax and workflow YAML parsing passed. The
authoring environment does not have Flutter, Dart, Cargo or rustc, so this
archive does not claim a real FRB generation, Rust compile, Android build or
APK/device qualification. A fresh pinned GitHub Actions run is the acceptance
gate.
