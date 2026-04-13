<!-- Step 1 in SKILL.md dispatches to this mode file. Steps here continue from Step 2. -->

## Mode: routing

> **Codex integration: disabled.** Problem generation and scoring are Claude-only for this mode. Routing tests orchestrator dispatch logic — scoring is a deterministic binary match (`selected == expected`), and Codex lacks context about the agent system internals needed to generate realistic routing problems.

Routing accuracy test: measures how accurately a `general-purpose` orchestrator selects the correct `subagent_type` for synthetic task prompts. Not a per-agent quality benchmark; included in `all`. Use the explicit `routing` target to run this mode in isolation.

Thresholds (from SKILL.md constants): `ROUTING_ACCURACY_THRESHOLD=0.90`, `ROUTING_HARD_THRESHOLD=0.80`.

### Step 2: Spawn routing pipeline subagent

Mark "Calibrate routing" in_progress. Read `.claude/skills/calibrate/templates/routing-pipeline-prompt.md`. Substitute `<N>` (5 for fast, 10 for full), `<TIMESTAMP>`, `<MODE>`. Spawn a **single** `general-purpose` pipeline subagent with the substituted template as its prompt — it handles all phases internally. Proceed to Step 3 after spawning.

Run dir: `.reports/calibrate/<TIMESTAMP>/routing/`

### Report format (Step 3 output)

When target is `routing`, replace the standard combined report table with:

```
## Routing Calibration — <date> — <MODE>

| Metric           | Value      | Status |
|------------------|------------|--------|
| Routing accuracy | N/M (XX%)  | ≥90% ✓ / 80–90% ~ / <80% ⚠ |
| Hard accuracy    | N/M (XX%)  | ≥80% ✓ / <80% ⚠ |
| Confusion errors | N          | 0 ✓ / >0 list pairs |
```

Flag routing accuracy < 0.90 or hard accuracy < 0.80 with ⚠. Print confused pair details from the routing report's Confused Pairs section. Mark "Calibrate routing" completed.

### Follow-up chain

Routing accuracy < 0.90 or hard accuracy < 0.80 → update descriptions for confused pairs → `/calibrate routing` to verify improvement. Max 3 re-run cycles; if accuracy is still below threshold after the third, surface the persistent confusion pairs to the user for manual review.

Proposals written to: `.reports/calibrate/<TIMESTAMP>/routing/report.md` — Proposals section has targeted wording suggestions per confused pair.
