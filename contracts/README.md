# Leo domain contracts — v0.1.0

These contracts define boundaries before feature implementations are migrated. They are platform-independent and must not mention Android SDK types, Windows COM types, Flutter widgets, llama.cpp structures, Hermes API payloads, or MCP transport objects directly.

## Contracts introduced

| Contract | Purpose | Owner |
|---|---|---|
| `RuntimeDescriptor` / `RuntimeCapabilities` | Describe an inference engine without exposing its implementation | `leo-runtime` |
| `AssistantRequest` / `RuntimeEvent` | Send a conversation to a selected runtime and stream its lifecycle | `leo-runtime` |
| `AgentProfile` | Built-in or user-customized specialist profile | `leo-orchestration` |
| `TaskPlan` / `TaskStep` | Validated work graph and dependency edges | `leo-orchestration` |
| `MemoryRecord` | Durable, inspectable memory with type and provenance | memory subsystem (future) |
| `SkillMetadata` | Versioned, testable skill package metadata | skill subsystem (future) |
| `CapabilityDescriptor` | Discover an OS/app/native/MCP capability and its risk | Capability Hub (future) |
| `PermissionGrant` | Durable user-granted access scope | permission subsystem (future) |
| `ActionApproval` | One-off approval for a consequential action | execution broker (future) |
| `ExecutionResult` | Structured outcome and references to produced artifacts | execution engine (future) |

## Required invariants

1. A runtime is selected behind `AssistantRuntime`; UI code never knows whether it is local llama.cpp or an optional adapter.
2. `PermissionGrant` is not an execution instruction. It only enables an allowed capability within its recorded scope.
3. `ActionApproval` is separate from a permission grant. High-impact actions may require per-action confirmation even after a capability permission was granted.
4. Agents do not own operating-system permissions. Every tool request passes through the Capability Hub and execution broker.
5. A skill is procedural guidance plus optional reviewed assets/scripts. A skill does not itself grant access to files, network, shell, or applications.
6. Memory records retain provenance and user controls. Model-generated guesses must not be silently stored as user facts.
7. Runtime and agent events carry request/task identifiers so cancellation, audit and UI state can be correlated.
8. Unsupported platform capabilities must report `unavailable`; they must never be simulated by an online fallback when offline mode is selected.

The Rust types in `core/shared/src/contracts.rs` are the initial source of truth for in-process domain types. A versioned JSON serialization schema will be added when the first platform bridge is introduced, rather than locking a wire format prematurely in the foundation milestone.
