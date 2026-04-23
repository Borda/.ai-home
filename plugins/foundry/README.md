# 🏭 foundry — Claude Code Plugin

OSS Claude Code config: 9 specialist agents, 8 skills, event-driven hooks, and a self-improvement loop for professional AI-assisted development.

> For OSS workflows, also install the `oss` plugin (`/oss:review`, `/oss:release`, ...). For development workflows, install `develop` (`/develop:feature`, `/develop:fix`, ...). For ML research, install `research` (`/research:run`, `/research:topic`, ...).

______________________________________________________________________

<details>
<summary><strong>📋 Contents</strong></summary>

- [What is foundry?](#what-is-foundry)
- [Why foundry?](#why-foundry)
- [Install](#install)
- [Quick start](#quick-start)
- [Skills reference](#skills-reference)
  - [`/foundry:init`](#foundryinit)
  - [`/foundry:audit`](#foundryaudit)
  - [`/foundry:calibrate`](#foundrycalibrate)
  - [`/foundry:manage`](#foundrymanage)
  - [`/foundry:brainstorm`](#foundrybrainstorm)
  - [`/foundry:investigate`](#foundryinvestigate)
  - [`/foundry:distill`](#foundrydistill)
  - [`/foundry:session`](#foundrysession)
- [Agents reference](#agents-reference)
  - [foundry:sw-engineer](#foundrysw-engineer)
  - [foundry:solution-architect](#foundrysolution-architect)
  - [foundry:qa-specialist](#foundryqa-specialist)
  - [foundry:linting-expert](#foundrylinting-expert)
  - [foundry:perf-optimizer](#foundryperf-optimizer)
  - [foundry:doc-scribe](#foundrydoc-scribe)
  - [foundry:web-explorer](#foundryweb-explorer)
  - [foundry:self-mentor](#foundryself-mentor)
  - [foundry:challenger](#foundrychallenger)
- [Agent relationships](#agent-relationships)
- [Rules installed](#rules-installed)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Plugin structure](#plugin-structure)
- [Upgrade](#upgrade)
- [Uninstall](#uninstall)
- [Contributing / feedback](#contributing--feedback)

</details>

______________________________________________________________________

## 🤔 What is foundry?

foundry is the base infrastructure plugin for Claude Code on Python and ML OSS projects. It gives Claude Code a team of nine non-overlapping specialist agents — each with deep, calibrated domain knowledge — paired with skills for managing their lifecycle, benchmarking their accuracy, and feeding corrections back into their instructions.

Without foundry, Claude Code is a generalist. It helps with code but does not know your release conventions, does not enforce routing to the right specialist, and has no mechanism to measure or improve its own accuracy over time. foundry packages all of that infrastructure in a single installable plugin.

______________________________________________________________________

## 🎯 Why foundry?

**Without it**: one model handles architecture, implementation, documentation, linting, testing, and performance — with no boundary enforcement between them. Corrections made in one session evaporate. There is no way to know whether agent accuracy has drifted.

**With it**:

- `/foundry:audit` catches config drift before it becomes a debugging session
- `/foundry:calibrate` measures recall versus stated confidence so you know exactly where agents fall short
- `/foundry:manage` creates, renames, and deletes agents with full cross-reference propagation in a single command
- `/foundry:brainstorm` turns a vague idea into an approved spec before a single line of code is written
- `/foundry:distill` converts accumulated corrections into durable rules and agent instruction updates
- Hooks keep lint, task tracking, and teammate quality gates running on every file save

The self-improvement loop — `/foundry:audit` catches structural drift; `/foundry:calibrate` catches behavioral drift; `/foundry:distill` surfaces patterns from your corrections — closes the feedback loop automatically.

______________________________________________________________________

## 📦 Install

**Prerequisites**: Claude Code with plugin support; `jq` on PATH; `node` on PATH (required by hooks).

```bash
# Run from the directory that CONTAINS your Borda-AI-Rig clone
claude plugin marketplace add ./Borda-AI-Rig
claude plugin install foundry@borda-ai-rig
```

Install companion plugins if you need the full workflow suite:

```bash
claude plugin install oss@borda-ai-rig
claude plugin install develop@borda-ai-rig
claude plugin install research@borda-ai-rig
```

**One-time setup** — run inside Claude Code after installing:

```text
/foundry:init
```

This merges `statusLine`, `permissions.allow`, and `enabledPlugins` into `~/.claude/settings.json`, and symlinks all rule files and `TEAM_PROTOCOL.md` into `~/.claude/`. It is idempotent — safe to re-run.

**After any plugin upgrade**, re-run `/foundry:init` to refresh symlinks pointing to the new cache path.

______________________________________________________________________

## ⚡ Quick start

The one command that confirms everything is working:

```text
/foundry:audit setup
```

Expected output: a structured report of system configuration checks (hooks, settings.json, plugin integration, symlinks). Zero critical findings means you are ready.

Follow up with:

```text
/foundry:calibrate routing fast
```

This runs a quick routing accuracy benchmark — measures whether Claude Code dispatches tasks to the right agent. You should see routing accuracy at or above 90%.

______________________________________________________________________

## 🔧 Skills reference

### `/foundry:init`

Post-install setup. Merges settings and creates symlinks. Run once after install, and again after any upgrade.

```text
/foundry:init
/foundry:init --approve      # non-interactive; auto-accepts all recommended choices
```

What it does:

- Backs up `~/.claude/settings.json` before touching it
- Merges `statusLine`, `permissions.allow`, `permissions.deny`, `enabledPlugins`
- Copies `permissions-guide.md` to `.claude/` (only if absent — preserves project-local edits)
- Symlinks all `plugins/foundry/rules/*.md` and `TEAM_PROTOCOL.md` into `~/.claude/`
- Removes stale `hooks` block from settings if present (hooks now register via plugin manifest)

Hooks (`hooks.json`) register automatically when the plugin is enabled — `/foundry:init` does not touch them directly.

______________________________________________________________________

### `/foundry:audit`

Full-sweep quality audit of `.claude/` configuration and all `plugins/*/` agent and skill files. Catches broken cross-references, inventory drift, model-tier mismatches, description overlap, and documentation staleness. Reports findings by severity; auto-fixes at the requested level.

```text
/foundry:audit                      # full sweep, report only
/foundry:audit fix                  # auto-fix critical + high + medium
/foundry:audit fix high             # auto-fix critical + high only
/foundry:audit fix all              # auto-fix everything including low
/foundry:audit upgrade              # fetch latest Claude Code docs, apply improvements with A/B testing

/foundry:audit agents               # agents only
/foundry:audit skills               # skills only
/foundry:audit rules                # rules only
/foundry:audit communication        # communication governance files only
/foundry:audit setup                # system config: settings.json, hooks, plugin integration
/foundry:audit plugin               # foundry plugin integration checks only
/foundry:audit plugins              # deep audit of all installed plugins + Codex adversarial pass
/foundry:audit plugins foundry      # deep audit of foundry plugin only

# Combine scope and fix level
/foundry:audit agents fix medium
/foundry:audit rules fix all
```

`fix` and `upgrade` are mutually exclusive — never combine them.

**What the sweep checks (30 checks)**:

- Inventory drift: MEMORY.md roster vs files on disk
- Broken cross-references between agents and skills
- Hardcoded absolute user paths
- Model-tier appropriateness (reasoning vs execution roles)
- Agent description routing overlap (40%+ consecutive step overlap flagged)
- settings.json permissions vs Bash calls in skills
- Hook event names vs documented schema
- Claude Code docs freshness (spawns `foundry:web-explorer` to fetch live docs)
- Plugin integration correctness (codex plugin, foundry plugin)
- File length, heading hierarchy, LLM context minimality
- Config token overhead: total always-loaded config >100 KB, single rules file >10 KB (rules/ loads at session start; agents/skills are lazy-loaded)

Outputs a structured report. With a fix level: delegates fixes to sub-agents (never edits inline), then re-audits modified files to confirm fixes held. Convergence loop runs up to 5 passes.

______________________________________________________________________

### `/foundry:calibrate`

Benchmarks agents and skills against synthetic problems with defined ground truth. Primary signal is calibration bias — the gap between self-reported confidence and actual recall. A well-calibrated agent reports 0.9 when it finds roughly 90% of issues.

```text
/foundry:calibrate all fast              # quick benchmark across all modes (3 problems each)
/foundry:calibrate all full              # thorough benchmark (10 problems each)
/foundry:calibrate routing fast          # routing accuracy only — run after any agent description change
/foundry:calibrate agents fast ab        # agents + general-purpose baseline comparison
/foundry:calibrate all fast apply        # benchmark then immediately apply improvement proposals
/foundry:calibrate apply                 # apply proposals from the most recent past run
/foundry:calibrate foundry:sw-engineer fast    # single agent
```

**Thresholds**:

- Routing accuracy: 90% (hard-problem accuracy: 80%)
- Recall per agent: 0.70 (below this, instruction improvement is needed)
- Calibration bias: within +/-0.15 (beyond this, confidence is decoupled from quality)

**Modes**:

- `agents` — all 9 specialist agents
- `skills` — `/foundry:audit` and `/oss:review`
- `routing` — measures orchestrator dispatch accuracy for synthetic task prompts
- `communication` — team protocol compliance, file-handoff protocol violations
- `rules` — rule adherence across global and path-scoped rule files
- `all` — all of the above

Results saved to `.reports/calibrate/<timestamp>/<target>/`. Improvement proposals written to `proposal.md` in each target directory and applied with `apply`.

Agents and skills modes use dual-source evaluation: Claude and Codex generate problems and score responses independently, with Claude as 51% tiebreaker.

______________________________________________________________________

### `/foundry:manage`

Create, update, or delete agents, skills, rules, and hooks with full cross-reference propagation. Keeps MEMORY.md, README, and `settings.json` in sync automatically.

```text
/foundry:manage create agent security-auditor "Vulnerability scanning specialist for OWASP Top 10 and supply chain threats"
/foundry:manage create skill benchmark "Benchmark orchestrator for measuring performance across commits"
/foundry:manage create rule torch-patterns "PyTorch coding patterns — compile, AMP, distributed"

/foundry:manage update my-agent "add a section on error handling patterns"
/foundry:manage update my-agent new-agent-name        # rename
/foundry:manage update my-agent docs/spec.md          # apply spec file as change directive

/foundry:manage delete old-agent-name

/foundry:manage add perm "Bash(jq:*)" "Parse and filter JSON" "Extract fields from REST API responses"
/foundry:manage remove perm "Bash(jq:*)"
```

**Create**: fetches the latest Claude Code agent/skill frontmatter schema, picks an unused color, assigns a model tier based on role complexity, then delegates content generation to `foundry:self-mentor`. Checks for overlap with existing agents before creating.

**Update**: auto-detects type from disk. Rename is atomic (write-before-delete). Content edits are delegated to `foundry:self-mentor` (agents/skills) or `foundry:sw-engineer` (hooks). Propagates description changes to cross-references when more than 3 files are affected.

**Delete**: removes the file, cleans up broken references across `.claude/`, updates MEMORY.md and README.

**Permissions**: `add perm` and `remove perm` update both `settings.json` and `permissions-guide.md` atomically — never one without the other.

After any create or update, follow up with `/foundry:calibrate routing fast` to confirm routing accuracy is unaffected.

______________________________________________________________________

### `/foundry:brainstorm`

Turns a fuzzy idea into an approved exploration tree, then into a spec, then into an ordered action plan. Nothing is implemented until the user approves a design.

```text
/foundry:brainstorm "add caching layer to the data pipeline"
/foundry:brainstorm "add caching layer to the data pipeline" --tight    # fewer questions and operations
/foundry:brainstorm "add caching layer to the data pipeline" --deep     # more exploration
/foundry:brainstorm "add caching layer to the data pipeline" --type workflow

/foundry:brainstorm breakdown .plans/blueprint/2026-04-01-caching-layer.md       # tree -> spec
/foundry:brainstorm breakdown .plans/blueprint/2026-04-01-caching-layer-spec.md  # spec -> action plan
```

**Idea mode** (default):

1. Scans codebase for relevant existing code and constraints
2. Asks up to 10 clarifying questions (5 with `--tight`, 15 with `--deep`), one at a time
3. Presents 3-5 initial branches with core idea, tension resolved, and what it trades away
4. Interactive operations loop: deepen, reject, resolve, merge, add — up to 10 rounds
5. Saves tree to `.plans/blueprint/YYYY-MM-DD-<slug>.md` with `Status: tree`
6. Live tree viewer available at the URL printed during Step 1 (serve project root with `python3 -m http.server 8000`)

**Breakdown mode** (`breakdown <file>`):

- `Status: tree` file: distillation questions then section-by-section spec, saved with `Status: draft`
- `Status: draft` file: resolves blocking open questions, then produces ordered action plan with tagged invocations

`--type` hint (`application`, `workflow`, `utility`, `config`, `research`) shapes question framing and codebase scan patterns in idea mode.

______________________________________________________________________

### `/foundry:investigate`

Systematic diagnosis for unknown failures. Gathers signals, ranks hypotheses, probes the top candidates, and reports a confirmed root cause with a recommended next action.

```text
/foundry:investigate "hooks not firing on Save"
/foundry:investigate "CI fails but passes locally"
/foundry:investigate "codex agent exits 127 on this machine"
/foundry:investigate "/calibrate times out every run"
```

**What it covers**: broken local setup, environment mismatches, tool misconfigurations, hook misbehavior, CI vs local divergence, permission errors, runtime anomalies.

**Not for**: known Python test failures with a traceback (use `/develop:debug`); `.claude/` config quality sweep (use `/foundry:audit`).

Workflow: parse symptom -> gather signals in parallel (tool versions, PATH, recent git changes, config state, logs) -> rank hypotheses -> optional Codex adversarial review for ambiguous cases -> probe top hypotheses -> report root cause and recommended next skill.

Output always includes: confirmed root cause (or narrowed suspects), key evidence, what was ruled out, and a single recommended next action.

______________________________________________________________________

### `/foundry:distill`

Extracts patterns from work history and corrections, then distills them into durable improvements — new agent or skill suggestions, roster quality review, memory pruning, promoting lessons into rules, or analysing external plugins and agentic resources for adoption.

```text
/foundry:distill                              # analyze project patterns, suggest new agents/skills
/foundry:distill review                       # review existing roster for quality and gaps (no new suggestions)
/foundry:distill prune                        # trim stale/redundant entries from project MEMORY.md
/foundry:distill lessons                      # promote patterns from .notes/lessons.md into rules/agents/skills
/foundry:distill "external https://..."       # analyse external plugin/skill/agent resource, produce adoption proposal
/foundry:distill "external ./path/to/plugin"  # same — local path or directory
/foundry:distill "I keep doing X manually"    # use description as context for suggestions
```

**`lessons` mode** is the primary post-correction consolidation path. It reads `.notes/lessons.md` and `feedback_*.md` memory files, clusters them by domain, classifies each entry as `→ rule`, `→ agent update`, `→ skill update`, `→ already covered`, or `→ too narrow`, then generates proposals. Before applying, it runs a conflict pre-check — greps each target file for the section the delta would land in and flags cross-proposal collisions with ⚠. Confirmed changes are applied and followed by a `git diff` gate so you can inspect or revert before committing.

**`external` mode** does a fast + slow read of the source (URL, file, or directory), extracts the mental model and standout implementation details, compares against the live local setup, then splits candidates into two groups: *Align + improve* (maps cleanly onto existing agents/skills/rules) and *Differentiated highlights* (novel, structurally different — interesting but larger work). Each candidate is scored and assigned to an adoption lane: adopt-as-is / tweak / discuss / skip. When Group A is thin or cumulative edit effort is large, it recommends installing the source as a standalone plugin with justification, rather than cherry-picking. Nothing is written until you confirm.

After applying: run `/foundry:init` to propagate new rule files to `~/.claude/`.

Run monthly or after any burst of corrections.

______________________________________________________________________

### `/foundry:session`

Parking lot for open-loop ideas and unanswered questions that arise mid-session. Parks items automatically as they arise; three on-demand commands manage them.

```text
/foundry:session resume           # list all pending parked items for this project
/foundry:session archive <text>   # fuzzy-match and close a parked item
/foundry:session summary          # session digest: completed tasks, parked items, recent commits
```

Items are stored in project-scoped memory (`~/.claude/projects/<slug>/memory/session-open-*.md`). Items older than 14 days are marked stale; items older than 30 days are deleted silently on `resume`.

**Automatic parking** (no command needed): when you send a new top-level request before answering Claude's prior clarifying question, or defer something with "let's come back to that", Claude parks the open item automatically so it is not lost to context compaction.

______________________________________________________________________

## 🤖 Agents reference

All eight agents are available by their full plugin-prefixed name. In spawn directives and `subagent_type` values, always use the full prefix (`foundry:sw-engineer`, not `sw-engineer`).

### foundry:sw-engineer

**Role**: senior software engineer for writing and refactoring Python code.

**Use for**: implementing features, fixing bugs, TDD/test-first development, SOLID principles, type safety, production-quality Python for OSS libraries.

**Model**: `opus`

**Not for**: docstrings (use `foundry:doc-scribe`), configuring ruff/mypy (use `foundry:linting-expert`), system design decisions (use `foundry:solution-architect`), test quality analysis (use `foundry:qa-specialist`), performance profiling (use `foundry:perf-optimizer`), ML paper implementations (use `research:scientist`), editing `.claude/` config files (use `foundry:self-mentor`).

Runs in an isolated worktree by default to keep changes sandboxed until review.

______________________________________________________________________

### foundry:solution-architect

**Role**: system design specialist for ADRs, API surface design, interface specs, migration plans, and coupling analysis.

**Use for**: evaluating architectural trade-offs, designing public API contracts, planning deprecation strategies, assessing architectural feasibility of AI-generated hypotheses against codebase constraints.

**Model**: `opusplan` (plan-gated Opus)

**Not for**: writing implementation code (use `foundry:sw-engineer`), release management (use `oss:shepherd`).

Produces documentation — ADRs, interface contracts, migration plans, component diagrams — not production code. Hands off to `foundry:sw-engineer` for execution.

______________________________________________________________________

### foundry:qa-specialist

**Role**: QA specialist for writing, reviewing, and fixing tests.

**Use for**: writing new pytest tests, analyzing coverage gaps, building edge-case matrices, fixing failing tests, integration test design. Automatically includes OWASP Top 10 security perspective when used in agent teams. Includes anti-hallucination assertion protocol for code reviews: occurrence thresholds (>10 established / 3–10 emerging / \<3 skip), conditional context loading by diff content type, and structured uncertainty markers.

**Model**: `opus`

**Not for**: linting, type checking, or annotation fixes (use `foundry:linting-expert`), production implementation (use `foundry:sw-engineer`).

Writes deterministic, parametrized, behavior-focused tests following Arrange-Act-Assert. Follows TDD for new features: write tests before implementation.

______________________________________________________________________

### foundry:linting-expert

**Role**: static analysis and tooling specialist for Python.

**Use for**: configuring ruff rules, mypy strictness, pre-commit hooks, fixing lint/type violations, adding missing type annotations, defining the lint/type content of quality gates. Handles final code sanitization before handover.

**Model**: `haiku` (high-frequency, lightweight diagnostics)

**Not for**: CI pipeline structure or runner strategy (use `oss:ci-guardian`), writing test logic (use `foundry:qa-specialist`), implementation fixes beyond annotation/style (use `foundry:sw-engineer`).

Always downstream of `foundry:sw-engineer` — never lints code that has not yet been implemented.

______________________________________________________________________

### foundry:perf-optimizer

**Role**: performance engineer for profiling and optimizing CPU, GPU, memory, and I/O bottlenecks.

**Use for**: profiling Python/ML workloads, identifying DataLoader bottlenecks, applying mixed precision, vectorizing loops, tuning PyTorch throughput.

**Model**: `opus`

**Not for**: general code refactoring (use `foundry:sw-engineer`), architectural redesign (use `foundry:solution-architect`).

Strictly profile-first: measures before changing, changes one thing, measures again. Optimization order: algorithm -> data structure -> I/O -> memory -> concurrency -> vectorization -> compute -> caching. Never jumps to GPU tuning before checking I/O.

______________________________________________________________________

### foundry:doc-scribe

**Role**: documentation specialist for docstrings, API references, and README files.

**Use for**: auditing missing docstrings, writing Google-style (Napoleon) docstrings from code, creating or updating README content, finding doc/code inconsistencies.

**Model**: `sonnet`

**Not for**: CHANGELOG entries or release notes (use `oss:shepherd` for lifecycle/format decisions, `/oss:release` for automated generation), linting code examples (use `foundry:linting-expert`), implementation code (use `foundry:sw-engineer`).

Always downstream — documents finalized code, never shapes design. After `foundry:doc-scribe` produces content, follow with `foundry:linting-expert` to sanitize code examples in the output.

______________________________________________________________________

### foundry:web-explorer

**Role**: web fetch and content extraction specialist.

**Use for**: fetching live library docs, API references, changelogs, migration guides, package version lookups, GitHub release extraction. Used internally by `/foundry:audit upgrade` and `/foundry:manage create`.

**Model**: `sonnet`

**Not for**: code analysis or implementation (use `foundry:sw-engineer`), ML paper analysis (use `research:scientist`), writing docstrings (use `foundry:doc-scribe`), dependency upgrade lifecycle decisions (use `oss:shepherd`).

Feeds `research:scientist` — fetches current docs and papers; scientist interprets.

______________________________________________________________________

### foundry:self-mentor

**Role**: quality guardian of Claude config markdown files — agents, skills, and rules.

**Use for**: auditing `.claude/` config files for verbosity creep, cross-agent duplication, broken cross-references, structural violations, outdated content, and roster overlap. Used internally by `/foundry:audit` and `/foundry:manage`.

**Model**: `opusplan`

**Not for**: hook files (`*.js`) — those belong to `foundry:sw-engineer`. Not for creating or scaffolding new agents or skills (use `/foundry:manage create`). Not for routing new tasks to other agents.

You will generally not invoke this agent directly. `/foundry:audit` spawns it in batches across all config files; `/foundry:manage` delegates content generation and editing to it.

______________________________________________________________________

### foundry:challenger

**Role**: adversarial reviewer for implementation plans, architecture proposals, and significant code reviews.

**Use for**: red-teaming a plan before committing to it, challenging architectural decisions before they ship, adversarial code review on security-sensitive or irreversible operations. Attacks across 5 dimensions (Assumptions, Missing Cases, Security Risks, Architectural Concerns, Complexity Creep) then applies a mandatory refutation step to eliminate false positives.

**Model**: `opusplan` (plan-gated Opus)

**Not for**: designing plans or ADRs (use `foundry:solution-architect`), writing tests (use `foundry:qa-specialist`), config file quality review (use `foundry:self-mentor`).

Read-only — never writes or edits files. Runs by default in all `/develop:*` skills and `/oss:review` — skip with `--no-challenge`.

______________________________________________________________________

## 🔗 Agent relationships

Agents form a directed pipeline, not a flat pool:

- `foundry:linting-expert` is always **downstream** of `foundry:sw-engineer` — never lints code that has not been implemented
- `foundry:doc-scribe` is always **downstream** — documents finalized code, never shapes design
- `foundry:qa-specialist` runs **parallel** to `foundry:sw-engineer` during review, or downstream after implementation
- `foundry:challenger` is **pre-implementation** — challenges plans and proposals before any code is written; use before `foundry:sw-engineer`
- `foundry:self-mentor` is **orthogonal** — audits `.claude/` config files, not user code
- `foundry:web-explorer` **feeds** `research:scientist` — fetches current docs and papers; scientist interprets

**Model tiering**: reasoning agents (`foundry:sw-engineer`, `foundry:qa-specialist`, `foundry:perf-optimizer`) use `opus`; plan-gated roles (`foundry:solution-architect`, `foundry:self-mentor`, `foundry:challenger`) use `opusplan`; execution agents (`foundry:doc-scribe`, `foundry:web-explorer`) use `sonnet`; high-frequency diagnostics (`foundry:linting-expert`) use `haiku`.

______________________________________________________________________

## 📋 Rules installed

`/foundry:init` symlinks all rule files from `plugins/foundry/rules/` into `~/.claude/rules/`. These govern Claude's behavior globally across all sessions after install.

| Rule file               | Applies to                      | What it governs                                                                                         |
| ----------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `communication.md`      | all                             | Re: anchor format, progress narration, tone, output routing, breaking-findings format, terminal colors  |
| `quality-gates.md`      | all                             | Confidence block format, Internal Quality Loop, link verification, output routing (long output to file) |
| `git-commit.md`         | all                             | Commit message format, diff-gathering before writing, co-author trailers, branch and push safety        |
| `claude-config.md`      | all                             | Bash timeouts (3x P90), directory navigation rules, no hardcoded absolute paths                         |
| `artifact-lifecycle.md` | all                             | Canonical artifact layout (`.plans/`, `.reports/`, `.temp/`), run directory naming, TTL policy          |
| `external-data.md`      | all                             | Pagination rules for GitHub CLI, REST APIs, GraphQL, Cloud APIs — never work on partial result set      |
| `foundry-config.md`     | `.claude/**`                    | Plan-mode gate before any `.claude/` edit, post-edit checklist, XML tag conventions, distribution rules |
| `python-code.md`        | `**/*.py`                       | Google-style docstrings (no exceptions), deprecation version check before generating deprecation code   |
| `testing.md`            | `tests/**/*.py`, `**/test_*.py` | pytest design: TDD process, fixture conventions, parametrization, what to test in priority order        |
| `public-github.md`      | all                             | Read-only policy on public GitHub — permitted reads vs permanently forbidden write operations           |

______________________________________________________________________

## ⚙️ Configuration

### settings.json keys merged by `/foundry:init`

| Key                                    | What it does                                                                             |
| -------------------------------------- | ---------------------------------------------------------------------------------------- |
| `statusLine.command`                   | Runs `statusline.js` to display active agent count in the Claude Code status bar         |
| `permissions.allow`                    | Adds pre-approved Bash commands, git operations, and WebFetch domains                    |
| `permissions.deny`                     | Adds permanently denied write operations (public GitHub mutations, destructive git)      |
| `enabledPlugins["codex@openai-codex"]` | Enables Codex plugin for adversarial review in `/foundry:calibrate` and `/foundry:audit` |

### Optional flags and knobs

**`--approve`** on `/foundry:init`: skips all interactive prompts and auto-accepts recommended choices. Use for scripted or CI setups.

**`--skip-audit`** on `/foundry:manage`: skips the trailing `/foundry:audit` validation step. Use inside `audit fix` loops to avoid recursion.

**Calibration pace**: `fast` (3 problems per target, default) vs `full` (10 problems per target). Use `fast` for routine checks after agent edits; use `full` for thorough benchmarks before releases or after major instruction changes.

**Brainstorm ceremony**: `--tight` (5/5/1 caps for well-scoped ideas), default (10/10/2), `--deep` (15/15/3 for genuinely ambiguous problems).

### Environment

No environment variables required. foundry reads from `~/.claude/settings.json` and the plugin's installed cache path, both resolved automatically by `/foundry:init`.

______________________________________________________________________

<details>
<summary>

## 🔍 Troubleshooting

</summary>

## 🔍 Troubleshooting

**`/foundry:audit` reports broken symlinks (Check I3)**

Symlinks in `~/.claude/rules/` point to the previous plugin cache path after an upgrade. Re-run `/foundry:init` — Step 9 detects stale symlinks as conflicts and offers to replace them.

**Hooks not firing**

Run `/foundry:investigate "hooks not firing on Save"`. Most common cause: a `hooks` block is still present in `~/.claude/settings.json` from a pre-plugin-migration install (hooks now register via plugin manifest, not the `hooks` key). `/foundry:init` Step 3 detects and removes the stale block.

**`/foundry:calibrate` times out**

Each pipeline subagent has a 10-minute hard cutoff (15 minutes when Codex is active). If a target consistently times out, run it in isolation: `/foundry:calibrate foundry:sw-engineer fast`. For persistent issues: `/foundry:investigate "/calibrate times out every run"`.

**`/foundry:manage create` picks wrong model tier**

Model tier is chosen by role complexity at creation time: `opusplan` for plan-gated roles, `opus` for complex implementation, `sonnet` for focused execution, `haiku` for high-frequency diagnostics. To fix after creation: `/foundry:manage update <name> "change model to sonnet"`.

**`foundry:self-mentor` returns low confidence during `/foundry:audit`**

The audit re-runs the agent with the specific gap named in its `Gaps:` field. If confidence remains below 0.7 after one retry, the gap is surfaced with a warning in the final report for manual review. Add recurring gaps to `foundry:self-mentor`'s antipatterns section: `/foundry:manage update foundry-self-mentor "add gap X to antipatterns_to_flag"`.

**`jq` not found warning during `/foundry:audit setup`**

Check 4 (permissions-guide drift) requires `jq`. Install it with `brew install jq` on macOS or `apt install jq` on Linux. The audit continues without it — only Check 4 is skipped.

______________________________________________________________________

</details>

<details>
<summary>

## 🏗️ Plugin structure

</summary>

## 🏗️ Plugin structure

```text
plugins/foundry/
├── .claude-plugin/
│   ├── plugin.json              version + metadata
│   ├── permissions-allow.json   allow-list merged by /foundry:init
│   └── permissions-deny.json    deny-list merged by /foundry:init
├── agents/                      9 specialist agent files
├── skills/                      8 skill directories (audit, brainstorm, calibrate, distill,
│                                    init, investigate, manage, session)
├── rules/                       10 rule files symlinked to ~/.claude/rules/ by /foundry:init
├── CLAUDE.md                    workflow rules distributed via /foundry:init
├── TEAM_PROTOCOL.md             AgentSpeak v2 inter-agent protocol
├── permissions-guide.md         annotated allow/deny reference (copied to .claude/ by init)
└── hooks/
    ├── hooks.json               hook registrations (${CLAUDE_PLUGIN_ROOT} paths)
    ├── task-log.js              SubagentStart/Stop tracking to /tmp/claude-state-<session>/
    ├── statusline.js            status bar agent counts
    ├── teammate-quality.js      TaskCompleted/TeammateIdle teammate output quality gate
    ├── lint-on-save.js          runs pre-commit after every Write/Edit
    ├── rtk-rewrite.js           transparently rewrites CLI calls for token compression
    ├── commit-guard.js          PreToolUse Bash guard that blocks git commit unless authorized by a skill sentinel
    └── md-compress.js           compresses large markdown files before they enter context
```

______________________________________________________________________

</details>

<a id="upgrade"></a>

<details>
<summary><strong>🔄 Upgrade</strong></summary>

```bash
cd Borda-AI-Rig
git pull
claude plugin install foundry@borda-ai-rig
```

Then, inside Claude Code:

```text
/foundry:init
```

Re-running `/foundry:init` after an upgrade is required — symlinks point to the versioned cache path and go stale after reinstall.

</details>

______________________________________________________________________

<a id="uninstall"></a>

<details>
<summary><strong>🗑️ Uninstall</strong></summary>

```bash
claude plugin uninstall foundry
```

Settings keys merged by `/foundry:init` (`statusLine`, `permissions.allow` entries) remain in `~/.claude/settings.json` after uninstall — remove them manually if desired. Symlinks created by `/foundry:init` in `~/.claude/rules/` and `~/.claude/TEAM_PROTOCOL.md` also persist.

______________________________________________________________________

## 🙏 Contributing / feedback

foundry is part of the Borda-AI-Rig repository. To suggest an improvement or report a bug:

1. Run `/foundry:brainstorm "your idea"` to develop the idea before filing anything
2. File an issue on the repository — include the output of `/foundry:audit setup` and your Claude Code version
3. Plugin updates propagate to users via `git pull` + `claude plugin install foundry@borda-ai-rig` + `/foundry:init`

To add a new agent or skill, use `/foundry:manage create` — it handles scaffolding, README sync, and MEMORY.md updates automatically.
