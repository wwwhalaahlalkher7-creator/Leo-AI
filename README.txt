LEO AI — FRB 2.13.0 output path correction

The latest GitHub Actions failure showed:
  code_path=apps/leo_app/src/frb_generated.rs
  base_dir=core/bridge/src
  prefix not found

FRB resolves rust_output from dart_root (apps/leo_app). Therefore the correct
configuration is:
  rust_root: ../../core/bridge
  rust_output: ../../core/bridge/src/frb_generated.rs

The preflight and regression tests now use this exact anchor and reject the
former src/frb_generated.rs value. See:
  docs/audit/FRB_2.13_OUTPUT_PATH_CORRECTION_2026-11-25.md

Local validation does not replace a real FRB generation run. Re-run
Prepare Leo Android Bootstrap Files after pushing this correction.
