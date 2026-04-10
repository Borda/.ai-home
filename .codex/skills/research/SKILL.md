---
name: research
description: Minimal codex-native research loop. Use for docs/papers/state-of-the-art scan with source-backed recommendations.
---

# Research

Run a linear research loop with source validation.

## Workflow

1. Define research question and constraints.
2. Gather primary sources.
3. Summarize findings with citations and confidence.
4. Translate findings into actionable next steps.
5. Decide gate result (`pass` or `fail`).
6. Write artifact to `.reports/codex/research/<timestamp>/result.json`.

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
  "artifact_path": ".reports/codex/research/<timestamp>/result.json"
}
```
