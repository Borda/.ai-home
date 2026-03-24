## Mode: routing

Routing accuracy test: measures how accurately a `general-purpose` orchestrator selects the correct `subagent_type` for synthetic task prompts. Not a per-agent quality benchmark; not included in `all`, `agents`, or `skills` — invoke explicitly.

Thresholds (from SKILL.md constants): `ROUTING_ACCURACY_THRESHOLD=0.90`, `ROUTING_HARD_THRESHOLD=0.80`.

### Step 2: Spawn routing pipeline subagent

Mark "Calibrate routing" in_progress. Read `.claude/skills/calibrate/templates/routing-pipeline-prompt.md`. Substitute `<N>` (5 for fast, 10 for full), `<TIMESTAMP>`, `<MODE>`. Spawn a **single** `general-purpose` pipeline subagent with the substituted template as its prompt — it handles all phases internally. Proceed to Step 3 after spawning.

Run dir: `.claude/calibrate/runs/<TIMESTAMP>/routing/`

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

Routing accuracy < 0.90 or hard accuracy < 0.80 → update descriptions for confused pairs → `/calibrate routing` to verify improvement.

Proposals written to: `.claude/calibrate/runs/<TIMESTAMP>/routing/report.md` — Proposals section has targeted wording suggestions per confused pair.
