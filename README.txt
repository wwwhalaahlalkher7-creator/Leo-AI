LEO AI — FRB 2.13.0 output path correction

The latest GitHub Actions failure showed:
  code_path=apps/leo_app/../../core/bridge/src/frb_generated.rs
  base_dir=core/bridge/src
  prefix not found

Root cause: FRB 2.13.0 replaces the YAML base_dir with the directory that
contains flutter_rust_bridge.yaml. It canonicalizes rust_root, but a configured
relative rust_output retains its lexical `..` segments. Its subsequent
strip_prefix comparison therefore fails.

Correction:
  rust_root: ../../core/bridge
  dart_output: lib/src/rust

The config intentionally omits base_dir and rust_output. FRB derives the
Rust output from its already canonicalized Rust crate root, so the generated
path is exactly core/bridge/src/frb_generated.rs. The script preflight checks
this contract before invoking the pinned generator.

See docs/audit/FRB_2.13_OUTPUT_PATH_CORRECTION_2026-11-25.md for the evidence
and validation boundary. Hermetic tests do not replace a real FRB generation
run. Re-run Prepare Leo Android Bootstrap Files after pushing this correction.
