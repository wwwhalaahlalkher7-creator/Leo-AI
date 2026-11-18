# ADR-0005: Learning starts with durable memory and validated skills

- Status: Accepted for Alpha foundation
- Date: 2026-11-15

## Decision

Leo's first learning system consists of inspectable long-term memory and versioned procedural skills. A skill proposed from a task must be tested and explicitly promoted by the user before automatic reuse. Model-weight training / LoRA is not required for v1.0.0.

## Consequences

- Learning remains feasible on both Android and Windows without continuous retraining.
- A failed or stale skill can be disabled or rolled back.
- Personal memory and procedural skills remain separate data types with different retrieval and privacy controls.
