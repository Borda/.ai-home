---
name: calibrate
description: Calibration testing for agents and skills. Generates synthetic problems with known outcomes (quasi-ground-truth), runs targets against them, and measures recall, precision, and confidence calibration — revealing whether self-reported confidence scores track actual quality.
argument-hint: '[agent-name|all|/skill-name] [fast|full]'
allowed-tools: Read, Write, Bash, Grep, Glob, Task
---

<objective>

Validate agents and skills by measuring their outputs against synthetic problems with defined ground truth. The primary signal is **calibration bias** — the gap between self-reported confidence and actual recall. A well-calibrated agent reports 0.9 confidence when it genuinely finds ~90% of issues. A miscalibrated one may report 0.9 while only finding 60%.

Calibration data drives the improvement loop: systematic gaps become instruction updates; persistent overconfidence adjusts effective re-run thresholds stored in MEMORY.md.

</objective>

<inputs>

- **$ARGUMENTS**: optional
  - Omitted / `all` → fast benchmark across all agents
  - `<agent-name>` → fast benchmark for one agent (e.g., `sw-engineer`)
  - `/<skill-name>` → benchmark a skill (e.g., `/audit`, `/review`, `/security`)
  - Append `full` for 10 problems instead of 3 (e.g., `sw-engineer full`, `all full`)

</inputs>

<constants>

- FAST_N: 3 problems per target
- FULL_N: 10 problems per target
- RECALL_THRESHOLD: 0.70 (below → agent needs instruction improvement)
- CALIBRATION_WARN: ±0.15 (bias beyond this → confidence decoupled from quality)
- CALIBRATE_LOG: `.claude/logs/calibrations.jsonl`

Problem domain by agent:

- `sw-engineer` → Python bugs: type errors, logic errors, anti-patterns, bare `except:`, mutable defaults
- `qa-specialist` → coverage gaps: uncovered edge cases, missing exception tests, ML non-determinism
- `linting-expert` → violations: ruff rules, mypy errors, annotation gaps
- `self-mentor` → config issues: broken cross-refs, missing workflow blocks, wrong model, step gaps
- `doc-scribe` → docs gaps: missing docstrings, incomplete NumPy sections, broken examples
- `perf-optimizer` → perf issues: unnecessary loops, repeated computation, wrong dtype, missing vectorisation
- `ci-guardian` → CI issues: non-pinned action SHAs, missing cache, inefficient matrix
- `data-steward` → data issues: label leakage, split contamination, augmentation order bugs
- `ai-researcher` → paper analysis: missed contributions, wrong method attribution
- `solution-architect` → design issues: leaky abstractions, circular dependencies, missing ADR, backward-compat violations without deprecation path
- `web-explorer` → content quality: broken or unverified URLs, outdated docs, incomplete extraction from fetched pages
- `oss-maintainer` → OSS governance: incorrect SemVer decision, missing CHANGELOG entry, bad deprecation path, wrong release checklist item

Skill domains:

- `/audit` → synthetic `.claude/` config with N injected structural issues
- `/review` → synthetic Python module with N cross-domain issues (arch + tests + docs + lint)
- `/security` → synthetic Python code with N OWASP vulnerabilities

</constants>

<workflow>

## Step 1: Parse and select targets

From `$ARGUMENTS`, determine:

- Target list: one agent, one skill, or all (expand "all" to the full agent list above)
- Mode: fast (N=3) or full (N=10)

## Step 2: Generate synthetic problems

For each target, spawn a **general-purpose** problem-generator agent (built-in Claude Code subagent type, not a named project agent):

```
Generate N synthetic calibration problems for <target> targeting <domain>.

For each problem return a JSON object:
{
  "problem_id": "kebab-slug",
  "difficulty": "easy|medium|hard",
  "task_prompt": "instruction to give the target (what to analyse)",
  "input": "the code / config / content inline — no file path",
  "ground_truth": [
    {"issue": "concise description", "location": "function:line or section", "severity": "critical|high|medium|low"}
  ]
}

Rules:
- Issues must be unambiguous — a domain expert would confirm them
- Cover ≥1 easy and ≥1 medium problem; hard is optional
- Each problem has 2–5 known issues; no runtime-only-detectable issues
- Do NOT reveal the issues in the task_prompt — the agent must discover them independently
- Return a valid JSON array only, no prose
```

Write problems to `.claude/calibrate/runs/<timestamp>/<target>/problems.json` (create dirs as needed).

## Step 3: Run target agent / skill on each problem (parallel)

Spawn the target agent (or run the skill) via Task for each problem simultaneously. Agent prompt template:

```
<task_prompt from problem>

<input from problem>
```

The `## Confidence` block is now part of every agent's standard output (per CLAUDE.md output standards) — no need to request it explicitly. If it is absent from the response, treat confidence as 0.5 and note the gap.

For **skill targets**: create a temporary synthetic config or file, point the skill at it, capture findings from the skill's consolidated output.

## Step 4: Score each response

For each (problem, agent_response) pair, spawn a **general-purpose** scorer agent (built-in Claude Code subagent type):

```
Ground truth issues:
<ground_truth JSON from problem>

Agent response:
<full agent response text>

For each ground truth issue: determine whether the agent found it.
A finding counts as "found" if the agent identified the same issue type at the same location
(exact match or semantically equivalent description).

Extract the confidence score from the agent's ## Confidence block.

Return JSON (no prose):
{
  "problem_id": "...",
  "found": [true|false per ground truth issue in order],
  "false_positives": N,
  "confidence": 0.N,
  "recall": found_count / total_issues,
  "precision": found_count / (found_count + false_positives + 1e-9)
}
```

## Step 5: Aggregate and compute calibration

Collect all per-problem scores and compute:

- `mean_recall` = mean of all recall scores
- `mean_confidence` = mean of all confidence scores
- `calibration_bias` = `mean_confidence − mean_recall`
  - `+bias` → overconfident (confidence inflated vs quality)
  - `−bias` → underconfident (conservative; actual quality better than reported)
  - `~0` → calibrated ✓
- `mean_f1` = mean of 2·recall·precision / (recall + precision) per problem

Classify calibration:

- `|bias| < 0.10` → **calibrated ✓**
- `0.10 ≤ |bias| ≤ 0.15` → **borderline** — monitor; no immediate action unless persistent across runs
- `bias > 0.15` → **⚠ overconfident** — adjust effective re-run threshold upward
- `bias < −0.15` → **underconfident** — no action needed; confidence is conservative

## Step 6: Report

```
## Benchmark Report — <target> — <date>
Mode: fast | Problems: N | Total known issues: M

### Per-Problem Results
| Problem ID | Difficulty | Recall | Precision | Confidence | Cal. Δ |
|------------|-----------|--------|-----------|-----------|--------|
| bug-001    | easy       | 1.00   | 0.80      | 0.92      | −0.08 ✓ |
| bug-002    | medium     | 0.67   | 1.00      | 0.88      | +0.21 ⚠ |
| bug-003    | hard       | 0.33   | 0.50      | 0.75      | +0.42 ⚠ |

### Aggregate
| Metric           | Value | Status                    |
|------------------|-------|---------------------------|
| Mean recall      | 0.67  | ⚠ below threshold (0.70)  |
| Mean confidence  | 0.85  |                           |
| Calibration bias | +0.18 | ⚠ overconfident           |
| Mean F1          | 0.71  |                           |

### Calibration Verdict
Confidence decoupled from quality (bias +0.18 > ±0.15 threshold).
→ Treat confidence < 0.85 as the reliable re-run trigger for this agent (not the default 0.70).
→ Document adjusted threshold in MEMORY.md.

### Systematic Gaps (missed in ≥2 problems)
- async error paths: missed in 2/3 problems
- false positive rate: 0.3 per problem (spurious findings reduce trust)

### Improvement Signals
1. [specific gap → add to agent's `<antipatterns_to_flag>`]
2. [domain weakness → candidate for instruction update or model tier upgrade]
```

## Step 7: Log result

Append to `.claude/logs/calibrations.jsonl` (create dir if needed):

```json
{
  "ts": "...",
  "target": "sw-engineer",
  "mode": "fast",
  "mean_recall": 0.67,
  "mean_confidence": 0.85,
  "calibration_bias": 0.18,
  "mean_f1": 0.71,
  "problems": 3
}
```

This log enables tracking calibration improvement over time as agent instructions evolve. Compare runs before and after instruction changes to quantify impact.

</workflow>

<notes>

- **Quasi-ground-truth limitation**: problems are generated by Claude — the same model family as the agents under test. A truly adversarial benchmark requires expert-authored problems. This benchmark reliably catches systematic blind spots and calibration drift even with this limitation.
- **Calibration bias is the key signal**: positive bias (overconfident) → raise the agent's effective re-run threshold in MEMORY.md. Negative bias (underconfident) → confidence is conservative, no action needed. Near-zero → confidence is trustworthy.
- **Do NOT use real project files**: benchmark only against synthetic inputs — no sensitive data and real files have no ground truth.
- **Skill benchmarks** run the skill as a Task subagent against synthetic config or code; scored identically to agent benchmarks.
- **Improvement loop**: systematic gaps → `<antipatterns_to_flag>` | consistent low recall → consider model tier upgrade (sonnet → opus) | large calibration bias → document adjusted threshold in MEMORY.md | re-calibrate after instruction changes to quantify improvement.
- Follow-up chains:
  - Recall < 0.70 → update agent instructions → `/calibrate <agent>` to confirm improvement
  - Calibration bias > 0.15 → add adjusted threshold to MEMORY.md → note in next audit
  - Recommended cadence: run before and after any significant agent instruction change

</notes>
