---
name: sync
description: Minimal codex-native sync loop. Use to keep project and home Codex configs aligned and report drift.
---

# Sync

Run a linear configuration sync loop.

## Workflow

1. Compare `.codex/` and `~/.codex/` configuration targets.
2. Detect drift in agents, skills, and key config entries.
3. Apply minimal sync actions where approved.
4. Run required checks from `../_shared/quality-gates.md`.
5. Decide gate result (`pass` or `fail`).
6. Write artifact to `.reports/codex/sync/<timestamp>/result.json`.

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
  "artifact_path": ".reports/codex/sync/<timestamp>/result.json"
}
```
