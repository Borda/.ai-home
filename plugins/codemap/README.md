# 🧭 CodeMap — Claude Code Plugin

> **You're about to change `models.py`. Do you know which 38 other modules import it?**

Scan your Python project once. Every agent, skill, and developer session answers structural questions — blast radius, coupling, dependency paths — in a single JSON call instead of 20 Glob/Grep passes.

> [!TIP]
>
> Standalone — no other plugins required. Pairs with the `develop` plugin: `develop:feature`, `develop:fix`, `develop:plan`, and `develop:refactor` pick up the index automatically.

> [!NOTE]
>
> **Python first.** `scan-index` uses `ast.parse` to index `.py` files. Support for additional languages (TypeScript, Go, Rust) is planned — Python is the only language indexed today. Non-Python files are not scanned and will not appear in any query result.

## 📋 Contents

- [Why](#-why)
- [Key Principles](#-key-principles)
- [Quick start](#-quick-start)
- [How to Use](#-how-to-use)
- [Real-world demo](#-real-world-demo--pytorch-lightning-646-modules)
- [Benchmark evidence](#-benchmark-evidence)
- [Integrating codemap](#-integrating-codemap)
- [Overview](#-overview)
- [Plugin details](#-plugin-details)

## 🎯 Why

Every session starts the same way: the agent gropes through the codebase with Glob and Grep, assembling a structural picture from scratch. On a 50-module project that burns 20–30 tool calls before the first line of code changes. On a 200-module project it still misses blast-radius risks and import cycles that a structural scan would surface in one query.

`codemap` scans once and gives every future session a structural head start:

- **Blast-radius in one call** — `rdeps mypackage.models` returns everything that imports `models` — know the impact before the first edit
- **Most-central modules** — `central --top 5` returns the five most-imported modules; changing any of them ripples the furthest
- **Coupling map** — `coupled --top 5` returns the modules that import the most others; fragile to upstream changes
- **Import path tracing** — `path mypackage.api mypackage.db` finds the shortest import chain between any two modules
- **Agents start informed** — structural context injected into spawn prompts automatically; no cold-start exploration

## 💡 Key Principles

- **Build once, query forever** — a full scan takes under 60s on a 200-module project; the index persists until code changes
- **Zero external dependencies** — uses only `ast.parse` from the standard library; no pip install required
- **Sidecar-free** — the index is a plain JSON file; `scan-query` is a bundled CLI script; nothing needs to keep running
- **Commit-aware freshness** — staleness detected by `git log`; docs-only and CI commits never trigger a stale warning
- **Fail gracefully** — files that can't be parsed are marked `degraded` with a reason; the scan never aborts
- **JSON everywhere** — every query returns JSON; pipe directly into spawn prompts or scripts

## ⚡ Quick start

```bash
# Run from the directory that CONTAINS your Borda-AI-Rig clone
claude plugin marketplace add ./Borda-AI-Rig
claude plugin install codemap@borda-ai-rig
```

**Inside Claude Code** — `scan-index` and `scan-query` are on PATH automatically via the plugin's `bin/` directory. No shell config needed.

<details>
<summary>In your terminal</summary>

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Picks up the latest installed version automatically
CODEMAP_TOOLS=$(ls -d "$HOME/.claude/plugins/cache/borda-ai-rig/codemap"/*/bin 2>/dev/null | sort -V | tail -1)
[ -n "$CODEMAP_TOOLS" ] && export PATH="$PATH:$CODEMAP_TOOLS"
```

Reload your shell (`source ~/.zshrc`) and `scan-query` is on PATH. No version pins, no manual updates.

</details>

## 🔁 How to Use

### Build the index

```bash
/codemap:scan
```

Run once per project, or after significant refactors. Takes under 60s for a 200-module project.

### Query before you code

```bash
scan-query rdeps mypackage.models   # what breaks if I touch models?
scan-query deps mypackage.auth      # what does auth pull in?
scan-query central --top 5          # which modules have the widest blast radius?
scan-query coupled --top 5          # which modules are most entangled?
scan-query path mypackage.api mypackage.db  # are api and db coupled?
scan-query list                     # enumerate all indexed modules
scan-query symbol MyClass.method    # get function source (~94% token reduction)
scan-query find-symbol "validate.*" # regex search across all symbols
```

All output is JSON — pipe directly into your analysis or pass to an agent.

### Wire into your skills

```bash
/codemap:integration init    # onboard — discovers installed skills/agents, recommends and wires in injection
/codemap:integration check   # verify — scan-query reachable, index fresh, injection present in skills
```

Run `init` once per project to wire codemap into your development skills and agents. Run `check` anytime to confirm the setup is healthy.

### With the develop plugin — automatic

```bash
/develop:feature "add OAuth2 support"
# ↳ scan-query central injected into sw-engineer spawn prompt
# ↳ agent starts with blast-radius picture — no cold Glob/Grep

/develop:refactor "simplify auth module"
# ↳ scan-query central + deps/rdeps for the target module injected
# ↳ agent knows coupling and blast radius before a single read
```

If codemap is not installed, develop skills work exactly as before — zero coupling, zero failure.

## 📊 Real-world demo — pytorch-lightning (646 modules)

Scanned [`pytorch-lightning`](https://github.com/Lightning-AI/pytorch-lightning) — a real production Python project, `src/` layout, 646 modules. Scan time: ~15s.

**5 developer questions, 5 tool calls, answered in full.**

<details>
<summary><strong>Q: Which modules have the widest blast radius?</strong></summary>

```bash
scan-query central --top 5
```

```json
{
  "central": [
    {
      "name": "lightning.pytorch",
      "rdep_count": 245
    },
    {
      "name": "lightning.pytorch.demos.boring_classes",
      "rdep_count": 134
    },
    {
      "name": "lightning.pytorch.utilities.exceptions",
      "rdep_count": 89
    },
    {
      "name": "lightning.fabric.utilities.types",
      "rdep_count": 76
    },
    {
      "name": "lightning.pytorch.callbacks",
      "rdep_count": 73
    }
  ]
}
```

`lightning.pytorch` is imported by 245 of 646 modules. Any breaking change there cascades to 38% of the codebase. `boring_classes.py` — a demo file — affects more modules than the entire callbacks package.

</details>

<details>
<summary><strong>Q: What breaks if I touch <code>Trainer</code>?</strong></summary>

```bash
scan-query rdeps lightning.pytorch.trainer.trainer
```

```json
{
  "imported_by": [
    "lightning.pytorch.trainer",
    "tests.tests_pytorch.loops.test_loop_state_dict",
    "tests.tests_pytorch.loops.test_training_epoch_loop",
    "tests.tests_pytorch.trainer.flags.test_check_val_every_n_epoch",
    "tests.tests_pytorch.trainer.flags.test_val_check_interval"
  ]
}
```

</details>

<details>
<summary><strong>Q: What does <code>CheckpointConnector</code> depend on?</strong></summary>

```bash
scan-query deps lightning.pytorch.trainer.connectors.checkpoint_connector
```

```json
{
  "direct_imports": [
    "fsspec.core",
    "fsspec.implementations.local",
    "lightning.fabric.plugins.environments.slurm",
    "lightning.fabric.utilities.cloud_io",
    "lightning.pytorch",
    "lightning.pytorch.callbacks",
    "lightning.pytorch.trainer",
    "lightning.pytorch.trainer.states",
    "lightning.pytorch.utilities.exceptions",
    "lightning.pytorch.utilities.rank_zero",
    "torch",
    "omegaconf",
    "os",
    "re",
    "typing"
  ]
}
```

24 direct imports — high coupling. Any upstream change in `fsspec`, `omegaconf`, or the fabric utilities layer touches this connector.

</details>

<details>
<summary><strong>Q: How is <code>fabric.connector</code> connected to <code>Trainer</code>?</strong></summary>

```bash
scan-query path lightning.fabric.connector lightning.pytorch.trainer.trainer
```

```json
{
  "path": [
    "lightning.fabric.connector",
    "lightning.fabric.utilities",
    "lightning.fabric.utilities.throughput",
    "lightning.fabric",
    "lightning",
    "lightning.pytorch.trainer",
    "lightning.pytorch.trainer.trainer"
  ]
}
```

7-hop import chain — found instantly. Without the graph this chain has to be traced manually across 7 files.

</details>

<details>
<summary><strong>Q: Which modules import the most things (most fragile to upstream)?</strong></summary>

```bash
scan-query coupled --top 5
```

```json
{
  "coupled": [
    {
      "name": "lightning.pytorch.trainer.trainer",
      "dep_count": 49
    },
    {
      "name": "lightning.pytorch.core.module",
      "dep_count": 45
    },
    {
      "name": "lightning.fabric.strategies.fsdp",
      "dep_count": 40
    },
    {
      "name": "lightning.pytorch.strategies.fsdp",
      "dep_count": 40
    },
    {
      "name": "lightning.fabric.fabric",
      "dep_count": 34
    }
  ]
}
```

`Trainer` both imports 49 modules (most coupled) and is imported by 5 others. It is the highest-risk file to touch in the entire repo — one query surfaced that.

</details>

______________________________________________________________________

### vs. cold Glob/Grep

| Question                  | codemap | Cold Glob/Grep                                                          |
| ------------------------- | ------- | ----------------------------------------------------------------------- |
| Most central modules      | 1 call  | ~20 calls — Glob all files, read each, count manually; still can't rank |
| What breaks if I touch X? | 1 call  | 3–5 Greps; misses transitive importers                                  |
| What does X depend on?    | 1 call  | 1 Read + parse (comparable)                                             |
| Import path A → B         | 1 call  | Infeasible — requires tracing N files by hand                           |
| Most coupled modules      | 1 call  | 646 Reads — one per file to count imports                               |

4 of 5 questions are structurally infeasible without a pre-built graph.

## 📈 Benchmark evidence

Controlled benchmark on **pytorch-lightning** (646 modules) — 8 tasks × 3 model tiers × 2 arms = 48 runs. Tasks cover all four developer workflows: fix, feature, refactor, review.

> Source: `benchmarks/results/agentic-2026-04-17-5.md` · Savings = median `1 − (codemap / plain)` · positive = codemap needs less

### Efficiency savings

| Metric             |  Haiku   |  Sonnet  |   Opus   |
| :----------------- | :------: | :------: | :------: |
| Elapsed time       | **−51%** | **−60%** | **−71%** |
| Tool result tokens | **−85%** | **−84%** | **−93%** |
| Tool calls         |   −43%   |   −61%   |   −77%   |
| Input tokens       |   −68%   |  −5%\*   |   −60%   |

_\* Sonnet input token savings are low due to context expansion on large review tasks — see Known Issues._

Tool result token savings are the most consistent signal (84–93% across all model tiers): codemap returns a compact JSON answer where plain-arm grep passes return full file excerpts, multiplied by the number of tool calls.

### Quality — where it matters most

Plain-arm runs **failed or timed out** on complex tasks; codemap arm completed all tasks:

| Task | Type     | Model  |        Plain recall         | Codemap recall |
| :--- | :------- | :----- | :-------------------------: | :------------: |
| T03  | feature  | haiku  |           **16%**           |      100%      |
| T03  | feature  | opus   |           **16%**           |      100%      |
| T04  | feature  | haiku  |           **40%**           |      100%      |
| T05  | refactor | haiku  |       **0%** (failed)       |      100%      |
| T05  | refactor | sonnet | ⏱ timeout (300s, 27 calls)  |      100%      |
| T05  | refactor | opus   | ⏱ timeout (300s, 101 calls) |      100%      |
| T07  | review   | opus   | ⏱ timeout (300s, 87 calls)  |      100%      |

Recall = fraction of ground-truth reverse-dependencies surfaced in the agent's final answer. Ground truth is deterministic (index-derived); matching uses multi-form surface patterns (2+ path components) to avoid false positives.

Three plain-arm runs hit the hard 300-second timeout. Zero codemap timeouts.

### Known issues (actively being worked on)

- **Input token expansion on large review tasks**: when codemap returns a wide rdep list, some models re-echo the full structured result in their reasoning, consuming more input tokens than the equivalent grep passes would (Sonnet T07: codemap used 6× more input tokens than plain). We are investigating context-trimming for large query results before injection.

- **Refactor tasks benefit less**: on tasks where the challenge is reshaping code rather than locating what to change, structural context provides less uplift (T06 Sonnet: ≈0% elapsed savings; T06 Opus: −48%). Targeted context injection (rdeps + deps of the specific target module, not global central) is on the roadmap for the `develop:refactor` integration.

- **Single-codebase validation**: all 48 runs on `pytorch-lightning`. Savings likely generalise to any large Python monorepo, but small projects (< 50 modules) and non-Python projects have not been benchmarked.

- **Quality metric is rdep recall, not correctness**: the benchmark measures whether the agent surfaces the right blast-radius modules — not whether the resulting code change is correct. End-to-end correctness evaluation is planned.

## 🔌 Integrating codemap

The fastest path is the integration skill — it discovers your installed skills and agents, scores candidates by how much structural context helps, and wires in the correct injection block:

```bash
/codemap:integration init        # interactive onboarding: recommends candidates, asks which to wire in
/codemap:integration check       # audit: scan-query reachable, index fresh, injection present in skills
```

`init` builds the index if it is missing and handles first-run setup end-to-end. Run `check` after any change to confirm everything is correctly wired.

### Query reference — which command to use when

| Situation                              | Query                                         |
| -------------------------------------- | --------------------------------------------- |
| "What breaks if I change X?"           | `rdeps X`                                     |
| "What does X pull in?"                 | `deps X`                                      |
| "Are A and B already coupled?"         | `path A B` — `null` means not connected       |
| "What's the riskiest module to touch?" | `central --top 10` (highest rdep_count)       |
| "What's the most entangled module?"    | `coupled --top 10` (highest internal imports) |
| "List all modules in the project"      | `list`                                        |
| "What does function F call?"           | `fn-deps module::F` (v3 index)                |
| "What calls function F?"               | `fn-rdeps module::F` (v3 index)               |
| "Most-called functions?"               | `fn-central --top 10` (v3 index)              |
| "Transitive callers of F?"             | `fn-blast module::F` (v3 index)               |
| "Get source of a function/class?"      | `symbol MyClass.method`                       |
| "Find symbols matching a pattern?"     | `find-symbol "validate.*"`                    |
| "List all symbols in module X?"        | `symbols X`                                   |
| "Exclude tests from blast-radius?"     | `central --exclude-tests --top 10`            |

<details>
<summary>Manual injection — adding codemap to a custom skill or agent</summary>

### Adding codemap to a custom skill

Drop this soft-check block into any `SKILL.md` **before the first agent spawn**. It injects structural context when available and silently skips when codemap is not installed:

```bash
# Structural context (codemap — Python projects only, silent skip if absent)
PROJ=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null) || PROJ=$(basename "$PWD")
if command -v scan-query >/dev/null 2>&1 && [ -f ".cache/scan/${PROJ}.json" ]; then
    scan-query central --top 5  # timeout: 5000
fi
```

If results are returned: prepend a `## Structural Context (codemap)` block to your agent spawn prompt. For skills that know the target module up front, also add targeted queries:

```bash
scan-query rdeps "$TARGET_MODULE" 2>/dev/null   # what depends on it?
scan-query deps  "$TARGET_MODULE" 2>/dev/null   # what does it import?
```

### Adding codemap to a custom agent

In any agent `.md` file, add to the workflow instructions:

```markdown
If a codemap index exists (`.cache/scan/<project>.json`), run `scan-query central --top 5`
and `scan-query rdeps <target_module>` before analyzing — do not Glob/Grep for structural
information that can be queried directly. If the index is absent, proceed normally.
```

Or inject context programmatically in a skill bash block before spawning the agent:

```bash
PROJ=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null) || PROJ=$(basename "$PWD")
CODEMAP_CONTEXT=""
if command -v scan-query >/dev/null 2>&1 && [ -f ".cache/scan/${PROJ}.json" ]; then
    CODEMAP_CONTEXT=$(scan-query rdeps "$TARGET_MODULE" 2>/dev/null)
fi
# then pass $CODEMAP_CONTEXT in the spawn prompt as "## Structural Context"
```

</details>

## 🗺️ Overview

### 3 Skills

| Skill           | Trigger                            | What it does                                                                    |
| --------------- | ---------------------------------- | ------------------------------------------------------------------------------- |
| **scan**        | `/codemap:scan`                    | Runs `ast.parse` across all Python files; writes `.cache/scan/<project>.json`   |
| **query**       | `/codemap:query`                   | Queries the index; checks staleness on every call; returns JSON                 |
| **integration** | `/codemap:integration check\|init` | Audits install health (`check`) or onboards codemap into skills/agents (`init`) |

### CLI Commands

| Command                                   | Question it answers                                             |
| ----------------------------------------- | --------------------------------------------------------------- |
| `central [--top N]`                       | Which modules are imported by the most others? (blast radius)   |
| `coupled [--top N]`                       | Which modules import the most others? (coupling)                |
| `deps <module>`                           | What does this module import?                                   |
| `rdeps <module>`                          | What imports this module?                                       |
| `path <from> <to>`                        | What is the shortest import chain between two modules?          |
| `list`                                    | Enumerate all indexed modules                                   |
| `fn-deps <qname>`                         | What does this function call? (call graph — v3 index)           |
| `fn-rdeps <qname>`                        | What functions call this one? (call graph — v3 index)           |
| `fn-central [--top N]`                    | Most-called functions globally (call graph — v3 index)          |
| `fn-blast <qname>`                        | Transitive reverse-call BFS with depth (call graph — v3 index)  |
| `symbol <name> [--exclude-tests]`         | Get function/class/method source by name (~94% token reduction) |
| `symbols <module>`                        | List all symbols in a module (no file I/O)                      |
| `find-symbol <pattern> [--exclude-tests]` | Regex search across all symbol names in index                   |

### Index schema (`.cache/scan/<project>.json`)

```json
{
  "scan_version": 3,
  "scanned_at": "2026-04-15T12:00:00+00:00",
  "project": "mypackage",
  "src_layout": true,
  "file_shas": {
    "src/mypackage/auth.py": "a1b2c3d4"
  },
  "modules": [
    {
      "name": "mypackage.auth",
      "path": "src/mypackage/auth.py",
      "loc": 234,
      "rdep_count": 8,
      "rcall_count": 12,
      "dep_count": 5,
      "direct_imports": [
        "mypackage.models",
        "mypackage.config"
      ],
      "is_entry_point": false,
      "has_star_imports": false,
      "is_test": false,
      "status": "ok",
      "symbols": [
        {
          "name": "validate_token",
          "qualified_name": "validate_token",
          "type": "function",
          "start_line": 15,
          "end_line": 42,
          "calls": [
            {
              "target": "mypackage.db::fetch_user",
              "resolution": "import"
            },
            {
              "target": "mypackage.auth::_check_cache",
              "resolution": "local"
            }
          ]
        }
      ]
    },
    {
      "name": "mypackage.generated.proto",
      "path": "src/mypackage/generated/proto.py",
      "status": "degraded",
      "reason": "SyntaxError: invalid syntax"
    }
  ]
}
```

`rdep_count` — how many project modules import this one (blast radius proxy). `dep_count` — how many modules this one imports (coupling proxy). `rcall_count` — how many functions across the project call any function in this module (function-level blast radius proxy, v3). `file_shas` — git blob SHAs per file used for incremental rebuild.

### Staleness detection

`scan-query` checks on every call. For v3 indexes (with `file_shas`):

```bash
git ls-files -s -- '*.py'   # compare blob SHAs against stored file_shas
```

Reports exactly which N files are stale and suggests `--incremental`. For v2 indexes, falls back to:

```bash
git log --since=<scanned_at> --name-only --pretty="" -- '*.py' \
    ':!docs/' ':!*.md' ':!.github/' ':!**/*.yml'
```

In both cases, a warning is printed to stderr and results are returned — the agent decides whether to re-scan.

## ⚡ Function-level call graph (v3)

Build once — query who calls what down to individual function level.

```bash
scan-query fn-deps mypackage.auth::validate_token    # what does validate_token call?
scan-query fn-rdeps mypackage.db::fetch_user         # who calls fetch_user?
scan-query fn-central --top 10                       # most-called functions across project
scan-query fn-blast mypackage.db::fetch_user         # transitive callers, BFS with depth
```

`fn-blast` answers: "If I change `fetch_user`, which functions are transitively affected?" — finer than module-level `rdeps`.

Use `module::function` format for qualified names (e.g. `mypackage.auth::AuthMiddleware.process`). Resolution: `import` edges are cross-module calls with confirmed import scope; `local` edges are same-file calls; `self` edges are `self.method()` calls where the class is known but target class type is not inferred; `star` edges are calls to names from star imports where the source module could not be determined. Requires a v3 index from `/codemap:scan`.

## 🔄 Incremental rebuild

After the first full scan, keep the index fresh without re-scanning everything:

```bash
/codemap:scan --incremental      # re-parse only changed files (git SHA comparison)
```

**Performance**: ~75ms for 5 changed files vs ~25s full scan on a 646-module project. Falls back to full scan when no v3 index exists.

**Automatic with git hook** — run `/codemap:integration init` and choose the post-commit hook option. After every `git commit`, `scan-index --incremental` runs in the background:

```bash
# .git/hooks/post-commit (installed by /codemap:integration init)
# codemap: incremental index rebuild — do not remove this line
if command -v scan-index >/dev/null 2>&1; then
    scan-index --incremental 2>/dev/null &
fi
```

Index stays current with zero developer action.

## 📦 Plugin details

### Upgrade

```bash
cd Borda-AI-Rig && git pull
claude plugin install codemap@borda-ai-rig
```

### Uninstall

```bash
claude plugin uninstall codemap
```

### Structure

```
plugins/codemap/
├── .claude-plugin/
│   └── plugin.json          ← manifest (zero external dependencies)
├── README.md
├── skills/
│   ├── scan/SKILL.md        ← /codemap:scan
│   ├── query/SKILL.md       ← /codemap:query
│   └── integration/SKILL.md ← /codemap:integration check|init
└── bin/
    ├── scan-index           ← scanner: ast.parse → JSON index with graph metrics
    └── scan-query           ← query CLI: central / coupled / deps / rdeps / path / list
```
