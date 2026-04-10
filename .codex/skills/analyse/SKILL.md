---
name: analyse
description: Minimal codex-native analysis loop. Use for issue/PR/problem analysis before implementation with measurable gates.
---

# Analyse

Run a linear analysis loop.

## Workflow

1. Define the analysis question and scope.
2. Gather evidence from code, diffs, and optional external sources.
3. Produce structured findings and confidence.
4. Run required checks from `../_shared/quality-gates.md`.
5. Decide gate result (`pass` or `fail`).
6. Write artifact to `.reports/codex/analyse/<timestamp>/result.json`.

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
  "artifact_path": ".reports/codex/analyse/<timestamp>/result.json"
}
```
