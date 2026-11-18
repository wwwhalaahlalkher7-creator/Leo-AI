# Leo architecture boundaries

## Runtime boundary

The Flutter application and agent orchestration depend on `AssistantRuntime`. The initial concrete target is a local `llama.cpp` runtime for Android and Windows. Any optional remote runtime is disabled unless a user explicitly configures it; the core assistant workflow has no hosted-service dependency.

## Capability boundary

All device and application actions are represented by `CapabilityDescriptor` records and resolved through the Capability Hub. Resolution preference:

1. OS API / official platform integration.
2. Installed application API, URI scheme, Intent, CLI, or automation contract.
3. Existing local tool / MCP server.
4. Small Leo native adapter only when the previous choices are not suitable.
5. UI automation only as a constrained fallback.

Leo must not embed a duplicate utility when the OS or an installed application already provides a reliable, permissioned implementation.

## Permission boundary

- Ask for platform permission at first use, not on install or initial launch.
- Persist the exact grant scope and honor revocation.
- Separate long-lived permission grants from per-action approval.
- Default to least privilege and user-level Windows execution.
- Denial, unavailable permission APIs, and unsupported capabilities fail closed.

## Agent boundary

A built-in agent catalog is shipped with Leo. Users are not required to create agents. A router selects the smallest suitable agent set; a planner delegates multi-domain work and a reviewer checks outcomes. Agents can request capabilities but cannot call OS APIs directly.

## Memory and skill boundary

Memory stores personal, episodic, semantic, procedural and project records in a versioned SQLite database under the app-private support directory. Proposals remain pending until explicit user approval; retrieval includes only approved and active records. The Flutter memory screen exposes add, approve, edit, disable/re-enable and delete controls. Chat retrieval is relevance-ranked, bounded, transient (never written into the chat transcript), and marked as untrusted reference data behind a fixed system instruction. The initial SQLite layer is not encrypted by itself.

Skills capture reusable procedures, include tests/examples, are versioned, and require user promotion before becoming active. Neither mechanism updates model weights in v0.x.

## Platform boundary

Flutter provides the shared UI. Rust provides shared domain/runtime/orchestration code. Platform-specific integrations stay in Android Kotlin/Java and Windows native adapters (Rust/Win32/COM as justified), exposed through narrow bridge contracts.
