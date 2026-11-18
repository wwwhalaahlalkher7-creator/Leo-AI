# ADR-0013: Portable declarative SKILL.md interchange

**Status:** Accepted for Alpha v0.9.0

## Context

Skills should be portable between Android and Windows and interoperable with the emerging Agent Skills file convention. The current Leo skill library stores declarative workflows in an app-private JSON catalogue. Arbitrary external skill bundles may contain scripts or assets, which would expand Leo's attack surface and could be mistaken for trusted executable tools.

## Decision

- Import and export a single UTF-8 `SKILL.md` file using `name` and `description` YAML frontmatter.
- Support Leo's documented Markdown sections for triggers, instructions, ordered steps, acceptance scenarios and required capability identifiers.
- Imported skills always become `proposed`; never import an active state, validation result, version history, permission grant or action approval.
- Limit each document to 64 KiB and apply field/count limits before saving.
- Do not import or execute scripts, asset folders, reference folders or arbitrary bundled files in this milestone.
- Continue to run Leo's own structural/safety preflight and require explicit user activation.

## Consequences

Users can move declarative skills between supported platforms and exchange basic skills with compatible tools. This is a safe subset, not a complete implementation of every Agent Skills optional field or folder resource. Folder/ZIP handling, provenance/signatures and executable tool integrations remain deferred.
