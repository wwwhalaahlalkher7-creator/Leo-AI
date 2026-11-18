# Leo Alpha v0.18.0 — source validation report

## Scope

The source package adds an executable multi-agent reasoning coordinator, a Flutter/Rust stream API, request-scoped cancellation and automatic chat routing for complex reasoning requests. The current local runtime remains single-generation, so execution is intentionally sequential.

## Checks run in this workspace

```bash
python -m unittest discover -s scripts/tests -v
python scripts/check_version.py
python scripts/check_version.py --previous v0.17.0 --kind minor --next v0.18.0
python scripts/verify_sources.py
```

## Validation boundary

Commands completed successfully:

```text
python -m unittest discover -s scripts/tests -q                 97/97 passed
python scripts/check_version.py                                 PASS
python scripts/check_version.py --previous v0.17.0 --kind minor --next v0.18.0  PASS
python scripts/verify_sources.py                                PASS (both source archive hashes)
```

Structured source validation also parsed all files successfully: **10 JSON, 8 TOML, 5 YAML and 4 CSV** files (including consistent CSV row widths).

| Area | Result | Notes |
|---|---|---|
| Python architecture/contract tests | **PASS — 97/97** | Includes new scheduler/bridge/chat source contracts |
| Version policy | **PASS** | `v0.17.0` → `v0.18.0` minor increment; Flutter/Cargo metadata synchronized |
| Immutable source archives | **PASS** | J.A.R.V.I.S and NEXUS SHA-256 baselines match |
| Rust unit tests | Added, not run | Cargo/Rust toolchain unavailable; includes executor-cancel-without-token regression case |
| Rust formatting / Clippy | Not run | Cargo/Rust toolchain unavailable |
| FRB generation and Dart bindings | Not run | Flutter/Dart/FRB codegen unavailable |
| Dart format / Flutter analyze / Flutter tests | Not run | Flutter/Dart unavailable |
| Android / Windows builds | Not run | Android SDK/NDK and Windows MSVC toolchain unavailable |
| Physical-device agent tests | Not run | No target device attached |

## Manual and CI acceptance tests still required

1. Generate FRB bindings and confirm `AgentTaskRequestDto`, `AgentTaskEventDto`, `executeAgentTask` and `cancelAgentTask` signatures in Dart.
2. Verify a multi-domain request routes to multiple built-in agents while a simple request stays on the ordinary one-agent path.
3. With a loaded GGUF model, execute planner → specialist(s) → verifier and confirm the final response is the verifier result.
4. Cancel during a streamed specialist response and confirm that no later specialist starts and the normal chat stop state is restored.
5. Force a transient runtime-busy error and confirm one retry; force a permanent failure and confirm dependent steps are skipped.
6. Confirm that communication, device and file action requests remain on the Capability Hub approval path and that specialist prompts do not execute side effects.
7. Measure end-to-end latency and peak process RSS on representative Android and Windows hardware.

## Honesty note

Passing Python source checks does not execute Rust, Dart, llama.cpp or the built-in agents. This is a source-implemented Alpha milestone, not a verified installable build or a validated agent-quality release.
