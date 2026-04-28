# Codemap Benchmarks

Empirical validation for the `codemap` plugin — two independent benchmarks, shared task files and results directory.

<details>
<summary><strong>Files</strong></summary>

| File | Purpose |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `run-codemap-agentic.py` | 3-arm agentic benchmark — measures how much structural context (codemap / semble) reduces Claude's exploration overhead |
| `run-codemap-scan-query.py` | Query-level benchmark — measures scan-query correctness, coverage, and latency against a real repo |
| `tasks-agentic.json` | 8 import-graph navigation tasks (T01–T08) used by the agentic benchmark |
| `tasks-code.json` | 15 code-level tasks used by the scan-query benchmark |
| `requirements.txt` | Python dependencies for both benchmarks |
| `results/` | JSON snapshots and markdown reports from past runs |

</details>

## Agentic benchmark (`run-codemap-agentic.py`)

Runs the same 8 import-graph tasks under three arms:

| Arm | What the agent has |
| --------- | ------------------------------------------------------------------- |
| `plain` | Grep / Glob / Bash only |
| `codemap` | + `/codemap:query` skill (structural AST index) |
| `semble` | + `mcp__semble__search` MCP tool (hybrid semantic + lexical search) |

**Metrics**: tool call count, elapsed time, input tokens, exposure recall (erec), report recall (rrec), discovery efficiency (deff).

<details>
<summary><strong>Tasks</strong></summary>

| ID | Type | Primary module | Scenario |
| --- | -------- | ----------------------- | -------------------------------------------------------------------------------------------------- |
| T01 | fix | `checkpoint_connector` | Final epoch skipped when `max_epochs` divisible by check interval — map blast radius before fixing |
| T02 | fix | `slurm` (environments) | SLURM jobs requeued twice on preemption — identify all callers before tightening the guard |
| T03 | feature | `callback` | Adding `on_before_predict_epoch` hook — find all callback implementers that must be updated |
| T04 | feature | `fsdp` (strategies) | Adding new distributed strategy modelled on FSDP — assess coupling before hooking in |
| T05 | refactor | `rank_zero` (utilities) | Moving `rank_zero` to standalone package — scope all importers before extraction |
| T06 | refactor | `cloud_io` (utilities) | Async I/O refactor changing call interface — map every direct caller before changing signatures |
| T07 | review | `fsdp` (strategies) | API surface change review — quantify risk by mapping second-order importers |
| T08 | review | `model_checkpoint` | Changing save-decision logic — map full impact chain before merging |

</details>

### Quick start

```bash
# 1. Install deps
pip install -r benchmarks/requirements.txt

# 2. Build codemap index once (excluded from benchmark timing)
python plugins/codemap/bin/scan-index --root /path/to/repo

# 3. Run all tasks, all arms, all model tiers
python benchmarks/run-codemap-agentic.py --repo-path /path/to/repo --all --report

# 4. Spot-check one task
python benchmarks/run-codemap-agentic.py --repo-path /path/to/repo \
    --tasks T01 --arm plain --model haiku

# Skip semble arm (if not configured)
python benchmarks/run-codemap-agentic.py --repo-path /path/to/repo --all --arm plain
python benchmarks/run-codemap-agentic.py --repo-path /path/to/repo --all --arm codemap
```

<details>
<summary><strong>Enabling the semble arm</strong></summary>

See [semble docs](https://github.com/MinishLab/semble) for full MCP server documentation. One-time setup:

```bash
claude mcp add semble -s user -- uvx --from "semble[mcp]" semble
```

`-s user` registers it globally (all projects). Use `-s project` to scope to this repo only.

**Verify** — the preflight check in `run-codemap-agentic.py` will raise a `RuntimeError` with instructions if semble is not found.

</details>

<details>
<summary><strong>CLI flags</strong></summary>

| Flag | Default | Description |
| ------------------------------ | ------------- | --------------------------------------------------------------- |
| `--repo-path PATH` | required | Absolute path to the repo under test |
| `--index PATH` | auto-detected | Override index path (default: `<repo>/.cache/scan/<name>.json`) |
| `--arm plain\|codemap\|semble` | all three | Run a single arm only |
| `--model haiku\|sonnet\|opus` | all three | Run a single model tier only |
| `--tasks T01 T02 …` | all 8 | Run specific task IDs |
| `--all` | off | Run all tasks (required unless `--tasks` given) |
| `--report` | off | Write markdown report to `results/` after run |
| `--dry-run` | off | Print system prompts, skip actual claude invocations |

</details>

### Output

Each run prints one coloured line:

```
[NN/TT] T01 (fix) | haiku  | codemap  | elapsed= 45.2s | tokens= 120.3k | calls= 3 (grep=  0; glob= 0; bash=  0; skill= 1; semble= 0) | erec= 94% rrec= 88%  sc=100%
```

Colour: yellow = plain · cyan = codemap · green = semble · red = failure.

JSON snapshot written to `results/agentic-YYYY-MM-DD[-N].json` after every run (partial results survive interruptions). Markdown report written to `results/agentic-YYYY-MM-DD[-N].md` with `--report`.

### Failure conditions

| Condition | Meaning |
| ----------------- | ---------------------------------------------------------------------------- |
| `timeout` | claude subprocess exceeded 300 s |
| `non-zero exit` | claude returned non-success subtype |
| `codemap no-call` | codemap arm never called the Skill tool |
| `semble no-call` | semble arm never called `mcp__semble__search` or `mcp__semble__find_related` |

______________________________________________________________________

## Query benchmark (`run-codemap-scan-query.py`)

Validates `scan-query` directly — no LLM involved. Requires a pre-built index.

Suites:

| Suite | What it measures |
| ------------- | -------------------------------------------------------------------------- |
| **Coverage** | Fraction of known importers found by codemap vs cold grep |
| **Accuracy** | Precision / recall / F1 on rdeps queries against grep ground truth |
| **Latency** | Wall-clock time for `central`, `rdeps`, index build, vs cold grep baseline |
| **Injection** | Verifies that develop/oss skills inject `has_rdeps` + `has_deps` fields |

### Quick start

```bash
# Run against a pre-built pytorch-lightning index
python benchmarks/run-codemap-scan-query.py \
    --index /path/to/.cache/scan/pytorch-lightning-master.json \
    --report
```

See `--help` for full flag list and suite selection (`--suite coverage accuracy latency injection`).

______________________________________________________________________

## Results

`results/` holds all past run outputs:

| Pattern | Source |
| ----------------------------- | --------------------------------- |
| `agentic-YYYY-MM-DD[-N].json` | Agentic benchmark JSON snapshot |
| `agentic-YYYY-MM-DD[-N].md` | Agentic benchmark markdown report |
| `code-YYYY-MM-DD[-N].md` | Query benchmark markdown report |

Latest full result: `results/agentic-2026-04-17-5.md` (pytorch-lightning, 85% pass rate, 11/13 scenarios).
