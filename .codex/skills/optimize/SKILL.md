---
name: optimize
description: Minimal codex-native optimization loop. Use for metric-driven improvements with guardrails and measurable gates.
---

# Optimize

Run a linear optimization loop.

## Workflow

1. Define target metric and guard metric.
2. Capture baseline measurement.
3. Apply one minimal optimization change.
4. Re-measure and compare against baseline and guards.
5. Decide gate result (`pass` or `fail`).
6. Write artifact to `.reports/codex/optimize/<timestamp>/result.json`.

## Output Contract

Use shared gate schema from `../_shared/quality-gates.md`.

Minimum artifact payload:

```json
{
  "status": "pass|fail",
  "checks_run": [
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
  "artifact_path": ".reports/codex/optimize/<timestamp>/result.json"
}
```
