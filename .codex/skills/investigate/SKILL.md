---
name: investigate
description: Minimal codex-native investigation loop. Use for unknown failures and root-cause narrowing with measurable gates.
---

# Investigate

Run a linear diagnosis loop for unclear failures.

## Workflow

1. Capture symptom, scope, and reproduction context.
2. Gather evidence from logs, errors, and changed files.
3. Rank top hypotheses and map them to validation checks.
4. Run required checks from `../_shared/quality-gates.md`.
5. Decide most likely root cause and gate result.
6. Write artifact to `.reports/codex/investigate/<timestamp>/result.json`.

## Output Contract

Use shared gate schema from `../_shared/quality-gates.md`.

Minimum artifact payload:

```json
{
  "status": "pass|fail",
  "checks_run": [
    "lint",
    "format",
    "types",
    "tests",
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
  "artifact_path": ".reports/codex/investigate/<timestamp>/result.json"
}
```
