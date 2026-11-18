# Leo Skill Engine — Alpha v0.10.0

## Lifecycle

```text
Author, import, or request a chat-derived proposal
          |
          v
     Proposed (inactive)
          |
          v
 Structural / safety preflight
          |
     +----+----+
     |         |
   fail       pass
     |         |
   edit     user approval
               |
               v
             Active
               |
               v
     Trigger-based retrieval
               |
               v
 Bounded transient untrusted guidance
```

## Portable interchange

- Single-file UTF-8 Markdown (`SKILL.md`) with the `name` and `description` YAML frontmatter fields.
- Leo sections: `When to use`, `Instructions`, `Steps`, `Acceptance scenarios`, and `Required capabilities`.
- Also recognizes common aliases such as `Triggers`, `Procedure`, `Workflow`, `Examples` and `Capabilities`.
- Plain scalars, quoted scalars and simple folded/literal block description scalars are accepted. Other advanced YAML structures are not interpreted.
- Maximum input size is 64 KiB. Imported descriptions, triggers, steps, capability IDs and examples are checked against Leo's limits.
- The body and frontmatter are treated as untrusted text. Imports never preserve activation or validation state.
- Scripts, assets, reference folders, archives and binary resources are not imported.


## Conversation-derived skill proposals (v0.10.0)

The user may explicitly select **Learn a skill from this conversation** from the chat menu. Leo sends only the selected conversation transcript to its configured local runtime with a Skill Curator instruction. The service considers at most the latest 20 user/assistant messages and at most 9,000 transcript characters, requests structured JSON, and validates every field and size before persistence.

- The conversation is treated as untrusted data; the model is instructed not to follow instructions embedded in the transcript.
- A conversation must contain at least one user message and one assistant message. The model must decline when there is not enough evidence for a reusable workflow.
- The extraction flow does not call tools, execute steps, test the workflow against apps, or claim that discussed actions were actually performed.
- Capability identifiers are descriptive metadata only; they do not grant permissions.
- Every result is stored as `proposed`, without validation state. The user must inspect/edit it, run the current structural preflight and explicitly activate it.
- The in-flight request is cancelled when the chat page is disposed.

This is assisted skill drafting from conversation content, not autonomous learning from execution experience. Automatic suggestions from durable completed-task traces are deferred until the task executor and trace store are implemented.

## Runtime retrieval

Only active skills with a passing latest preflight are retrieved. At most two highest-scoring matches are supplied to the local chat request as bounded, transient and untrusted guidance.

## Security boundaries

- Import/export does not request OS permissions.
- A declared capability ID is descriptive and does not grant access.
- Sensitive actions still require the Capability Broker and per-action user confirmation.
- No skill script or shell command is executed by this engine.
- Preflight is heuristic structure checking, not scenario simulation or proof of runtime safety.

## Deferred

Automatic skill extraction from completed-task execution traces; isolated scenario simulation; full SKILL.md folder/ZIP support; signed provenance; dependency/conflict management; encrypted skill storage.
