---
name: manage
description: Minimal codex-native management loop. Use to create, update, or remove Codex agents/skills/config entries with guardrails.
---

# Manage

Run a linear config-management loop.

## Workflow

1. Parse management intent (create/update/delete).
2. Resolve target files and blast radius.
3. Apply minimal edits and keep references consistent.
4. Run required checks from `../_shared/quality-gates.md`.
5. Decide gate result (`pass` or `fail`).
6. Write artifact to `.reports/codex/manage/<timestamp>/result.json`.

## Output Contract

Use shared gate schema from `../_shared/quality-gates.md`.

Minimum artifact payload:

```json
{
  "status": "pass|fail",
  "checks_run": [
    "review"
  ],
  "checks_failed": [],
  "findings": {
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0
  },
  "confidence": 0.0,
  "artifact_path": ".reports/codex/manage/<timestamp>/result.json"
}
```
