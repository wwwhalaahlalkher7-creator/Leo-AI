# FRB 2.13.0 output-path correction — 2026-11-25 (initial correction; superseded by follow-up)

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


## Follow-up: FRB 2.13.0 config-parent and lexical-path behavior — 2026-11-26

The next Actions run (`45759264852`, job `139705151899`) disproved the
previous path-resolution assumption. FRB still failed with:

```text
code_path=".../apps/leo_app/../../core/bridge/src/frb_generated.rs"
base_dir=".../core/bridge/src"
prefix not found
```

Inspection of the pinned **FRB 2.13.0 source** established the actual rules:

1. `Config::from_config_file` calls `with_base_dir` using the directory
   containing `flutter_rust_bridge.yaml`. That overwrites a YAML `base_dir`
   value. In this repository the effective base directory is therefore
   `apps/leo_app`, not the repository root.
2. `compute_rust_crate_dir` canonicalizes
   `base_dir.join(rust_root)`, producing the canonical
   `core/bridge` directory.
3. `compute_rust_output_path` does not canonicalize a configured
   `rust_output`; joining `../../core/bridge/src/frb_generated.rs` leaves
   lexical `..` segments. `compute_mod_from_rust_crate_path` then calls
   `strip_prefix` against the canonical `core/bridge/src` directory, which
   fails even though both paths refer to the same filesystem location.
4. When `rust_output` is omitted, FRB's own fallback derives
   `src/frb_generated.rs` from the already canonicalized Rust crate directory.
   This produces the exact canonical path that its `strip_prefix` operation
   expects.

**Source correction:** the checked-in config now omits both `base_dir` and
`rust_output`; `rust_root` remains `../../core/bridge`, and `dart_output` is
`lib/src/rust` because FRB's effective base directory is the config's parent.
The generator preflight models those exact rules and rejects a configured
`rust_output`. The bridge output is still checked at the absolute path
`core/bridge/src/frb_generated.rs` after code generation.

The regression test now corrupts `rust_root` to ensure the preflight rejects
an incorrect crate before invoking the generator, and the generator shim
models FRB's canonical-crate fallback. The next pinned Actions run remains
required to prove the real code generator, after which `cargo check` and the
Android qualification steps can proceed. No real FRB generation or Android
build success is claimed by the local tests.
