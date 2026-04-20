# 🌐 oss — Claude Code Plugin

OSS workflow plugin for Python/ML open-source projects: two specialist agents and four slash-command skills for issue triage, parallel code review, PR resolution, and SemVer-disciplined releases.

> [!NOTE]
>
> Works standalone — foundry is not required. Without it, agent dispatches fall back to `general-purpose` with role descriptions (lower quality). Installing foundry unlocks specialized agents (`foundry:sw-engineer`, `foundry:qa-specialist`, etc.) and is strongly recommended for production use.

## 🎯 Why

Maintaining an open-source project means juggling three competing demands: reviewing code carefully enough to catch regressions, responding to contributors quickly enough that they stay engaged, and shipping releases confidently enough that users upgrade. Each of these is a context-switch tax.

`oss` removes that tax:

- **Parallel review in one command** — six specialist agents run simultaneously across architecture, tests, performance, docs, linting, and security; you get a consolidated report in minutes, not hours
- **Codex pre-pass before the expensive agents** — a fast 60-second Codex review catches obvious issues first; if nothing critical surfaces, the full fan-out runs; no wasted compute on trivial diffs
- **Contributor-facing output built in** — `--reply` drafts a welcoming comment in the project's voice, citing specific conventions, so you spend 30 seconds reviewing instead of 10 minutes writing
- **Three-source resolution** — `resolve` closes the gap between review findings and merged code; applies Codex-driven fixes from live PR comments, a saved report, or both at once
- **Release pipeline with SemVer discipline** — `shepherd` enforces bump rules, writes the changelog with deprecation tracking, generates migration guides, and audits readiness before the tag goes out

## 💡 Key Principles

- **Codex pre-pass before expensive agents** — Tier 1 runs first; trivial PRs close in 60 seconds without spawning six agents
- **Welcoming by default** — `--reply` output leads with what is good, follows project conventions, and treats contributors as partners; never adversarial
- **Shepherd owns contributor communication** — all PR replies, issue comments, and release notes go through shepherd for consistent voice; other agents never write external-facing text
- **Semantic conflict resolution** — `resolve` reads intent from both sides of a conflict; it does not pick one side mechanically
- **SemVer is a gate, not a label** — `release` refuses to tag until the bump type is justified by the actual diff; no accidental major bumps

## ⚡ Quick start

```bash
# Run from the directory that CONTAINS your Borda-AI-Rig clone
claude plugin marketplace add ./Borda-AI-Rig
claude plugin install oss@borda-ai-rig
```

<details>
<summary>Install the full suite</summary>

```bash
claude plugin install foundry@borda-ai-rig   # base agents — strongly recommended
claude plugin install oss@borda-ai-rig
claude plugin install develop@borda-ai-rig
claude plugin install research@borda-ai-rig
```

</details>

> [!NOTE]
>
> Skills are always invoked with the `oss:` prefix: `/oss:analyse`, `/oss:review`, `/oss:resolve`, `/oss:release`.

## 🔁 How to Use

### Morning triage

```bash
/oss:analyse health                 # repo overview, duplicate clustering, stale PRs
/oss:analyse 123                    # deep-dive on a specific issue or PR
```

### Review a PR

```bash
/oss:review 55                      # full tiered review → saves findings report
/oss:review 55 --reply              # review + draft contributor-facing comment
```

> [!NOTE]
>
> `/oss:review` requires a GitHub PR number. To review local files or the current git diff without a PR, use `/develop:review` from the develop plugin.

### Apply findings after review

```bash
# Option 1: Apply from the saved review report
/oss:resolve 55 report

# Option 2: Apply from live GitHub comments
/oss:resolve 55 pr

# Option 3: Both sources in one pass (deduplicates)
/oss:resolve 55 pr report
```

### Release pipeline

```bash
/oss:release notes v1.2.0..HEAD     # generate release notes from git range
/oss:release prepare v2.1.0         # full pipeline: notes + changelog + migration + readiness audit
/oss:release audit                  # readiness check before tagging
```

### Common full-cycle sequence

```bash
/oss:analyse health                 # morning: understand what needs attention
/oss:review 55 --reply              # review top PR; post welcoming comment
/develop:fix 42                     # fix a reported bug (develop plugin)
/oss:release prepare v2.1.0         # cut a release
```

### Direct agent dispatch

```bash
use shepherd to draft a response for issue #88, citing the contributing guide
use ci-guardian to reduce the build time in .github/workflows/ci.yml
```

## 🗺️ Overview

### 2 Specialist Agents

| Agent           | Role                                                                                          | Model  |
| --------------- | --------------------------------------------------------------------------------------------- | ------ |
| **shepherd**    | Issue triage, PR review, SemVer discipline, release pipeline, trusted publishing, deprecation | opus   |
| **ci-guardian** | GitHub Actions, test matrices, caching, branch protections, flaky test detection              | sonnet |

**shepherd** is the external interface of the project — it owns all contributor-facing communication, release notes, and changelog entries. It never writes implementation code.

**ci-guardian** owns CI configuration quality: workflow topology, runner strategy, caching correctness, and the structural health of quality gates. It does not select ruff/mypy rules or fix type annotations — those belong to `linting-expert` (foundry plugin).

### Tiered Review Pipeline

`/oss:review` runs in three tiers to balance speed and thoroughness — input is always a GitHub PR number:

```
Tier 0: git diff --stat — mechanical gate; skips trivial diffs (whitespace, docs-only)
Tier 1: Codex pre-pass (~60s) — independent diff review; surfaces obvious issues first
Tier 2: 6 parallel agents — sw-engineer, qa-specialist, perf-optimizer,
         doc-scribe, solution-architect, linting-expert
→ consolidator reads all agent findings → ranked report
→ shepherd writes --reply output (if --reply flag present)
```

> [!TIP]
>
> Tier 2 only runs when Tier 1 does not surface a blocking issue on its own. The full pipeline completes in under 10 minutes on typical PRs.

### Three-Source Resolution

`/oss:resolve` applies fixes from three source modes — choose based on what is already available:

| Mode          | Source                      | When to use                                       |
| ------------- | --------------------------- | ------------------------------------------------- |
| `pr`          | Live GitHub PR comments     | Apply review feedback posted directly on GitHub   |
| `report`      | `/oss:review` findings file | Apply findings from a saved review report         |
| `pr + report` | Both sources, aggregated    | Full close: Codex deduplicates across both inputs |

### Skills

| Skill          | What It Does                                                                                                       |
| -------------- | ------------------------------------------------------------------------------------------------------------------ |
| `/oss:analyse` | GitHub thread analysis (issue/PR/discussion); `health` = repo overview + duplicate clustering + stale PR detection |
| `/oss:review`  | Tiered parallel review of GitHub PRs; `--reply` drafts a welcoming contributor comment citing project conventions  |
| `/oss:resolve` | Fast-close: apply Codex-driven fixes from PR comments, a review report, or both; semantic conflict resolution      |
| `/oss:release` | SemVer-disciplined pipeline: notes, changelog with deprecation tracking, migration guides, readiness audit         |

## Dependencies

**Optional**: `foundry` plugin. When installed, skills use specialized agents (`foundry:sw-engineer`, `foundry:qa-specialist`, etc.) for higher-quality output. Without foundry, skills fall back to `general-purpose` agents with role-description prompts — all skills remain functional.

## 📦 Plugin details

### Upgrade

```bash
cd Borda-AI-Rig && git pull
claude plugin install oss@borda-ai-rig
```

### Uninstall

```bash
claude plugin uninstall oss
```

### Structure

```
plugins/oss/
├── .claude-plugin/
│   └── plugin.json          ← manifest
├── agents/
│   ├── shepherd.md
│   └── ci-guardian.md
└── skills/
    ├── analyse/
    ├── review/
    ├── resolve/
    └── release/
```
