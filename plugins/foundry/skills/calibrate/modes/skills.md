**Re: Compress markdown to caveman format**

<!-- Step 1 in SKILL.md dispatches to this mode file. Steps here continue from Step 2. -->

## Mode: skills

### Domain table

Skill domains:

- `/audit` → synthetic `.claude/` config with N injected structural issues
- `/oss:review` → synthetic Python module with N cross-domain issues (arch + tests + docs + lint) *(oss plugin required — skip if `$OSS_AVAILABLE` empty)*
- `/research:plan` → synthetic optimization goal (e.g. "reduce pytest runtime by 30%"); measure whether plan mode produces complete, valid `program.md` with all required sections, plausible `metric_cmd`, correct `direction`, coherent `scope_files` *(research plugin required — skip if `$RESEARCH_AVAILABLE` empty)*
- `/research:judge` → synthetic `program.md` with N injected plan-quality issues (e.g. missing guard command, absent `direction`, non-existent `scope_files` path, invalid `agent_strategy`); measure whether judge correctly identifies each injected issue at right severity *(research plugin required — skip if `$RESEARCH_AVAILABLE` empty)*
- `/develop:review` → synthetic Python file with N injected code-quality issues (style, correctness, coverage gaps); measure whether review identifies each injected issue at correct severity level *(develop plugin required — skip if `$DEVELOP_AVAILABLE` empty)*
- `/codemap:query` → synthetic codemap index with known centrality/coupling values; measure whether `central`, `coupled`, `deps`, `rdeps`, `path` queries return correct modules matching ground-truth graph structure *(codemap plugin required — skip if `$CODEMAP_AVAILABLE` empty)*
- `/codemap:scan` → synthetic Python project with known module structure; measure whether scan correctly identifies modules, dependencies, and produces valid index *(codemap plugin required — skip if `$CODEMAP_AVAILABLE` empty)*
- `/codemap:integration` → synthetic project with known skill integration opportunities; measure whether integration correctly scores and ranks candidate skills *(codemap plugin required — skip if `$CODEMAP_AVAILABLE` empty)*
- `/research:verify` → paper-vs-code fidelity check; inject N known deviations (hyperparams, architecture, loss function, preprocessing); score recall per dimension (F, H, E, N, C) *(research plugin required — skip if `$RESEARCH_AVAILABLE` empty)*
- `/oss:analyse` → synthetic GitHub issue number (fixture: known type, known thread length, known duplicate link); measure whether thread analysis correctly classifies item type (issue/PR/discussion), surfaces duplicate, and produces actionable summary; ground truth = injected issue metadata *(oss plugin required — skip if `$OSS_AVAILABLE` empty)*
- `/oss:release` → synthetic git log with N commits of known classification (breaking, feature, fix, internal); measure whether release notes correctly classify each commit and omit internal-only entries; ground truth = injected commit metadata and expected output sections *(oss plugin required — skip if `$OSS_AVAILABLE` empty)*
- `/distill:lessons` → synthetic `.notes/lessons.md` corpus with N injected lessons of known disposition (→ rule, → agent update, → skill update, → already covered, → too narrow); measure whether distill correctly classifies each lesson and generates accurate proposals; ground truth = injected dispositions and target files
- `/manage:create` → synthetic create-agent and create-skill directives; measure whether output file has valid frontmatter, correct structure, NOT-for clause, non-empty domain content; ground truth = structural completeness checklist
- `/manage:update` → synthetic rename and content-edit directives against a fixture agent/skill file; measure whether cross-reference propagation is complete and description-changed flag is correctly set; ground truth = known cross-ref targets in fixture

### Step 2: Spawn skill pipeline subagents

Mark "Calibrate skills" in_progress. **Availability check** (vars set in SKILL.md Step 2): exclude skills marked with plugin requirements above when that plugin is absent. Log: "<plugin> plugin not installed — skipping <skill> calibration" per excluded skill.

For each skill in domain table (after exclusions), spawn one `general-purpose` pipeline subagent. Issue ALL spawns in **single response**.

For skill targets (target name starts with `/`): spawn `general-purpose` subagent with skill's `SKILL.md` content prepended as context, running against synthetic input from problem. Pipeline template write-and-acknowledge pattern still applies.

For mode-specific targets (`/research:plan`, `/research:judge`): prepend relevant mode file as context instead of full `SKILL.md`. Resolve the skill file via installed path first, falling back to source-tree path:
- `/research:plan`: `ls ~/.claude/plugins/cache/borda-ai-rig/research/*/skills/plan/SKILL.md 2>/dev/null | sort -V | tail -1` — fallback: `plugins/research/skills/plan/SKILL.md`
- `/research:judge`: `ls ~/.claude/plugins/cache/borda-ai-rig/research/*/skills/judge/SKILL.md 2>/dev/null | sort -V | tail -1` — fallback: `plugins/research/skills/judge/SKILL.md`

Read the resolved path (plan wizard steps P-P0–P-P3 for `/research:plan`; steps J1–J6 for `/research:judge`). `<TARGET>` substitution uses kebab form without leading slash (e.g. `research-plan`, `research-judge`).

For `/research:judge`, calibration pattern mirrors `/audit`: inject N specific known issues into synthetic `program.md`, score recall of injected issues against judge's findings list. Ground truth = injected issues and severities (per J2 severity table: critical/high/medium/low).

For `/research:plan`, calibration measures output completeness: generate synthetic goal, score whether produced `program.md` (a) contains all four required sections (Goal, Metric, Guard, Config), (b) has `direction` field, (c) has non-empty `scope_files`, (d) includes plausible `metric_cmd`. Ground truth = checklist; recall = fraction of checklist items present.

Each subagent receives pipeline template from `.claude/skills/calibrate/templates/pipeline-prompt.md` with substitutions:

- `<TARGET>` = skill name including `/` prefix (e.g., `/audit`)
- `<DOMAIN>` = domain string from table above for that skill
- `<N>` = 3 (fast) or 10 (full)
- `<TIMESTAMP>` = current run timestamp
- `<MODE>` = `fast` or `full`
- `<AB_MODE>` = `true` or `false`

**Partial-calibration principle**: individual skill modes with deterministic, auditable outputs can be calibrated even when full orchestration skill cannot. Full `optimize run` loop (requires live metric commands, git state, real guard scripts) excluded. Sub-modes producing structured, inspectable output are in scope:

- `optimize plan` — config wizard; output is `program.md` checkable against completeness schema
- `optimize judge` — plan auditor; output is findings list checkable against injected known issues (same pattern as `/audit`)

Other orchestration-heavy skills excluded: `resolve`, `manage`, `develop`, `research`, `brainstorm`. Outputs too context-dependent or long-horizon for synthetic ground truth without significant test infrastructure.

Run dir per skill: `.reports/calibrate/<TIMESTAMP>/<TARGET>/` (strip `/` from target name for dir, e.g. `audit` or `review`)

### Future Candidates

Modes evaluated for calibration but deferred — significant barriers. `/audit` Check 19 skips modes listed here to avoid false-positive recommendations.

| Mode | Barrier | Re-evaluate when |
| --- | --- | --- |
| `/analyse-thread` | Requires GitHub API mocking — thread analysis fetches live issue/PR data | GitHub fixture infrastructure exists |
| `/analyse-health` | Requires live GitHub API — health overview fetches real repo stats (issue/PR counts) | GitHub fixture infrastructure exists |
| `/analyse-ecosystem` | Requires live GitHub API — ecosystem analysis fetches real package/dependency data | GitHub fixture infrastructure exists |
| `/release-notes` | Requires controlled git history — output depends on real commit range | Git-history fixture helper exists |
| `/release-changelog` | Same as `/release-notes` — git-history dependent | Git-history fixture helper exists |
| `/release-summary` | Same as `/release-notes` — git-history dependent | Git-history fixture helper exists |
| `/release-audit` | Requires controlled repo state (version tags, CHANGELOG, CI status) | Release fixture infrastructure exists |
| `/release-demo` | Requires controlled git history — output depends on real commit range | Git-history fixture helper exists |
| `/develop-plan` | Output is somewhat subjective; no clear ground-truth checklist beyond section presence | Structured plan schema is formalized |
| `/distill-review` | Reads real agent/skill files; synthetic roster possible but overlaps `/audit` calibration | Distinct synthetic scenarios identified |
| `/distill-prune` | Likely calibratable — construct a synthetic memory corpus with known entries to drop (stale, redundant, duplicated-in-CLAUDE.md), then score recall of correct drop/trim/keep decisions; ground truth is constructable | Synthetic memory corpus fixtures built |
| `/distill-lessons` | Promoted to domain table — synthetic lesson corpus calibration now defined | — |
| `/distill-external` | Calibratable with two concrete GT fixture cases: **(1) caveman plugin** — narrow communication-mode tool, no local overlap → GT outcome: install-as-is recommendation; **(2) Karpathy autoresearch** — research automation with strong structural overlap to `research:` plugin → GT outcome: Group A candidates map to research plugin, digest recommended. Score whether adoption-table lane assignments (adopt-as-is/tweak/discuss/skip) and install-as-is flag match GT. Ground truth constructable without live external source — fixture = static snapshot of each tool's agent/skill/rule files. | GT fixture snapshots authored |

**Excluded** (inherently non-calibratable — documented to avoid recurring evaluation):

- `/resolve` — orchestrates live PR review, lint, push; fully external-service-dependent
- `/manage` (delete, perm ops) — CRUD on config files with no structured findings list to score; `/manage:create` and `/manage:update` promoted to domain table with structural completeness ground truth
- `/develop:feature`/`/develop:fix`/`/develop:refactor`/`/develop:debug` — full dev lifecycle; requires git, tests, linting
- `/research:topic` — SOTA literature search; depends on live web results; no deterministic ground truth
- `/brainstorm` — creative ideation; no deterministic ground truth
- `/investigate` — open-ended diagnosis; output varies completely by symptom
- `/session` — session lifecycle management; no quality signal to measure
- `/foundry:session` — session lifecycle management — no quality signal to measure; output fully context-dependent
- `/calibrate` itself — meta-calibration circular
- `/research:run` — sustained iteration loop with live metric commands and git state
- `/research:run --resume` — continuation of run; same barriers as run
- `/research:sweep` — same barriers as `/research:run` — sustained iteration loop requiring live metrics and git state; not calibratable synthetically
- `/research:fortify` — requires completed `/research:run` ablation output; ground truth not constructable synthetically
- `/research:retro` — requires live `experiments.jsonl`; same barrier as `/research:run`
- `/foundry:init` — system-state-dependent — installs symlinks and merges settings; ground truth not constructable
