# ⚒️ foundry — Claude Code Plugin

Base plugin for Python/ML OSS development: 8 specialist agents, config-management skills, event-driven hooks, and a continuous self-improvement loop.

> [!TIP] For OSS workflows, install the `oss` plugin (`/oss:review`, `/oss:release`, …). For development workflows, install the `develop` plugin (`/develop:feature`, `/develop:fix`, …). For ML research, install the `research` plugin (`/research:run`, `/research:topic`, …).

## 🎯 Why

Generic Claude Code is a generalist. It will help with code, but it does not know your project's release conventions, does not enforce SemVer, does not benchmark itself for accuracy drift, and will not catch when its own agent descriptions start conflicting with each other.

`foundry` packages the infrastructure that makes specialised AI-assisted development sustainable:

- **Specialist agents** with deep, non-overlapping domain knowledge — routing accuracy benchmarked with `/calibrate`
- **Config lifecycle tools** — create, rename, and delete agents/skills with full cross-reference propagation
- **Quality gates** — hooks enforce lint-on-save, teammate output quality, and task tracking
- **Self-improvement loop** — `/audit` catches structural drift; `/calibrate` catches behavioural drift; `/distill` surfaces patterns from your corrections; together they close the feedback loop

## 💡 Key Principles

- **Profile-first on everything** — `/calibrate` measures before and after any agent change; `/audit upgrade` A/B tests capability proposals before applying
- **No duplication** — agents reference each other instead of repeating content; `/audit` Check 16 detects ≥40% overlap
- **Routing accuracy is a first-class metric** — agent descriptions are precise enough that `routing accuracy ≥90%` is a failing gate, not a suggestion
- **File-based handoff** — agents producing >500 tokens of findings write to a file and return a compact JSON envelope; the orchestrator never accumulates raw agent output in context
- **Hooks are transparent** — `rtk-rewrite.js` compresses CLI output without modifying commands; `lint-on-save.js` runs pre-commit after every write; both are no-ops when the tools are absent

## ⚡ Quick start

```bash
# Run from the directory that CONTAINS your Borda-AI-Home clone
claude plugin marketplace add ./Borda-AI-Home
claude plugin install foundry@borda-ai-home
```

<details>
<summary>Install companion plugins for the full workflow suite</summary>

```bash
claude plugin install oss@borda-ai-home
claude plugin install develop@borda-ai-home
claude plugin install research@borda-ai-home
```

</details>

**One-time setup** — run inside Claude Code:

```
/foundry:init        # settings merge + copy rules and TEAM_PROTOCOL.md to ~/.claude/
/foundry:init link   # same, but symlinked; also symlinks agents and skills for root-namespace access
```

Use `link` to invoke foundry commands without a prefix (`/audit` instead of `/foundry:audit`). Both modes are idempotent — safe to re-run. OSS, develop, and research skills always use their plugin prefix regardless.

**Why the copy/symlink split?**

| What                     | How                                          | Why                                                                                                                                                                                    |
| ------------------------ | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rules + TEAM_PROTOCOL.md | copied (plain `init`) or symlinked (`+link`) | Rules load at session startup — a stale symlink after a plugin upgrade would silently serve old content. Copies are upgrade-safe; `+link` trades that safety for always-fresh content. |
| Agents + skills          | symlinked only (`+link`)                     | Resolved dynamically at call time — a stale symlink produces an obvious error, not silent wrong behaviour. Copying large directories would also bloat `~/.claude/`.                    |
| `hooks/hooks.json`       | automatic (plugin system)                    | Claude Code registers hooks from the plugin manifest automatically when the plugin is enabled. No init step needed.                                                                    |

## 🔁 How to Use

### Config management

```bash
/manage create agent security-auditor "Vulnerability scanning specialist for OWASP Top 10 and supply chain threats"
/manage update my-agent "add a section on error handling patterns"
/manage delete old-agent-name
/manage add perm "Bash(safety:*)" "Python dependency safety scanner" "Check deps before release"
```

### Quality sweep

```bash
/audit                    # report only — lists all findings + upgrade proposals
/audit fix                # auto-fix critical + high findings
/audit fix medium         # auto-fix critical + high + medium
/audit upgrade            # apply docs-sourced improvements (A/B tested for capability changes)
/audit agents             # agents only
/audit setup              # system config only: settings.json, hooks, plugin integration
```

### Calibration

```bash
/calibrate all fast       # quick benchmark across all modes
/calibrate routing fast   # routing accuracy only — run after any agent description change
/calibrate agents full    # deep agent accuracy benchmark with AB comparison
/calibrate all fast apply # benchmark + apply improvement proposals
```

> [!NOTE] Thresholds: routing accuracy ≥90%, hard-problem accuracy ≥80%.

### Brainstorm → spec → action plan

```bash
/brainstorm "add caching layer to the data pipeline"
# clarifying questions (max 10) → build divergent branch tree (deepen, close, merge, max 10 ops)
# → self-mentor review → save .plans/blueprint/YYYY-MM-DD-<slug>.md (Status: tree)

/brainstorm breakdown .plans/blueprint/2026-04-01-caching-layer.md
# Status: tree → distillation questions → section-by-section spec (Status: draft)
# Status: draft → blocking questions → ordered action plan with tagged invocations
```

### Failure diagnosis

```bash
/investigate "hooks not firing on Save"
/investigate "CI fails but passes locally"
/investigate "codex agent exits 127 on this machine"
```

### Self-improvement loop

```bash
/distill                        # surface patterns from corrections, suggest new agents/skills
/calibrate all fast ab apply    # benchmark + apply improvement proposals
/audit fix                      # structural sweep: catch anything calibrate changed
```

Run after any burst of corrections or monthly as routine hygiene.

## 🗺️ Overview

### 8 Specialist Agents

| Agent                  | Role                                                                                        | Model    |
| ---------------------- | ------------------------------------------------------------------------------------------- | -------- |
| **sw-engineer**        | Architecture, implementation, SOLID principles, type safety                                 | opus     |
| **solution-architect** | ADRs, interface specs, migration plans, coupling analysis                                   | opusplan |
| **qa-specialist**      | pytest, hypothesis, mutation testing, ML test patterns; auto-includes OWASP Top 10 in teams | opus     |
| **linting-expert**     | ruff, mypy, pre-commit, rule selection, CI quality gates; runs autonomously                 | haiku    |
| **perf-optimizer**     | Profile-first CPU/GPU/memory/I/O optimisation, torch.compile, mixed precision               | opus     |
| **doc-scribe**         | Google/Napoleon docstrings, Sphinx/mkdocs, API references                                   | sonnet   |
| **web-explorer**       | API version comparison, migration guides, PyPI tracking                                     | sonnet   |
| **self-mentor**        | Agent/skill auditing, cross-ref validation, duplication detection                           | opusplan |

**Model tiering**: reasoning agents (`sw-engineer`, `qa-specialist`, `perf-optimizer`, `solution-architect`) default to `opus`; execution agents (`doc-scribe`, `linting-expert`, `web-explorer`) default to `sonnet`; `self-mentor` uses `opusplan` (plan-gated Opus — pays for reasoning only when the task warrants it).

### Agent Relationships

Agents are not independent — they form a directed pipeline:

- `linting-expert` is always **downstream** of `sw-engineer` — never lints code that hasn't been implemented
- `doc-scribe` is always **downstream** — documents finalised code, never shapes design
- `qa-specialist` runs **parallel** to `sw-engineer` during review, or downstream after implementation
- `self-mentor` is **orthogonal** — audits `.claude/` config files, not user code
- `web-explorer` **feeds** `research:scientist` — fetches current docs/papers, scientist interprets

### Skills

| Skill          | What It Does                                                                                                                                  |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `/audit`       | Config audit: broken refs, inventory drift, docs freshness; `fix [high\|medium\|all]` auto-fixes; `upgrade` applies docs-sourced improvements |
| `/manage`      | Create, update, delete agents/skills/rules with full cross-reference propagation; add/remove permissions                                      |
| `/calibrate`   | Synthetic benchmarks measuring recall vs confidence bias across all agent modes                                                               |
| `/brainstorm`  | Idea → divergent branch tree → spec → action plan; two modes: `idea` and `breakdown`                                                          |
| `/investigate` | Systematic failure diagnosis — env, tools, hooks, CI divergence; ranks hypotheses                                                             |
| `/distill`     | Surface patterns from corrections, suggest new agents/skills, prune MEMORY.md                                                                 |
| `/session`     | Parking lot for diverging ideas — auto-parks unanswered questions across sessions                                                             |

### Hooks

| Hook                  | Event                  | What It Does                                                       |
| --------------------- | ---------------------- | ------------------------------------------------------------------ |
| `task-log.js`         | SubagentStart/Stop     | Tracks background agents to `/tmp/claude-state-<session>/`         |
| `statusline.js`       | SessionStart           | Reads agent state for the status bar                               |
| `teammate-quality.js` | PostToolUse            | Gates teammate output quality before it reaches the orchestrator   |
| `lint-on-save.js`     | PostToolUse:Write/Edit | Runs pre-commit hooks after every file change                      |
| `rtk-rewrite.js`      | PreToolUse:Bash        | Transparently rewrites CLI calls through RTK for token compression |
| `md-compress.js`      | PreToolUse:Read        | Compresses large markdown files before they enter context          |

## 📦 Plugin details

### Upgrade

```bash
cd Borda-AI-Home && git pull
claude plugin install foundry@borda-ai-home
```

> [!IMPORTANT] Re-run `/foundry:init link` after upgrading — symlinks point to the versioned cache path and go stale after reinstall.

### Uninstall

```bash
claude plugin uninstall foundry
```

> [!NOTE] Settings merged by `/foundry:init` (`statusLine`, `permissions.allow` entries) remain in `~/.claude/settings.json` — remove manually if desired. Symlinks from `/foundry:init link` in `~/.claude/agents/` and `~/.claude/skills/` also persist after uninstall.

### Structure

```
plugins/foundry/
├── .claude-plugin/
│   ├── plugin.json          ← manifest
│   ├── permissions-allow.json ← allow-list merged by /foundry:init
│   └── permissions-deny.json  ← deny-list merged by /foundry:init
├── agents/                  ← canonical agent files (symlinked from .claude/agents/)
├── skills/                  ← canonical skill files (symlinked from .claude/skills/)
├── rules/                   ← canonical rule files (symlinked from .claude/rules/)
├── CLAUDE.md                ← workflow rules (symlinked from .claude/CLAUDE.md; distributed via init)
├── TEAM_PROTOCOL.md         ← AgentSpeak v2 inter-agent protocol (symlinked from .claude/TEAM_PROTOCOL.md)
├── permissions-guide.md     ← allow/deny annotated reference (copied to .claude/ by init if absent; edited project-locally)
└── hooks/
    ├── hooks.json           ← hook registrations (${CLAUDE_PLUGIN_ROOT} paths)
    ├── task-log.js          ← SubagentStart/Stop tracking
    ├── statusline.js        ← status bar agent counts
    ├── teammate-quality.js  ← teammate output quality gate
    ├── lint-on-save.js      ← pre-commit on write/edit
    ├── rtk-rewrite.js       ← CLI token compression
    └── md-compress.js       ← large markdown compression
```
