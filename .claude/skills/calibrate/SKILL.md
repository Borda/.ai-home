---
name: calibrate
description: Calibration testing for agents and skills. Generates synthetic problems with known outcomes (quasi-ground-truth), runs targets against them, and measures recall, precision, and confidence calibration — revealing whether self-reported confidence scores track actual quality.
argument-hint: '{all|agents|skills|<name>} [fast|full] [ab] [apply]'
allowed-tools: Read, Write, Edit, Bash, Agent, TaskCreate, TaskUpdate
---

<objective>

Validate agents and skills by measuring their outputs against synthetic problems with defined ground truth. The primary signal is **calibration bias** — the gap between self-reported confidence and actual recall. A well-calibrated agent reports 0.9 confidence when it genuinely finds ~90% of issues. A miscalibrated one may report 0.9 while only finding 60%.

Calibration data drives the improvement loop: systematic gaps become instruction updates; persistent overconfidence adjusts effective re-run thresholds stored in MEMORY.md.

</objective>

<inputs>

- **$ARGUMENTS**: `{all|agents|skills|<name>} [fast|full] [ab] [apply]`

  - **Target** (first token — defaults to `all`):
    - `all` — all agents + all calibratable skills (`/audit`, `/review`)
    - `agents` — all agents only
    - `skills` — calibratable skills only (`/audit`, `/review`)
    - `<agent-name>` — single agent (e.g., `sw-engineer`)
    - `/audit` or `/review` — single skill
  - **Pace** (optional, default `fast`):
    - `fast` — 3 problems per target
    - `full` — 10 problems per target
  - **`ab`** (optional): also run a `general-purpose` baseline and report delta metrics
  - **`apply`** (optional):
    - With `fast` or `full`: run the calibration benchmark then immediately apply the new proposals at the end
    - Without `fast`/`full`: skip benchmark; apply proposals from the most recent past run

  Every invocation surfaces a report: benchmark runs print the new results; bare `apply` prints the saved report from the last run before applying any changes.

</inputs>

<constants>

- FAST_N: 3 problems per target
- FULL_N: 10 problems per target
- RECALL_THRESHOLD: 0.70 (below → agent needs instruction improvement)
- CALIBRATION_BORDERLINE: ±0.10 (|bias| within this → calibrated; between 0.10 and 0.15 → borderline)
- CALIBRATION_WARN: ±0.15 (bias beyond this → confidence decoupled from quality)
- CALIBRATE_LOG: `.claude/logs/calibrations.jsonl`
- AB_ADVANTAGE_THRESHOLD: 0.10 (delta recall or F1 above this → meaningful advantage; below → marginal or none)
- PHASE_TIMEOUT_MIN: 5 (per-phase budget — if spawned subagents haven't all returned, collect partial results and continue)
- PIPELINE_TIMEOUT_MIN: 10 (hard cutoff — pipeline not notified within 10 min of launch is timed out; extendable if the agent explains the delay)
- HEALTH_CHECK_INTERVAL_MIN: 5 (orchestrator polls each running pipeline every 5 min for liveness)
- EXTENSION_MIN: 5

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

</constants>

<workflow>

**Task tracking**: create tasks at the start of execution (Step 1) for each phase that will run:

- "Calibrate agents" — Step 2 (benchmark mode, when target includes agents)
- "Calibrate skills" — Step 2 Skills sub-section (benchmark mode, when target includes skills)
- "Analyse and report" — Steps 3–5 (benchmark mode)
- "Apply findings" — Step 6 (apply mode only)
  Mark each in_progress when starting, completed when done. On loop retry or scope change, create a new task.

## Step 1: Parse targets and create run directory

From `$ARGUMENTS`, determine:

- **Target list** — parse the first token:
  - `all` or omitted → all agents + `/audit` + `/review`
  - `agents` → all agents only (the full agent list in `<constants>`)
  - `skills` → `/audit` and `/review` only
  - Any other token → single agent or skill name
- **Mode**: look for `fast` or `full` in remaining tokens — default `fast`
- **A/B flag**: `ab` present → also spawn a `general-purpose` baseline per problem
- **Apply flag**:
  - `apply` without `fast`/`full` → pure apply mode: skip Steps 2–5; go directly to Step 6
  - `apply` with `fast`/`full` → benchmark + auto-apply: run Steps 2–5 then continue to Step 6

If benchmark will run (i.e., `fast` or `full` is present, with or without `apply`): generate timestamp `YYYYMMDDTHHMMSSZ` (UTC, e.g. `20260303T134448Z`). All run dirs use this timestamp.

Create tasks before proceeding:

- Benchmark only (no `apply`): TaskCreate "Calibrate agents" (if target includes agents), TaskCreate "Calibrate skills" (if target includes skills), TaskCreate "Analyse and report"
- Benchmark + auto-apply (`fast`/`full` + `apply`): TaskCreate "Calibrate agents" (if target includes agents), TaskCreate "Calibrate skills" (if target includes skills), TaskCreate "Analyse and report", TaskCreate "Apply findings"
- Pure apply mode (only `apply`, no `fast`/`full`): TaskCreate "Apply findings" only

## Step 2: Spawn pipeline subagents

Mark "Calibrate agents" in_progress. Issue all agent pipeline subagent spawns.

### Skills

Mark "Calibrate skills" in_progress. Issue all skill pipeline subagent spawns.

Issue all subagents from both agents and skills in a **single response** — agents and skills are independent and run concurrently. One `general-purpose` subagent per target; do not wait for one to finish before spawning the next.

Each subagent receives this self-contained prompt (substitute `<TARGET>`, `<DOMAIN>`, `<N>`, `<TIMESTAMP>`, `<MODE>`, `<AB_MODE>` before spawning — set `<AB_MODE>` to `true` or `false`):

______________________________________________________________________

You are a calibration pipeline runner for `<TARGET>`. Complete all phases in sequence.

AB mode: `<AB_MODE>` — when `true`, also run a `general-purpose` baseline on every problem and compute delta metrics.

Run dir: `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/`

### Phase 1 — Generate problems

Generate `<N>` synthetic calibration problems for `<TARGET>` targeting domain: `<DOMAIN>`.

For each problem produce a JSON object with these fields:

- `problem_id`: kebab-slug string
- `difficulty`: `"easy"`, `"medium"`, or `"hard"`
- `task_prompt`: the instruction to give the target — what to analyse (do NOT reveal the issues)
- `input`: the code / config / content inline (no file paths)
- `ground_truth`: array of objects, each with `issue` (concise description), `location` (function:line or section), and `severity` (`critical`, `high`, `medium`, or `low`)

Rules:

- Issues must be unambiguous — a domain expert would confirm them
- Cover ≥1 easy and ≥1 medium problem; hard is optional
- Each problem has 2–5 known issues; no runtime-only-detectable issues
- **Include exactly 1 out-of-scope problem** (difficulty: `"scope"`): input is clearly outside the agent's domain (e.g., for `linting-expert`, a natural-language question; for `ci-guardian`, a Python data pipeline). Set `ground_truth: []`. A correct response is declining, redirecting, or returning no findings. Any findings reported = false positives (scope failure). This tests scope discipline directly.
- Return a valid JSON array only (no prose)

Write the JSON array to `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/problems.json` (use Bash `mkdir -p` to create dirs).

### Phase 2 — Run target on each problem (parallel)

Spawn one `<TARGET>` named subagent per problem. Issue ALL spawns in a **single response** — no waiting between spawns.

The prompt for each subagent is exactly:

> `<task_prompt from that problem>`
>
> `<input from that problem>`
>
> End your response with a `## Confidence` block: **Score**: 0.N (high >=0.9 / moderate 0.7-0.9 / low \<0.7) and **Gaps**: what limited thoroughness.
>
> Do not self-review or refine before answering — report your initial analysis directly.

Write each subagent's full response to `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/response-<problem_id>.md`.

**Phase timeout (PHASE_TIMEOUT_MIN = 5 min)**: if any spawned subagent has not returned within 5 minutes, do not wait — collect the responses that arrived, mark missing ones as `{"timed_out": true}` in scores.json, and proceed to the next phase with partial data. Never block indefinitely on a single response.

For **skill targets** (target starts with `/`): spawn a `general-purpose` subagent with the skill's SKILL.md content prepended as context, running against the synthetic input from the problem.

### Phase 2b — Run general-purpose baseline (skip if AB_MODE is false)

Spawn one `general-purpose` subagent per problem using the **identical prompt** as Phase 2 (same task_prompt + input + Confidence instruction). Issue ALL spawns in a **single response** — no waiting between spawns.

Write each response to `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/response-<problem_id>-general.md`.

**Phase timeout**: same 5-minute budget applies — proceed with partial baseline data if any response hangs.

### Phase 3 — Score responses (parallel scorer subagents)

Spawn one `general-purpose` scorer subagent per problem. Issue ALL spawns in a **single response** — no waiting between spawns.

Each scorer receives this prompt (substitute `<PROBLEM_ID>`, `<GROUND_TRUTH_JSON>`, `<RUN_DIR>`, `<AB_MODE>`):

> You are scoring agent responses against calibration ground truth.
>
> **Problem ID**: `<PROBLEM_ID>`
>
> **Ground truth** (JSON array — each entry has `issue`, `location`, `severity`):
>
> ```text
> <GROUND_TRUTH_JSON>
> ```
>
> Read the target response from `<RUN_DIR>/response-<PROBLEM_ID>.md`.
> \[If AB_MODE is true: also read `<RUN_DIR>/response-<PROBLEM_ID>-general.md`.\]
>
> For each ground truth issue: mark `true` if the response identified the same issue type at the same location (exact match or semantically equivalent). Count false positives: reported issues with no corresponding ground truth entry. Extract confidence from the `## Confidence` block (use 0.5 if absent).
>
> **For out-of-scope problems** (`ground_truth: []`): recall = N/A (skip from recall aggregate). Count all reported findings as false positives. If the response declines or reports nothing, false_positives = 0 (correct scope discipline). Set severity_accuracy = N/A and format_score = N/A for this problem.
>
> **Measure response length**: count the number of characters in the target response and (if AB_MODE) the general response. This is a token efficiency proxy — shorter is more focused.
>
> **Severity accuracy**: for each found issue (true positive), check whether the response assigned the same severity as ground truth. Allow ±1 tier (tiers ordered: critical > high > medium > low — "critical" vs "high" is a 1-tier miss; "critical" vs "low" is a 3-tier miss). Count exact-or-adjacent matches. `severity_accuracy = correct_severity / found_count` (N/A if found_count = 0). This is orthogonal to recall — an agent can find everything but mislabel severity.
>
> **Format score**: for each found issue (true positive), check whether the response includes all three of: (a) a location reference (line number, function name, or section), (b) a severity or priority label, (c) a fix or action suggestion. `format_score = fully_structured_count / found_count` (N/A if found_count = 0). Measures actionability of findings, not just whether the issue was detected.
>
> Compute: `recall = found / total` (skip if total=0), `precision = found / (found + fp + 1e-9)`, `f1 = 2·r·p / (r+p+1e-9)`.
>
> Return **only** this JSON (no prose):
> `{"problem_id":"<PROBLEM_ID>","found":[true/false,...],"false_positives":N,"confidence":0.N,"recall":0.N,"precision":0.N,"f1":0.N,"severity_accuracy":0.N,"format_score":0.N,"target_chars":N}`
>
> \[If AB_MODE is true, also include: `"recall_general":0.N,"precision_general":0.N,"f1_general":0.N,"confidence_general":0.N,"severity_accuracy_general":0.N,"format_score_general":0.N,"general_chars":N`\]

Collect the compact JSON from each scorer (each ~200 bytes). Write all to `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/scores.json` as a JSON array.

### Phase 4 — Aggregate, write report and result

Compute aggregates (exclude out-of-scope problem from recall/F1/severity/format averages; include in FP count):

- `mean_recall` = mean of `recall` values for in-scope problems only
- `mean_confidence` = mean of all `confidence` values
- `calibration_bias` = `mean_confidence − mean_recall`
- `mean_f1` = mean of `f1` values for in-scope problems only
- `scope_fp` = false_positives from the out-of-scope problem (0 = correct discipline, >0 = scope failure)
- `mean_severity_accuracy` = mean of `severity_accuracy` values for in-scope problems with found_count > 0 (omit if no found issues)
- `mean_format_score` = mean of `format_score` values for in-scope problems with found_count > 0
- `token_ratio` = mean(target_chars) / mean(general_chars) across all problems — if AB_MODE, else omit (ratio < 1.0 = specialist more concise)
- **Recall by difficulty**: `recall_easy`, `recall_medium`, `recall_hard` — mean recall for in-scope problems at each difficulty level (omit if fewer than 1 problem at that level). Not a separate metric — surfaced in report display only to show where the agent struggles.

Verdict:

- `|bias| < 0.10` → `calibrated`
- `0.10 ≤ |bias| ≤ 0.15` → `borderline`
- `bias > 0.15` → `overconfident`
- `bias < −0.15` → `underconfident`

Write full report to `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/report.md` using this structure:

```
## Benchmark Report — <TARGET> — <date>
Mode: <MODE> | Problems: <N> (in-scope) + 1 (out-of-scope) | Total known issues: M

### Per-Problem Results
| Problem ID | Difficulty | Recall | Precision | SevAcc | Fmt  | Confidence | Cal. Δ |
| ...
| <scope-id> | scope      | —      | —         | —      | —    | —          | scope_fp=N |

*Recall: issues found / total. Precision: found / (found + FP). SevAcc: severity match rate for found issues (±1 tier). Fmt: fraction of found issues with location + severity + fix. Cal. Δ: confidence − recall (negative = conservative).*

### Aggregate
| Metric            | Value | Status |
| ...
| Severity accuracy | X.XX  | high ≥0.80 / moderate 0.60–0.80 / low <0.60 |
| Format score      | X.XX  | high ≥0.80 / moderate 0.60–0.80 / low <0.60 |
| Scope discipline  | scope_fp=0 ✓ / scope_fp=N ⚠ | pass/fail |

Recall by difficulty: easy=X.XX | medium=X.XX | hard=X.XX (omit levels with 0 problems)

### A/B Comparison — specialized vs. general-purpose (AB mode only)
| Metric            | Specialized | General | Delta  | Verdict   |
|-------------------|-------------|---------|--------|-----------|
| Mean Recall       | X.XX        | X.XX    | ±X.XX  | significant ✓ / marginal ~ / none ⚠ |
| Mean F1           | X.XX        | X.XX    | ±X.XX  |           |
| Severity accuracy | X.XX        | X.XX    | ±X.XX  | better ✓ / similar ~ / worse ⚠ |
| Format score      | X.XX        | X.XX    | ±X.XX  | better ✓ / similar ~ / worse ⚠ |
| Token ratio       | X.XX        | 1.00    | ±X.XX  | concise ✓ / verbose ⚠ |
| Scope FP          | N           | N       | —      | pass/fail |

*ΔRecall: specialist recall − general recall. SevAcc: correct severity assignment rate (±1 tier) — independent of recall; high recall with low SevAcc means issues found but misprioritized. Fmt: fraction of findings with location + severity + fix — measures actionability, not just detection. Token ratio: specialist chars / general chars (below 1.0 = more focused). Scope FP: findings on out-of-scope input (0 = correct discipline).*
Verdict: `significant` (delta_recall or delta_f1 > 0.10) / `marginal` (0.05–0.10) / `none` (<0.05)

### Systematic Gaps (missed in ≥2 problems)
...

### Improvement Signals
...
```

Write a single-line JSONL result to `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/result.jsonl`:

`{"ts":"<TIMESTAMP>","target":"<TARGET>","mode":"<MODE>","mean_recall":0.N,"mean_confidence":0.N,"calibration_bias":0.N,"mean_f1":0.N,"severity_accuracy":0.N,"format_score":0.N,"problems":<N>,"scope_fp":N,"verdict":"...","gaps":["..."]}`

**If AB_MODE is true**, append these fields to the same JSON line: `"delta_recall":0.N,"delta_f1":0.N,"delta_severity_accuracy":0.N,"delta_format_score":0.N,"token_ratio":0.N,"scope_fp_general":N,"ab_verdict":"significant|marginal|none"`

### Phase 5 — Propose instruction edits

Read the current agent/skill file:

- Agent: `.claude/agents/<TARGET>.md`
- Skill: `.claude/skills/<TARGET>/SKILL.md` (strip the leading `/` from target name)

Read `report.md` from Phase 4 — specifically the **Systematic Gaps** and **Improvement Signals** sections.

Spawn a **self-mentor** subagent with this prompt:

> You are reviewing the agent/skill file below in the context of a calibration benchmark.
>
> **Benchmark findings (from report.md):**
> [paste Systematic Gaps and Improvement Signals sections verbatim]
>
> **Current file content:**
> [paste full file content]
>
> Propose specific, minimal instruction edits that directly address each systematic gap (issues missed in ≥2/N problems) and each false-positive pattern. Be conservative: one targeted change per gap. Do not refactor sections unrelated to the findings.
>
> Format your response as:
>
> ```
> ## Proposed Changes — <TARGET>
>
> ### Change 1: <gap name>
> **File**: `.claude/agents/<TARGET>.md`
> **Section**: `<antipatterns_to_flag>` / `<workflow>` / `<notes>` / etc.
> **Current**: [exact verbatim text to replace; or "none" if inserting new content]
> **Proposed**: [exact replacement text]
> **Rationale**: one sentence — why this closes the gap
>
> [repeat for each gap — omit changes for calibrated targets with no actionable gaps]
> ```

Write the self-mentor response verbatim to `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/proposal.md`.

### Return value

Return **only** this compact JSON (no prose before or after):

`{"target":"<TARGET>","mean_recall":0.N,"mean_confidence":0.N,"calibration_bias":0.N,"mean_f1":0.N,"severity_accuracy":0.N,"format_score":0.N,"scope_fp":N,"verdict":"calibrated|borderline|overconfident|underconfident","gaps":["..."],"proposed_changes":N}`

If AB_MODE is true, also include: `"delta_recall":0.N,"delta_f1":0.N,"delta_severity_accuracy":0.N,"delta_format_score":0.N,"token_ratio":0.N,"scope_fp_general":N,"ab_verdict":"significant|marginal|none"`

______________________________________________________________________

## Step 3: Collect results and print combined report

**Health monitoring** — apply the protocol from CLAUDE.md §8 (Background Agent Health Monitoring). Run dir for liveness checks: `.claude/calibrate/runs/<TIMESTAMP>/<TARGET>/`. Constants below tighten the global defaults for this skill:

```bash
# Initialise checkpoints after all pipeline spawns
LAUNCH_AT=$(date +%s)
for TARGET in <target-list>; do touch /tmp/calibrate-check-$TARGET; done

# Every HEALTH_CHECK_INTERVAL_MIN (5 min): check each still-running pipeline
NEW=$(find .claude/calibrate/runs/<TIMESTAMP>/$TARGET/ -newer /tmp/calibrate-check-$TARGET -type f 2>/dev/null | wc -l | tr -d ' ')
touch /tmp/calibrate-check-$TARGET
ELAPSED=$(( ($(date +%s) - LAUNCH_AT) / 60 ))
[ "$NEW" -gt 0 ] && echo "✓ $TARGET active" || { [ "$ELAPSED" -ge 10 ] && echo "⏱ $TARGET TIMED OUT"; }
```

**On timeout**: read `tail -100 <output_file>` for partial JSON; if none use: `{"target":"<TARGET>","verdict":"timed_out","mean_recall":null,"gaps":["pipeline timed out at 10 min — re-run individually with /calibrate <target> fast"]}`. Timed-out targets appear in the report with ⏱ prefix and null metrics.

After all pipeline subagents have completed or timed out: mark "Calibrate agents" and "Calibrate skills" completed. Mark "Analyse and report" in_progress. Parse the compact JSON summary from each.

Print the combined benchmark report:

```
## Calibrate — <date> — <MODE>

| Target           | Recall | SevAcc | Fmt  | Confidence | Bias    | F1   | Scope | Verdict    | Top Gap              |
|------------------|--------|--------|------|------------|---------|------|-------|------------|----------------------|
| sw-engineer      | 0.83   | 0.91   | 0.87 | 0.85       | +0.02 ✓ | 0.81 | 0 ✓   | calibrated | async error paths    |
| ...              |        |        |      |            |         |      |       |            |                      |

*Recall: in-scope issues found / total. SevAcc: severity match rate for found issues (±1 tier) — high recall + low SevAcc = issues found but misprioritized. Fmt: fraction of found issues with location + severity + fix (actionability). Bias: confidence − recall (+ = overconfident). Scope: FP on out-of-scope input (0 ✓).*
```

**If AB mode**, add `ΔRecall`, `ΔSevAcc`, `ΔFmt`, `ΔTokens`, and `AB Verdict` columns after F1. ΔTokens = token_ratio − 1.0 (negative = specialist more concise).

```
| Target      | Recall | SevAcc | Fmt  | Bias    | F1   | ΔRecall | ΔSevAcc | ΔFmt  | ΔTokens | Scope | AB Verdict |
|-------------|--------|--------|------|---------|------|---------|---------|-------|---------|-------|------------|
| sw-engineer | 0.83   | 0.91   | 0.87 | +0.02 ✓ | 0.81 | +0.05 ~ | +0.12 ✓ | +0.15 ✓ | −0.18 ✓ | 0 ✓ | marginal ~ |

*ΔRecall/ΔSevAcc/ΔFmt: specialist − general (positive = specialist better). ΔTokens: token_ratio − 1.0 (negative = more focused). AB Verdict covers ΔRecall and ΔF1 only; use ΔSevAcc and ΔFmt as supplementary evidence for agents where ΔRecall ≈ 0.*
```

Flag any target where recall < 0.70 or |bias| > 0.15 with ⚠.

After the table, print the full content of each `proposal.md` for targets where `proposed_changes > 0`.

If `apply` was **not** set, print:

```
→ Review proposals above, then run `/calibrate <targets> [fast|full] apply` to apply them.
→ Proposals saved to: .claude/calibrate/runs/<TIMESTAMP>/<TARGET>/proposal.md
```

If `apply` **was** set (benchmark + auto-apply mode), print `→ Auto-applying proposals now…` and proceed to Step 6.

Targets with verdict `calibrated` and no proposed changes get a single line: `✓ <target> — no instruction changes needed`.

## Step 4: Concatenate JSONL logs

Append each target's result line to `.claude/logs/calibrations.jsonl` (create dir if needed):

```bash
mkdir -p .claude/logs
cat .claude/calibrate/runs/<TIMESTAMP>/*/result.jsonl >> .claude/logs/calibrations.jsonl
```

## Step 5: Surface improvement signals

For each flagged target (recall < 0.70 or |bias| > 0.15):

- **Recall < 0.70**: `→ Update <target> <antipatterns_to_flag> for: <gaps from result>`
- **Bias > 0.15**: `→ Raise effective re-run threshold for <target> in MEMORY.md (default 0.70 → ~<mean_confidence>)`
- **Bias < −0.15**: `→ <target> is conservative; threshold can stay at default`

Proposals shown in Step 3 already surface the actionable signals. If `apply` was **not** set, end with:

`→ Run /calibrate <target> [fast|full] apply to run a fresh benchmark and apply proposals.`

Mark "Analyse and report" completed. If `apply` was set: proceed to Step 6.

## Step 6: Apply proposals (apply mode)

Mark "Apply findings" in_progress.

**Determine run directory**:

- Benchmark + auto-apply mode (`fast`/`full` + `apply`): use the TIMESTAMP already generated in Step 1 — proposals were just written by Steps 2–5.
- Pure apply mode (only `apply`, no `fast`/`full`): find the most recent run:

```bash
LATEST=$(ls -td .claude/calibrate/runs/*/ 2>/dev/null | head -1)
TIMESTAMP=$(basename "$LATEST")
```

For each target in the target list, check whether `.claude/calibrate/runs/<TIMESTAMP>/<target>/proposal.md` exists. Collect the set of targets that have a proposal (`found`) and those that don't (`missing`).

Print `⚠ No proposal found for <target> — run /calibrate <target> [fast|full] first` for each missing target.

**Print the run's report before applying**: for each found target, read and print `.claude/calibrate/runs/<TIMESTAMP>/<target>/report.md` verbatim so the user sees the benchmark basis before any file is changed.

**Spawn one `general-purpose` subagent per found target. Issue ALL spawns in a single response — no waiting between spawns.**

Each subagent receives this self-contained prompt (substitute `<TARGET>`, `<PROPOSAL_PATH>`, `<AGENT_FILE>`):

______________________________________________________________________

Read the proposal file at `<PROPOSAL_PATH>` and apply each "Change N" block to `<AGENT_FILE>` (or the skill file if the target is a skill).

For each change:

1. Print: `Applying Change N to <file> [<section>]`
2. Use the Edit tool — `old_string` = **Current** text verbatim, `new_string` = **Proposed** text
3. If **Current** is `"none"` (new insertion): find the section header and insert the **Proposed** text after the last item in that block
4. Skip if **Current** text is not found verbatim → print `⚠ Skipped — current text not found`
5. Skip if **Proposed** text is already present → print `✓ Already applied — skipped`

After processing all changes return **only** this compact JSON:

`{"target":"<TARGET>","applied":N,"skipped":N}`

______________________________________________________________________

After all subagents complete, collect their JSON results and print the final summary:

```
## Fix Apply — <date>

| Target      | File                          | Applied | Skipped |
|-------------|-------------------------------|---------|---------|
| sw-engineer | .claude/agents/sw-engineer.md | 2       | 0       |

→ Run /calibrate <targets> to verify improvement.
```

Mark "Apply findings" completed.

</workflow>

<notes>

- **Timeout handling**: phases have a 5-min budget (`PHASE_TIMEOUT_MIN`); the orchestrator hard-cuts at 10 min of no progress (`PIPELINE_TIMEOUT_MIN`) with a 5-min health pulse (`HEALTH_CHECK_INTERVAL_MIN`). Extension is granted once if the pipeline explicitly explains its delay in its output file — a second unexplained stall still triggers the cutoff. The most common hang cause is a nested subagent waiting indefinitely for a response — the phase timeout prevents this from cascading to the whole run. Timed-out pipelines appear in the report with ⏱ prefix and `verdict:"timed_out"`; re-run individually with `/calibrate <target> fast` after the session.
- **Context safety**: each target runs in its own pipeline subagent — only a compact JSON (~200 bytes) returns to the main context. `all full ab` with 14 targets returns ~2.8KB total, well within limits.
- **Scorer delegation**: Phase 3 delegates scoring to per-problem `general-purpose` subagents. Each scorer reads response files from disk, returns ~200 bytes. The pipeline subagent holds only compact JSONs regardless of N or A/B mode — no context budget concern.
- **Nesting depth**: main → pipeline subagent → target/scorer agents (2 levels). Pipeline spawns both target agents (Phase 2) and scorer agents (Phase 3) at the same depth — no additional nesting.
- **Quasi-ground-truth limitation**: problems are generated by Claude — the same model family as the agents under test. A truly adversarial benchmark requires expert-authored problems. This benchmark reliably catches systematic blind spots and calibration drift even with this limitation.
- **Calibration bias is the key signal**: positive bias (overconfident) → raise the agent's effective re-run threshold in MEMORY.md. Negative bias (underconfident) → confidence is conservative, no action needed. Near-zero → confidence is trustworthy.
- **Do NOT use real project files**: benchmark only against synthetic inputs — no sensitive data and real files have no ground truth.
- **Skill benchmarks** run the skill as a subagent against synthetic config or code; scored identically to agent benchmarks.
- **Improvement loop**: systematic gaps → `<antipatterns_to_flag>` | consistent low recall → consider model tier upgrade (sonnet → opus) | large calibration bias → document adjusted threshold in MEMORY.md | re-calibrate after instruction changes to quantify improvement.
- **Report always**: every invocation surfaces a report — benchmark runs print the new results table; bare `apply` (no `fast`/`full`) prints the saved report from the last run before applying, so the user always sees the basis for any changes before files are touched.
- **`apply` semantics**: `fast apply` / `full apply` = run fresh benchmark then auto-apply the new proposals in one go. `apply` alone (no `fast`/`full`) = apply proposals from the most recent past run without re-running the benchmark.
- **Stale proposals**: `apply` uses verbatim text matching (`old_string` = **Current** from proposal). If the agent file was edited between the benchmark run and `apply`, any change whose **Current** text no longer matches is skipped with a warning — no silent clobbering of intermediate edits.
- Follow-up chains:
  - Recall < 0.70 or borderline → `/calibrate <agent> fast apply` → `/calibrate <agent>` to verify improvement — stop and escalate to user if recall is still < 0.70 after this cycle (max 1 apply cycle per run)
  - Calibration bias > 0.15 → add adjusted threshold to MEMORY.md → note in next audit
  - Recommended cadence: run before and after any significant agent instruction change
- **Internal Quality Loop suppressed during benchmarking**: the Phase 2 prompt explicitly tells target agents not to self-review before answering. This ensures calibration measures raw instruction quality — not the `(agent + loop)` composite. If the loop were enabled, it would inflate both recall and confidence by an unknown ratio, masking real instruction gaps and making it impossible to attribute improvement to instruction changes vs. the loop self-correcting at inference time.
- **Skill-creator complement**: `/calibrate` benchmarks agents and skills via synthetic ground-truth problems; the official `skill-creator` from the anthropics/skills repository <!-- verify at use time --> handles skill-level eval — trigger accuracy, A/B description testing, and description optimization. The two are complementary: run `/calibrate` for quality and recall, `skill-creator` for trigger reliability.
- **A/B mode rationale**: every specialized agent adds system-prompt tokens — if a `general-purpose` subagent matches its recall and F1, the specialization adds no value. `ab` mode quantifies this gap per-target so you can decide whether to keep, retrain, or retire an agent. `significant` (Δ>0.10) confirms the agent's domain depth earns its cost; `marginal` (0.05–0.10) suggests instruction improvements may help; `none` (\<0.05) signals the agent's current instructions add no measurable lift over a vanilla agent — consider strengthening domain-specific antipatterns and re-running. Token cost is informational (logged in scores.json) but not part of the verdict — prioritize recall/F1 delta as the primary signal.
- **A/B blind spot — role-specificity beyond recall**: for any agent whose domain is well-covered by general training data (structured rule application, documented conventions, standard code patterns), `none` AB verdict does NOT mean "retire the agent". Their specialization shows up in severity accuracy, output actionability, token efficiency, and scope discipline — not recall alone. The benchmark measures all four: `delta_severity_accuracy` (correct prioritization), `delta_format_score` (structured, actionable output), `token_ratio` (conciseness), and `scope_fp` (domain refusal). A `none` ΔRecall result paired with positive ΔSevAcc, ΔFmt, and negative ΔTokens still confirms the specialist earns its cost — use ΔSevAcc and ΔFmt as the primary evidence in this case.
- **AB mode nesting**: Phase 2b spawns `general-purpose` baseline agents inside the pipeline subagent. Phase 3 spawns `general-purpose` scorer agents inside the same pipeline subagent. All at 2 levels (main → pipeline → agents) — no additional depth.

</notes>
