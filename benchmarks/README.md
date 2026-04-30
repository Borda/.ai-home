# Codemap Benchmarks

Empirical validation for the `codemap` plugin — two independent benchmarks, shared task files and results directory.

<details>
<summary><strong>Files</strong></summary>

| File                        | Purpose                                                                                                                            |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `run-codemap-agentic.py`    | 4-arm agentic benchmark — measures how much structural context (codemap / semble / combined) reduces Claude's exploration overhead |
| `run-codemap-scan-query.py` | Query-level benchmark — measures scan-query correctness, coverage, and latency against a real repo                                 |
| `tasks-agentic.json`        | 16 import-graph navigation tasks (T01–T16), 4 types x 4 difficulty tiers, used by the agentic benchmark                            |
| `tasks-code.json`           | 15 code-level tasks used by the scan-query benchmark                                                                               |
| `requirements.txt`          | Python dependencies for both benchmarks                                                                                            |
| `results/`                  | JSON snapshots and markdown reports from past runs                                                                                 |

</details>

## Agentic benchmark (`run-codemap-agentic.py`)

Runs the same 8 import-graph tasks under four arms:

| Arm        | Tools available                                                                           | Protocol                                              |
| ---------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `plain`    | Grep / Glob / Bash only                                                                   | Freeform exploration                                  |
| `codemap`  | + `/codemap:query` skill (structural AST index); semble blocked                           | Skill-first; no semble                                |
| `semble`   | + `mcp__semble__search` MCP tool (hybrid semantic + lexical search); Skill + Bash blocked | Semble-only; iterate until convergence                |
| `combined` | Both `/codemap:query` and `mcp__semble__search`; no restrictions                          | Sequential: codemap anchor → semble gap-fill → report |

**Combined arm protocol**: codemap runs first (deterministic anchor). If exhaustive, write report directly — count-anchoring enforces list completeness. If non-exhaustive, semble gap-fills with varied queries until two consecutive calls add zero new modules (convergence signal), then report. No interleaving between phases.

**Metrics**: tool call count, elapsed time, input tokens, exposure recall (erec), top-10 exposure recall (e@10), report recall (rrec), discovery efficiency (deff).

| Metric | What it measures                                                                  |
| ------ | --------------------------------------------------------------------------------- |
| `erec` | Fraction of ground-truth rdeps found anywhere in the agent output or tool results |
| `e@10` | erec restricted to the 10 most-central rdeps by dep_count                         |
| `rrec` | Fraction of ground-truth rdeps present in the agent final written answer only     |
| `deff` | Tool calls saved vs plain arm, normalised                                         |

<details>
<summary><strong>Tasks</strong></summary>

16 tasks: 4 types (fix / feature / refactor / review) x 4 difficulty tiers (simple / medium / hard / extreme). Difficulty maps to rdep count: simple 1-4 * medium 5-15 * hard 16-50 * extreme 50+.

| ID  | Type     | Difficulty | Primary module                                              | Scenario                                                                                |
| --- | -------- | ---------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| T01 | fix      | simple     | `lightning.pytorch.callbacks.timer`                         | Timer bug: `timedelta` compared as float, premature training stop                       |
| T02 | fix      | medium     | `lightning.pytorch.core.optimizer`                          | LR scheduler fires twice per batch when `optimizer_step` overridden                     |
| T03 | fix      | hard       | `lightning.pytorch.utilities.model_helpers`                 | `is_overridden` returns True for inherited methods — silent callback errors             |
| T04 | fix      | extreme    | `lightning.pytorch.utilities.exceptions`                    | Rename `MisconfigurationException` to `LightningConfigError` — assess full blast radius |
| T05 | feature  | simple     | `lightning.pytorch.callbacks.finetuning`                    | Add `freeze_until_epoch` — scope callers before coding                                  |
| T06 | feature  | medium     | `lightning.fabric.utilities.load`                           | Add `map_location` to checkpoint loaders — assess caller integration surface            |
| T07 | feature  | hard       | `lightning.fabric.utilities.rank_zero`                      | Add `group` parameter to rank-zero logging — find dual-importer consistency risk        |
| T08 | feature  | extreme    | `lightning.fabric.utilities.types`                          | Add `ReduceOp` protocol, deprecate `torch.distributed.ReduceOp`                         |
| T09 | refactor | simple     | `lightning.pytorch.callbacks.lr_finder`                     | Extract `_lr_find` helper into standalone function — classify callers                   |
| T10 | refactor | medium     | `lightning.fabric.plugins.environments.cluster_environment` | Rename `creates_processes_externally` — enumerate all call sites                        |
| T11 | refactor | hard       | `lightning.fabric.utilities.distributed`                    | Replace barrier wrappers with `DistributedBarrier` context manager                      |
| T12 | refactor | extreme    | `lightning.pytorch.callbacks`                               | Split `callbacks.__init__` into training/evaluation sub-modules                         |
| T13 | review   | simple     | `lightning.pytorch.strategies.deepspeed`                    | PR adds ZeRO-3 CPU offload — verify isolation                                           |
| T14 | review   | medium     | `lightning.fabric.plugins.precision.utils`                  | PR makes `_convert_fp_tensor` dtype arg keyword-only — quantify coupling                |
| T15 | review   | hard       | `lightning.pytorch.utilities`                               | PR removes 3 deprecated symbols — identify non-migrated callers                         |
| T16 | review   | extreme    | `lightning.pytorch.utilities.rank_zero`                     | PR replaces `rank_zero_warn` with deduplicating variant — full risk assessment          |

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

# Run only non-semble arms (if semble not configured)
python benchmarks/run-codemap-agentic.py --repo-path /path/to/repo --all --arm plain
python benchmarks/run-codemap-agentic.py --repo-path /path/to/repo --all --arm codemap
```

<details>
<summary><strong>Enabling the semble arm (required for semble + combined)</strong></summary>

See [semble docs](https://github.com/MinishLab/semble) for full MCP server documentation. One-time setup:

```bash
claude mcp add semble -s user -- uvx --from "semble[mcp]" semble
```

`-s user` registers it globally (all projects). Use `-s project` to scope to this repo only.

**Verify** — the preflight check in `run-codemap-agentic.py` will raise a `RuntimeError` with instructions if semble is not found.

</details>

<details>
<summary><strong>CLI flags</strong></summary>

| Flag                                     | Default       | Description                                                     |
| ---------------------------------------- | ------------- | --------------------------------------------------------------- |
| `--repo-path PATH`                       | required      | Absolute path to the repo under test                            |
| `--index PATH`                           | auto-detected | Override index path (default: `<repo>/.cache/scan/<name>.json`) |
| `--arm plain\|codemap\|semble\|combined` | all four      | Run a single arm only                                           |
| `--model haiku\|sonnet\|opus`            | all three     | Run a single model tier only                                    |
| `--tasks T01 T02 …`                      | all 16        | Run specific task IDs                                           |
| `--all`                                  | off           | Run all tasks (required unless `--tasks` given)                 |
| `--report`                               | off           | Write markdown report to `results/` after run                   |
| `--dry-run`                              | off           | Print system prompts, skip actual claude invocations            |

</details>

### Output

Each run prints one coloured line:

```
[NN/TT] T01 (fix) | haiku  | codemap  | elapsed= 45.2s | tokens= 120.3k | calls= 3 (grep=  0; glob= 0; bash=  0; skill= 1; semble= 0) | erec= 94% rrec= 88%  sc=100%
```

Colour: yellow = plain · cyan = codemap · blue = semble · green = combined · red = failure.

JSON snapshot written to `results/agentic-YYYY-MM-DD[-N].json` after every run (partial results survive interruptions). Markdown report written to `results/agentic-YYYY-MM-DD[-N].md` with `--report`.

### Failure conditions

| Condition              | Meaning                                                                                                                   |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `timeout`              | claude subprocess exceeded 300 s                                                                                          |
| `non-zero exit`        | claude returned non-success subtype                                                                                       |
| `codemap no-call`      | codemap arm never called the Skill tool                                                                                   |
| `semble no-call`       | semble arm never called `mcp__semble__search` or `mcp__semble__find_related`                                              |
| `degenerate_grep_loop` | codemap arm made zero skill calls but ≥70% of calls were grep/bash-grep — index ignored, fell back to plain-arm behaviour |

______________________________________________________________________

## Query benchmark (`run-codemap-scan-query.py`)

Validates `scan-query` directly — no LLM involved. Requires a pre-built index.

Suites:

| Suite         | What it measures                                                           |
| ------------- | -------------------------------------------------------------------------- |
| **Coverage**  | Fraction of known importers found by codemap vs cold grep                  |
| **Accuracy**  | Precision / recall / F1 on rdeps queries against grep ground truth         |
| **Latency**   | Wall-clock time for `central`, `rdeps`, index build, vs cold grep baseline |
| **Injection** | Verifies that develop/oss skills inject `has_rdeps` + `has_deps` fields    |

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

| Pattern                       | Source                            |
| ----------------------------- | --------------------------------- |
| `agentic-YYYY-MM-DD[-N].json` | Agentic benchmark JSON snapshot   |
| `agentic-YYYY-MM-DD[-N].md`   | Agentic benchmark markdown report |
| `code-YYYY-MM-DD[-N].md`      | Query benchmark markdown report   |

Latest full result: `results/agentic-2026-04-29.md` (pytorch-lightning, 4 arms × 3 models × 8 tasks = 96 runs).
