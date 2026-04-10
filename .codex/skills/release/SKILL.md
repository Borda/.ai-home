---
name: release
description: Minimal codex-native release loop. Use for SemVer-aware release readiness with measurable gates and artifact output.
---

# Release

Run a linear release readiness loop.

## Workflow

1. Determine release scope and target version.
2. Verify changelog and migration notes.
3. Run required checks from `../_shared/quality-gates.md`.
4. Classify release blockers and warnings.
5. Decide gate result (`pass` or `fail`).
6. Write artifact to `.reports/codex/release/<timestamp>/result.json`.

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
  "artifact_path": ".reports/codex/release/<timestamp>/result.json"
}
```
