# 🔬 research — Claude Code Plugin

ML research plugin: two specialist agents and five slash-command skills for literature search, experiment design, methodology review, metric-driven optimization loops, and automated research sweeps — built on a profile-first, judge-gated pipeline that spends compute only on experiments worth running.

> [!NOTE] Requires the `foundry` plugin for base agents. Install order does not matter.

## 🎯 Why

ML improvement is expensive and iterative. The typical failure pattern is not "we ran the wrong experiments" — it is running experiments without a methodology review, without reproducible baselines, without a rollback gate, and without capturing what was learned. Each failed run is not just wasted GPU hours; it is context that disappears.

`research` structures the entire loop:

- **Literature search before implementation** — `topic` fetches current SOTA papers and produces a codebase-mapped implementation plan; you start with evidence, not intuition
- **Judge gate before the expensive run** — `judge` reviews experimental methodology (hypothesis clarity, measurement validity, controls, scope, strategy fit) and returns APPROVED / NEEDS-REVISION / BLOCKED; no run loop starts without a passing judge
- **Auto-rollback on regression** — `run` tracks the target metric from the first iteration; if a change regresses it, the run automatically reverts and continues from the last good checkpoint
- **Team mode for parallel hypotheses** — `--team` spawns multiple scientist instances exploring competing method families simultaneously; the best-performing branch wins
- **Non-interactive sweep pipeline** — `sweep` chains plan → judge → run end-to-end with no user gates; safe to run overnight

## 💡 Key Principles

- **Profile-first on everything** — `plan <file.py>` runs cProfile before asking what to optimize; never optimize based on intuition alone
- **Judge gate is mandatory** — no run loop starts without an APPROVED judgment; NEEDS-REVISION and BLOCKED stop the pipeline with specific, actionable feedback
- **Auto-rollback on regression** — a run that makes things worse rolls back automatically; the baseline is never permanently damaged
- **Evidence before hypothesis** — `topic` fetches current papers before scientist forms any hypothesis; literature search precedes experiment design
- **Data integrity before modeling** — data-steward validates splits, checks for leakage, and verifies completeness before scientist designs experiments; bad data produces confident wrong results
- **Non-interactive by default** — `sweep` is designed for unattended operation; `run` checkpoints continuously so manual stops are always recoverable

## ⚡ Quick start

```bash
# Run from the directory that CONTAINS your Borda-AI-Home clone
claude plugin marketplace add ./Borda-AI-Home
claude plugin install research@borda-ai-home
```

<details>
<summary>Install the full suite</summary>

```bash
claude plugin install foundry@borda-ai-home   # base agents — required first
claude plugin install oss@borda-ai-home
claude plugin install develop@borda-ai-home
claude plugin install research@borda-ai-home
```

</details>

> [!NOTE] Skills are always invoked with the `research:` prefix: `/research:topic`, `/research:plan`, `/research:judge`, `/research:run`, `/research:sweep`.

## 🔁 How to Use

### Literature search and implementation plan

```bash
/research:topic "contrastive learning for tabular data"
/research:topic "efficient fine-tuning methods for LLMs" --team   # parallel scientist instances
```

### Configure an optimization experiment

```bash
/research:plan "improve F1 from 0.82 to 0.87"            # interactive wizard
/research:plan src/train.py                               # profile-first from existing script
/research:plan "reduce inference latency by 30%"          # writes program.md
```

### Review methodology before running

```bash
/research:judge                     # review program.md in current directory
/research:judge coverage.md         # review a specific program file
```

### Run the improvement loop

```bash
/research:run "improve F1 from 0.82 to 0.87"             # from goal string
/research:run program.md                                  # from config file
/research:run program.md --team                           # parallel hypothesis exploration
/research:run program.md --colab                          # GPU workloads via Colab MCP
```

### Resume after crash or manual stop

```bash
/research:run --resume              # reads program_file from state.json
/research:run program.md --resume   # resume specific run
```

### Automated end-to-end sweep

```bash
/research:sweep "increase test coverage to 90%"           # plan → judge → run, no prompts
/research:sweep program.md                                # sweep from existing config
```

### Standard pipeline

```bash
/research:topic "flash attention variants"                # 1. understand SOTA
/research:plan "reduce training step time by 20%"         # 2. configure experiment
/research:judge                                           # 3. validate methodology
/research:run program.md                                  # 4. run loop with auto-rollback
```

### Direct agent dispatch

```bash
use scientist to analyze the methodology in this paper and suggest ablations
use data-steward to verify train/val split integrity and check for data leakage
```

## 🗺️ Overview

### 2 Specialist Agents

| Agent            | Role                                                                                             | Model  |
| ---------------- | ------------------------------------------------------------------------------------------------ | ------ |
| **scientist**    | Paper analysis, hypothesis generation, experiment design, LLM evaluation, inference optimization | opus   |
| **data-steward** | Dataset acquisition, completeness verification, split validation, leakage detection, DVC         | sonnet |

**scientist** (formerly `researcher`) owns the intellectual work: reading papers, forming hypotheses, designing ablations, implementing methods from publications. It delegates data acquisition and pipeline integrity to data-steward.

**data-steward** owns data lifecycle: fetching datasets from external sources, verifying completeness from paginated APIs, versioning with DVC, auditing train/val/test splits, detecting data leakage, and configuring DataLoaders. It does not design experiments — it ensures the data feeding them is correct.

### Five Research Modes

| Mode      | What It Does                                                                                                                                      |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| **topic** | SOTA literature search + codebase-mapped implementation plan; uses web-explorer to fetch current papers, scientist to analyze and design          |
| **plan**  | Interactive config wizard → `program.md`; or `plan <file.py>` for profile-first bottleneck discovery from an existing script                      |
| **judge** | Methodology review: hypothesis clarity, measurement validity, controls, scope fit, strategy appropriateness → APPROVED / NEEDS-REVISION / BLOCKED |
| **run**   | Metric-driven iteration loop with auto-rollback on regression; reads `program.md`; supports `--team` (parallel) and `--colab` (GPU via Colab MCP) |
| **sweep** | Non-interactive pipeline: auto-plan → judge gate → run; safe for overnight runs                                                                   |

### Orchestration Flows

> [!NOTE] These flows document the skill implementations. If any divergence exists between this section and the skill files, the skill files are authoritative.

<details>
<summary><strong>`/research:topic`</strong> — evidence-first research</summary>

```
web-explorer (fetch current papers, docs, benchmarks — writes to file)
→ scientist (deep analysis: methodology, results, applicability to codebase)
→ consolidator reads findings → implementation plan with phased steps
(--team: multiple scientist instances on competing method families)
```

</details>

<details>
<summary><strong>`/research:plan`</strong> — scope and program</summary>

```
Option A (goal string): interactive wizard → elicits metric, baseline, constraints,
                         iteration budget → writes program.md
Option B (profile-first): cProfile on <file.py> → identify top bottlenecks
                           → ask what to optimize → wizard from there
```

</details>

<details>
<summary><strong>`/research:judge`</strong> — methodology gate</summary>

```
Read program.md (or specified file)
Evaluate: hypothesis clarity, metric definition, baseline existence,
          control conditions, scope vs budget, strategy fit
→ APPROVED (proceed to run), NEEDS-REVISION (specific gaps), BLOCKED (fundamental flaw)
```

</details>

<details>
<summary><strong>`/research:run`</strong> — improvement loop</summary>

```
Read program.md → establish baseline metric
Iteration loop (default 20):
  scientist: propose change → sw-engineer: implement → measure metric
  If metric regressed: auto-rollback to last good checkpoint
  If metric improved: commit checkpoint, continue
→ Final report: trajectory, best checkpoint, what was tried
```

</details>

<details>
<summary><strong>`/research:sweep`</strong> — non-interactive</summary>

```
plan (auto-config from goal) → judge gate (must pass) → run loop
No user prompts; designed for unattended operation
```

</details>

### Team Mode

`--team` available on `topic`, `run`, and `sweep`. Spawns multiple scientist instances on competing hypotheses or method families simultaneously. Results are compared and the best-performing approach is selected.

> [!NOTE] Use `--team` for genuinely ambiguous optimizations where the best direction is unknown. Expect higher token cost proportional to the number of parallel branches.

### Colab Integration (GPU)

> [!NOTE] `--colab` routes `run` iterations to Google Colab via the `colab-mcp` server. Opt-in: add `"colab-mcp"` to `enabledMcpjsonServers` in `settings.local.json`, then restart Claude Code.

## 📦 Plugin details

### Upgrade

```bash
cd Borda-AI-Home && git pull
claude plugin install research@borda-ai-home
```

### Uninstall

```bash
claude plugin uninstall research
```

### Structure

```
plugins/research/
├── .claude-plugin/
│   └── plugin.json          ← manifest
├── agents/
│   ├── scientist.md
│   └── data-steward.md
└── skills/
    ├── topic/
    ├── plan/
    ├── judge/
    ├── run/
    └── sweep/
```
