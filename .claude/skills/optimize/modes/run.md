<!-- Mode-file include: loaded by .claude/skills/optimize/SKILL.md — not a standalone skill -->

<!-- Implements three modes: plan (P-P0–P-P3), default run (R0–R7), resume (see Resume Mode section) -->

# Run Mode

______________________________________________________________________

## Plan Mode (Steps P-P0–P-P3)

<!-- P-P prefix = Plan-mode steps; R-prefix = Run-mode steps; these labels appear in task-tracking instructions -->

Triggered by `plan <goal|file>`. Interactive wizard to configure a run.

**Task tracking**: create tasks for P-P0, P-P1, P-P2, P-P3 at start.

### Step P-P0: Detect input type

Parse `<input>` from arguments. Determine whether it is a **file path** or a **goal string**:

1. If the argument contains no spaces AND `test -f <argument>` succeeds → **file path**. Enter profiling flow below.
2. Otherwise → **goal string**. Skip to Step P-P1.

**Profiling flow** (file path detected):

Run baseline profiling:

```bash
python3 -m cProfile -s cumtime "$ARGUMENTS" 2>&1 | head -40
time python3 "$ARGUMENTS"
```

Present the top 5 bottleneck functions. Then ask:

```
Top bottleneck functions:
1. <function> — <cumtime>s (<percentage>%)
2. <function> — <cumtime>s (<percentage>%)
...

What would you like to optimize?
  (a) Overall execution time
  (b) Memory usage
  (c) Specific function: <top function name>
  (d) Custom goal: <describe>
```

Construct a goal string from the user's selection:

- (a) → `"Reduce wall-clock execution time of <file>"`
- (b) → `"Reduce peak memory usage of <file>"`
- (c) → `"Optimize <function> in <file> (currently <time>s)"`
- (d) → user's text

Set the constructed string as `<goal>` and proceed to Step P-P1.

### Step P-P1: Parse and scan

**Scope guard (first action)**: Before scanning, check whether `<goal>` is an optimization goal. If the input is clearly not an optimization goal — e.g., a question about code semantics, a regex or algorithm explanation request, a debugging question, or any prompt that does not describe a measurable improvement target — print:

```
⚠ This input does not look like an optimization goal.
/optimize plan expects: "Reduce X" / "Increase Y" / "Improve Z metric".
Use /research for explanatory questions.
```

Then stop. Do not proceed to P-P2 or P-P3.

Parse `<goal>` from arguments. Scan the codebase to detect:

- Language and framework (Python, PyTorch, pytest, etc.)
- Available test runners or benchmark scripts
- Candidate metric commands (pytest coverage, benchmark scripts, eval scripts)
- Candidate guard commands (test suite, lint, type check)
- Files relevant to the goal (scope files)

### Step P-P2: Present proposed config

Present the proposed config as a code block for user review. Include:

```
metric_cmd:      [command that prints a single numeric result]
metric_direction: higher | lower
guard_cmd:       [command that must pass (exit 0) on every kept commit]
max_iterations:  [default 20]
agent_strategy:  [auto | perf | code | ml | arch]
scope_files:     [files the ideation agent may modify]
compute:         local | colab | docker
```

Dry-run both commands before presenting. If either fails, flag the error and propose corrections. Do not proceed to P-P3 until the user confirms or edits the config.

### Step P-P3: Write program.md

Determine the output path: if the user provided a second argument after `<goal>`, use that path; otherwise use `program.md` at the project root.

**Overwrite check**: if the output path already exists, print a one-line warning and use `AskUserQuestion` to ask: (a) Overwrite — proceed; (b) Abort — stop. No silent overwrite.

Write the file using this canonical template, pre-populated from the wizard's findings:

````markdown
# Program: <title from goal>

## Goal
<one-paragraph description of what to improve and why>

## Metric
```
command: <metric_cmd from wizard>
direction: higher | lower
target: <optional numeric goal — campaign stops when crossed>
```

## Guard
```
command: <guard_cmd from wizard>
```

## Config
```
max_iterations: 20
agent_strategy: auto | perf | code | ml | arch
scope_files:
  - <path or glob>
compute: local | colab | docker
colab_hw:                         # optional: H100 | L4 | T4 | A100 (used when compute: colab)
sandbox_network: none | bridge
```

## Notes
<optional free-form text — strategy hints, context, known constraints — ignored by the skill>
````

Print:

```
✓ Program saved to program.md

Next steps:
  /optimize judge program.md   ← validate plan before running (recommended)
  /optimize run program.md     ← start iteration loop directly
```

______________________________________________________________________

## Default Mode (Steps R1–R7)

Triggered by `run <goal|file.md>`.

**Task tracking**: create tasks for R0–R7 at start. If neither `--researcher` nor `--architect` is set, mark R0 as skipped or omit it. If `--codex` is active, also create task `R5b: Codex co-pilot (iter ?/max)` with status `pending`.

### Step R0: Hypothesis pre-phase (`--researcher` / `--architect`)

If neither `--researcher` nor `--architect` is set, skip to Step R1.

> **Research run directory**: Research outputs (`hypotheses.jsonl`, `checkpoint.json`, `journal.md`) go to `.experiments/<run-id>/` — a timestamped directory created at the start of R0, distinct from the main state directory `.experiments/state/<run-id>/`. Referred to as `<RUN_DIR>` throughout this step. See `.claude/rules/optimize-hypothesis-protocol.md` for the full layout.

1. **Build hypothesis queue** — if `--hypothesis <path>` is provided, read that file as the pre-built queue (skip oracle phase). Otherwise, spawn oracle agents based on active flags — agents run in parallel if both flags are set:

   **If `--researcher` is set** — spawn `ai-researcher` (`maxTurns: 15`):

   ```
   Read the program file and the project codebase. Generate 5–10 ML experiment hypotheses grounded in SOTA literature and the specific metric goal. Write to `<RUN_DIR>/hypotheses.jsonl` — one JSON object per line, each with fields: hypothesis, rationale, confidence (float 0–1), expected_delta, priority (int, 1=highest), source: "oracle". Write your full analysis, reasoning, and Confidence block to `<RUN_DIR>/oracle-ai-researcher.md` using the Write tool. Return ONLY: {"status":"done","file":"<path>","count":N,"confidence":0.N}
   ```

   **If `--architect` is set** — spawn `solution-architect` (`maxTurns: 15`) as hypothesis generator (not just feasibility annotator):

   ```
   Read the program file and the project codebase. Analyze the architecture, coupling, and structural design. Generate 5–10 architectural optimization hypotheses (refactoring opportunities, coupling reductions, abstraction improvements) that could improve the metric. Write to `<RUN_DIR>/hypotheses-arch.jsonl` — one JSON object per line with the same schema as the research oracle (hypothesis, rationale, confidence, expected_delta, priority, source: "architect"). Write your full analysis, reasoning, and Confidence block to `<RUN_DIR>/oracle-solution-architect.md` using the Write tool. Return ONLY: {"status":"done","file":"<path>","count":N,"confidence":0.N}
   ```

   **If both `--researcher` and `--architect` are set**: run both oracle agents in parallel (two separate Agent calls). After both complete, merge the two JSONL files into a single `<RUN_DIR>/hypotheses.jsonl`, interleaving by priority (lower priority number = higher priority, round-robin on ties). Update priority values in the merged file to reflect the interleaved order.

   After oracle phase(s), always run the feasibility annotation pass — spawn `solution-architect` (`maxTurns: 10`):

   ```
   Read `<RUN_DIR>/hypotheses.jsonl` and the project codebase. For each hypothesis, annotate with: feasible (bool), blocker (str|null, required if feasible=false), codebase_mapping (str). Write the annotated queue back to the same file preserving order. Write your full analysis, reasoning, and Confidence block to `<RUN_DIR>/oracle-feasibility.md` using the Write tool. Return ONLY: {"status":"done","file":"<path>","feasible":N,"infeasible":N,"confidence":0.N}
   ```

   Note: when `--architect` is the only flag (no `--researcher`), skip the feasibility annotation pass — the architect already validated feasibility during hypothesis generation. Set `feasible: true` on all entries implicitly.

   Both agents follow the handoff envelope protocol (see CLAUDE.md §2). Schema: `.claude/rules/optimize-hypothesis-protocol.md`.

2. **Filter and sort** — load the annotated queue. Infeasible entries (`feasible: false`) remain in the file for audit but are excluded from execution. Sort by `priority` ascending (1 = first to run).

3. **Resume skip** — if `<RUN_DIR>/checkpoint.json` already exists (i.e., resuming a crashed research run), read it. Skip any hypothesis whose 0-indexed position matches a `hypothesis_id` already present in the checkpoint.

4. Store the active queue in memory as `RESEARCH_QUEUE`.

**Per-iteration hypothesis selection** (active when `--researcher` or `--architect` is set, inside Step R5's loop): pop the next hypothesis from `RESEARCH_QUEUE` as the iteration's direction. Append to the Phase 2 ideation prompt: "Focus this iteration on testing this hypothesis: `<hypothesis text>`."

**Per-iteration journal hook** (inside Step R5, after Phase 7 keep-decision): if `--journal` is active, append a journal entry to `<RUN_DIR>/journal.md` after EVERY iteration — regardless of outcome. Entry format: see `.claude/rules/optimize-hypothesis-protocol.md`. Journals record both kept and reverted iterations so the ideation agent can learn what approaches failed and avoid repeating them.

**Per-iteration checkpoint write** (after Phase 7, keep or rollback): if `--researcher` or `--architect` is active, append one line to `<RUN_DIR>/checkpoint.json` per the schema in `.claude/rules/optimize-hypothesis-protocol.md`: `{iteration, hypothesis_id, metric_before, metric_after, status: "passed"|"rolled_back"}`.

### Step R1: Load / build config

**Auto-detect**: if the first non-flag argument ends in `.md`, treat it as a program file path and parse it. Otherwise, treat it as a text goal (existing behavior).

**Clarification prompt** (`.md` file path only): after extracting the `.md` file path argument, inspect the next token (before any `--` flags):

- If absent or starts with `--` → `clarification_prompt = null`
- If a quoted string (starts and ends with `"`) → extract as `clarification_prompt`, strip the surrounding quotes
- If a bare unquoted token (no leading `--`, no surrounding `"`) → accept it as `clarification_prompt` as-is; print a one-line advisory: `ℹ clarification set to "<token>" (tip: quote multi-word hints — e.g. "/optimize run program.md \"focus on sort\" --codex")`

After clarification extraction, any remaining non-flag tokens (tokens that do not start with `--`) are unrecognized. For each such token, print:

```
⚠ Unrecognized argument "<token>" — ignored.
  Known positional args: <program.md path> [clarification]
  Known flags: --team, --colab[=HW], --codex, --compute=local|colab|docker, --docker, --researcher, --architect, --journal, --hypothesis <path>
  If you meant to override the algo, edit the ## Config block in your program.md (algo: sort) and update ## Metric to match.
  If you meant to set a clarification hint, pass it as a quoted string: "/optimize run program.md \"sort improvements\" --codex"
```

Do not stop the run for unrecognized tokens — warn and continue.

**If argument is a `.md` file** — read and parse with these rules:

1. Find each `## <Section>` heading (case-insensitive).
2. Extract the first fenced code block following that heading.
3. Parse the block as `key: value` lines; multi-value fields use indented `  - value` list items. Path values containing spaces must be wrapped in double quotes.
4. Missing required fields (`command` under `## Metric` and `## Guard`) → stop with a clear error.
5. `agent_strategy: auto` (or omitted) → apply keyword heuristics from `<constants>` in `.claude/skills/optimize/SKILL.md` to `## Goal` text and metric command.
6. `target` under `## Metric`: `direction: higher` → stop when metric ≥ target; `direction: lower` → stop when metric ≤ target. If `target` is omitted, run until `max_iterations`.
7. Unrecognized keys and section headings → warn once, then ignore.
8. `## Notes` and the `# Program:` title are never parsed — human-only. (Legacy `# Campaign:` heading is accepted as an alias.)

**If argument is text** — attempt auto-detection of `metric_cmd` and `guard_cmd` from the goal string and codebase scan (same logic as Plan P-P1, but non-interactive — infer reasonable defaults). `config.json` is not read.

**`--colab[=HW]` parsing**: if the flag is `--colab` (no `=`), set `compute = "colab"`, `colab_hw = null`. If the flag is `--colab=<value>`, set `compute = "colab"` and `colab_hw = <value>` (uppercased). If `<value>` is not in the known set `{H100, L4, T4, A100}`, print a one-line warning: `"⚠ Unknown Colab hardware '<value>' — proceeding with default GPU. Known: H100, L4, T4, A100"` and set `colab_hw = null`. `--compute=colab` (without `--colab=HW`) sets `compute = "colab"`, `colab_hw = null`.

The optional `colab_hw` key in `## Config` sets the hardware preference (`H100`, `L4`, `T4`, `A100`); CLI `--colab=HW` overrides it.

Generate a `run-id` = `$(date +%Y%m%d-%H%M%S)`. Create the run directory:

```
.experiments/state/<run-id>/
  state.json         ← iteration count, best metric, status
  experiments.jsonl  ← one line per iteration
  diary.md           ← human-readable research diary (hypothesis → outcome → decision)
```

Convert `program_file` to absolute path before storing: use `os.path.abspath(<argument>)` or shell `realpath` — Resume Mode matches on absolute path.

Write initial `state.json` (`program_file` is the absolute path to the `.md` file, or `null` when launching from a text goal):

```json
{
  "run_id": "<run-id>",
  "goal": "<goal>",
  "config": {},
  "program_file": "<absolute path to program.md, or null>",
  "iteration": 0,
  "best_metric": null,
  "best_commit": null,
  "status": "running",
  "started_at": "<ISO timestamp>",
  "clarification_prompt": null,
  "colab_hw": null,
  "sandbox_mode": "local"
}
```

### Step R2: Precondition checks

Run all checks before touching code. Fail fast with a clear message if any fail:

1. **Clean git**: `git status --porcelain` → must be empty. If dirty: print the dirty files and stop.
2. **Not detached HEAD**: `git rev-parse --abbrev-ref HEAD` → must not be `HEAD`.
3. **Metric command produces numeric output**: run `metric_cmd` once; parse stdout for a float. If no float found: show the output and stop.
4. **Guard command passes**: run `guard_cmd` once; must exit 0. If it fails: show the output and stop.
5. **`--colab` check** (if flag present): verify Colab MCP tools are available by checking for `mcp__colab-mcp__runtime_execute_code`. If unavailable, print setup instructions (see Colab MCP section) and stop.
   If `--colab=HW` was specified (`colab_hw` is non-null): print:
   `  Hardware requested: --colab=<colab_hw>. Ensure your Colab notebook is running with a <colab_hw> GPU before proceeding.`
6. **`--codex` check** (if flag present): verify `claude plugin list 2>/dev/null | grep -q 'codex@openai-codex'`. If unavailable: print `⚠ codex plugin not found. Install it with: /plugin marketplace add openai/codex-plugin-cc` and **stop** — do not proceed with the run.
7. **`compute: docker` check** (if `compute` field = `docker` or `--docker` flag was passed): run `docker ps` using the Bash tool with `timeout: 5000`. If it exits non-zero: print `⚠ Docker daemon not running. Start Docker Desktop and retry.` and **stop** — do not proceed with the run.
8. **Flag conflict check**: if both `--colab` (or `compute: colab`) and `--docker` (or `compute: docker`) are active: print `⚠ --colab and --docker are mutually exclusive. Use one or the other.` and **stop**.
9. **`--journal` prerequisite check** (if `--journal` flag set): verify that `--researcher` or `--architect` is also set. If neither is active: print `⚠ --journal requires --researcher or --architect — omit --journal or add a hypothesis pipeline flag.` and **stop**.

**Initialize `sandbox_mode`** (after all checks above pass):

- `compute: docker` (daemon check passed in #7) → `sandbox_mode = "docker"`. Print: `sandbox: Docker daemon reachable — sandbox mode active`
- All other cases (`compute: local`, `compute: colab`) → `sandbox_mode = "local"`

### Step R3: Select ideation agent

Apply the `agent_strategy` mapping from `<constants>` in `.claude/skills/optimize/SKILL.md`. If `auto`, apply keyword heuristics to `metric_cmd`. Log selected agent to `state.json`.

### Step R4: Establish baseline (iteration 0)

Run `metric_cmd` and `guard_cmd`. Parse the metric value. Append to `experiments.jsonl`:

```json
{
  "iteration": 0,
  "commit": "<HEAD sha>",
  "metric": 0.0,
  "delta": 0.0,
  "guard": "pass",
  "status": "baseline",
  "description": "baseline",
  "agent": null,
  "confidence": null,
  "timestamp": "<ISO>",
  "files": []
}
```

Update `state.json`: `best_metric = <baseline>`, `best_commit = <HEAD sha>`.

Print: `Baseline: <metric_cmd key> = <value>`.

Write initial diary header to `.experiments/state/<run-id>/diary.md`:

```markdown
# Research Diary — <goal>

**Run**: <run-id>
**Started**: <ISO timestamp>
**Baseline**: <metric_key> = <baseline value>

---
```

Then proceed to Step R5.

### Step R5: Iteration loop

For each iteration `i` from 1 to `max_iterations`:

**Phase overview** (all phases run per iteration):

| Phase | Name             | Trigger / description                                                                                                             |
| ----- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 0     | Print header     | Always — print `[→ Iter N/max · starting]`; TaskUpdate R5 subject with current iteration                                          |
| 1     | Build context    | Always — build compact context from git log, JSONL history, and recent diff                                                       |
| 2     | Propose change   | Always — spawn specialist agent to read code, research, investigate, and generate a hypothesis with optional sandbox scripts      |
| 2a    | Sandbox validate | `compute: docker` only — run agent's exploratory scripts in Docker sandbox (read-only mount)                                      |
| 2b    | Apply change     | `compute: docker` only — agent applies the (validated) proposal to real codebase using Write/Edit tools only; no Bash on codebase |
| 2c    | Codex co-pilot   | `--codex` only — **MANDATORY every iteration**; Codex second pass after Phase 2b; must not be skipped                             |
| 3     | Verify files     | Always — check `git diff --stat`; skip to Phase 8 if no files changed (no-op)                                                     |
| 4     | Commit change    | Always — stage modified files and commit before verifying metric                                                                  |
| 5     | Verify metric    | Always — run `metric_cmd` via `compute` mode (local/colab/docker); revert on timeout                                              |
| 6     | Run guard        | Always — run `guard_cmd` via `compute` mode; record pass or fail                                                                  |
| 7     | Evaluate outcome | Always — keep, rework, or revert based on metric + guard result                                                                   |
| 7a    | Write diary      | Always — append one structured entry to `diary.md` recording hypothesis, outcome, and decision rationale                          |
| 8     | Write log        | Always — append JSONL record, update `state.json`, print iteration summary, TaskUpdate R5 with result                             |
| 9     | Progress checks  | Always — summary every SUMMARY_INTERVAL, stuck detection, diminishing-returns warn, early-stop check                              |

**Command execution rules** (apply to ALL phases that run external commands):

1. **No compound commands**: Never `cd /path && command`. Always two separate Bash calls — CWD persists between calls.
2. **Use Bash tool `timeout` parameter**: Never the `timeout` shell command wrapper. Pass `timeout: <ms>` on the Bash tool call itself.
3. **No inline multi-line Python**: For Python logic longer than 3 lines, always write the script to `.experiments/state/<run-id>/scripts/script-<i>.py` using the Write tool, then execute with `python3 <path>` or `uv run python <path>`. Two triggers that Claude Code always flags regardless of allow list: (a) patterns like `=([0-9.]+)` inside `-c "..."` (false Zsh substitution match); (b) multi-line `-c "..."` containing `#`-prefixed comment lines ("quoted newline followed by #-prefixed line" safety check). Writing to a file sidesteps both.
4. **No Zsh constructs**: Never use `=()`, `<()`, `>()` in Bash commands — even inside quoted strings; Claude Code scans raw command text.
5. **Local exploratory scripts that write to real files** (e.g., scanning config combos, patching JSON, running experiments with temp overrides): write to `.experiments/state/<run-id>/scripts/`, execute locally with `python3 <path>`. These scripts legitimately modify project files and must run locally — NOT in Docker sandbox.
6. **Docker sandbox** (when available — see Phase 2a): Phases 4–6 route `metric_cmd`/`guard_cmd` through Docker when `compute: docker`. Phase 2a runs read-only hypothesis scripts in sandbox. Scripts that write to project files always run locally regardless of compute mode.
7. **One change per iteration, no batch loops**: Never write a script that iterates over multiple config variants, parameter combos, or implementations in a single Bash/Python call. Each variant is one campaign iteration — the loop, measurement, and comparison are the campaign framework's job, not the ideation agent's.

#### Phase 0 — Print header

Before any phase work, print the iteration header and update the R5 task subject:

```
[→ Iter N/max_iterations — best so far: <best_metric> (Δ<best_delta_pct>% vs baseline)]
```

TaskUpdate R5 subject: `R5: Iteration N/max_iterations — running`

#### Phase 1 — Build context

Build context for the ideation agent and write it to a file — do NOT accumulate this inline in the main context:

```bash
# Collect signals
git log --oneline -10 > .experiments/state/<run-id>/context-<i>.md
tail -10 .experiments/state/<run-id>/experiments.jsonl >> .experiments/state/<run-id>/context-<i>.md
git diff --stat HEAD~5 HEAD >> .experiments/state/<run-id>/context-<i>.md
```

Prepend a header block to `context-<i>.md` with: goal, current metric vs baseline, delta trend (last 5 kept deltas), and the iteration number. The ideation agent in Phase 2 reads this file directly — the content is never echoed back to the main context.

If `--journal` is active and `<RUN_DIR>/journal.md` exists with 1+ entries: append the last 5 journal entries to `context-<i>.md` under a `## Recent journal (avoid repeating reverted approaches)` heading. The ideation agent reads this and should not reproduce any approach marked `outcome: reverted`.

#### Phase 2 — Propose change

Spawn the selected specialist agent with `maxTurns: 15` and this prompt (adapt as needed):

```
Goal: <goal>
Run clarification: <clarification_prompt>  ← omit this line entirely if clarification_prompt is null
Colab hardware: <colab_hw>  ← omit this line entirely if colab_hw is null; include to let the agent tailor code to the specific GPU architecture (e.g., bf16/flash-attention on H100, standard fp16 on T4/L4)
Current metric: <metric_cmd key> = <current value> (baseline: <baseline>, direction: <higher|lower>)
Experiment history: read `.experiments/state/<run-id>/context-<i>.md` for the full context block.
Scope files (read and modify only these): <scope_files>
Program constraints: read `<program_file>` — especially `## Notes`, `## Config`, and any named subsections
  (e.g., "Hard boundaries", "Optuna's role", "What the agent is free to change"). These take precedence
  over general campaign rules. If program_file is null, skip this step.

**If `sandbox_mode = "local"`**: Read `context-<i>.md`, the scope files, and the program constraints. Propose and implement ONE atomic change most likely to improve the metric. The change must not break `<guard_cmd>`. Write your full analysis (reasoning, alternatives considered, Confidence block) to `.experiments/state/<run-id>/ideation-<i>.md` using the Write tool. Return ONLY the JSON result line:
`{"description":"...","files_modified":[...],"scripts":[],"confidence":0.N}`

**If `sandbox_mode = "docker"`**: Read `context-<i>.md`, the scope files, and the program constraints. Propose ONE atomic change most likely to improve the metric. Write your full analysis and the proposed change description to `.experiments/state/<run-id>/ideation-<i>.md`. Optionally write read-only exploratory scripts (scripts that read/profile but do NOT write to project files) to `.experiments/state/<run-id>/scripts/explore-<i>-<slug>.py`. Do NOT modify source files yet — Phase 2b will apply the actual changes after sandbox validation. Return ONLY the JSON result line:
`{"description":"...","files_modified":[],"scripts":["explore-<i>-<slug>.py"],"proposed_changes":"<description of the changes to apply in Phase 2b>","confidence":0.N}`
```

For `--colab` runs: the ideation agent (especially `ai-researcher`) may call `mcp__colab-mcp__runtime_execute_code` during this phase to prototype GPU code before committing.

<!-- MCP tool call — invoked via MCP protocol, not Bash; requires colab-mcp server enabled in settings.local.json -->

If the Agent tool is unavailable (nested subagent context), implement the change inline and construct the JSON result manually.

#### Phase 2a — Sandbox validate (`sandbox_mode = "docker"` only)

Skip entirely if `sandbox_mode = "local"`.

If Phase 2 returned `"scripts": [...]` with a non-empty list: run each script inside a Docker sandbox with a read-only project mount. For each script path in the list:

```bash
docker run --rm --network <sandbox_network> \
  -v "$(pwd):/workspace:ro" \
  --tmpfs /tmp:rw,size=256m \
  -w /workspace \
  python:3.11-slim \
  python3 /workspace/.experiments/state/<run-id>/scripts/<script>
```

Use the Bash tool `timeout` parameter: `timeout: <VERIFY_TIMEOUT_SEC * 1000>`. Do NOT use the `timeout` shell command.

If any script exits non-zero: append `status: sandbox-failed` to `ideation-<i>.md`, skip to Phase 8 (log) with `status: sandbox-failed`. Do not proceed to Phase 2b.

If `"scripts"` is empty or absent: Phase 2a is a no-op — proceed directly to Phase 2b.

#### Phase 2b — Apply change (`sandbox_mode = "docker"` only)

Skip entirely if `sandbox_mode = "local"` (Phase 2 already applied changes when in local mode).

Spawn the same specialist agent selected in Step R3, with `maxTurns: 10` and this prompt:

```
Read the proposed change in `.experiments/state/<run-id>/ideation-<i>.md`.
Apply the proposed change to the source files.
Use Write and Edit tools ONLY — no Bash execution on the codebase files.
Scope files (read and modify only these): <scope_files>
Return ONLY: {"files_modified":[...]}
```

#### Phase 2c — Codex co-pilot (`--codex` only)

> **MANDATORY — do not skip.** When `--codex` was confirmed available at Step R2, this phase MUST run on every iteration regardless of Phase 2 outcome. Print the narration line and update the R5b task before calling Agent.

Print:

```
[→ Iter N/max · Phase 2c: Codex co-pilot — running]
```

TaskUpdate R5b subject: `R5b: Codex co-pilot — iter N/max_iterations running`, status: `in_progress`

Run Phase 2c on **every iteration** when `--codex` is active. Codex co-pilot — Codex always runs a second pass, building on Claude's kept change or making a fresh attempt after a revert/no-op. Codex wins only if its delta ≥ 0.1% AND guard passes.

- If Claude's Phase 2 change was **kept**: Codex runs a second pass on the current state — building on Claude's work, trying an additional improvement.
- If Claude's Phase 2 change was **reverted or no-op**: the working tree has already been restored to the pre-Phase-2 state; Codex gets a fresh attempt on the clean tree.

Run Codex ideation:

```
Agent(
  subagent_type="codex:codex-rescue",
  prompt="Goal: <goal>. Run clarification: <clarification_prompt>  ← omit this clause entirely if clarification_prompt is null. Current metric: <metric_key>=<current_value> (baseline: <baseline>, direction: <higher|lower>). Scope files: <scope_files>. Read context from .experiments/state/<run-id>/context-<i>.md. Starting state: Claude's change was [kept|reverted|no-op]. [If kept: try to improve further from the current state. If reverted/no-op: propose a fresh approach.] Propose and implement ONE atomic optimization change most likely to improve the metric without breaking <guard_cmd>. Write your full reasoning to .experiments/state/<run-id>/codex-ideation-<i>.md."
)
```

- If Claude's change was **kept** AND Codex proposes additional changes: proceed through Phases 3–7 exactly as for a standard ideation (commit, verify metric, run guard, decide keep/revert). Codex wins only if delta ≥ 0.1% AND guard passes.
- If Claude's change was **kept** AND Codex produces no changes (no-op on top of Claude's kept change): append a `codex-no-op` record and continue — Claude's kept result stands.
- If Claude's change was **reverted or no-op** AND Codex proposes changes: proceed through Phases 3–7 exactly as for a Claude ideation — commit, verify metric, run guard, decide keep/revert.
- If Claude's change was **reverted or no-op** AND Codex returns no file changes: append `status: codex-no-op` to JSONL with `ideation_source: "codex"`, continue loop.
- Set `"ideation_source": "codex"` in the Phase 8 JSONL record for any Codex-proposed change.

After Codex completes (any outcome — kept, reverted, no-op):

TaskUpdate R5b subject: `R5b: Codex co-pilot — iter N done (<outcome>)`

**Stuck escalation with `--codex`**: when Phase 9 detects `STUCK_THRESHOLD` consecutive discards and `--codex` is active, increase Codex ideation effort — add this hint to the Codex prompt for the next iteration: "Previous N attempts were all reverted. Focus on a fundamentally different approach (different file, different algorithm, different abstraction)."

#### Phase 3 — Verify files changed

`git diff --stat`. If no files changed (no-op): append to JSONL with `status: no-op`, skip to Phase 8 (log), continue loop.

#### Phase 4 — Commit change

Stage only the modified files (never `git add -A`):

```bash
git add <files_modified from agent JSON>
git commit -m "experiment(optimize/i<N>): <description>"
```

If pre-commit hooks fail:

- Delegate to `linting-expert` agent: provide the failing hook output and the modified files; ask it to fix the issues. Max 2 attempts.
- If still failing after 2 attempts: `git restore --staged .` + `git checkout -- .` to clean up, append `status: hook-blocked`, continue loop.

#### Phase 5 — Verify metric

**If `sandbox_mode = "docker"`** (set in Step R2):

```bash
docker run --rm --network <sandbox_network> \
  -v "$(pwd):/workspace:ro" \
  -v "$(pwd)/.experiments:/workspace/.experiments:rw" \
  --tmpfs /tmp:rw,size=256m \
  python:3.11-slim \
  sh -c '<metric_cmd>'
```

No resource limits — the container may use all available CPU and memory. Use the Bash tool `timeout` parameter (not the `timeout` command): `timeout: <VERIFY_TIMEOUT_SEC * 1000>`.

**If `sandbox_mode = "local"`**:
Run `metric_cmd` directly using the Bash tool with `timeout: <VERIFY_TIMEOUT_SEC * 1000>` (milliseconds). Do NOT use the `timeout` shell command wrapper.
If the command requires a different working directory, issue a separate `cd <path>` Bash call first (CWD persists).
If metric parsing requires complex Python logic (regex, JSON), write a parser script to `.experiments/state/<run-id>/scripts/parse-metric-<i>.py` using the Write tool and execute it with `python3 <path>` instead of an inline `python3 -c "..."` one-liner.

**If `--colab` active**: Colab routes all execution through the remote GPU runtime via `mcp__colab-mcp__runtime_execute_code`; Docker sandbox is not used. (`--colab` + `--docker` conflict is caught at R2 — they never coexist at runtime.) If `colab_hw` is non-null, prepend a GPU identity check to the `metric_cmd` call: execute `import torch; actual=torch.cuda.get_device_name(0); assert '<colab_hw>' in actual, f'Wrong GPU: expected <colab_hw>, got {actual}'` via `mcp__colab-mcp__runtime_execute_code` before running the metric command. If the assertion fails, print a warning and stop the run: `"⚠ GPU mismatch: requested <colab_hw> but runtime has {actual}. Change the Colab runtime type and re-run."` Do not proceed to Phase 6.

If timeout expires: append `status: timeout`, revert via `git revert HEAD --no-edit`, continue loop.

#### Phase 6 — Run guard

**If `sandbox_mode = "docker"`**: run `guard_cmd` inside the same Docker container as Phase 5 (same flags: `--network <sandbox_network>`, `:ro` project mount, `:rw` `.experiments/` mount, `--tmpfs /tmp`; no resource limits). Check exit code only.

**If `sandbox_mode = "local"`**: run `guard_cmd` directly.

Record pass (exit 0) or fail (non-zero).

#### Phase 7 — Evaluate outcome

| Condition                                             | Action                                                                                                           |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| metric improved AND guard pass                        | Keep commit. Update `state.json`: `best_metric`, `best_commit`.                                                  |
| metric improved AND guard fail                        | Rework: re-spawn agent with guard failure output. Max `GUARD_REWORK_MAX` (2) attempts. If still failing: revert. |
| metric improved AND gain < 0.1% AND change > 50 lines | Discard (simplicity override): `git revert HEAD --no-edit`.                                                      |
| no improvement                                        | Revert: `git revert HEAD --no-edit`.                                                                             |

`git revert HEAD --no-edit` — never `git reset --hard` (preserves history, not in deny list).

#### Phase 7a — Write diary

After the Phase 7 decision, append one entry to `diary.md`:

```markdown
## Iteration N — <ISO timestamp>

**Hypothesis**: <agent's description from Phase 2 JSON — the proposed change and expected improvement>

**Outcome**: <metric_key> = <value> (Δ<delta>% vs baseline) — <kept|reverted|rework|no-op|hook-blocked|timeout>

**Decision**: <one sentence: why the outcome was accepted or rejected — e.g. "Metric improved 1.2% with guard passing" or "Reverted: metric regressed by 0.5%" or "Guard failed after 2 rework attempts">

---
```

For `no-op` iterations (agent made no file changes), write:

```markdown
## Iteration N — <ISO timestamp>

**Hypothesis**: <description> — no files modified

**Outcome**: no-op

**Decision**: Skipped (no changes made)

---
```

#### Phase 8 — Write log

Append one JSONL record to `experiments.jsonl`:

```json
{
  "iteration": 1,
  "commit": "<sha of experiment commit or revert>",
  "metric": 0.0,
  "delta": 0.0,
  "guard": "pass|fail",
  "status": "kept|reverted|rework|no-op|hook-blocked|timeout",
  "description": "<agent description>",
  "agent": "<agent type>",
  "confidence": 0.0,
  "timestamp": "<ISO>",
  "files": [],
  "ideation_source": "claude"
}
```

`ideation_source` is `"claude"` when the Claude specialist agent proposed the change, `"codex"` when Phase 2c (Codex fallback) proposed it.

Update `state.json`: `iteration = i`, `status = running`.

Print iteration summary:

```
[✓ Iter N/max — <kept|reverted|no-op|...> · metric=<value> (Δ<delta>%) · agent=<agent_type>]
```

TaskUpdate R5 subject: `R5: Iter N/max — last: <status>, best: <best_metric>`

#### Phase 9 — Progress checks

- **Summary every SUMMARY_INTERVAL iterations**: print compact table (iteration, metric, delta, status) for the last N iterations.
- **Stuck detection**: if last `STUCK_THRESHOLD` entries all have `status: reverted|no-op|hook-blocked`, trigger escalation (see `<constants>` in `.claude/skills/optimize/SKILL.md`). Log escalation action.
- **Diminishing returns**: if last `DIMINISHING_RETURNS_WINDOW` kept entries each improved < 0.5%, print a warning and suggest stopping. Do not auto-stop — let the user decide.
- **Early stop**: if `target` is set in the program file (or config), stop when the metric crosses it (`direction: higher` → metric ≥ target; `direction: lower` → metric ≤ target). Mark `state.json` `status: goal-achieved`.
- **Context compaction** (every SUMMARY_INTERVAL iterations): write a full iteration summary table to `.experiments/state/<run-id>/progress-<i>.md` and actively discard verbose per-iteration details from working memory. Retain in working memory only: current metric value, iteration count, JSONL file path, and `best_commit`. This prevents linear context growth in long campaigns — full history is always recoverable from `experiments.jsonl` and `ideation-<i>.md` files on disk.

### Step R6: Results report

Pre-compute the branch before writing: `BRANCH=$(git branch --show-current 2>/dev/null | tr '/' '-' || echo 'main')`

Write full report to `.temp/output-optimize-run-$BRANCH-$(date +%Y-%m-%d).md` using the Write tool. Do not print the full report to terminal.

**Report structure:**

```markdown
## Run: <goal>

**Run ID**: <run-id>
**Date**: <date>
**Iterations**: <total> (<kept> kept, <reverted> reverted, <other> other)
**Baseline**: <metric> = <baseline value>
**Best**: <metric> = <best value> (<delta>% improvement)
**Best commit**: <sha>
**Diary**: ".experiments/state/<run-id>/diary.md"
**Codex co-pilot**: active (ran every iteration) — <N> Codex passes run (omit line if --codex not used)
**Codex wins**: <N> Codex proposals kept vs <N> Claude proposals kept

### Experiment History

| #   | Metric | Delta  | Status   | Description | Agent | Confidence |
| --- | ------ | ------ | -------- | ----------- | ----- | ---------- |
| N   | value  | +X.X%  | status   | desc        | agent | 0.N        |

### Summary
[2-3 sentences on what strategies worked, what didn't, what to try next]

### Recommended Follow-ups
- [next action]
```

Print compact terminal summary:

```
---
Run — <goal>
Iterations: <total>  Kept: <kept>  Reverted: <reverted>
Baseline:   <metric_key> = <baseline>
Best:       <metric_key> = <best> (<delta>% improvement, commit <sha>)
Agent:      <agent type used>
→ saved to .temp/output-optimize-run-<branch>-<date>.md
→ diary: .experiments/state/<run-id>/diary.md
---
```

Update `state.json`: `status = completed`.

### Step R7: Codex delegation (optional)

After confirming results, inspect applied changes (`git diff <baseline_commit>...<best_commit> --stat`) and identify tasks Codex can complete (inline comments on non-obvious changes, docstring updates for modified functions, test coverage for the modified path). Read `.claude/skills/_shared/codex-delegation.md` and apply the criteria defined there.

______________________________________________________________________

## Resume Mode

Triggered by `resume` or `resume <file.md>`.

**Locating the run**:

- `resume` (no argument): scan all run dirs in `.experiments/state/`, select the one with the latest `started_at` that has `status: running`.
- `resume <file.md>`: resolve the path to absolute. Scan all run dirs, filter for those whose `state.json` has `"program_file"` matching that absolute path. Pick the one with the latest `started_at`. If no match: stop with a clear error.

1. Read `state.json` from the located run dir. Also restore `clarification_prompt` and `colab_hw` from `state.json` into the active config (may be null if the original run had no clarification or hardware specification).
2. **Re-parse program file**: if `program_file` is non-null, re-read and re-parse that file (Step R1 parsing rules) and update config in memory. This applies any edits the user made between runs. Note: edits to `program.md` while a campaign loop is actively running do not take effect until the next `resume`.
3. **Validate `experiments.jsonl` integrity**: read the last line of `experiments.jsonl` and attempt to parse it as JSON. If the last line is truncated or not valid JSON, warn the user:
   ```
   ⚠ experiments.jsonl last line appears corrupt (truncated or invalid JSON).
   Offer to truncate the corrupt entry (y/n)?
   ```
   If the user confirms, remove the last line before resuming. If they decline, stop and let the user fix it manually.
4. Validate git HEAD: if the current HEAD has diverged from `state.json.best_commit` in an unexpected direction, warn and ask before continuing.
5. Continue the iteration loop from `state.json.iteration + 1`. The `diary.md` file is NOT re-initialized on resume — iteration entries continue appending to the existing file.

______________________________________________________________________

## Team Mode (`--team`)

**When to trigger**: goal spans multiple optimization axes (e.g., "improve training speed" = model architecture + data pipeline + compute efficiency), OR user explicitly passes `--team`.

**Architecture**: two-phase pipeline — parallel hypothesis generation (read-only, no code changes) followed by sequential implementation on the live codebase ordered from minimal to largest change scope. This eliminates cross-axis conflicts: no worktrees, no cherry-picking; every implementation step sees the cumulative state of all prior kept changes.

**Team Mode directory layout**:

- `<RUN_DIR>` (`.experiments/<timestamp>/`) — hypothesis artifacts: `hypotheses-<axis-slug>.jsonl`, `hypothesis-analyst-<axis-slug>.md`, `team-queue.jsonl`, `team-results.jsonl`
- `.experiments/state/<run-id>/` — standard iteration artifacts: `ideation-team-<M>.md`, `diary.md`, `experiments.jsonl`

**Workflow:**

### Phase A: Parallel Hypothesis Generation (read-only)

1. Lead completes Steps R1–R4 (config, preconditions, baseline) solo.

2. Lead identifies 2–3 distinct optimization axes from the goal + codebase analysis. Example for "reduce training time": model architecture · data pipeline · compute efficiency.

3. Lead creates the run output directory:

   ```bash
   RUN_DIR=".experiments/$(date -u +%Y-%m-%dT%H-%M-%SZ)"
   mkdir -p "$RUN_DIR"
   ```

   Store `RUN_DIR` as a run-level variable — do not re-evaluate `date` at later phases. All references to `<RUN_DIR>` in Phases B, C, and D use this same value.

   Write `phase: "A"` to `state.json` immediately after creating `RUN_DIR` — this makes Phase A resume reachable:

   ```
   {"team_mode": {"phase": "A", "run_dir": "<RUN_DIR>"}}
   ```

4. Spawn 2–3 hypothesis agents in parallel (reasoning agents at `opus` per CLAUDE.md §Agent Teams). **No worktrees** — agents perform read-only analysis only. Each agent is assigned one axis and a matching specialist type (same `agent_strategy` mapping from SKILL.md constants).

   Each hypothesis agent's spawn prompt:

   ```
   Read .claude/TEAM_PROTOCOL.md and use AgentSpeak v2.
   You are a hypothesis analyst. Your axis: <axis description>.
   Agent type: <agent type>.
   READ-ONLY: do NOT modify source files. You may only write to your designated output files.

   Analyze the codebase through the lens of your axis. Generate 3–5 concrete, implementable hypotheses.

   Baseline metric: <metric_cmd key> = <baseline>. Direction: <higher|lower>.
   Scope files: <scope_files>.
   Run clarification: <clarification_prompt>  ← omit this line entirely if clarification_prompt is null
   Program constraints: read <program_file> — especially ## Notes, ## Config.

   For each hypothesis, produce a JSON object with ALL these fields:
   - hypothesis: concrete description of the change
   - rationale: why this should improve the metric
   - confidence: float 0–1
   - expected_delta: expected metric change (e.g. "+1–3% val_loss")
   - priority: int (1 = highest within this axis)
   - source: "team"
   - axis: "<axis name>"
   - agent_type: "<your agent type>"
   - change_scope: "small" | "medium" | "large"
   - feasible: true | false
   - blocker: null | "<blocker description if feasible=false>"
   - codebase_mapping: "<files, classes, or functions to change>"

   change_scope guide:
   - small: 1–2 files, localized change (parameter tweak, single-function edit)
   - medium: 3–5 files, cross-cutting but bounded (module refactor, data path change)
   - large: 6+ files or architectural restructuring

   Write all hypotheses as JSONL (one JSON object per line) to `<RUN_DIR>/hypotheses-<axis-slug>.jsonl`.
   Write your full analysis, reasoning, and Confidence block to `<RUN_DIR>/hypothesis-analyst-<axis-slug>.md` using the Write tool.
   Return ONLY: {"status":"done","axis":"<axis>","count":N,"file":"<jsonl path>","confidence":0.N}
   Call TaskUpdate(in_progress) when starting; TaskUpdate(completed) when done.
   ```

**Health monitoring** (CLAUDE.md §8): after spawning all agents in step 4, create a checkpoint:

```bash
LAUNCH_AT=$(date +%s)
CHECKPOINT="/tmp/optimize-check-$LAUNCH_AT"
touch "$CHECKPOINT"
```

Poll every 5 min: `find $RUN_DIR -newer "$CHECKPOINT" -type f | wc -l` — new files = alive; zero = stalled.

- **Hard cutoff: 15 min** of no file activity → timed out
- **One extension (+5 min)**: if `tail -20 <output_file>` shows active progress, grant one extension; second stall = hard cutoff
- **On timeout**: read partial output from `<RUN_DIR>/hypotheses-<axis-slug>.jsonl`; surface with ⏱ in Phase D report — never silently omit a timed-out agent

5. Collect compact JSON envelopes from all hypothesis agents. Do not read the `.md` analysis files into lead context directly — they are inputs to Phase B queue assembly only.

   **`--researcher` / `--architect` interaction**: if R0 pre-phase ran before Team Mode, the R0 hypotheses in `<RUN_DIR>/hypotheses.jsonl` are included in Phase B queue assembly alongside the axis hypotheses. R0 entries lacking `axis`/`agent_type`/`change_scope` are backfilled: `axis: "cross-cutting"`, `agent_type` inferred from `source` field, `change_scope` inferred from `codebase_mapping` length (1–2 targets = small, 3–5 = medium, 6+ = large).

### Phase B: Queue Assembly + User Gate

1. Read all `<RUN_DIR>/hypotheses-*.jsonl` files (and `<RUN_DIR>/hypotheses.jsonl` if present from R0).

2. Filter: exclude entries with `feasible: false` (retain in file for audit). Move entries with `confidence < 0.7` to end of queue.

3. Sort the combined queue:

   - Primary: `change_scope` ascending — `small` first, then `medium`, then `large`
   - Secondary: `expected_delta` descending within scope tier (parse the delta string to extract numeric midpoint, e.g., "+1–3%" → 2.0; if `expected_delta` cannot be parsed to a numeric value, treat it as 0 — sort to end of scope tier)
   - Tertiary (tiebreaker): `confidence` descending

4. Assign sequential `queue_position` (1-indexed) to each entry in sorted order.

5. Print the queue as a formatted table:

   ```
   ┌────┬──────────────────────────────────┬────────────────────┬────────┬───────────────┬──────────┬────────────┐
   │ #  │ Hypothesis                       │ Axis               │ Scope  │ Expected Δ    │ Conf.    │ Agent      │
   ├────┼──────────────────────────────────┼────────────────────┼────────┼───────────────┼──────────┼────────────┤
   │ 1  │ Cache embeddings in forward pass │ data pipeline      │ small  │ +2–4% speed   │ 0.90     │ perf-opt   │
   │ 2  │ Fuse batch-norm + conv layers    │ model architecture │ small  │ +1–2% speed   │ 0.85     │ ai-res     │
   │ …  │ …                                │ …                  │ …      │ …             │ …        │ …          │
   └────┴──────────────────────────────────┴────────────────────┴────────┴───────────────┴──────────┴────────────┘

   Total: N hypotheses (N small, N medium, N large) across N axes
   ```

Before presenting the user gate, update `state.json` `team_mode.phase` to `"B"` — ensures resume can re-display the queue if interrupted:

```
{"team_mode": {"phase": "B", "run_dir": "<RUN_DIR>"}}
```

6. Present the user gate using `AskUserQuestion`:

   ```
   Proceed with implementation?
     (a) Run all N hypotheses in order shown
     (b) Select specific hypotheses (enter numbers, e.g. "1,3,5-7")
     (c) Abort
   ```

   - (a) proceeds with full queue
   - (b) filters to selected entries, preserving sort order
   - (c) stops; write partial report noting that hypotheses were generated but not tested

7. Write the final ordered queue to `<RUN_DIR>/team-queue.jsonl` (one JSON object per line, in execution order). Add `team_mode` to `state.json`:

   ```
   {
     "team_mode": {
       "axes": ["<axis-1>", "<axis-2>"],
       "phase": "C",
       "queue_file": "<RUN_DIR>/team-queue.jsonl",
       "current_hypothesis": 0,
       "total_hypotheses": N
     }
   }
   ```

### Phase C: Sequential Implementation + Guard

For each hypothesis in `<RUN_DIR>/team-queue.jsonl` (in sorted order, 1-indexed as M of N):

1. **Print header**: `[→ Team Hyp M/N · axis: <axis> · scope: <change_scope> · "<hypothesis short>"]`

2. **Spawn specialist agent** matching `agent_type` from the hypothesis. **On the real codebase** — no worktree. The spawn prompt follows the R5 Phase 2 ideation template with the hypothesis pre-specified:

   ```
   Goal: <goal>
   Run clarification: <clarification_prompt>  ← omit if null
   Current metric: <metric_cmd key> = <current_value> (baseline: <baseline>, direction: <higher|lower>)
   Scope files: <scope_files>
   Program constraints: read <program_file>

   Focus this iteration on implementing this hypothesis:
   "<hypothesis text>"
   Rationale: <rationale>
   Expected change scope: <change_scope>
   Target files: <codebase_mapping>

   Propose and implement ONE atomic change. Write analysis to
   `.experiments/state/<run-id>/ideation-team-<M>.md` using the Write tool.
   Return ONLY: {"description":"...","files_modified":[...],"scripts":[],"confidence":0.N}
   ```

3. **Run R5 Phases 3–7a identically** (verify changed files → commit → run metric → run guard → keep/rework/rollback → write diary entry). Phase 8 writes to `experiments.jsonl` and `state.json` as in standard mode; Phase 9 progress checks apply as in standard mode (stuck detection, diminishing returns, context compaction). Phase C does not duplicate this logic — it uses the same per-phase steps with the hypothesis-driven ideation output from step 2.

4. **Log outcome** to `<RUN_DIR>/team-results.jsonl` (append, one line per hypothesis):

   ```json
   {
     "queue_position": 1,
     "hypothesis": "<text>",
     "axis": "<axis>",
     "agent_type": "<agent>",
     "change_scope": "<scope>",
     "metric_before": 0.0,
     "metric_after": 0.0,
     "delta_pct": 0.0,
     "status": "kept|reverted|rework|no-op|hook-blocked|timeout",
     "commit": "<sha or null>",
     "timestamp": "<ISO>"
   }
   ```

5. **If kept**: update the running current metric value for the next hypothesis. Each subsequent hypothesis sees the cumulative state of all prior kept changes.

6. Update `state.json` `team_mode.current_hypothesis` after each hypothesis (enables resume).

7. `--codex`, `--colab`, `--journal` flags apply identically to standard R5.

### Phase D: Consolidated Report

After all hypotheses are processed (or the user stops early with Ctrl-C / user abort):

1. Read `<RUN_DIR>/team-results.jsonl`.

2. Write the full report to `.temp/output-optimize-team-<branch>-<YYYY-MM-DD>.md`:

   ```markdown
   ## Team Run: <goal>

   **Run ID**: <run-id>
   **Date**: <date>
   **Axes**: <comma-separated list>
   **Hypotheses tested**: <kept> kept · <reverted> reverted · <other> other (of <total>)
   **Baseline**: <metric> = <baseline>
   **Final**: <metric> = <final> (<total delta>%)

   ### Per-Hypothesis Results

   | #  | Hypothesis            | Axis    | Scope  | Δ%     | Status   | Commit |
   |----|-----------------------|---------|--------|--------|----------|--------|
   | 1  | Cache embeddings …    | data    | small  | +2.1%  | kept     | abc123 |

   ### Per-Axis Summary

   | Axis               | Tested | Kept | Best Δ% | Cumulative Δ% |
   |--------------------|--------|------|---------|----------------|
   | data pipeline      | 3      | 2    | +2.1%   | +2.9%          |

   ### Summary
   [2–3 sentences on what strategies worked, cross-axis interactions observed]

   ### Recommended Follow-ups
   - [next action if metric goal not fully reached]
   ```

3. Print compact terminal summary:

   ```
   ---
   Team Run — <goal>
   Hypotheses tested: <total>  Kept: <kept>  Reverted: <reverted>
   Axes:     <comma-separated list>
   Baseline: <metric_key> = <baseline>
   Final:    <metric_key> = <final> (<total delta>% improvement)
   → saved to .temp/output-optimize-team-<branch>-<date>.md
   ---
   ```

4. No teammates to shut down — hypothesis agents completed in Phase A; Phase C implementation agents are one-shot spawns.

**CLAUDE.md §8**: Health monitoring for Phase A is described in the Health monitoring block above (after step 4). Phase C implementation agents are standard single-iteration spawns — same timeouts as R5.

**Resume support**: `resume` mode reads `state.json.team_mode` to determine phase:

- `phase: "A"` — re-run Phase A from scratch (read-only, cheap to repeat)
- `phase: "B"` — re-display queue, re-prompt user gate
- `phase: "C"` — resume from `current_hypothesis + 1` (completed entries already in `team-results.jsonl`)
- `phase: "D"` — re-generate report

______________________________________________________________________

## Colab MCP Integration (`--colab`)

**Purpose**: route metric verification and GPU code testing to a Colab notebook runtime instead of local execution. Essential for ML training metrics, CUDA benchmarks, and any workload requiring a GPU.

**Hardware selection** (`--colab=HW`): optionally specify the GPU type for the Colab runtime. Known values: `H100`, `L4`, `T4`, `A100`. If omitted, Colab picks the default GPU. This is advisory — the actual hardware is configured in the Colab notebook UI. Claude Code validates the GPU identity at Phase 5 via a `torch.cuda.get_device_name()` assertion and halts the run if the runtime does not match.

**Setup** (user must complete before running `--colab`):

1. Add `"colab-mcp"` to `enabledMcpjsonServers` in `settings.local.json`:
   ```json
   {
     "enabledMcpjsonServers": [
       "colab-mcp"
     ]
   }
   ```
2. Ensure `colab-mcp` server is defined in `.mcp.json` under `mcpServers` (see project `.mcp.json`).
3. Open a Colab notebook with the runtime connected and execute the MCP connection cell.

**How it works during a run:**

- Step R2 (preconditions): checks for `mcp__colab-mcp__runtime_execute_code` availability.
- Phase 5 (verify metric): calls `mcp__colab-mcp__runtime_execute_code` with `metric_cmd` instead of local `timeout <cmd>`.
- Phase 2 (ideate): `ai-researcher` agent can call `mcp__colab-mcp__runtime_execute_code` to prototype GPU code before committing.
- `VERIFY_TIMEOUT_SEC` = 300 (vs 120 local) to account for network + GPU startup latency.

If Colab MCP is unavailable at Step R2, print:

```
⚠ Colab MCP not available. To enable:
  1. Add "colab-mcp" to enabledMcpjsonServers in settings.local.json
  2. Open a Colab notebook and connect the runtime
  3. Execute the MCP connection cell in the notebook
Then re-run with --colab.
```

______________________________________________________________________

## Notes

- **Commit before verify** is the foundational pattern — it enables a clean `git revert HEAD` if the metric does not improve. Never verify before committing.
- **`git revert` over `git reset --hard`** — preserves experiment history, is not in the deny list.
- **Never `git add -A`** — always stage specific files returned by the agent JSON.
- **Never `--no-verify`** — if a pre-commit hook blocks, delegate to `linting-expert` and fix.
- **Guard ≠ Verify** — guard checks for regressions (tests, lint); verify checks the target metric. Both must pass to keep a commit.
- **Scope files are read-only for guard/test files** — the ideation agent must not modify test files or the metric/guard scripts themselves.
- **JSONL over TSV** — richer structured fields, `jq`-parseable, no delimiter ambiguity; query with `jq -c 'select(.status == "kept")' experiments.jsonl`.
- **State persistence enables resume** — if the loop crashes or times out, `resume` picks up exactly where it stopped.
- **Safety break**: max iterations default is 20; the skill never exceeds MAX_ITERATIONS without a user override in config.
- **Explicit flags = hard requirements**: any flag the user passes (`--colab`, `--docker`, `--codex`, `--researcher`, `--architect`) must be available at R2 precondition checks. If unavailable, stop immediately — never silently degrade to a mode the user did not request.
