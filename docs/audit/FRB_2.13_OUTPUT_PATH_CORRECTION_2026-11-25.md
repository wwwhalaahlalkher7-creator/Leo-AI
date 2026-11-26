# FRB 2.13.0 output-path correction — 2026-11-25

## Observed failure

The latest `Prepare Leo Android Bootstrap Files` run passed dependency
resolution and printed the FRB path contract, then failed with:

```text
code_path=".../apps/leo_app/src/frb_generated.rs"
base_dir=".../core/bridge/src"
prefix not found
```

The generator's `code_path` is outside the Rust bridge crate while its module
base is inside that crate. This is the direct cause of the prefix error.

## Root cause

The configuration used:

```yaml
rust_root: ../../core/bridge
rust_output: src/frb_generated.rs
```

The actual run demonstrates that `rust_output` is resolved from the Dart
project root (`dart_root: .`, the `apps/leo_app` directory). Consequently,
`src/frb_generated.rs` points to `apps/leo_app/src/frb_generated.rs`; it is not
relative to `rust_root` as the previous preflight incorrectly assumed.

## Correction

The configuration now uses:

```yaml
base_dir: ../..
rust_root: ../../core/bridge
rust_output: ../../core/bridge/src/frb_generated.rs
dart_root: .
```

The script resolves the output exactly as FRB does from `dart_root` and asserts
that it equals the canonical `core/bridge/src/frb_generated.rs`. The negative
regression test restores the old bad value and verifies that preflight stops
before invoking code generation.

## Validation and boundary

- The path contract is checked from the temporary repository layout used by
the hermetic bootstrap test.
- The shell workflow is exercised with stub Flutter, Cargo, Dart and FRB
  executables, including the malformed path regression.
- The full Python suite, version checks, source-archive checks and shell syntax
  checks are run for this correction.
- This environment does not have the pinned Flutter/Rust toolchains, so it
  cannot prove the real FRB 2.13.0 generator succeeds. That remains the next
  required GitHub Actions confirmation.

Project version remains `v0.27.0 / ALPHA`.

## Follow-up: lexical path versus canonical path — 2026-11-26

A later run proved that `Path.resolve()` in the preflight was not enough. FRB
received a lexical `code_path` containing `apps/leo_app/../../core/bridge`,
while its Rust module base was already canonicalized to `core/bridge/src`.
The filesystem destinations match, but the lexical path does not start with
the canonical prefix, so `strip_prefix` still fails.

The definitive source-side mitigation is now in `scripts/generate_bridge.sh`:
create a temporary FRB config containing canonical absolute paths for
`base_dir`, `rust_root`, `rust_output`, `dart_output` and `dart_root`, then call
`generate --config-file <temporary-config> --skip-fvm-install`. The checked-in
YAML remains portable and relative. A hermetic test inspects the temporary
config passed to the fake generator and rejects paths containing `..`.

This closes the known lexical-path mismatch in the invocation contract, but
actual FRB 2.13.0 code generation still needs to pass in GitHub Actions before
the issue can be marked fully resolved.
